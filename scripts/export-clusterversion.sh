#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

check_prereqs
OUTPUT_FILE="$OUTPUT_DIR/clusterversion-$TIMESTAMP.csv"

echo 'name,clusterID,desired_version,history_state,history_version,available,progressing,failing,observedGeneration' > "$OUTPUT_FILE"

oc get clusterversion version -o json | jq -r '
  . as $cv
  | [
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

announce_output "$OUTPUT_FILE"
