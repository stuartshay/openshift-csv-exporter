#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

check_prereqs
OUTPUT_FILE="$OUTPUT_DIR/clusteroperators-$TIMESTAMP.csv"

echo 'name,version,available,progressing,degraded,upgradeable' > "$OUTPUT_FILE"

oc get clusteroperators -o json | jq -r '
  .items[] |
  [
    (.metadata.name // ""),
    (.status.versions[0].version // ""),
    ((.status.conditions[]? | select(.type=="Available") | .status) // ""),
    ((.status.conditions[]? | select(.type=="Progressing") | .status) // ""),
    ((.status.conditions[]? | select(.type=="Degraded") | .status) // ""),
    ((.status.conditions[]? | select(.type=="Upgradeable") | .status) // "")
  ] | @csv
' >> "$OUTPUT_FILE"

announce_output "$OUTPUT_FILE"
