#!/usr/bin/env bash
# Description: Discovers governance and policy tooling deployed on the cluster — Gatekeeper, Kyverno, Compliance Operator, ACS/StackRox, ACM, Quay, and image policy
# Audit Area:  Governance & Policy Ecosystem
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

LABEL="governance-ecosystem"
SCRIPT_START_SECONDS=$SECONDS

RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "[$LABEL] Starting export at $(date)"

OUTPUT_FILE="$OUTPUT_DIR/governance-policy-ecosystem-${CLUSTER_NAME_SAFE}-$TIMESTAMP.csv"

echo "cluster_name,cluster_context,cluster_server,record_type,product_name,installed,namespace,operator_version,detail_1,detail_2,detail_3" > "$OUTPUT_FILE"

PRODUCTS_DETECTED=0
PRODUCTS_CHECKED=0

# ── Helper: write a CSV row ──────────────────────────────────────────────────
write_row() {
  local record_type="$1" product_name="$2" installed="$3" namespace="$4" operator_version="$5" detail_1="$6" detail_2="$7" detail_3="$8"
  jq -rn \
    --arg cluster_name "$CLUSTER_NAME" \
    --arg cluster_context "$CLUSTER_CONTEXT" \
    --arg cluster_server "$CLUSTER_SERVER" \
    --arg record_type "$record_type" \
    --arg product_name "$product_name" \
    --arg installed "$installed" \
    --arg namespace "$namespace" \
    --arg operator_version "$operator_version" \
    --arg detail_1 "$detail_1" \
    --arg detail_2 "$detail_2" \
    --arg detail_3 "$detail_3" \
    '[$cluster_name,$cluster_context,$cluster_server,$record_type,$product_name,$installed,$namespace,$operator_version,$detail_1,$detail_2,$detail_3] | @csv' \
    >> "$OUTPUT_FILE"
}

# ── Helper: find operator CSV version in a namespace ─────────────────────────
get_operator_csv_version() {
  local ns="$1" name_pattern="$2"
  local csv_version=""
  csv_version=$(oc get csv -n "$ns" -o json 2>/dev/null | tr -d '\r' | \
    jq -r --arg pattern "$name_pattern" '
      [.items[] | select(.metadata.name | test($pattern; "i"))] |
      sort_by(.metadata.creationTimestamp) | last |
      .spec.version // ""
    ' 2>/dev/null || echo "")
  echo "$csv_version"
}

# ═══════════════════════════════════════════════════════════════════════════════
# Section 1: OPA Gatekeeper
# ═══════════════════════════════════════════════════════════════════════════════
PRODUCTS_CHECKED=$((PRODUCTS_CHECKED + 1))
echo "[$LABEL] Checking OPA Gatekeeper..."

GK_INSTALLED="false"
GK_NS=""
GK_VERSION=""
GK_TEMPLATES="0"
GK_CONSTRAINTS="0"
GK_ENFORCEMENT=""

# Detect Gatekeeper namespace
for NS in openshift-gatekeeper-system gatekeeper-system; do
  if oc get namespace "$NS" >/dev/null 2>&1; then
    GK_NS="$NS"
    GK_INSTALLED="true"
    PRODUCTS_DETECTED=$((PRODUCTS_DETECTED + 1))
    break
  fi
done

if [ "$GK_INSTALLED" = "true" ]; then
  GK_VERSION=$(get_operator_csv_version "$GK_NS" "gatekeeper")
  # Count ConstraintTemplates
  if oc get crd constrainttemplates.templates.gatekeeper.sh >/dev/null 2>&1; then
    GK_TEMPLATES=$(oc get constrainttemplates -o json 2>/dev/null | tr -d '\r' | \
      jq '.items | length' 2>/dev/null || echo "0")
    # Count total constraints across all templates
    TEMPLATE_NAMES=$(oc get constrainttemplates -o json 2>/dev/null | tr -d '\r' | \
      jq -r '.items[].metadata.name' 2>/dev/null || echo "")
    TOTAL_CONSTRAINTS=0
    DENY_COUNT=0
    WARN_COUNT=0
    DRYRUN_COUNT=0
    if [ -n "$TEMPLATE_NAMES" ]; then
      while IFS= read -r TNAME; do
        [ -z "$TNAME" ] && continue
        CONSTRAINT_JSON=$(oc get "$TNAME" -o json 2>/dev/null | tr -d '\r' || echo '{"items":[]}')
        COUNT=$(echo "$CONSTRAINT_JSON" | jq '.items | length' 2>/dev/null || echo "0")
        TOTAL_CONSTRAINTS=$((TOTAL_CONSTRAINTS + COUNT))
        D=$(echo "$CONSTRAINT_JSON" | jq '[.items[] | select(.spec.enforcementAction == "deny" or .spec.enforcementAction == null)] | length' 2>/dev/null || echo "0")
        W=$(echo "$CONSTRAINT_JSON" | jq '[.items[] | select(.spec.enforcementAction == "warn")] | length' 2>/dev/null || echo "0")
        DR=$(echo "$CONSTRAINT_JSON" | jq '[.items[] | select(.spec.enforcementAction == "dryrun")] | length' 2>/dev/null || echo "0")
        DENY_COUNT=$((DENY_COUNT + D))
        WARN_COUNT=$((WARN_COUNT + W))
        DRYRUN_COUNT=$((DRYRUN_COUNT + DR))
      done <<< "$TEMPLATE_NAMES"
    fi
    GK_CONSTRAINTS="$TOTAL_CONSTRAINTS"
    GK_ENFORCEMENT="deny:${DENY_COUNT};warn:${WARN_COUNT};dryrun:${DRYRUN_COUNT}"
  fi
  echo "[$LABEL]   Gatekeeper found in $GK_NS — $GK_TEMPLATES templates, $GK_CONSTRAINTS constraints"
else
  echo "[$LABEL]   Gatekeeper not detected"
fi

write_row "policy_engine" "gatekeeper" "$GK_INSTALLED" "$GK_NS" "$GK_VERSION" \
  "templates:$GK_TEMPLATES" "constraints:$GK_CONSTRAINTS" "$GK_ENFORCEMENT"
echo "[$LABEL] Gatekeeper done."

# ═══════════════════════════════════════════════════════════════════════════════
# Section 2: Kyverno
# ═══════════════════════════════════════════════════════════════════════════════
PRODUCTS_CHECKED=$((PRODUCTS_CHECKED + 1))
echo "[$LABEL] Checking Kyverno..."

KV_INSTALLED="false"
KV_NS=""
KV_VERSION=""
KV_CLUSTER_POLICIES="0"
KV_POLICIES="0"
KV_ENFORCEMENT=""

# Check CRD existence first
if oc get crd clusterpolicies.kyverno.io >/dev/null 2>&1; then
  # Find Kyverno namespace
  for NS in kyverno openshift-kyverno; do
    if oc get namespace "$NS" >/dev/null 2>&1; then
      KV_NS="$NS"
      break
    fi
  done
  KV_INSTALLED="true"
  PRODUCTS_DETECTED=$((PRODUCTS_DETECTED + 1))
  KV_VERSION=$(get_operator_csv_version "${KV_NS:-kyverno}" "kyverno")

  # Count ClusterPolicies
  KV_CLUSTER_POLICIES=$(oc get clusterpolicies.kyverno.io -o json 2>/dev/null | tr -d '\r' | \
    jq '.items | length' 2>/dev/null || echo "0")

  # Count namespace-scoped Policies
  KV_POLICIES=$(oc get policies.kyverno.io -A -o json 2>/dev/null | tr -d '\r' | \
    jq '.items | length' 2>/dev/null || echo "0")

  # Enforcement breakdown for ClusterPolicies
  ENFORCE_COUNT=$(oc get clusterpolicies.kyverno.io -o json 2>/dev/null | tr -d '\r' | \
    jq '[.items[] | select(.spec.validationFailureAction == "Enforce" or .spec.validationFailureAction == "enforce")] | length' 2>/dev/null || echo "0")
  AUDIT_COUNT=$(oc get clusterpolicies.kyverno.io -o json 2>/dev/null | tr -d '\r' | \
    jq '[.items[] | select(.spec.validationFailureAction == "Audit" or .spec.validationFailureAction == "audit" or .spec.validationFailureAction == null)] | length' 2>/dev/null || echo "0")
  KV_ENFORCEMENT="enforce:${ENFORCE_COUNT};audit:${AUDIT_COUNT}"

  echo "[$LABEL]   Kyverno found — $KV_CLUSTER_POLICIES cluster policies, $KV_POLICIES namespace policies"
else
  echo "[$LABEL]   Kyverno not detected"
fi

write_row "policy_engine" "kyverno" "$KV_INSTALLED" "$KV_NS" "$KV_VERSION" \
  "cluster_policies:$KV_CLUSTER_POLICIES" "namespace_policies:$KV_POLICIES" "$KV_ENFORCEMENT"
echo "[$LABEL] Kyverno done."

# ═══════════════════════════════════════════════════════════════════════════════
# Section 3: Compliance Operator
# ═══════════════════════════════════════════════════════════════════════════════
PRODUCTS_CHECKED=$((PRODUCTS_CHECKED + 1))
echo "[$LABEL] Checking Compliance Operator..."

CO_INSTALLED="false"
CO_NS=""
CO_VERSION=""
CO_SUITES="0"
CO_PROFILES=""
CO_STATUS=""

if oc get crd compliancesuites.compliance.openshift.io >/dev/null 2>&1; then
  # Find namespace
  for NS in openshift-compliance compliance-operator; do
    if oc get namespace "$NS" >/dev/null 2>&1; then
      CO_NS="$NS"
      break
    fi
  done
  CO_INSTALLED="true"
  PRODUCTS_DETECTED=$((PRODUCTS_DETECTED + 1))
  CO_VERSION=$(get_operator_csv_version "${CO_NS:-openshift-compliance}" "compliance")

  # Count ComplianceSuites
  CO_SUITES=$(oc get compliancesuites -A -o json 2>/dev/null | tr -d '\r' | \
    jq '.items | length' 2>/dev/null || echo "0")

  # Get suite names + statuses + profile references
  SUITE_JSON=$(oc get compliancesuites -A -o json 2>/dev/null | tr -d '\r' || echo '{"items":[]}')

  CO_STATUS=$(echo "$SUITE_JSON" | jq -r '
    [.items[] | "\(.metadata.name)=\(.status.phase // "Unknown")"] | join(";")
  ' 2>/dev/null || echo "")

  CO_PROFILES=$(echo "$SUITE_JSON" | jq -r '
    [.items[].spec.scans[]? | .profile // empty] | unique | join(";")
  ' 2>/dev/null || echo "")

  echo "[$LABEL]   Compliance Operator found — $CO_SUITES suites, profiles: ${CO_PROFILES:-none}"
else
  echo "[$LABEL]   Compliance Operator not detected"
fi

write_row "compliance_framework" "compliance-operator" "$CO_INSTALLED" "$CO_NS" "$CO_VERSION" \
  "suites:$CO_SUITES" "profiles:$CO_PROFILES" "status:$CO_STATUS"
echo "[$LABEL] Compliance Operator done."

# ═══════════════════════════════════════════════════════════════════════════════
# Section 4: Red Hat ACS / StackRox
# ═══════════════════════════════════════════════════════════════════════════════
PRODUCTS_CHECKED=$((PRODUCTS_CHECKED + 1))
echo "[$LABEL] Checking Red Hat ACS (StackRox)..."

ACS_INSTALLED="false"
ACS_NS=""
ACS_VERSION=""
ACS_CENTRAL=""
ACS_SENSOR=""

# Check for ACS namespaces
for NS in stackrox rhacs-operator openshift-acs; do
  if oc get namespace "$NS" >/dev/null 2>&1; then
    ACS_NS="${ACS_NS:+${ACS_NS};}$NS"
  fi
done

if [ -n "$ACS_NS" ]; then
  ACS_INSTALLED="true"
  PRODUCTS_DETECTED=$((PRODUCTS_DETECTED + 1))
  # Use the first found namespace for version lookup
  FIRST_NS="${ACS_NS%%;*}"
  ACS_VERSION=$(get_operator_csv_version "$FIRST_NS" "rhacs\\|stackrox\\|advanced-cluster-security")

  # Check Central deployment status
  if oc get crd centrals.platform.stackrox.io >/dev/null 2>&1; then
    ACS_CENTRAL=$(oc get centrals -A -o json 2>/dev/null | tr -d '\r' | \
      jq -r '[.items[] | "\(.metadata.namespace)/\(.metadata.name)"] | join(";")' 2>/dev/null || echo "")
  fi

  # Check Sensor/SecuredCluster
  if oc get crd securedclusters.platform.stackrox.io >/dev/null 2>&1; then
    ACS_SENSOR=$(oc get securedclusters -A -o json 2>/dev/null | tr -d '\r' | \
      jq -r '[.items[] | "\(.metadata.namespace)/\(.metadata.name)"] | join(";")' 2>/dev/null || echo "")
  fi

  echo "[$LABEL]   ACS/StackRox found in: $ACS_NS"
else
  echo "[$LABEL]   ACS/StackRox not detected"
fi

write_row "runtime_security" "acs-stackrox" "$ACS_INSTALLED" "$ACS_NS" "$ACS_VERSION" \
  "centrals:${ACS_CENTRAL:-none}" "secured_clusters:${ACS_SENSOR:-none}" ""
echo "[$LABEL] ACS/StackRox done."

# ═══════════════════════════════════════════════════════════════════════════════
# Section 5: Advanced Cluster Management (ACM)
# ═══════════════════════════════════════════════════════════════════════════════
PRODUCTS_CHECKED=$((PRODUCTS_CHECKED + 1))
echo "[$LABEL] Checking Advanced Cluster Management (ACM)..."

ACM_INSTALLED="false"
ACM_NS=""
ACM_VERSION=""
ACM_POLICIES="0"
ACM_POLICY_SETS="0"

if oc get crd policies.policy.open-cluster-management.io >/dev/null 2>&1; then
  # Find ACM namespace
  for NS in open-cluster-management multicluster-engine; do
    if oc get namespace "$NS" >/dev/null 2>&1; then
      ACM_NS="$NS"
      break
    fi
  done
  ACM_INSTALLED="true"
  PRODUCTS_DETECTED=$((PRODUCTS_DETECTED + 1))
  ACM_VERSION=$(get_operator_csv_version "${ACM_NS:-open-cluster-management}" "advanced-cluster-management")

  # Count policies
  ACM_POLICIES=$(oc get policies.policy.open-cluster-management.io -A -o json 2>/dev/null | tr -d '\r' | \
    jq '.items | length' 2>/dev/null || echo "0")

  # Count PolicySets if CRD exists
  if oc get crd policysets.policy.open-cluster-management.io >/dev/null 2>&1; then
    ACM_POLICY_SETS=$(oc get policysets.policy.open-cluster-management.io -A -o json 2>/dev/null | tr -d '\r' | \
      jq '.items | length' 2>/dev/null || echo "0")
  fi

  echo "[$LABEL]   ACM found — $ACM_POLICIES policies, $ACM_POLICY_SETS policy sets"
else
  echo "[$LABEL]   ACM not detected"
fi

write_row "multicluster_governance" "acm" "$ACM_INSTALLED" "$ACM_NS" "$ACM_VERSION" \
  "policies:$ACM_POLICIES" "policy_sets:$ACM_POLICY_SETS" ""
echo "[$LABEL] ACM done."

# ═══════════════════════════════════════════════════════════════════════════════
# Section 6: Quay Operator
# ═══════════════════════════════════════════════════════════════════════════════
PRODUCTS_CHECKED=$((PRODUCTS_CHECKED + 1))
echo "[$LABEL] Checking Quay Operator..."

QUAY_INSTALLED="false"
QUAY_NS=""
QUAY_VERSION=""
QUAY_REGISTRIES="0"

if oc get crd quayregistries.quay.redhat.com >/dev/null 2>&1; then
  for NS in openshift-quay quay-enterprise; do
    if oc get namespace "$NS" >/dev/null 2>&1; then
      QUAY_NS="$NS"
      break
    fi
  done
  QUAY_INSTALLED="true"
  PRODUCTS_DETECTED=$((PRODUCTS_DETECTED + 1))
  QUAY_VERSION=$(get_operator_csv_version "${QUAY_NS:-openshift-quay}" "quay")

  QUAY_REGISTRIES=$(oc get quayregistries -A -o json 2>/dev/null | tr -d '\r' | \
    jq '.items | length' 2>/dev/null || echo "0")

  echo "[$LABEL]   Quay found — $QUAY_REGISTRIES registries"
else
  echo "[$LABEL]   Quay Operator not detected"
fi

write_row "image_registry" "quay" "$QUAY_INSTALLED" "$QUAY_NS" "$QUAY_VERSION" \
  "registries:$QUAY_REGISTRIES" "" ""
echo "[$LABEL] Quay done."

# ═══════════════════════════════════════════════════════════════════════════════
# Section 7: Image Policy (image.config.openshift.io)
# ═══════════════════════════════════════════════════════════════════════════════
PRODUCTS_CHECKED=$((PRODUCTS_CHECKED + 1))
echo "[$LABEL] Checking image policy configuration..."

IMG_ALLOWED=""
IMG_BLOCKED=""
IMG_INSECURE=""
IMG_CONFIGURED="false"

IMAGE_JSON=$(oc get image.config.openshift.io cluster -o json 2>/dev/null | tr -d '\r' || echo '{}')

IMG_ALLOWED=$(echo "$IMAGE_JSON" | jq -r '
  [.spec.registrySources.allowedRegistries // [] | .[]] | join(";")
' 2>/dev/null || echo "")

IMG_BLOCKED=$(echo "$IMAGE_JSON" | jq -r '
  [.spec.registrySources.blockedRegistries // [] | .[]] | join(";")
' 2>/dev/null || echo "")

IMG_INSECURE=$(echo "$IMAGE_JSON" | jq -r '
  [.spec.registrySources.insecureRegistries // [] | .[]] | join(";")
' 2>/dev/null || echo "")

if [ -n "$IMG_ALLOWED" ] || [ -n "$IMG_BLOCKED" ]; then
  IMG_CONFIGURED="true"
  echo "[$LABEL]   Image policy configured — allowed: ${IMG_ALLOWED:-none}, blocked: ${IMG_BLOCKED:-none}"
else
  echo -e "${YELLOW}[$LABEL]   WARNING: No image registry allow/block lists configured${NC}"
fi

write_row "image_policy" "image-config" "$IMG_CONFIGURED" "" "" \
  "allowed:${IMG_ALLOWED:-none}" "blocked:${IMG_BLOCKED:-none}" "insecure:${IMG_INSECURE:-none}"
echo "[$LABEL] Image policy done."

# ═══════════════════════════════════════════════════════════════════════════════
# Summary
# ═══════════════════════════════════════════════════════════════════════════════
echo ""
echo "[$LABEL] ┌──────────────────────────────────────────┐"
echo "[$LABEL] │     Governance Ecosystem Summary          │"
echo "[$LABEL] ├──────────────────────────────────────────┤"
echo "[$LABEL] │  Products checked:  $PRODUCTS_CHECKED                      │"
echo "[$LABEL] │  Products detected: $PRODUCTS_DETECTED                      │"
echo "[$LABEL] ├──────────────────────────────────────────┤"

if [ "$GK_INSTALLED" = "true" ]; then
  echo "[$LABEL] │  ✓ Gatekeeper      ($GK_CONSTRAINTS constraints)"
else
  echo "[$LABEL] │  ✗ Gatekeeper       not installed"
fi
if [ "$KV_INSTALLED" = "true" ]; then
  echo "[$LABEL] │  ✓ Kyverno          ($KV_CLUSTER_POLICIES cluster policies)"
else
  echo "[$LABEL] │  ✗ Kyverno          not installed"
fi
if [ "$CO_INSTALLED" = "true" ]; then
  echo "[$LABEL] │  ✓ Compliance Op    ($CO_SUITES suites)"
else
  echo "[$LABEL] │  ✗ Compliance Op    not installed"
fi
if [ "$ACS_INSTALLED" = "true" ]; then
  echo "[$LABEL] │  ✓ ACS/StackRox     detected"
else
  echo "[$LABEL] │  ✗ ACS/StackRox     not installed"
fi
if [ "$ACM_INSTALLED" = "true" ]; then
  echo "[$LABEL] │  ✓ ACM              ($ACM_POLICIES policies)"
else
  echo "[$LABEL] │  ✗ ACM              not installed"
fi
if [ "$QUAY_INSTALLED" = "true" ]; then
  echo "[$LABEL] │  ✓ Quay             ($QUAY_REGISTRIES registries)"
else
  echo "[$LABEL] │  ✗ Quay             not installed"
fi
if [ "$IMG_CONFIGURED" = "true" ]; then
  echo "[$LABEL] │  ✓ Image Policy     configured"
else
  echo "[$LABEL] │  ✗ Image Policy     not configured"
fi

echo "[$LABEL] └──────────────────────────────────────────┘"

# Critical warnings
if [ "$GK_INSTALLED" = "false" ] && [ "$KV_INSTALLED" = "false" ]; then
  echo -e "${RED}[$LABEL] CRITICAL: No policy engine detected (Gatekeeper or Kyverno) — cluster has no admission policy enforcement${NC}"
fi

if [ "$CO_INSTALLED" = "false" ]; then
  echo -e "${YELLOW}[$LABEL] WARNING: Compliance Operator not detected — no automated compliance scanning${NC}"
fi

if [ "$ACS_INSTALLED" = "false" ]; then
  echo -e "${YELLOW}[$LABEL] WARNING: ACS/StackRox not detected — no runtime security enforcement${NC}"
fi

if [ "$PRODUCTS_DETECTED" -eq 0 ]; then
  echo -e "${RED}[$LABEL] CRITICAL: Zero governance products detected — cluster has no policy tooling${NC}"
fi

ELAPSED=$(( SECONDS - SCRIPT_START_SECONDS ))
echo ""
echo "[$LABEL] Completed at $(date) — total time: ${ELAPSED}s"
echo "Created: $OUTPUT_FILE"
