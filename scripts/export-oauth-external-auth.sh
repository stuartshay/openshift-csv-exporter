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

OUTPUT_FILE="$OUTPUT_DIR/oauth-external-auth-${CLUSTER_NAME_SAFE}-$TIMESTAMP.csv"

echo "cluster_name,cluster_context,cluster_server,external_auth_enforced,kubeadmin_removed,identity_providers_count,idp_name,idp_type,idp_mapping_method,idp_issuer,idp_client_id,access_token_max_age_seconds" > "$OUTPUT_FILE"

# Check if kubeadmin secret has been removed (indicates external auth is enforced)
KUBEADMIN_REMOVED="false"
if ! oc get secret kubeadmin -n kube-system >/dev/null 2>&1; then
  KUBEADMIN_REMOVED="true"
fi

oc get oauth cluster -o json | jq -r \
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

echo "Created: $OUTPUT_FILE"
