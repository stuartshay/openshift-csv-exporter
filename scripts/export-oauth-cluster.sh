#!/usr/bin/env bash
set -euo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/common.sh"

check_prereqs
OUTPUT_FILE="$OUTPUT_DIR/oauth-cluster-$TIMESTAMP.csv"

echo 'name,identityProviders_count,tokenConfig_accessTokenMaxAgeSeconds,templates_error,templates_login,templates_providerSelection' > "$OUTPUT_FILE"

oc get oauth cluster -o json | jq -r '
  [
    (.metadata.name // ""),
    ((.spec.identityProviders // []) | length),
    (.spec.tokenConfig.accessTokenMaxAgeSeconds // ""),
    (.spec.templates.error // ""),
    (.spec.templates.login // ""),
    (.spec.templates.providerSelection // "")
  ] | @csv
' >> "$OUTPUT_FILE"

announce_output "$OUTPUT_FILE"
