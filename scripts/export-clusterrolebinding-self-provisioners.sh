#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

check_prereqs
OUTPUT_FILE="$OUTPUT_DIR/clusterrolebinding-self-provisioners-$TIMESTAMP.csv"

echo 'name,roleRef_kind,roleRef_name,subject_kind,subject_name,subject_namespace' > "$OUTPUT_FILE"

oc get clusterrolebinding self-provisioners -o json | jq -r '
  . as $crb
  | if ((.subjects // []) | length) > 0 then
      .subjects[] |
      [
        $crb.metadata.name,
        ($crb.roleRef.kind // ""),
        ($crb.roleRef.name // ""),
        (.kind // ""),
        (.name // ""),
        (.namespace // "")
      ] | @csv
    else
      [
        $crb.metadata.name,
        ($crb.roleRef.kind // ""),
        ($crb.roleRef.name // ""),
        "",
        "",
        ""
      ] | @csv
    end
' >> "$OUTPUT_FILE"

announce_output "$OUTPUT_FILE"
