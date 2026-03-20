#!/usr/bin/env bash
# Description: Exports CI/CD pipeline enforcement status including GitOps and Tekton operator presence and ArgoCD application details
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

echo "cluster_name,cluster_context,cluster_server,gitops_installed,gitops_namespace,pipelines_installed,pipelines_namespace,app_name,app_project,app_source_repo,app_source_path,app_source_target_revision,app_destination_server,app_destination_namespace,app_sync_status,app_health_status,app_sync_policy,app_auto_prune,app_self_heal" > "$OUTPUT_FILE"

# --- Detect OpenShift GitOps (ArgoCD) ---
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

# --- Detect OpenShift Pipelines (Tekton) ---
PIPELINES_NS=""
for NS in openshift-pipelines tekton-pipelines; do
  if oc get namespace "$NS" >/dev/null 2>&1; then
    PIPELINES_NS="$NS"
    break
  fi
done

PIPELINES_INSTALLED="false"
if [ -n "$PIPELINES_NS" ]; then
  PIPELINES_INSTALLED="true"
fi

# --- Enumerate ArgoCD Applications across all namespaces ---
APPS_JSON=""
if [ "$GITOPS_INSTALLED" = "true" ]; then
  APPS_JSON=$(oc get applications.argoproj.io --all-namespaces -o json 2>/dev/null || echo '{"items":[]}')
fi

APP_COUNT=0
if [ -n "$APPS_JSON" ]; then
  APP_COUNT=$(echo "$APPS_JSON" | jq '.items | length')
fi

if [ "$APP_COUNT" -eq 0 ]; then
  # No ArgoCD applications — write a single summary row
  jq -rn \
    --arg cluster_name "$CLUSTER_NAME" \
    --arg cluster_context "$CLUSTER_CONTEXT" \
    --arg cluster_server "$CLUSTER_SERVER" \
    --arg gitops_installed "$GITOPS_INSTALLED" \
    --arg gitops_ns "$GITOPS_NS" \
    --arg pipelines_installed "$PIPELINES_INSTALLED" \
    --arg pipelines_ns "$PIPELINES_NS" '
    [
      $cluster_name,
      $cluster_context,
      $cluster_server,
      $gitops_installed,
      $gitops_ns,
      $pipelines_installed,
      $pipelines_ns,
      "",
      "",
      "",
      "",
      "",
      "",
      "",
      "",
      "",
      "",
      "",
      ""
    ] | @csv
  ' >> "$OUTPUT_FILE"
  echo "Created: $OUTPUT_FILE"
  exit 0
fi

# One row per ArgoCD Application
echo "$APPS_JSON" | jq -r \
  --arg cluster_name "$CLUSTER_NAME" \
  --arg cluster_context "$CLUSTER_CONTEXT" \
  --arg cluster_server "$CLUSTER_SERVER" \
  --arg gitops_installed "$GITOPS_INSTALLED" \
  --arg gitops_ns "$GITOPS_NS" \
  --arg pipelines_installed "$PIPELINES_INSTALLED" \
  --arg pipelines_ns "$PIPELINES_NS" '
  .items[] |
  [
    $cluster_name,
    $cluster_context,
    $cluster_server,
    $gitops_installed,
    $gitops_ns,
    $pipelines_installed,
    $pipelines_ns,
    (.metadata.name // ""),
    (.spec.project // ""),
    (.spec.source.repoURL // ""),
    (.spec.source.path // ""),
    (.spec.source.targetRevision // ""),
    (.spec.destination.server // ""),
    (.spec.destination.namespace // ""),
    (.status.sync.status // ""),
    (.status.health.status // ""),
    (if .spec.syncPolicy.automated then "automated" else "manual" end),
    (if .spec.syncPolicy.automated.prune then "true" else "false" end),
    (if .spec.syncPolicy.automated.selfHeal then "true" else "false" end)
  ] | @csv
' >> "$OUTPUT_FILE"

echo "Created: $OUTPUT_FILE"
