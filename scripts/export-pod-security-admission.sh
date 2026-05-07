#!/usr/bin/env bash
# Description: Exports per-namespace Pod Security Admission (PSA) labels — pod-security.kubernetes.io/{enforce,audit,warn} levels and versions — for OCP-43 Pod Security Context auditing
# Audit Area:  Pod Security Context (PSA)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./common.sh
source "$SCRIPT_DIR/common.sh"

SCRIPT_START_SECONDS=$SECONDS
LABEL="psa"
RED='\033[0;31m'
NC='\033[0m' # No Color

: "${CLUSTER_NAME_SAFE:?CLUSTER_NAME_SAFE is not set}"
: "${CLUSTER_NAME:?CLUSTER_NAME is not set}"
: "${CLUSTER_CONTEXT:?CLUSTER_CONTEXT is not set}"
: "${CLUSTER_SERVER:?CLUSTER_SERVER is not set}"
: "${OUTPUT_DIR:?OUTPUT_DIR is not set}"
: "${TIMESTAMP:?TIMESTAMP is not set}"

echo "[$(date +%H:%M:%S)] [$LABEL] Starting export at $(date)"

OUTPUT_FILE="$OUTPUT_DIR/pod-security-admission-${CLUSTER_NAME_SAFE}-$TIMESTAMP.csv"

echo "cluster_name,cluster_context,cluster_server,namespace,is_system_namespace,enforce_level,enforce_version,audit_level,audit_version,warn_level,warn_version" > "$OUTPUT_FILE"

echo "[$(date +%H:%M:%S)] [$LABEL] Fetching all namespaces..."
if ! NS_JSON=$(oc get ns -o json 2>/dev/null); then
  echo -e "${RED}[$(date +%H:%M:%S)] [$LABEL] ERROR: cannot list namespaces${NC}"
  ELAPSED=$(( SECONDS - SCRIPT_START_SECONDS ))
  echo "[$(date +%H:%M:%S)] [$LABEL] Completed at $(date) — total time: ${ELAPSED}s"
  echo "Created: $OUTPUT_FILE"
  exit 0
fi

TOTAL=$(echo "$NS_JSON" | jq '.items | length')
echo "[$(date +%H:%M:%S)] [$LABEL] Processing $TOTAL namespaces..."

echo "$NS_JSON" | jq -r \
  --arg cluster_name "$CLUSTER_NAME" \
  --arg cluster_context "$CLUSTER_CONTEXT" \
  --arg cluster_server "$CLUSTER_SERVER" '
  .items[] |
  (.metadata.name // "") as $ns |
  (.metadata.labels // {}) as $l |
  [
    $cluster_name,
    $cluster_context,
    $cluster_server,
    $ns,
    (if ($ns | test("^(openshift|kube|default$)")) then "true" else "false" end),
    ($l["pod-security.kubernetes.io/enforce"] // ""),
    ($l["pod-security.kubernetes.io/enforce-version"] // ""),
    ($l["pod-security.kubernetes.io/audit"] // ""),
    ($l["pod-security.kubernetes.io/audit-version"] // ""),
    ($l["pod-security.kubernetes.io/warn"] // ""),
    ($l["pod-security.kubernetes.io/warn-version"] // "")
  ] | @csv
' >> "$OUTPUT_FILE"

# ── Summary ──────────────────────────────────────────────────────────────────
USER_NS=$(echo "$NS_JSON" | jq '[.items[] | select((.metadata.name // "") | test("^(openshift|kube|default$)") | not)] | length')
USER_RESTRICTED=$(echo "$NS_JSON" | jq '[.items[] | select((.metadata.name // "") | test("^(openshift|kube|default$)") | not) | select((.metadata.labels["pod-security.kubernetes.io/enforce"] // "") == "restricted")] | length')
USER_PRIVILEGED=$(echo "$NS_JSON" | jq '[.items[] | select((.metadata.name // "") | test("^(openshift|kube|default$)") | not) | select((.metadata.labels["pod-security.kubernetes.io/enforce"] // "") == "privileged")] | length')
USER_UNSET=$(echo "$NS_JSON" | jq '[.items[] | select((.metadata.name // "") | test("^(openshift|kube|default$)") | not) | select((.metadata.labels["pod-security.kubernetes.io/enforce"] // "") == "")] | length')

echo ""
echo "┌──────────────────────────────────────────────────────┐"
echo "│ Pod Security Admission Summary (user namespaces)     │"
echo "├──────────────────────────────────────────────────────┤"
echo "│ User namespaces                : $USER_NS"
echo "│ enforce=restricted             : $USER_RESTRICTED"
echo "│ enforce=privileged             : $USER_PRIVILEGED"
echo "│ enforce label unset            : $USER_UNSET"
echo "└──────────────────────────────────────────────────────┘"
echo ""

if [ "$USER_PRIVILEGED" -gt 0 ]; then
  echo -e "${RED}[$(date +%H:%M:%S)] [$LABEL] WARNING: $USER_PRIVILEGED user namespace(s) have enforce=privileged${NC}"
fi
if [ "$USER_UNSET" -gt 0 ]; then
  echo -e "${RED}[$(date +%H:%M:%S)] [$LABEL] WARNING: $USER_UNSET user namespace(s) have no PSA enforce label${NC}"
fi

ELAPSED=$(( SECONDS - SCRIPT_START_SECONDS ))
echo "[$(date +%H:%M:%S)] [$LABEL] Completed at $(date) — total time: ${ELAPSED}s"
echo "Created: $OUTPUT_FILE"
