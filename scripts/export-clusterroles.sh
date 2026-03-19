#!/usr/bin/env bash
# Description: Exports all ClusterRoles with their permission rules
# Audit Area:  Granular Role-Based Access Controls
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

OUTPUT_FILE="$OUTPUT_DIR/clusterroles-${CLUSTER_NAME_SAFE}-$TIMESTAMP.csv"

echo "cluster_name,cluster_context,cluster_server,role_name,creation_timestamp,api_groups,resources,verbs,non_resource_urls" > "$OUTPUT_FILE"

oc get clusterroles -o json | jq -r \
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

echo "Created: $OUTPUT_FILE"
