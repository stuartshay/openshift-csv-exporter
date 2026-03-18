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

OUTPUT_FILE="$OUTPUT_DIR/oauth-cluster-${CLUSTER_NAME_SAFE}-$TIMESTAMP.csv"

echo "cluster_name,cluster_context,cluster_server,name,identity_providers_count,access_token_max_age_seconds,grant_config_method,template_login,template_provider_selection,template_error" > "$OUTPUT_FILE"

oc get oauth cluster -o json | jq -r \
  --arg cluster_name "$CLUSTER_NAME" \
  --arg cluster_context "$CLUSTER_CONTEXT" \
  --arg cluster_server "$CLUSTER_SERVER" '
  [
    $cluster_name,
    $cluster_context,
    $cluster_server,
    (.metadata.name // ""),
    ((.spec.identityProviders // []) | length),
    (.spec.tokenConfig.accessTokenMaxAgeSeconds // ""),
    (.spec.grantConfig.method // ""),
    (.spec.templates.login.name // ""),
    (.spec.templates.providerSelection.name // ""),
    (.spec.templates.error.name // "")
  ] | @csv
' >> "$OUTPUT_FILE"

echo "Created: $OUTPUT_FILE"
