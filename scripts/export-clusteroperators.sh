#!/usr/bin/env bash
# Description: Exports status of all cluster operators
# Audit Area:  Cluster Version & Health
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

OUTPUT_FILE="$OUTPUT_DIR/clusteroperators-${CLUSTER_NAME_SAFE}-$TIMESTAMP.csv"

echo "cluster_name,cluster_context,cluster_server,name,version,available,progressing,degraded,upgradeable" > "$OUTPUT_FILE"

oc get clusteroperators -o json | jq -r \
  --arg cluster_name "$CLUSTER_NAME" \
  --arg cluster_context "$CLUSTER_CONTEXT" \
  --arg cluster_server "$CLUSTER_SERVER" '
  .items[] |
  [
    $cluster_name,
    $cluster_context,
    $cluster_server,
    (.metadata.name // ""),
    (.status.versions[0].version // ""),
    ((.status.conditions[]? | select(.type=="Available") | .status) // ""),
    ((.status.conditions[]? | select(.type=="Progressing") | .status) // ""),
    ((.status.conditions[]? | select(.type=="Degraded") | .status) // ""),
    ((.status.conditions[]? | select(.type=="Upgradeable") | .status) // "")
  ] | @csv
' >> "$OUTPUT_FILE"

echo "Created: $OUTPUT_FILE"
