#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

check_prereqs
OUTPUT_FILE="$OUTPUT_DIR/infrastructure-cluster-$TIMESTAMP.csv"

echo 'name,infrastructureName,platform,apiServerURL,apiServerInternalURL,controlPlaneTopology,infrastructureTopology' > "$OUTPUT_FILE"

oc get infrastructure cluster -o json | jq -r '
  [
    (.metadata.name // ""),
    (.status.infrastructureName // ""),
    (.status.platformStatus.type // .status.platform // ""),
    (.status.apiServerURL // ""),
    (.status.apiServerInternalURL // ""),
    (.status.controlPlaneTopology // ""),
    (.status.infrastructureTopology // "")
  ] | @csv
' >> "$OUTPUT_FILE"

announce_output "$OUTPUT_FILE"
