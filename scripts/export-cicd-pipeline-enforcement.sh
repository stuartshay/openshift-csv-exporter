#!/usr/bin/env bash
# Description: Exports CI/CD pipeline enforcement status — detects in-cluster GitOps, Tekton, Flux, and external CI/CD service accounts
# Audit Area:  CI/CD Pipeline Enforcement
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

OUTPUT_FILE="$OUTPUT_DIR/cicd-pipeline-enforcement-${CLUSTER_NAME_SAFE}-$TIMESTAMP.csv"

echo "cluster_name,cluster_context,cluster_server,detection_type,tool_name,installed,namespace,resource_name,detail_1,detail_2,detail_3,detail_4,detail_5,detail_6" > "$OUTPUT_FILE"

WROTE_ROWS="false"

# =============================================================================
# 1) ArgoCD / OpenShift GitOps
# =============================================================================
GITOPS_NS=""
for NS in openshift-gitops gitops-system argocd; do
  if oc get namespace "$NS" >/dev/null 2>&1; then
    GITOPS_NS="$NS"
    break
  fi
done

GITOPS_INSTALLED="false"
if [ -n "$GITOPS_NS" ]; then
  GITOPS_INSTALLED="true"
fi

if [ "$GITOPS_INSTALLED" = "true" ]; then
  APPS_JSON=$(oc get applications.argoproj.io --all-namespaces -o json 2>/dev/null || echo '{"items":[]}')
  APP_COUNT=$(echo "$APPS_JSON" | jq '.items | length')

  if [ "$APP_COUNT" -eq 0 ]; then
    jq -rn \
      --arg cn "$CLUSTER_NAME" --arg cc "$CLUSTER_CONTEXT" --arg cs "$CLUSTER_SERVER" \
      --arg ns "$GITOPS_NS" '
      [$cn,$cc,$cs,"gitops","argocd","true",$ns,"","no applications found","","","","",""] | @csv
    ' >> "$OUTPUT_FILE"
    WROTE_ROWS="true"
  else
    echo "$APPS_JSON" | jq -r \
      --arg cn "$CLUSTER_NAME" --arg cc "$CLUSTER_CONTEXT" --arg cs "$CLUSTER_SERVER" \
      --arg ns "$GITOPS_NS" '
      .items[] |
      [
        $cn,$cc,$cs,
        "gitops","argocd","true",$ns,
        (.metadata.name // ""),
        ("repo=" + (.spec.source.repoURL // "")),
        ("path=" + (.spec.source.path // "")),
        ("revision=" + (.spec.source.targetRevision // "")),
        ("sync=" + (.status.sync.status // "")),
        ("health=" + (.status.health.status // "")),
        ("policy=" + (if .spec.syncPolicy.automated then "automated" else "manual" end))
      ] | @csv
    ' >> "$OUTPUT_FILE"
    WROTE_ROWS="true"
  fi
fi

# =============================================================================
# 2) Flux CD
# =============================================================================
FLUX_NS=""
if oc get namespace flux-system >/dev/null 2>&1; then
  FLUX_NS="flux-system"
fi

if [ -n "$FLUX_NS" ]; then
  # GitRepositories
  GITREPO_JSON=$(oc get gitrepositories.source.toolkit.fluxcd.io --all-namespaces -o json 2>/dev/null || echo '{"items":[]}')
  GITREPO_COUNT=$(echo "$GITREPO_JSON" | jq '.items | length')

  if [ "$GITREPO_COUNT" -gt 0 ]; then
    echo "$GITREPO_JSON" | jq -r \
      --arg cn "$CLUSTER_NAME" --arg cc "$CLUSTER_CONTEXT" --arg cs "$CLUSTER_SERVER" \
      --arg ns "$FLUX_NS" '
      .items[] |
      [
        $cn,$cc,$cs,
        "gitops","fluxcd","true",$ns,
        (.metadata.name // ""),
        ("type=GitRepository"),
        ("url=" + (.spec.url // "")),
        ("branch=" + (.spec.ref.branch // "")),
        ("ready=" + ((.status.conditions[]? | select(.type=="Ready") | .status) // "")),
        "",""
      ] | @csv
    ' >> "$OUTPUT_FILE"
    WROTE_ROWS="true"
  fi

  # Kustomizations
  KUST_JSON=$(oc get kustomizations.kustomize.toolkit.fluxcd.io --all-namespaces -o json 2>/dev/null || echo '{"items":[]}')
  KUST_COUNT=$(echo "$KUST_JSON" | jq '.items | length')

  if [ "$KUST_COUNT" -gt 0 ]; then
    echo "$KUST_JSON" | jq -r \
      --arg cn "$CLUSTER_NAME" --arg cc "$CLUSTER_CONTEXT" --arg cs "$CLUSTER_SERVER" \
      --arg ns "$FLUX_NS" '
      .items[] |
      [
        $cn,$cc,$cs,
        "gitops","fluxcd","true",$ns,
        (.metadata.name // ""),
        ("type=Kustomization"),
        ("source=" + (.spec.sourceRef.name // "")),
        ("path=" + (.spec.path // "")),
        ("ready=" + ((.status.conditions[]? | select(.type=="Ready") | .status) // "")),
        ("prune=" + (if .spec.prune then "true" else "false" end)),
        ""
      ] | @csv
    ' >> "$OUTPUT_FILE"
    WROTE_ROWS="true"
  fi

  # HelmReleases
  HELM_JSON=$(oc get helmreleases.helm.toolkit.fluxcd.io --all-namespaces -o json 2>/dev/null || echo '{"items":[]}')
  HELM_COUNT=$(echo "$HELM_JSON" | jq '.items | length')

  if [ "$HELM_COUNT" -gt 0 ]; then
    echo "$HELM_JSON" | jq -r \
      --arg cn "$CLUSTER_NAME" --arg cc "$CLUSTER_CONTEXT" --arg cs "$CLUSTER_SERVER" \
      --arg ns "$FLUX_NS" '
      .items[] |
      [
        $cn,$cc,$cs,
        "gitops","fluxcd","true",$ns,
        (.metadata.name // ""),
        ("type=HelmRelease"),
        ("chart=" + (.spec.chart.spec.chart // "")),
        ("version=" + (.spec.chart.spec.version // "")),
        ("ready=" + ((.status.conditions[]? | select(.type=="Ready") | .status) // "")),
        "",""
      ] | @csv
    ' >> "$OUTPUT_FILE"
    WROTE_ROWS="true"
  fi

  if [ "$WROTE_ROWS" = "false" ] || [ "$GITREPO_COUNT" -eq 0 ] && [ "$KUST_COUNT" -eq 0 ] && [ "$HELM_COUNT" -eq 0 ]; then
    jq -rn \
      --arg cn "$CLUSTER_NAME" --arg cc "$CLUSTER_CONTEXT" --arg cs "$CLUSTER_SERVER" \
      --arg ns "$FLUX_NS" '
      [$cn,$cc,$cs,"gitops","fluxcd","true",$ns,"","no flux resources found","","","","",""] | @csv
    ' >> "$OUTPUT_FILE"
    WROTE_ROWS="true"
  fi
fi

# =============================================================================
# 3) OpenShift Pipelines (Tekton)
# =============================================================================
PIPELINES_NS=""
for NS in openshift-pipelines tekton-pipelines; do
  if oc get namespace "$NS" >/dev/null 2>&1; then
    PIPELINES_NS="$NS"
    break
  fi
done

if [ -n "$PIPELINES_NS" ]; then
  jq -rn \
    --arg cn "$CLUSTER_NAME" --arg cc "$CLUSTER_CONTEXT" --arg cs "$CLUSTER_SERVER" \
    --arg ns "$PIPELINES_NS" '
    [$cn,$cc,$cs,"pipeline","tekton","true",$ns,"","operator namespace detected","","","","",""] | @csv
  ' >> "$OUTPUT_FILE"
  WROTE_ROWS="true"
fi

# =============================================================================
# 4) External CI/CD — detect via ClusterRoleBindings for CI/CD service accounts
# =============================================================================
CICD_PATTERNS="jenkins|gitlab|github-action|azure-devops|azure-pipelines|bamboo|circleci|travis|teamcity|concourse|drone|spinnaker|harness|cicd|ci-cd|deploy-bot|deployment-sa"

CRB_JSON=$(oc get clusterrolebindings -o json 2>/dev/null || echo '{"items":[]}')

echo "$CRB_JSON" | jq -r \
  --arg cn "$CLUSTER_NAME" --arg cc "$CLUSTER_CONTEXT" --arg cs "$CLUSTER_SERVER" \
  --arg pattern "$CICD_PATTERNS" '
  .items[] |
  . as $binding |
  (.subjects // [])[] |
  select(
    (.name | test($pattern; "i")) or
    ($binding.metadata.name | test($pattern; "i"))
  ) |
  [
    $cn,$cc,$cs,
    "external-cicd",
    "clusterrolebinding",
    "true",
    (.namespace // ""),
    $binding.metadata.name,
    ("role=" + ($binding.roleRef.name // "")),
    ("subject_kind=" + (.kind // "")),
    ("subject_name=" + (.name // "")),
    ("subject_ns=" + (.namespace // "")),
    "",""
  ] | @csv
' >> "$OUTPUT_FILE"

# Check if external CI/CD rows were actually written
EXT_COUNT=$(echo "$CRB_JSON" | jq \
  --arg pattern "$CICD_PATTERNS" '
  [.items[] |
   . as $binding |
   (.subjects // [])[] |
   select(
     (.name | test($pattern; "i")) or
     ($binding.metadata.name | test($pattern; "i"))
   )] | length
')

if [ "$EXT_COUNT" -gt 0 ]; then
  WROTE_ROWS="true"
fi

# =============================================================================
# 5) External CI/CD — detect via namespaces matching CI/CD tool names
# =============================================================================
CICD_NS_JSON=$(oc get namespaces -o json 2>/dev/null || echo '{"items":[]}')

echo "$CICD_NS_JSON" | jq -r \
  --arg cn "$CLUSTER_NAME" --arg cc "$CLUSTER_CONTEXT" --arg cs "$CLUSTER_SERVER" \
  --arg pattern "$CICD_PATTERNS" '
  .items[] |
  select(.metadata.name | test($pattern; "i")) |
  [
    $cn,$cc,$cs,
    "external-cicd",
    "namespace",
    "true",
    (.metadata.name // ""),
    (.metadata.name // ""),
    ("status=" + (.status.phase // "")),
    "",
    "",
    "",
    "",""
  ] | @csv
' >> "$OUTPUT_FILE"

CICD_NS_COUNT=$(echo "$CICD_NS_JSON" | jq \
  --arg pattern "$CICD_PATTERNS" '
  [.items[] | select(.metadata.name | test($pattern; "i"))] | length
')

if [ "$CICD_NS_COUNT" -gt 0 ]; then
  WROTE_ROWS="true"
fi

# =============================================================================
# Summary row if nothing was detected
# =============================================================================
if [ "$WROTE_ROWS" = "false" ]; then
  jq -rn \
    --arg cn "$CLUSTER_NAME" --arg cc "$CLUSTER_CONTEXT" --arg cs "$CLUSTER_SERVER" '
    [$cn,$cc,$cs,"none","none","false","","","no CI/CD tooling detected on cluster","","","","",""] | @csv
  ' >> "$OUTPUT_FILE"
fi

echo "Created: $OUTPUT_FILE"
