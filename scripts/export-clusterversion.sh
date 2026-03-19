#!/usr/bin/env bash
# Description: Exports cluster version and update status
# Audit Area:  Cluster Version & Health
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./common.sh
source "$SCRIPT_DIR/common.sh"

: "${CLUSTER_NAME_SAFE:?CLUSTER_NAME_SAFE is not set}"
: "${CLUSTER_NAME:?CLUSTER_NAME is not set}"
: "${CLUSTER_CONTEXT:?CLUSTER_CONTEXT is not set}"
: "${CLUSTER_SERVER:?CLUSTER_SERVER is not set}"

OUTPUT_FILE="$OUTPUT_DIR/clusterversion-${CLUSTER_NAME_SAFE}-$TIMESTAMP.csv"

echo "cluster_name,cluster_context,cluster_server,name,cluster_id,desired_version,history_state,history_version,available,progressing,failing,observed_generation" > "$OUTPUT_FILE"

oc get clusterversion version -o json | jq -r \
  --arg cluster_name "$CLUSTER_NAME" \
  --arg cluster_context "$CLUSTER_CONTEXT" \
  --arg cluster_server "$CLUSTER_SERVER" '
  . as $cv
  | [
      $cluster_name,
      $cluster_context,
      $cluster_server,
      ($cv.metadata.name // ""),
      ($cv.spec.clusterID // ""),
      ($cv.status.desired.version // ""),
      ($cv.status.history[0].state // ""),
      ($cv.status.history[0].version // ""),
      (($cv.status.conditions[]? | select(.type=="Available") | .status) // ""),
      (($cv.status.conditions[]? | select(.type=="Progressing") | .status) // ""),
      (($cv.status.conditions[]? | select(.type=="Failing") | .status) // ""),
      ($cv.status.observedGeneration // "")
    ] | @csv
' >> "$OUTPUT_FILE"

echo "Created: $OUTPUT_FILE"
