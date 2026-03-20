#!/usr/bin/env bash
# Description: Reports whether external authentication is enforced
# Audit Area:  External Authentication Enforced
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./common.sh
source "$SCRIPT_DIR/common.sh"

SCRIPT_START_SECONDS=$SECONDS
LABEL="oauth-external-auth"
RED='\033[0;31m'
NC='\033[0m' # No Color

: "${CLUSTER_NAME_SAFE:?CLUSTER_NAME_SAFE is not set}"
: "${CLUSTER_NAME:?CLUSTER_NAME is not set}"
: "${CLUSTER_CONTEXT:?CLUSTER_CONTEXT is not set}"
: "${CLUSTER_SERVER:?CLUSTER_SERVER is not set}"
: "${OUTPUT_DIR:?OUTPUT_DIR is not set}"
: "${TIMESTAMP:?TIMESTAMP is not set}"

echo "[$LABEL] Starting export at $(date)"

OUTPUT_FILE="$OUTPUT_DIR/oauth-external-auth-${CLUSTER_NAME_SAFE}-$TIMESTAMP.csv"

echo "cluster_name,cluster_context,cluster_server,external_auth_enforced,kubeadmin_removed,identity_providers_count,idp_name,idp_type,idp_mapping_method,idp_issuer,idp_client_id,access_token_max_age_seconds" > "$OUTPUT_FILE"

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

# Check if kubeadmin secret has been removed (indicates external auth is enforced)
echo "[$LABEL] Checking kubeadmin secret..."
KUBEADMIN_REMOVED="false"
if ! oc get secret kubeadmin -n kube-system >/dev/null 2>&1; then
  KUBEADMIN_REMOVED="true"
fi
echo "[$LABEL]   kubeadmin removed: $KUBEADMIN_REMOVED"

echo "[$LABEL] Fetching oauth cluster..."
OAUTH_JSON=$(oc get oauth cluster -o json | tr -d '\r')

echo "[$LABEL] Processing oauth cluster..."
echo "$OAUTH_JSON" | jq -r \
  --arg cluster_name "$CLUSTER_NAME" \
  --arg cluster_context "$CLUSTER_CONTEXT" \
  --arg cluster_server "$CLUSTER_SERVER" \
  --arg kubeadmin_removed "$KUBEADMIN_REMOVED" '
  ((.spec.identityProviders // []) | length) as $idp_count |
  (.spec.tokenConfig.accessTokenMaxAgeSeconds // "") as $token_max_age |
  (if $idp_count > 0 and $kubeadmin_removed == "true" then "true" else "false" end) as $enforced |
  if $idp_count == 0 then
    [
      $cluster_name,
      $cluster_context,
      $cluster_server,
      $enforced,
      $kubeadmin_removed,
      $idp_count,
      "",
      "",
      "",
      "",
      "",
      $token_max_age
    ] | @csv
  else
    (.spec.identityProviders // [])[] |
    [
      $cluster_name,
      $cluster_context,
      $cluster_server,
      $enforced,
      $kubeadmin_removed,
      $idp_count,
      (.name // ""),
      (.type // ""),
      (.mappingMethod // ""),
      (.openID.issuer // .ldap.url // .htpasswd // .basicAuth.url // .github.hostname // ""),
      (.openID.clientID // .github.clientID // ""),
      $token_max_age
    ] | @csv
  end
' >> "$OUTPUT_FILE"

IDP_COUNT=$(echo "$OAUTH_JSON" | jq '(.spec.identityProviders // []) | length')
ENFORCED="false"
if [ "$IDP_COUNT" -gt 0 ] && [ "$KUBEADMIN_REMOVED" = "true" ]; then
  ENFORCED="true"
fi

echo "[$LABEL] External auth summary:"
echo "[$LABEL]   External auth enforced: $ENFORCED"
echo "[$LABEL]   kubeadmin removed: $KUBEADMIN_REMOVED"
echo "[$LABEL]   Identity providers: $IDP_COUNT"
echo "[$LABEL] Export done."

ELAPSED=$(( SECONDS - SCRIPT_START_SECONDS ))
echo "[$LABEL] Completed at $(date) — total time: ${ELAPSED}s"
echo "Created: $OUTPUT_FILE"
