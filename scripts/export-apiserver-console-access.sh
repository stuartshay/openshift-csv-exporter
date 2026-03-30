#!/usr/bin/env bash
# Description: Exports API server and console access restriction configuration
# Audit Area:  API & Console Access Restriction
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./common.sh
source "$SCRIPT_DIR/common.sh"

SCRIPT_START_SECONDS=$SECONDS
LABEL="apiserver-console"
RED='\033[0;31m'
NC='\033[0m' # No Color

: "${CLUSTER_NAME_SAFE:?CLUSTER_NAME_SAFE is not set}"
: "${CLUSTER_NAME:?CLUSTER_NAME is not set}"
: "${CLUSTER_CONTEXT:?CLUSTER_CONTEXT is not set}"
: "${CLUSTER_SERVER:?CLUSTER_SERVER is not set}"
: "${OUTPUT_DIR:?OUTPUT_DIR is not set}"
: "${TIMESTAMP:?TIMESTAMP is not set}"

echo "[$(date +%H:%M:%S)] [$LABEL] Starting export at $(date)"

OUTPUT_FILE="$OUTPUT_DIR/apiserver-console-access-${CLUSTER_NAME_SAFE}-$TIMESTAMP.csv"

echo "cluster_name,cluster_context,cluster_server,api_server_url,console_url,tls_security_profile_type,tls_min_version,audit_profile,client_ca_name,encryption_type,additional_cors_origins,serving_certs_count,cluster_admin_binding_count" > "$OUTPUT_FILE"

# Count how many subjects have cluster-admin access
echo "[$(date +%H:%M:%S)] [$LABEL] Counting cluster-admin bindings..."
BINDINGS_JSON=$(oc get clusterrolebindings -o json | tr -d '\r')
CLUSTER_ADMIN_COUNT=$(echo "$BINDINGS_JSON" | jq '
  [.items[] | select(.roleRef.name == "cluster-admin") | (.subjects // [])[] ] | length
')
echo "[$(date +%H:%M:%S)] [$LABEL]   cluster-admin subjects: $CLUSTER_ADMIN_COUNT"

# Get API server config
echo "[$(date +%H:%M:%S)] [$LABEL] Fetching apiserver cluster..."
APISERVER_JSON=$(oc get apiserver cluster -o json 2>/dev/null | tr -d '\r' || echo '{}')

# Get console config
echo "[$(date +%H:%M:%S)] [$LABEL] Fetching console URL..."
CONSOLE_URL=$(oc get consoles.config.openshift.io cluster -o jsonpath='{.status.consoleURL}' 2>/dev/null | tr -d '\r' || echo "")

# Get API server URL
echo "[$(date +%H:%M:%S)] [$LABEL] Fetching API server URL..."
API_SERVER_URL=$(oc whoami --show-server 2>/dev/null | tr -d '\r' || echo "")

echo "[$(date +%H:%M:%S)] [$LABEL] Processing apiserver configuration..."
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

# ── Summary ──────────────────────────────────────────────────────────────────
TLS_TYPE=$(echo "$APISERVER_JSON" | jq -r '.spec.tlsSecurityProfile.type // "not set"')
TLS_MIN=$(echo "$APISERVER_JSON" | jq -r '.spec.tlsSecurityProfile.custom.minTLSVersion // .spec.tlsSecurityProfile.intermediate.minTLSVersion // "not set"')
AUDIT_PROFILE=$(echo "$APISERVER_JSON" | jq -r '.spec.audit.profile // "not set"')
CLIENT_CA=$(echo "$APISERVER_JSON" | jq -r '.spec.clientCA.name // "not set"')
ENCRYPTION_TYPE=$(echo "$APISERVER_JSON" | jq -r '.spec.encryption.type // "not set"')
SERVING_CERTS=$(echo "$APISERVER_JSON" | jq '[(.spec.servingCerts.namedCertificates // [])] | length')
CORS_COUNT=$(echo "$APISERVER_JSON" | jq '[(.spec.additionalCORSAllowedOrigins // [])[]] | length')

echo "[$(date +%H:%M:%S)] [$LABEL] Processing done."
echo ""
echo "┌──────────────────────────────────────────────────────┐"
echo "│ API Server & Console Access Summary                  │"
echo "├──────────────────────────────────────────────────────┤"
echo "│ API server URL                 : $API_SERVER_URL"
echo "│ Console URL                    : $CONSOLE_URL"
echo "│ TLS security profile           : $TLS_TYPE"
echo "│ TLS minimum version            : $TLS_MIN"
echo "│ Audit profile                  : $AUDIT_PROFILE"
echo "│ Client CA                      : $CLIENT_CA"
echo "│ Encryption type                : $ENCRYPTION_TYPE"
echo "│ Named serving certificates     : $SERVING_CERTS"
echo "│ Additional CORS origins        : $CORS_COUNT"
echo "│ cluster-admin subject count    : $CLUSTER_ADMIN_COUNT"
echo "└──────────────────────────────────────────────────────┘"
echo ""

# ── Critical warnings ────────────────────────────────────────────────────────
if [ "$TLS_TYPE" = "not set" ] || [ "$TLS_TYPE" = "" ]; then
  echo -e "${RED}[$(date +%H:%M:%S)] [$LABEL] WARNING: TLS security profile is not set — API server uses the default profile; consider setting Intermediate or Custom${NC}"
fi

if [ "$AUDIT_PROFILE" = "not set" ] || [ "$AUDIT_PROFILE" = "" ] || [ "$AUDIT_PROFILE" = "Default" ]; then
  echo -e "${RED}[$(date +%H:%M:%S)] [$LABEL] WARNING: Audit profile is '${AUDIT_PROFILE}' — consider WriteRequestBodies or AllRequestBodies for security auditing${NC}"
fi

if [ "$ENCRYPTION_TYPE" = "not set" ] || [ "$ENCRYPTION_TYPE" = "" ]; then
  echo -e "${RED}[$(date +%H:%M:%S)] [$LABEL] WARNING: etcd encryption type is not set — secrets are stored unencrypted at rest${NC}"
fi

if [ "$CLIENT_CA" = "not set" ] || [ "$CLIENT_CA" = "" ]; then
  echo -e "${RED}[$(date +%H:%M:%S)] [$LABEL] WARNING: No custom client CA configured — mutual TLS for API clients is not enforced${NC}"
fi

if [ "$SERVING_CERTS" -eq 0 ]; then
  echo -e "${RED}[$(date +%H:%M:%S)] [$LABEL] WARNING: No named serving certificates — API server uses the default self-signed certificate${NC}"
fi

if [ "$CLUSTER_ADMIN_COUNT" -gt 0 ]; then
  echo -e "${RED}[$(date +%H:%M:%S)] [$LABEL] WARNING: $CLUSTER_ADMIN_COUNT subject(s) have cluster-admin access — review with export-cluster-admin-bindings.sh${NC}"
fi

ELAPSED=$(( SECONDS - SCRIPT_START_SECONDS ))
echo "[$(date +%H:%M:%S)] [$LABEL] Completed at $(date) — total time: ${ELAPSED}s"
echo "Created: $OUTPUT_FILE"
