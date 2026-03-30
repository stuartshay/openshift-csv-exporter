#!/usr/bin/env bash
# Description: Exports ClusterRoleBindings that grant cluster-admin access
# Audit Area:  API & Console Access Restriction
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./common.sh
source "$SCRIPT_DIR/common.sh"

SCRIPT_START_SECONDS=$SECONDS
LABEL="cluster-admin-bindings"
RED='\033[0;31m'
NC='\033[0m' # No Color

: "${CLUSTER_NAME_SAFE:?CLUSTER_NAME_SAFE is not set}"
: "${CLUSTER_NAME:?CLUSTER_NAME is not set}"
: "${CLUSTER_CONTEXT:?CLUSTER_CONTEXT is not set}"
: "${CLUSTER_SERVER:?CLUSTER_SERVER is not set}"
: "${OUTPUT_DIR:?OUTPUT_DIR is not set}"
: "${TIMESTAMP:?TIMESTAMP is not set}"

echo "[$(date +%H:%M:%S)] [$LABEL] Starting export at $(date)"

OUTPUT_FILE="$OUTPUT_DIR/cluster-admin-bindings-${CLUSTER_NAME_SAFE}-$TIMESTAMP.csv"

echo "cluster_name,cluster_context,cluster_server,binding_name,role_ref_name,subject_kind,subject_name,subject_namespace,creation_timestamp" > "$OUTPUT_FILE"

echo "[$(date +%H:%M:%S)] [$LABEL] Fetching clusterrolebindings..."
BINDINGS_JSON=$(oc get clusterrolebindings -o json | tr -d '\r')

echo "[$(date +%H:%M:%S)] [$LABEL] Filtering cluster-admin bindings..."
echo "$BINDINGS_JSON" | jq -r \
  --arg cluster_name "$CLUSTER_NAME" \
  --arg cluster_context "$CLUSTER_CONTEXT" \
  --arg cluster_server "$CLUSTER_SERVER" '
  .items[]
  | select(.roleRef.name == "cluster-admin")
  | . as $crb
  | if (($crb.subjects // []) | length) > 0 then
      $crb.subjects[] |
      [
        $cluster_name,
        $cluster_context,
        $cluster_server,
        ($crb.metadata.name // ""),
        ($crb.roleRef.name // ""),
        (.kind // ""),
        (.name // ""),
        (.namespace // ""),
        ($crb.metadata.creationTimestamp // "")
      ] | @csv
    else
      [
        $cluster_name,
        $cluster_context,
        $cluster_server,
        ($crb.metadata.name // ""),
        ($crb.roleRef.name // ""),
        "",
        "",
        "",
        ($crb.metadata.creationTimestamp // "")
      ] | @csv
    end
' >> "$OUTPUT_FILE"

# ── Summary ──────────────────────────────────────────────────────────────────
TOTAL_BINDINGS=$(echo "$BINDINGS_JSON" | jq '[.items[] | select(.roleRef.name == "cluster-admin")] | length')
TOTAL_SUBJECTS=$(echo "$BINDINGS_JSON" | jq '[.items[] | select(.roleRef.name == "cluster-admin") | (.subjects // [])[] ] | length')
USER_SUBJECTS=$(echo "$BINDINGS_JSON" | jq '[.items[] | select(.roleRef.name == "cluster-admin") | (.subjects // [])[] | select(.kind == "User")] | length')
GROUP_SUBJECTS=$(echo "$BINDINGS_JSON" | jq '[.items[] | select(.roleRef.name == "cluster-admin") | (.subjects // [])[] | select(.kind == "Group")] | length')
SA_SUBJECTS=$(echo "$BINDINGS_JSON" | jq '[.items[] | select(.roleRef.name == "cluster-admin") | (.subjects // [])[] | select(.kind == "ServiceAccount")] | length')
NON_SYSTEM=$(echo "$BINDINGS_JSON" | jq '[.items[] | select(.roleRef.name == "cluster-admin") | (.subjects // [])[] | select(.name | startswith("system:") | not)] | length')

echo "[$(date +%H:%M:%S)] [$LABEL] Processing done."
echo ""
echo "┌──────────────────────────────────────────────────────┐"
echo "│ Cluster-Admin Bindings Summary                       │"
echo "├──────────────────────────────────────────────────────┤"
echo "│ Bindings granting cluster-admin : $TOTAL_BINDINGS"
echo "│ Total subjects                  : $TOTAL_SUBJECTS"
echo "│   Users                         : $USER_SUBJECTS"
echo "│   Groups                        : $GROUP_SUBJECTS"
echo "│   ServiceAccounts               : $SA_SUBJECTS"
echo "│ Non-system subjects             : $NON_SYSTEM"
echo "└──────────────────────────────────────────────────────┘"
echo ""

# ── Critical warnings ────────────────────────────────────────────────────────
if [ "$NON_SYSTEM" -gt 0 ]; then
  echo -e "${RED}[$(date +%H:%M:%S)] [$LABEL] WARNING: $NON_SYSTEM non-system subject(s) have cluster-admin — each must be documented and authorized${NC}"
fi

if [ "$USER_SUBJECTS" -gt 0 ]; then
  echo -e "${RED}[$(date +%H:%M:%S)] [$LABEL] WARNING: $USER_SUBJECTS individual user(s) bound to cluster-admin — prefer group-based bindings managed via IDP${NC}"
fi

if [ "$SA_SUBJECTS" -gt 0 ]; then
  echo -e "${RED}[$(date +%H:%M:%S)] [$LABEL] WARNING: $SA_SUBJECTS ServiceAccount(s) bound to cluster-admin — verify each requires full cluster access${NC}"
fi

ELAPSED=$(( SECONDS - SCRIPT_START_SECONDS ))
echo "[$(date +%H:%M:%S)] [$LABEL] Completed at $(date) — total time: ${ELAPSED}s"
echo "Created: $OUTPUT_FILE"
