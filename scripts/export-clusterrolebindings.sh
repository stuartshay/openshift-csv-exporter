#!/usr/bin/env bash
# Description: Exports all ClusterRoleBindings with their subjects
# Audit Area:  Granular Role-Based Access Controls
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./common.sh
source "$SCRIPT_DIR/common.sh"

SCRIPT_START_SECONDS=$SECONDS
LABEL="clusterrolebindings"
RED='\033[0;31m'
NC='\033[0m' # No Color

: "${CLUSTER_NAME_SAFE:?CLUSTER_NAME_SAFE is not set}"
: "${CLUSTER_NAME:?CLUSTER_NAME is not set}"
: "${CLUSTER_CONTEXT:?CLUSTER_CONTEXT is not set}"
: "${CLUSTER_SERVER:?CLUSTER_SERVER is not set}"
: "${OUTPUT_DIR:?OUTPUT_DIR is not set}"
: "${TIMESTAMP:?TIMESTAMP is not set}"

echo "[$(date +%H:%M:%S)] [$LABEL] Starting export at $(date)"

OUTPUT_FILE="$OUTPUT_DIR/clusterrolebindings-${CLUSTER_NAME_SAFE}-$TIMESTAMP.csv"

echo "cluster_name,cluster_context,cluster_server,binding_name,role_ref_kind,role_ref_name,subject_kind,subject_name,subject_namespace" > "$OUTPUT_FILE"

echo "[$(date +%H:%M:%S)] [$LABEL] Fetching clusterrolebindings..."
BINDINGS_JSON=$(oc get clusterrolebindings -o json | tr -d '\r')

echo "[$(date +%H:%M:%S)] [$LABEL] Processing clusterrolebindings..."
echo "$BINDINGS_JSON" | jq -r \
  --arg cluster_name "$CLUSTER_NAME" \
  --arg cluster_context "$CLUSTER_CONTEXT" \
  --arg cluster_server "$CLUSTER_SERVER" '
  .items[] as $crb
  | if (($crb.subjects // []) | length) > 0 then
      $crb.subjects[] |
      [
        $cluster_name,
        $cluster_context,
        $cluster_server,
        ($crb.metadata.name // ""),
        ($crb.roleRef.kind // ""),
        ($crb.roleRef.name // ""),
        (.kind // ""),
        (.name // ""),
        (.namespace // "")
      ] | @csv
    else
      [
        $cluster_name,
        $cluster_context,
        $cluster_server,
        ($crb.metadata.name // ""),
        ($crb.roleRef.kind // ""),
        ($crb.roleRef.name // ""),
        "",
        "",
        ""
      ] | @csv
    end
' >> "$OUTPUT_FILE"

# ── Summary ──────────────────────────────────────────────────────────────────
TOTAL_BINDINGS=$(echo "$BINDINGS_JSON" | jq '[.items[]] | length')
CLUSTER_ADMIN_BINDINGS=$(echo "$BINDINGS_JSON" | jq '[.items[] | select(.roleRef.name == "cluster-admin")] | length')
USER_SUBJECTS=$(echo "$BINDINGS_JSON" | jq '[.items[] | (.subjects // [])[] | select(.kind == "User")] | length')
GROUP_SUBJECTS=$(echo "$BINDINGS_JSON" | jq '[.items[] | (.subjects // [])[] | select(.kind == "Group")] | length')
SA_SUBJECTS=$(echo "$BINDINGS_JSON" | jq '[.items[] | (.subjects // [])[] | select(.kind == "ServiceAccount")] | length')
SYSTEM_MASTERS=$(echo "$BINDINGS_JSON" | jq '[.items[] | (.subjects // [])[] | select(.kind == "Group" and .name == "system:masters")] | length')

echo "[$(date +%H:%M:%S)] [$LABEL] Processing done."
echo ""
echo "┌──────────────────────────────────────────────────────┐"
echo "│ ClusterRoleBindings Summary                          │"
echo "├──────────────────────────────────────────────────────┤"
echo "│ Total ClusterRoleBindings      : $TOTAL_BINDINGS"
echo "│ Bindings to cluster-admin      : $CLUSTER_ADMIN_BINDINGS"
echo "│ User subjects                  : $USER_SUBJECTS"
echo "│ Group subjects                 : $GROUP_SUBJECTS"
echo "│ ServiceAccount subjects        : $SA_SUBJECTS"
echo "│ system:masters group refs      : $SYSTEM_MASTERS"
echo "└──────────────────────────────────────────────────────┘"
echo ""

# ── Critical warnings ────────────────────────────────────────────────────────
if [ "$CLUSTER_ADMIN_BINDINGS" -gt 0 ]; then
  echo -e "${RED}[$(date +%H:%M:%S)] [$LABEL] WARNING: $CLUSTER_ADMIN_BINDINGS binding(s) grant cluster-admin — review each for least-privilege compliance${NC}"
fi

if [ "$SYSTEM_MASTERS" -gt 0 ]; then
  echo -e "${RED}[$(date +%H:%M:%S)] [$LABEL] WARNING: $SYSTEM_MASTERS reference(s) to system:masters group — this group bypasses all RBAC and admission controls${NC}"
fi

NON_SYSTEM_CA=$(echo "$BINDINGS_JSON" | jq '[.items[] | select(.roleRef.name == "cluster-admin") | (.subjects // [])[] | select(.name | startswith("system:") | not)] | length')
if [ "$NON_SYSTEM_CA" -gt 0 ]; then
  echo -e "${RED}[$(date +%H:%M:%S)] [$LABEL] WARNING: $NON_SYSTEM_CA non-system subject(s) bound to cluster-admin — verify each is authorized${NC}"
fi

ELAPSED=$(( SECONDS - SCRIPT_START_SECONDS ))
echo "[$(date +%H:%M:%S)] [$LABEL] Completed at $(date) — total time: ${ELAPSED}s"
echo "Created: $OUTPUT_FILE"
