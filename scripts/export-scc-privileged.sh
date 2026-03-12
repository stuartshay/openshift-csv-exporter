#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

check_prereqs
OUTPUT_FILE="$OUTPUT_DIR/scc-privileged-$TIMESTAMP.csv"

echo 'name,allowPrivilegedContainer,allowHostNetwork,allowHostPID,allowHostIPC,readOnlyRootFilesystem,runAsUser_type,seLinuxContext_type,users_count,groups_count' > "$OUTPUT_FILE"

oc get scc privileged -o json | jq -r '
  [
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

announce_output "$OUTPUT_FILE"
