#!/usr/bin/env bash
# Description: Exports ClusterRoleBindings that grant cluster-admin access
# Audit Area:  API & Console Access Restriction
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

OUTPUT_FILE="$OUTPUT_DIR/cluster-admin-bindings-${CLUSTER_NAME_SAFE}-$TIMESTAMP.csv"

echo "cluster_name,cluster_context,cluster_server,binding_name,role_ref_name,subject_kind,subject_name,subject_namespace,creation_timestamp" > "$OUTPUT_FILE"

oc get clusterrolebindings -o json | jq -r \
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

echo "Created: $OUTPUT_FILE"
