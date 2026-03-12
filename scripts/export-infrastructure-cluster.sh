#!/usr/bin/env bash
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

OUTPUT_FILE="$OUTPUT_DIR/infrastructure-cluster-${CLUSTER_NAME_SAFE}-$TIMESTAMP.csv"

echo "cluster_name,cluster_context,cluster_server,name,infrastructure_name,platform,api_server_url,api_server_internal_url,control_plane_topology,infrastructure_topology" > "$OUTPUT_FILE"

oc get infrastructure cluster -o json | jq -r \
  --arg cluster_name "$CLUSTER_NAME" \
  --arg cluster_context "$CLUSTER_CONTEXT" \
  --arg cluster_server "$CLUSTER_SERVER" '
  [
    $cluster_name,
    $cluster_context,
    $cluster_server,
    (.metadata.name // ""),
    (.status.infrastructureName // ""),
    (.status.platformStatus.type // .status.platform // ""),
    (.status.apiServerURL // ""),
    (.status.apiServerInternalURL // ""),
    (.status.controlPlaneTopology // ""),
    (.status.infrastructureTopology // "")
  ] | @csv
' >> "$OUTPUT_FILE"

echo "Created: $OUTPUT_FILE"