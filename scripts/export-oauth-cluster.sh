#!/usr/bin/env bash
# Description: Exports OAuth configuration summary
# Audit Area:  External Authentication Enforced
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./common.sh
source "$SCRIPT_DIR/common.sh"

SCRIPT_START_SECONDS=$SECONDS
LABEL="oauth-cluster"
RED='\033[0;31m'
NC='\033[0m' # No Color

: "${CLUSTER_NAME_SAFE:?CLUSTER_NAME_SAFE is not set}"
: "${CLUSTER_NAME:?CLUSTER_NAME is not set}"
: "${CLUSTER_CONTEXT:?CLUSTER_CONTEXT is not set}"
: "${CLUSTER_SERVER:?CLUSTER_SERVER is not set}"
: "${OUTPUT_DIR:?OUTPUT_DIR is not set}"
: "${TIMESTAMP:?TIMESTAMP is not set}"

echo "[$LABEL] Starting export at $(date)"

OUTPUT_FILE="$OUTPUT_DIR/oauth-cluster-${CLUSTER_NAME_SAFE}-$TIMESTAMP.csv"

echo "cluster_name,cluster_context,cluster_server,name,identity_providers_count,access_token_max_age_seconds,grant_config_method,template_login,template_provider_selection,template_error" > "$OUTPUT_FILE"

echo "[$LABEL] Checking permission for oauth cluster..."
if ! oc auth can-i get oauths.config.openshift.io >/dev/null 2>&1; then
  echo -e "${RED}[$LABEL] ERROR: Permission denied — cannot read oauths.config.openshift.io${NC}"
  echo -e "${RED}[$LABEL] Grant access: oc adm policy add-cluster-role-to-user cluster-reader <user>${NC}"
  echo -e "${RED}[$LABEL] Skipping export — CSV will contain header only.${NC}"
  ELAPSED=$(( SECONDS - SCRIPT_START_SECONDS ))
  echo "[$LABEL] Completed at $(date) — total time: ${ELAPSED}s"
  echo "Created: $OUTPUT_FILE"
  exit 0
fi

echo "[$LABEL] Fetching oauth cluster..."
OAUTH_JSON=$(oc get oauth cluster -o json | tr -d '\r')

echo "[$LABEL] Processing oauth cluster..."
echo "$OAUTH_JSON" | jq -r \
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

IDP_COUNT=$(echo "$OAUTH_JSON" | jq '(.spec.identityProviders // []) | length')
GRANT_METHOD=$(echo "$OAUTH_JSON" | jq -r '.spec.grantConfig.method // "(not set)"')
TOKEN_MAX_AGE=$(echo "$OAUTH_JSON" | jq -r '.spec.tokenConfig.accessTokenMaxAgeSeconds // "(not set)"')
TEMPLATE_LOGIN=$(echo "$OAUTH_JSON" | jq -r '.spec.templates.login.name // "(not set)"')
TEMPLATE_PROVIDER=$(echo "$OAUTH_JSON" | jq -r '.spec.templates.providerSelection.name // "(not set)"')
TEMPLATE_ERROR=$(echo "$OAUTH_JSON" | jq -r '.spec.templates.error.name // "(not set)"')

echo "[$LABEL] OAuth summary:"
echo "[$LABEL]   Identity providers: $IDP_COUNT"
echo "[$LABEL]   Grant config method: $GRANT_METHOD"
echo "[$LABEL]   Access token max age: $TOKEN_MAX_AGE"
echo "[$LABEL]   Template login: $TEMPLATE_LOGIN"
echo "[$LABEL]   Template provider selection: $TEMPLATE_PROVIDER"
echo "[$LABEL]   Template error: $TEMPLATE_ERROR"
echo "[$LABEL] Export done."

ELAPSED=$(( SECONDS - SCRIPT_START_SECONDS ))
echo "[$LABEL] Completed at $(date) — total time: ${ELAPSED}s"
echo "Created: $OUTPUT_FILE"
