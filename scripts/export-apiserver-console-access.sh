#!/usr/bin/env bash
# Description: Exports API server and console access restriction configuration
# Audit Area:  API & Console Access Restriction
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

OUTPUT_FILE="$OUTPUT_DIR/apiserver-console-access-${CLUSTER_NAME_SAFE}-$TIMESTAMP.csv"

echo "cluster_name,cluster_context,cluster_server,api_server_url,console_url,tls_security_profile_type,tls_min_version,audit_profile,client_ca_name,encryption_type,additional_cors_origins,serving_certs_count,cluster_admin_binding_count" > "$OUTPUT_FILE"

# Count how many subjects have cluster-admin access
CLUSTER_ADMIN_COUNT=$(oc get clusterrolebindings -o json | jq '
  [.items[] | select(.roleRef.name == "cluster-admin") | (.subjects // [])[] ] | length
')

# Get API server config
APISERVER_JSON=$(oc get apiserver cluster -o json 2>/dev/null || echo '{}')

# Get console config
CONSOLE_URL=$(oc get consoles.config.openshift.io cluster -o jsonpath='{.status.consoleURL}' 2>/dev/null || echo "")

# Get API server URL
API_SERVER_URL=$(oc whoami --show-server 2>/dev/null || echo "")

echo "$APISERVER_JSON" | jq -r \
  --arg cluster_name "$CLUSTER_NAME" \
  --arg cluster_context "$CLUSTER_CONTEXT" \
  --arg cluster_server "$CLUSTER_SERVER" \
  --arg api_server_url "$API_SERVER_URL" \
  --arg console_url "$CONSOLE_URL" \
  --arg cluster_admin_count "$CLUSTER_ADMIN_COUNT" '
  [
    $cluster_name,
    $cluster_context,
    $cluster_server,
    $api_server_url,
    $console_url,
    (.spec.tlsSecurityProfile.type // ""),
    (.spec.tlsSecurityProfile.custom.minTLSVersion // .spec.tlsSecurityProfile.intermediate.minTLSVersion // ""),
    (.spec.audit.profile // ""),
    (.spec.clientCA.name // ""),
    (.spec.encryption.type // ""),
    ((.spec.additionalCORSAllowedOrigins // []) | join(";")),
    ((.spec.servingCerts.namedCertificates // []) | length),
    $cluster_admin_count
  ] | @csv
' >> "$OUTPUT_FILE"

echo "Created: $OUTPUT_FILE"
