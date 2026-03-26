#!/usr/bin/env bash
# Description: Exports configuration drift signals — ArgoCD sync drift, Flux reconciliation status, Compliance Operator scan results, node version consistency, and operator version consistency
# Audit Area:  Configuration Drift Detection
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./common.sh
source "$SCRIPT_DIR/common.sh"

: "${CLUSTER_NAME_SAFE:?CLUSTER_NAME_SAFE is not set}"
: "${CLUSTER_NAME:?CLUSTER_NAME is not set}"
: "${CLUSTER_CONTEXT:?CLUSTER_CONTEXT is not set}"
: "${CLUSTER_SERVER:?CLUSTER_SERVER is not set}"
: "${OUTPUT_DIR:?OUTPUT_DIR is not set}"
: "${TIMESTAMP:?TIMESTAMP is not set}"

LABEL="drift-detection"
SCRIPT_START_SECONDS=$SECONDS

RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "[$(date +%H:%M:%S)] [$LABEL] Starting export at $(date)"

OUTPUT_FILE="$OUTPUT_DIR/configuration-drift-status-${CLUSTER_NAME_SAFE}-$TIMESTAMP.csv"

echo "cluster_name,cluster_context,cluster_server,record_type,component_name,status,namespace,detail_1,detail_2,detail_3,detail_4" > "$OUTPUT_FILE"

# ── Helper: write a CSV row ──────────────────────────────────────────────────
write_row() {
  local record_type="$1" component_name="$2" status="$3" namespace="$4" detail_1="$5" detail_2="$6" detail_3="$7" detail_4="$8"
  jq -rn \
    --arg cluster_name "$CLUSTER_NAME" \
    --arg cluster_context "$CLUSTER_CONTEXT" \
    --arg cluster_server "$CLUSTER_SERVER" \
    --arg record_type "$record_type" \
    --arg component_name "$component_name" \
    --arg status "$status" \
    --arg namespace "$namespace" \
    --arg detail_1 "$detail_1" \
    --arg detail_2 "$detail_2" \
    --arg detail_3 "$detail_3" \
    --arg detail_4 "$detail_4" \
    '[$cluster_name,$cluster_context,$cluster_server,$record_type,$component_name,$status,$namespace,$detail_1,$detail_2,$detail_3,$detail_4] | @csv' \
    >> "$OUTPUT_FILE"
}

DRIFT_SOURCES_DETECTED=0
DRIFT_ITEMS_FOUND=0

# ═══════════════════════════════════════════════════════════════════════════════
# Section 1: ArgoCD / OpenShift GitOps Sync Drift
# ═══════════════════════════════════════════════════════════════════════════════
echo "[$(date +%H:%M:%S)] [$LABEL] Checking ArgoCD sync drift..."

ARGO_INSTALLED="false"
ARGO_NS=""

# Check for ArgoCD CRD
if oc get crd applications.argoproj.io >/dev/null 2>&1; then
  ARGO_INSTALLED="true"
  DRIFT_SOURCES_DETECTED=$((DRIFT_SOURCES_DETECTED + 1))

  # Find namespace
  for NS in openshift-gitops gitops-system argocd; do
    if oc get namespace "$NS" >/dev/null 2>&1; then
      ARGO_NS="$NS"
      break
    fi
  done

  APPS_JSON=$(oc get applications.argoproj.io -A -o json 2>/dev/null | tr -d '\r' || echo '{"items":[]}')
  APP_TOTAL=$(echo "$APPS_JSON" | jq '.items | length' 2>/dev/null || echo "0")
  APP_SYNCED=$(echo "$APPS_JSON" | jq '[.items[] | select(.status.sync.status == "Synced")] | length' 2>/dev/null || echo "0")
  APP_OUTOFSYNC=$(echo "$APPS_JSON" | jq '[.items[] | select(.status.sync.status == "OutOfSync")] | length' 2>/dev/null || echo "0")
  APP_UNKNOWN=$(echo "$APPS_JSON" | jq '[.items[] | select(.status.sync.status == "Unknown" or .status.sync.status == null)] | length' 2>/dev/null || echo "0")
  APP_HEALTHY=$(echo "$APPS_JSON" | jq '[.items[] | select(.status.health.status == "Healthy")] | length' 2>/dev/null || echo "0")
  APP_DEGRADED=$(echo "$APPS_JSON" | jq '[.items[] | select(.status.health.status == "Degraded")] | length' 2>/dev/null || echo "0")

  echo "[$(date +%H:%M:%S)] [$LABEL]   ArgoCD apps: $APP_TOTAL (synced:$APP_SYNCED out-of-sync:$APP_OUTOFSYNC unknown:$APP_UNKNOWN)"
  echo "[$(date +%H:%M:%S)] [$LABEL]   Health: healthy:$APP_HEALTHY degraded:$APP_DEGRADED"

  # Summary row
  write_row "gitops_summary" "ArgoCD" "installed" "${ARGO_NS:-(multi)}" \
    "apps:$APP_TOTAL;synced:$APP_SYNCED;out_of_sync:$APP_OUTOFSYNC;unknown:$APP_UNKNOWN" \
    "healthy:$APP_HEALTHY;degraded:$APP_DEGRADED" "" ""

  # Per-app rows for drifted (OutOfSync) applications
  if [ "$APP_OUTOFSYNC" -gt 0 ]; then
    DRIFT_ITEMS_FOUND=$((DRIFT_ITEMS_FOUND + APP_OUTOFSYNC))
    echo -e "${YELLOW}[$(date +%H:%M:%S)] [$LABEL] WARNING: $APP_OUTOFSYNC ArgoCD applications are OutOfSync — configuration drift from git${NC}"

    echo "$APPS_JSON" | jq -c '.items[] | select(.status.sync.status == "OutOfSync")' 2>/dev/null | while IFS= read -r APP_ITEM; do
      [ -z "$APP_ITEM" ] && continue
      APP_NAME=$(echo "$APP_ITEM" | jq -r '.metadata.name // ""' 2>/dev/null)
      APP_NS=$(echo "$APP_ITEM" | jq -r '.metadata.namespace // ""' 2>/dev/null)
      APP_REPO=$(echo "$APP_ITEM" | jq -r '.spec.source.repoURL // ""' 2>/dev/null)
      APP_PATH=$(echo "$APP_ITEM" | jq -r '.spec.source.path // ""' 2>/dev/null)
      APP_HEALTH=$(echo "$APP_ITEM" | jq -r '.status.health.status // ""' 2>/dev/null)
      APP_SYNC_POLICY=$(echo "$APP_ITEM" | jq -r 'if .spec.syncPolicy.automated then "automated" else "manual" end' 2>/dev/null || echo "unknown")

      write_row "gitops_drift" "$APP_NAME" "OutOfSync" "$APP_NS" \
        "repo:$APP_REPO" "path:$APP_PATH" "health:$APP_HEALTH" "sync_policy:$APP_SYNC_POLICY"
    done
  fi

  # Per-app rows for degraded health
  if [ "$APP_DEGRADED" -gt 0 ]; then
    echo "$APPS_JSON" | jq -c '.items[] | select(.status.health.status == "Degraded")' 2>/dev/null | while IFS= read -r APP_ITEM; do
      [ -z "$APP_ITEM" ] && continue
      APP_NAME=$(echo "$APP_ITEM" | jq -r '.metadata.name // ""' 2>/dev/null)
      APP_NS=$(echo "$APP_ITEM" | jq -r '.metadata.namespace // ""' 2>/dev/null)
      APP_SYNC=$(echo "$APP_ITEM" | jq -r '.status.sync.status // ""' 2>/dev/null)
      APP_HEALTH_MSG=$(echo "$APP_ITEM" | jq -r '.status.health.message // ""' 2>/dev/null)

      write_row "gitops_degraded" "$APP_NAME" "Degraded" "$APP_NS" \
        "sync:$APP_SYNC" "message:$APP_HEALTH_MSG" "" ""
    done
  fi
else
  echo "[$(date +%H:%M:%S)] [$LABEL]   ArgoCD CRD not found — GitOps drift detection not available"
  write_row "gitops_summary" "ArgoCD" "not_installed" "" "" "" "" ""
fi

echo "[$(date +%H:%M:%S)] [$LABEL] ArgoCD sync drift done."

# ═══════════════════════════════════════════════════════════════════════════════
# Section 2: Flux CD Reconciliation Drift
# ═══════════════════════════════════════════════════════════════════════════════
echo "[$(date +%H:%M:%S)] [$LABEL] Checking Flux reconciliation drift..."

FLUX_INSTALLED="false"

# Check for Flux CRDs
FLUX_HAS_HELM="false"
FLUX_HAS_KUSTOMIZE="false"
if oc get crd helmreleases.helm.toolkit.fluxcd.io >/dev/null 2>&1; then
  FLUX_HAS_HELM="true"
  FLUX_INSTALLED="true"
fi
if oc get crd kustomizations.kustomize.toolkit.fluxcd.io >/dev/null 2>&1; then
  FLUX_HAS_KUSTOMIZE="true"
  FLUX_INSTALLED="true"
fi

if [ "$FLUX_INSTALLED" = "true" ]; then
  DRIFT_SOURCES_DETECTED=$((DRIFT_SOURCES_DETECTED + 1))
  echo "[$(date +%H:%M:%S)] [$LABEL]   Flux CRDs found (helm:$FLUX_HAS_HELM kustomize:$FLUX_HAS_KUSTOMIZE)"

  FLUX_DRIFT=0

  # HelmReleases
  if [ "$FLUX_HAS_HELM" = "true" ]; then
    HR_JSON=$(oc get helmreleases.helm.toolkit.fluxcd.io -A -o json 2>/dev/null | tr -d '\r' || echo '{"items":[]}')
    HR_TOTAL=$(echo "$HR_JSON" | jq '.items | length' 2>/dev/null || echo "0")
    HR_READY=$(echo "$HR_JSON" | jq '[.items[] | select(.status.conditions[]? | select(.type == "Ready" and .status == "True"))] | length' 2>/dev/null || echo "0")
    HR_NOT_READY=$((HR_TOTAL - HR_READY))

    echo "[$(date +%H:%M:%S)] [$LABEL]   HelmReleases: $HR_TOTAL (ready:$HR_READY not-ready:$HR_NOT_READY)"

    write_row "flux_summary" "HelmReleases" "total:$HR_TOTAL" "flux-system" \
      "ready:$HR_READY;not_ready:$HR_NOT_READY" "" "" ""

    # Per-item rows for not-ready HelmReleases
    if [ "$HR_NOT_READY" -gt 0 ]; then
      FLUX_DRIFT=$((FLUX_DRIFT + HR_NOT_READY))
      echo "$HR_JSON" | jq -c '.items[] | select((.status.conditions // []) | all(.type == "Ready" and .status == "True") | not)' 2>/dev/null | while IFS= read -r HR_ITEM; do
        [ -z "$HR_ITEM" ] && continue
        HR_NAME=$(echo "$HR_ITEM" | jq -r '.metadata.name // ""' 2>/dev/null)
        HR_NS=$(echo "$HR_ITEM" | jq -r '.metadata.namespace // ""' 2>/dev/null)
        HR_MSG=$(echo "$HR_ITEM" | jq -r '[.status.conditions[]? | select(.type == "Ready")] | first | .message // ""' 2>/dev/null || echo "")
        HR_CHART=$(echo "$HR_ITEM" | jq -r '.spec.chart.spec.chart // ""' 2>/dev/null || echo "")

        write_row "flux_drift" "$HR_NAME" "NotReady" "$HR_NS" \
          "type:HelmRelease" "chart:$HR_CHART" "message:$HR_MSG" ""
      done
    fi
  fi

  # Kustomizations
  if [ "$FLUX_HAS_KUSTOMIZE" = "true" ]; then
    KS_JSON=$(oc get kustomizations.kustomize.toolkit.fluxcd.io -A -o json 2>/dev/null | tr -d '\r' || echo '{"items":[]}')
    KS_TOTAL=$(echo "$KS_JSON" | jq '.items | length' 2>/dev/null || echo "0")
    KS_READY=$(echo "$KS_JSON" | jq '[.items[] | select(.status.conditions[]? | select(.type == "Ready" and .status == "True"))] | length' 2>/dev/null || echo "0")
    KS_NOT_READY=$((KS_TOTAL - KS_READY))

    echo "[$(date +%H:%M:%S)] [$LABEL]   Kustomizations: $KS_TOTAL (ready:$KS_READY not-ready:$KS_NOT_READY)"

    write_row "flux_summary" "Kustomizations" "total:$KS_TOTAL" "flux-system" \
      "ready:$KS_READY;not_ready:$KS_NOT_READY" "" "" ""

    if [ "$KS_NOT_READY" -gt 0 ]; then
      FLUX_DRIFT=$((FLUX_DRIFT + KS_NOT_READY))
      echo "$KS_JSON" | jq -c '.items[] | select((.status.conditions // []) | all(.type == "Ready" and .status == "True") | not)' 2>/dev/null | while IFS= read -r KS_ITEM; do
        [ -z "$KS_ITEM" ] && continue
        KS_NAME=$(echo "$KS_ITEM" | jq -r '.metadata.name // ""' 2>/dev/null)
        KS_NS=$(echo "$KS_ITEM" | jq -r '.metadata.namespace // ""' 2>/dev/null)
        KS_MSG=$(echo "$KS_ITEM" | jq -r '[.status.conditions[]? | select(.type == "Ready")] | first | .message // ""' 2>/dev/null || echo "")
        KS_PATH=$(echo "$KS_ITEM" | jq -r '.spec.path // ""' 2>/dev/null || echo "")

        write_row "flux_drift" "$KS_NAME" "NotReady" "$KS_NS" \
          "type:Kustomization" "path:$KS_PATH" "message:$KS_MSG" ""
      done
    fi
  fi

  DRIFT_ITEMS_FOUND=$((DRIFT_ITEMS_FOUND + FLUX_DRIFT))
  if [ "$FLUX_DRIFT" -gt 0 ]; then
    echo -e "${YELLOW}[$(date +%H:%M:%S)] [$LABEL] WARNING: $FLUX_DRIFT Flux resources are not reconciled — configuration drift${NC}"
  fi
else
  echo "[$(date +%H:%M:%S)] [$LABEL]   Flux CRDs not found — Flux drift detection not available"
  write_row "flux_summary" "Flux" "not_installed" "" "" "" "" ""
fi

echo "[$(date +%H:%M:%S)] [$LABEL] Flux reconciliation drift done."

# ═══════════════════════════════════════════════════════════════════════════════
# Section 3: Compliance Operator Scan Results
# ═══════════════════════════════════════════════════════════════════════════════
echo "[$(date +%H:%M:%S)] [$LABEL] Checking Compliance Operator scan results..."

COMPLIANCE_INSTALLED="false"

if oc get crd compliancescans.compliance.openshift.io >/dev/null 2>&1; then
  COMPLIANCE_INSTALLED="true"
  DRIFT_SOURCES_DETECTED=$((DRIFT_SOURCES_DETECTED + 1))
  echo "[$(date +%H:%M:%S)] [$LABEL]   Compliance Operator CRD found"

  # ComplianceScans — overall scan status
  CS_JSON=$(oc get compliancescans -A -o json 2>/dev/null | tr -d '\r' || echo '{"items":[]}')
  CS_TOTAL=$(echo "$CS_JSON" | jq '.items | length' 2>/dev/null || echo "0")
  echo "[$(date +%H:%M:%S)] [$LABEL]   ComplianceScans: $CS_TOTAL"

  echo "$CS_JSON" | jq -c '.items[]' 2>/dev/null | while IFS= read -r CS_ITEM; do
    [ -z "$CS_ITEM" ] && continue
    CS_NAME=$(echo "$CS_ITEM" | jq -r '.metadata.name // ""' 2>/dev/null)
    CS_NS=$(echo "$CS_ITEM" | jq -r '.metadata.namespace // ""' 2>/dev/null)
    CS_RESULT=$(echo "$CS_ITEM" | jq -r '.status.result // ""' 2>/dev/null)
    CS_PHASE=$(echo "$CS_ITEM" | jq -r '.status.phase // ""' 2>/dev/null)
    CS_PROFILE=$(echo "$CS_ITEM" | jq -r '.spec.profile // ""' 2>/dev/null)
    CS_CONTENT=$(echo "$CS_ITEM" | jq -r '.spec.content // ""' 2>/dev/null)

    write_row "compliance_scan" "$CS_NAME" "$CS_RESULT" "$CS_NS" \
      "phase:$CS_PHASE" "profile:$CS_PROFILE" "content:$CS_CONTENT" ""
  done

  # ComplianceCheckResults — individual check pass/fail
  echo "[$(date +%H:%M:%S)] [$LABEL] Fetching ComplianceCheckResults..."
  CCR_JSON=$(oc get compliancecheckresults -A -o json 2>/dev/null | tr -d '\r' || echo '{"items":[]}')
  CCR_TOTAL=$(echo "$CCR_JSON" | jq '.items | length' 2>/dev/null || echo "0")
  CCR_PASS=$(echo "$CCR_JSON" | jq '[.items[] | select(.status == "PASS")] | length' 2>/dev/null || echo "0")
  CCR_FAIL=$(echo "$CCR_JSON" | jq '[.items[] | select(.status == "FAIL")] | length' 2>/dev/null || echo "0")
  CCR_MANUAL=$(echo "$CCR_JSON" | jq '[.items[] | select(.status == "MANUAL")] | length' 2>/dev/null || echo "0")
  CCR_ERROR=$(echo "$CCR_JSON" | jq '[.items[] | select(.status == "ERROR")] | length' 2>/dev/null || echo "0")
  CCR_INFO=$(echo "$CCR_JSON" | jq '[.items[] | select(.status == "NOT-APPLICABLE" or .status == "INCONSISTENT")] | length' 2>/dev/null || echo "0")

  echo "[$(date +%H:%M:%S)] [$LABEL]   Check results: $CCR_TOTAL (pass:$CCR_PASS fail:$CCR_FAIL manual:$CCR_MANUAL error:$CCR_ERROR other:$CCR_INFO)"

  write_row "compliance_results_summary" "ComplianceCheckResults" "total:$CCR_TOTAL" "(cluster)" \
    "pass:$CCR_PASS;fail:$CCR_FAIL" "manual:$CCR_MANUAL;error:$CCR_ERROR" "other:$CCR_INFO" ""

  # Export individual FAIL results (these represent drift from compliance baseline)
  if [ "$CCR_FAIL" -gt 0 ]; then
    DRIFT_ITEMS_FOUND=$((DRIFT_ITEMS_FOUND + CCR_FAIL))
    echo -e "${YELLOW}[$(date +%H:%M:%S)] [$LABEL] WARNING: $CCR_FAIL compliance checks FAILED — drift from security baseline${NC}"

    # Limit to first 200 failures to avoid excessive output
    FAIL_LIMIT=200
    FAIL_COUNT=0
    echo "$CCR_JSON" | jq -c '.items[] | select(.status == "FAIL")' 2>/dev/null | while IFS= read -r CCR_ITEM; do
      [ -z "$CCR_ITEM" ] && continue
      FAIL_COUNT=$((FAIL_COUNT + 1))
      if [ "$FAIL_COUNT" -gt "$FAIL_LIMIT" ]; then
        break
      fi

      CCR_NAME=$(echo "$CCR_ITEM" | jq -r '.metadata.name // ""' 2>/dev/null)
      CCR_NS=$(echo "$CCR_ITEM" | jq -r '.metadata.namespace // ""' 2>/dev/null)
      CCR_SEVERITY=$(echo "$CCR_ITEM" | jq -r '.severity // ""' 2>/dev/null)
      CCR_DESC=$(echo "$CCR_ITEM" | jq -r '.description // ""' 2>/dev/null | head -c 200)
      CCR_SCAN=$(echo "$CCR_ITEM" | jq -r '.metadata.labels["compliance.openshift.io/scan-name"] // ""' 2>/dev/null)

      write_row "compliance_fail" "$CCR_NAME" "FAIL" "$CCR_NS" \
        "severity:$CCR_SEVERITY" "scan:$CCR_SCAN" "description:$CCR_DESC" ""
    done

    if [ "$CCR_FAIL" -gt "$FAIL_LIMIT" ]; then
      echo "[$(date +%H:%M:%S)] [$LABEL]   (exported first $FAIL_LIMIT of $CCR_FAIL failures)"
    fi
  fi
else
  echo "[$(date +%H:%M:%S)] [$LABEL]   Compliance Operator CRD not found — compliance drift detection not available"
  write_row "compliance_scan" "ComplianceOperator" "not_installed" "" "" "" "" ""
fi

echo "[$(date +%H:%M:%S)] [$LABEL] Compliance scan results done."

# ═══════════════════════════════════════════════════════════════════════════════
# Section 4: Node Version Consistency
# ═══════════════════════════════════════════════════════════════════════════════
echo "[$(date +%H:%M:%S)] [$LABEL] Checking node version consistency..."

NODES_JSON=$(oc get nodes -o json 2>/dev/null | tr -d '\r' || echo '{"items":[]}')
NODE_COUNT=$(echo "$NODES_JSON" | jq '.items | length' 2>/dev/null || echo "0")
echo "[$(date +%H:%M:%S)] [$LABEL]   Total nodes: $NODE_COUNT"

# Extract unique kubelet versions
KUBELET_VERSIONS=$(echo "$NODES_JSON" | jq -r '[.items[].status.nodeInfo.kubeletVersion] | unique | join(";")' 2>/dev/null || echo "")
KUBELET_VERSION_COUNT=$(echo "$NODES_JSON" | jq '[.items[].status.nodeInfo.kubeletVersion] | unique | length' 2>/dev/null || echo "0")

# Extract unique OS images
OS_IMAGES=$(echo "$NODES_JSON" | jq -r '[.items[].status.nodeInfo.osImage] | unique | join(";")' 2>/dev/null || echo "")
OS_IMAGE_COUNT=$(echo "$NODES_JSON" | jq '[.items[].status.nodeInfo.osImage] | unique | length' 2>/dev/null || echo "0")

# Extract unique container runtime versions
RUNTIME_VERSIONS=$(echo "$NODES_JSON" | jq -r '[.items[].status.nodeInfo.containerRuntimeVersion] | unique | join(";")' 2>/dev/null || echo "")

echo "[$(date +%H:%M:%S)] [$LABEL]   Kubelet versions: $KUBELET_VERSIONS ($KUBELET_VERSION_COUNT unique)"
echo "[$(date +%H:%M:%S)] [$LABEL]   OS images: $OS_IMAGE_COUNT unique"

write_row "node_consistency" "kubelet_versions" "unique:$KUBELET_VERSION_COUNT" "(cluster)" \
  "versions:$KUBELET_VERSIONS" "node_count:$NODE_COUNT" "" ""

write_row "node_consistency" "os_images" "unique:$OS_IMAGE_COUNT" "(cluster)" \
  "images:$OS_IMAGES" "node_count:$NODE_COUNT" "" ""

write_row "node_consistency" "container_runtime" "versions" "(cluster)" \
  "runtimes:$RUNTIME_VERSIONS" "node_count:$NODE_COUNT" "" ""

if [ "$KUBELET_VERSION_COUNT" -gt 1 ]; then
  DRIFT_ITEMS_FOUND=$((DRIFT_ITEMS_FOUND + 1))
  echo -e "${YELLOW}[$(date +%H:%M:%S)] [$LABEL] WARNING: $KUBELET_VERSION_COUNT different kubelet versions detected — nodes are not at the same version${NC}"

  # Per-node version detail for mismatched nodes
  MAJORITY_VERSION=$(echo "$NODES_JSON" | jq -r '[.items[].status.nodeInfo.kubeletVersion] | group_by(.) | sort_by(-length) | first | first' 2>/dev/null || echo "")

  echo "$NODES_JSON" | jq -c --arg majority "$MAJORITY_VERSION" '.items[] | select(.status.nodeInfo.kubeletVersion != $majority)' 2>/dev/null | while IFS= read -r NODE_ITEM; do
    [ -z "$NODE_ITEM" ] && continue
    NODE_NAME=$(echo "$NODE_ITEM" | jq -r '.metadata.name // ""' 2>/dev/null)
    NODE_KUBELET=$(echo "$NODE_ITEM" | jq -r '.status.nodeInfo.kubeletVersion // ""' 2>/dev/null)
    NODE_OS=$(echo "$NODE_ITEM" | jq -r '.status.nodeInfo.osImage // ""' 2>/dev/null)
    NODE_ROLE=$(echo "$NODE_ITEM" | jq -r '[.metadata.labels | to_entries[] | select(.key | startswith("node-role.kubernetes.io/")) | .key | ltrimstr("node-role.kubernetes.io/")] | join(";")' 2>/dev/null || echo "")

    write_row "node_version_drift" "$NODE_NAME" "version_mismatch" "(cluster)" \
      "kubelet:$NODE_KUBELET" "majority:$MAJORITY_VERSION" "os:$NODE_OS" "role:$NODE_ROLE"
  done
else
  echo "[$(date +%H:%M:%S)] [$LABEL]   All nodes at same kubelet version — no version drift"
fi

if [ "$OS_IMAGE_COUNT" -gt 1 ]; then
  echo -e "${YELLOW}[$(date +%H:%M:%S)] [$LABEL] WARNING: $OS_IMAGE_COUNT different OS images detected — nodes may be at different RHCOS versions${NC}"
fi

echo "[$(date +%H:%M:%S)] [$LABEL] Node version consistency done."

# ═══════════════════════════════════════════════════════════════════════════════
# Section 5: Operator Version Consistency
# ═══════════════════════════════════════════════════════════════════════════════
echo "[$(date +%H:%M:%S)] [$LABEL] Checking operator version consistency..."

CO_JSON=$(oc get clusteroperators -o json 2>/dev/null | tr -d '\r' || echo '{"items":[]}')
CO_COUNT=$(echo "$CO_JSON" | jq '.items | length' 2>/dev/null || echo "0")
echo "[$(date +%H:%M:%S)] [$LABEL]   Total ClusterOperators: $CO_COUNT"

# Extract operator versions — each operator has a "version" in .status.versions[]
CO_VERSIONS=$(echo "$CO_JSON" | jq -r '[.items[] | {name: .metadata.name, version: ([.status.versions[]? | select(.name == "operator")] | first | .version // "")}]' 2>/dev/null || echo "[]")

# Find unique operator versions
UNIQUE_OP_VERSIONS=$(echo "$CO_VERSIONS" | jq -r '[.[].version | select(. != "")] | unique | join(";")' 2>/dev/null || echo "")
UNIQUE_OP_VERSION_COUNT=$(echo "$CO_VERSIONS" | jq '[.[].version | select(. != "")] | unique | length' 2>/dev/null || echo "0")

echo "[$(date +%H:%M:%S)] [$LABEL]   Unique operator versions: $UNIQUE_OP_VERSIONS ($UNIQUE_OP_VERSION_COUNT unique)"

# Majority version (expected cluster version)
MAJORITY_OP_VERSION=$(echo "$CO_VERSIONS" | jq -r '[.[].version | select(. != "")] | group_by(.) | sort_by(-length) | first | first // ""' 2>/dev/null || echo "")

write_row "operator_consistency" "ClusterOperators" "unique:$UNIQUE_OP_VERSION_COUNT" "(cluster)" \
  "versions:$UNIQUE_OP_VERSIONS" "majority:$MAJORITY_OP_VERSION" "total:$CO_COUNT" ""

if [ "$UNIQUE_OP_VERSION_COUNT" -gt 1 ]; then
  DRIFT_ITEMS_FOUND=$((DRIFT_ITEMS_FOUND + 1))
  echo -e "${YELLOW}[$(date +%H:%M:%S)] [$LABEL] WARNING: $UNIQUE_OP_VERSION_COUNT different operator versions detected — upgrade may be in progress or stalled${NC}"

  # List operators not at the majority version
  echo "$CO_VERSIONS" | jq -c --arg majority "$MAJORITY_OP_VERSION" '.[] | select(.version != "" and .version != $majority)' 2>/dev/null | while IFS= read -r OP_ITEM; do
    [ -z "$OP_ITEM" ] && continue
    OP_NAME=$(echo "$OP_ITEM" | jq -r '.name // ""' 2>/dev/null)
    OP_VER=$(echo "$OP_ITEM" | jq -r '.version // ""' 2>/dev/null)

    # Get degraded/progressing status for this operator
    OP_DEGRADED=$(echo "$CO_JSON" | jq -r --arg name "$OP_NAME" '.items[] | select(.metadata.name == $name) | [.status.conditions[]? | select(.type == "Degraded")] | first | .status // ""' 2>/dev/null || echo "")
    OP_PROGRESSING=$(echo "$CO_JSON" | jq -r --arg name "$OP_NAME" '.items[] | select(.metadata.name == $name) | [.status.conditions[]? | select(.type == "Progressing")] | first | .status // ""' 2>/dev/null || echo "")

    write_row "operator_version_drift" "$OP_NAME" "version_mismatch" "(cluster)" \
      "version:$OP_VER" "majority:$MAJORITY_OP_VERSION" "degraded:$OP_DEGRADED" "progressing:$OP_PROGRESSING"
  done
else
  echo "[$(date +%H:%M:%S)] [$LABEL]   All operators at same version ($MAJORITY_OP_VERSION) — no version drift"
fi

# Also flag any degraded operators as misconfigured components (K09)
CO_DEGRADED_COUNT=$(echo "$CO_JSON" | jq '[.items[] | select(.status.conditions[]? | select(.type == "Degraded" and .status == "True"))] | length' 2>/dev/null || echo "0")
CO_PROGRESSING_COUNT=$(echo "$CO_JSON" | jq '[.items[] | select(.status.conditions[]? | select(.type == "Progressing" and .status == "True"))] | length' 2>/dev/null || echo "0")

echo "[$(date +%H:%M:%S)] [$LABEL]   Degraded operators: $CO_DEGRADED_COUNT"
echo "[$(date +%H:%M:%S)] [$LABEL]   Progressing operators: $CO_PROGRESSING_COUNT"

if [ "$CO_DEGRADED_COUNT" -gt 0 ]; then
  DRIFT_ITEMS_FOUND=$((DRIFT_ITEMS_FOUND + CO_DEGRADED_COUNT))
  echo -e "${RED}[$(date +%H:%M:%S)] [$LABEL] ERROR: $CO_DEGRADED_COUNT ClusterOperators are Degraded — misconfigured components detected (K09)${NC}"

  echo "$CO_JSON" | jq -c '.items[] | select(.status.conditions[]? | select(.type == "Degraded" and .status == "True"))' 2>/dev/null | while IFS= read -r DEG_ITEM; do
    [ -z "$DEG_ITEM" ] && continue
    DEG_NAME=$(echo "$DEG_ITEM" | jq -r '.metadata.name // ""' 2>/dev/null)
    DEG_MSG=$(echo "$DEG_ITEM" | jq -r '[.status.conditions[]? | select(.type == "Degraded")] | first | .message // ""' 2>/dev/null | head -c 200)
    DEG_VER=$(echo "$DEG_ITEM" | jq -r '[.status.versions[]? | select(.name == "operator")] | first | .version // ""' 2>/dev/null || echo "")

    write_row "operator_degraded" "$DEG_NAME" "Degraded" "(cluster)" \
      "version:$DEG_VER" "message:$DEG_MSG" "" ""
  done
fi

echo "[$(date +%H:%M:%S)] [$LABEL] Operator version consistency done."

# ═══════════════════════════════════════════════════════════════════════════════
# Summary
# ═══════════════════════════════════════════════════════════════════════════════
echo ""
echo "[$(date +%H:%M:%S)] [$LABEL] ┌──────────────────────────────────────────────────────┐"
echo "[$(date +%H:%M:%S)] [$LABEL] │       Configuration Drift Detection Summary           │"
echo "[$(date +%H:%M:%S)] [$LABEL] ├──────────────────────────────────────────────────────┤"
printf "[$(date +%H:%M:%S)] [$LABEL] │  Drift sources checked : %-27s│\n" "$DRIFT_SOURCES_DETECTED"
printf "[$(date +%H:%M:%S)] [$LABEL] │  ArgoCD                : %-27s│\n" "${ARGO_INSTALLED} (OutOfSync: ${APP_OUTOFSYNC:-n/a})"
printf "[$(date +%H:%M:%S)] [$LABEL] │  Flux                  : %-27s│\n" "${FLUX_INSTALLED}"
printf "[$(date +%H:%M:%S)] [$LABEL] │  Compliance Operator   : %-27s│\n" "${COMPLIANCE_INSTALLED} (Fail: ${CCR_FAIL:-n/a})"
printf "[$(date +%H:%M:%S)] [$LABEL] │  Kubelet versions      : %-27s│\n" "$KUBELET_VERSION_COUNT unique across $NODE_COUNT nodes"
printf "[$(date +%H:%M:%S)] [$LABEL] │  Operator versions     : %-27s│\n" "$UNIQUE_OP_VERSION_COUNT unique across $CO_COUNT operators"
printf "[$(date +%H:%M:%S)] [$LABEL] │  Degraded operators    : %-27s│\n" "$CO_DEGRADED_COUNT"
printf "[$(date +%H:%M:%S)] [$LABEL] │  Total drift items     : %-27s│\n" "$DRIFT_ITEMS_FOUND"
echo "[$(date +%H:%M:%S)] [$LABEL] └──────────────────────────────────────────────────────┘"
echo ""

# Critical: no drift detection tooling at all
if [ "$ARGO_INSTALLED" = "false" ] && [ "$FLUX_INSTALLED" = "false" ] && [ "$COMPLIANCE_INSTALLED" = "false" ]; then
  echo -e "${RED}[$(date +%H:%M:%S)] [$LABEL] CRITICAL: No GitOps (ArgoCD/Flux) and no Compliance Operator installed — no configuration drift detection tooling${NC}"
  echo -e "${RED}[$(date +%H:%M:%S)] [$LABEL]   Remediation: Deploy OpenShift GitOps (ArgoCD) for continuous drift detection, and Compliance Operator for baseline scanning${NC}"
fi

ELAPSED=$(( SECONDS - SCRIPT_START_SECONDS ))
echo "[$(date +%H:%M:%S)] [$LABEL] Completed at $(date) — total time: ${ELAPSED}s"
echo "Created: $OUTPUT_FILE"
