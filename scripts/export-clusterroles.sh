#!/usr/bin/env bash
# Description: Exports all ClusterRoles with their permission rules
# Audit Area:  Granular Role-Based Access Controls
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./common.sh
source "$SCRIPT_DIR/common.sh"

SCRIPT_START_SECONDS=$SECONDS
LABEL="clusterroles"
RED='\033[0;31m'
NC='\033[0m' # No Color

: "${CLUSTER_NAME_SAFE:?CLUSTER_NAME_SAFE is not set}"
: "${CLUSTER_NAME:?CLUSTER_NAME is not set}"
: "${CLUSTER_CONTEXT:?CLUSTER_CONTEXT is not set}"
: "${CLUSTER_SERVER:?CLUSTER_SERVER is not set}"
: "${OUTPUT_DIR:?OUTPUT_DIR is not set}"
: "${TIMESTAMP:?TIMESTAMP is not set}"

echo "[$(date +%H:%M:%S)] [$LABEL] Starting export at $(date)"

OUTPUT_FILE="$OUTPUT_DIR/clusterroles-${CLUSTER_NAME_SAFE}-$TIMESTAMP.csv"

echo "cluster_name,cluster_context,cluster_server,role_name,creation_timestamp,api_groups,resources,verbs,non_resource_urls" > "$OUTPUT_FILE"

echo "[$(date +%H:%M:%S)] [$LABEL] Fetching clusterroles..."
ROLES_JSON=$(oc get clusterroles -o json | tr -d '\r')

echo "[$(date +%H:%M:%S)] [$LABEL] Processing clusterroles..."
echo "$ROLES_JSON" | jq -r \
  --arg cluster_name "$CLUSTER_NAME" \
  --arg cluster_context "$CLUSTER_CONTEXT" \
  --arg cluster_server "$CLUSTER_SERVER" '
  .items[] as $cr |
  if (($cr.rules // []) | length) > 0 then
    $cr.rules[] |
    [
      $cluster_name,
      $cluster_context,
      $cluster_server,
      ($cr.metadata.name // ""),
      ($cr.metadata.creationTimestamp // ""),
      ((.apiGroups // []) | join(";")),
      ((.resources // []) | join(";")),
      ((.verbs // []) | join(";")),
      ((.nonResourceURLs // []) | join(";"))
    ] | @csv
  else
    [
      $cluster_name,
      $cluster_context,
      $cluster_server,
      ($cr.metadata.name // ""),
      ($cr.metadata.creationTimestamp // ""),
      "",
      "",
      "",
      ""
    ] | @csv
  end
' >> "$OUTPUT_FILE"

# ── Summary ──────────────────────────────────────────────────────────────────
TOTAL_ROLES=$(echo "$ROLES_JSON" | jq '[.items[]] | length')
WILDCARD_VERBS=$(echo "$ROLES_JSON" | jq '[.items[] | select((.rules // [])[] | (.verbs // [])[] == "*")] | unique_by(.metadata.name) | length')
WILDCARD_RESOURCES=$(echo "$ROLES_JSON" | jq '[.items[] | select((.rules // [])[] | (.resources // [])[] == "*")] | unique_by(.metadata.name) | length')
WILDCARD_ALL=$(echo "$ROLES_JSON" | jq '[.items[] | select((.rules // [])[] | ((.verbs // [])[] == "*") and ((.resources // [])[] == "*"))] | unique_by(.metadata.name) | length')

echo "[$(date +%H:%M:%S)] [$LABEL] Processing done."
echo ""
echo "┌──────────────────────────────────────────────────────┐"
echo "│ ClusterRoles Summary                                 │"
echo "├──────────────────────────────────────────────────────┤"
echo "│ Total ClusterRoles            : $TOTAL_ROLES"
echo "│ Roles with wildcard verbs (*)  : $WILDCARD_VERBS"
echo "│ Roles with wildcard resources (*): $WILDCARD_RESOURCES"
echo "│ Roles with full wildcard (*/*) : $WILDCARD_ALL"
echo "└──────────────────────────────────────────────────────┘"
echo ""

# ── Critical warnings ────────────────────────────────────────────────────────
if [ "$WILDCARD_ALL" -gt 0 ]; then
  echo -e "${RED}[$(date +%H:%M:%S)] [$LABEL] WARNING: $WILDCARD_ALL role(s) grant wildcard verbs AND resources — equivalent to full API access${NC}"
fi

if [ "$WILDCARD_VERBS" -gt 0 ]; then
  echo -e "${RED}[$(date +%H:%M:%S)] [$LABEL] WARNING: $WILDCARD_VERBS role(s) use wildcard verbs (*) — grants all actions on matched resources${NC}"
fi

if [ "$WILDCARD_RESOURCES" -gt 0 ]; then
  echo -e "${RED}[$(date +%H:%M:%S)] [$LABEL] WARNING: $WILDCARD_RESOURCES role(s) use wildcard resources (*) — grants access to all resource types${NC}"
fi

ELAPSED=$(( SECONDS - SCRIPT_START_SECONDS ))
echo "[$(date +%H:%M:%S)] [$LABEL] Completed at $(date) — total time: ${ELAPSED}s"
echo "Created: $OUTPUT_FILE"
