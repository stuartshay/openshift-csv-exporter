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

OUTPUT_FILE="$OUTPUT_DIR/scc-privileged-${CLUSTER_NAME_SAFE}-$TIMESTAMP.csv"

echo "cluster_name,cluster_context,cluster_server,name,allow_privileged_container,allow_host_network,allow_host_pid,allow_host_ipc,read_only_root_filesystem,run_as_user_type,se_linux_context_type,users_count,groups_count" > "$OUTPUT_FILE"

oc get scc privileged -o json | jq -r \
  --arg cluster_name "$CLUSTER_NAME" \
  --arg cluster_context "$CLUSTER_CONTEXT" \
  --arg cluster_server "$CLUSTER_SERVER" '
  [
    $cluster_name,
    $cluster_context,
    $cluster_server,
    (.metadata.name // ""),
    (.allowPrivilegedContainer // ""),
    (.allowHostNetwork // ""),
    (.allowHostPID // ""),
    (.allowHostIPC // ""),
    (.readOnlyRootFilesystem // ""),
    (.runAsUser.type // ""),
    (.seLinuxContext.type // ""),
    ((.users // []) | length),
    ((.groups // []) | length)
  ] | @csv
' >> "$OUTPUT_FILE"

echo "Created: $OUTPUT_FILE"
