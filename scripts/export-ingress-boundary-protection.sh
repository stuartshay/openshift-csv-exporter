#!/usr/bin/env bash
# Description: Exports external ingress/egress boundary protection and internal service exposure — WAF/API Gateway detection, IngressController security annotations, Route security annotations, 3scale/APIcast CRDs, and internal service exposure audit (ExternalName, externalIPs, ClusterIP summary)
# Audit Area:  External Egress/Ingress Boundary Protection / Internal Service Exposure Control
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

LABEL="ingress-boundary"
SCRIPT_START_SECONDS=$SECONDS

RED='\033[0;31m'
NC='\033[0m' # No Color

echo "[$(date +%H:%M:%S)] [$LABEL] Starting export at $(date)"

OUTPUT_FILE="$OUTPUT_DIR/ingress-boundary-protection-${CLUSTER_NAME_SAFE}-$TIMESTAMP.csv"

echo "cluster_name,cluster_context,cluster_server,record_type,component_name,status,namespace,detail_1,detail_2,detail_3,detail_4" > "$OUTPUT_FILE"

# ── Helper: write a CSV row ──────────────────────────────────────────────────
write_row() {
  local record_type="$1" component_name="$2" status="$3" namespace="$4" detail_1="$5" detail_2="$6" detail_3="$7" detail_4="$8"
  jq -rn \
    --arg cluster_name "$CLUSTER_NAME" \
    --arg cluster_context "$CLUSTER_CONTEXT" \
    --arg cluster_server "$CLUSTER_SERVER" \
    --arg record_type "$record_type" \
    --arg component_name "$component_name" \
    --arg status "$status" \
    --arg namespace "$namespace" \
    --arg detail_1 "$detail_1" \
    --arg detail_2 "$detail_2" \
    --arg detail_3 "$detail_3" \
    --arg detail_4 "$detail_4" \
    '[$cluster_name,$cluster_context,$cluster_server,$record_type,$component_name,$status,$namespace,$detail_1,$detail_2,$detail_3,$detail_4] | @csv' \
    >> "$OUTPUT_FILE"
}

# ── Tracking variables ───────────────────────────────────────────────────────
THREESCALE_CRD="false"
APICAST_CRD="false"
APIMANAGER_COUNT=0
EXTERNAL_NAME_COUNT=0
EXTERNAL_IP_SVC_COUNT=0
EXTERNAL_ENDPOINT_COUNT=0
CLUSTERIP_COUNT=0
TOTAL_SVC_COUNT=0
ROUTE_WAF_ANNOTATION_COUNT=0

###############################################################################
# Section 1 — IngressController Security Annotations (OCP.35)
###############################################################################
echo "[$(date +%H:%M:%S)] [$LABEL] Fetching IngressController annotations..."

IC_JSON=$(oc get ingresscontrollers -n openshift-ingress-operator -o json 2>/dev/null | tr -d '\r' || echo '{"items":[]}')
IC_COUNT=$(echo "$IC_JSON" | jq '.items | length')
echo "[$(date +%H:%M:%S)] [$LABEL] Found $IC_COUNT IngressController(s)"

if [ "$IC_COUNT" -gt 0 ]; then
  echo "$IC_JSON" | jq -c '.items[]' | while IFS= read -r item; do
    IC_NAME=$(echo "$item" | jq -r '.metadata.name // ""')

    # Extract WAF-related annotations
    WAF_ANNOTS=$(echo "$item" | jq -r '
      [(.metadata.annotations // {}) | to_entries[] |
        select(.key | test("waf|modsecurity|f5\\.com|cloudflare|aws.*waf|imperva|akamai|fortiweb"; "i"))] |
      if length > 0 then [.[].key] | join(";") else "" end')

    # Extract rate-limiting annotations
    RATE_ANNOTS=$(echo "$item" | jq -r '
      [(.metadata.annotations // {}) | to_entries[] |
        select(.key | test("rate.limit|ratelimit|throttl"; "i"))] |
      if length > 0 then [.[].key] | join(";") else "" end')

    # Extract all custom annotations (non-openshift, non-kubectl)
    CUSTOM_ANNOTS=$(echo "$item" | jq -r '
      [(.metadata.annotations // {}) | to_entries[] |
        select(.key | test("^(kubectl|openshift|operator|include\\.release)"; "i") | not)] |
      if length > 0 then [.[].key] | join(";") else "" end')

    IC_STATUS="no_waf_annotations"
    if [ -n "$WAF_ANNOTS" ]; then
      IC_STATUS="waf_detected"
    fi

    write_row "ingress_waf_check" "$IC_NAME" "$IC_STATUS" "openshift-ingress-operator" \
      "wafAnnotations:${WAF_ANNOTS:-none}" \
      "rateLimitAnnotations:${RATE_ANNOTS:-none}" \
      "customAnnotations:${CUSTOM_ANNOTS:-none}" ""
  done
fi

echo "[$(date +%H:%M:%S)] [$LABEL] IngressController annotations done."

###############################################################################
# Section 2 — Route Security Annotations (OCP.35)
###############################################################################
echo "[$(date +%H:%M:%S)] [$LABEL] Fetching Route annotations for WAF/rate-limit markers..."

ROUTES_JSON=$(oc get routes -A -o json 2>/dev/null | tr -d '\r' || echo '{"items":[]}')
TOTAL_ROUTES=$(echo "$ROUTES_JSON" | jq '.items | length')
echo "[$(date +%H:%M:%S)] [$LABEL] Found $TOTAL_ROUTES route(s), scanning annotations..."

# Scan for routes with WAF or rate-limiting annotations
WAF_ROUTE_DATA=$(echo "$ROUTES_JSON" | jq -c '
  [.items[] |
    {
      name: .metadata.name,
      namespace: .metadata.namespace,
      waf: [(.metadata.annotations // {}) | to_entries[] |
        select(.key | test("waf|modsecurity|f5\\.com|cloudflare|aws.*waf|imperva|akamai|fortiweb"; "i"))],
      rateLimit: [(.metadata.annotations // {}) | to_entries[] |
        select(.key | test("rate.limit|ratelimit|throttl"; "i"))]
    } |
    select((.waf | length) > 0 or (.rateLimit | length) > 0)
  ]')

ROUTE_WAF_ANNOTATION_COUNT=$(echo "$WAF_ROUTE_DATA" | jq 'length')
echo "[$(date +%H:%M:%S)] [$LABEL] Found $ROUTE_WAF_ANNOTATION_COUNT route(s) with WAF/rate-limit annotations"

if [ "$ROUTE_WAF_ANNOTATION_COUNT" -gt 0 ]; then
  echo "$WAF_ROUTE_DATA" | jq -c '.[]' | while IFS= read -r item; do
    RT_NAME=$(echo "$item" | jq -r '.name // ""')
    RT_NS=$(echo "$item" | jq -r '.namespace // ""')
    RT_WAF=$(echo "$item" | jq -r '[.waf[].key] | join(";") // ""')
    RT_RATE=$(echo "$item" | jq -r '[.rateLimit[].key] | join(";") // ""')

    write_row "route_waf_annotation" "$RT_NAME" "annotated" "$RT_NS" \
      "wafAnnotations:${RT_WAF:-none}" \
      "rateLimitAnnotations:${RT_RATE:-none}" "" ""
  done
fi

# Count routes with IP-whitelisting annotations (boundary control indicator)
IP_WHITELIST_COUNT=$(echo "$ROUTES_JSON" | jq '
  [.items[] | select((.metadata.annotations // {}) |
    to_entries[] | .key | test("whitelist|allowlist|ip.restriction|haproxy.*whitelist"; "i"))] | length')

if [ "$IP_WHITELIST_COUNT" -gt 0 ]; then
  write_row "route_ip_whitelist_summary" "cluster" "count:${IP_WHITELIST_COUNT}" "" \
    "totalRoutes:${TOTAL_ROUTES}" "" "" ""
fi

echo "[$(date +%H:%M:%S)] [$LABEL] Route annotations done."

###############################################################################
# Section 3 — API Gateway / 3scale Detection (OCP.35)
###############################################################################
echo "[$(date +%H:%M:%S)] [$LABEL] Checking API Gateway / 3scale CRDs..."

# 3scale APIManager CRD
if oc get crd apimanagers.apps.3scale.net > /dev/null 2>&1; then
  THREESCALE_CRD="true"
  echo "[$(date +%H:%M:%S)] [$LABEL] 3scale APIManager CRD found"
  AM_JSON=$(oc get apimanagers -A -o json 2>/dev/null | tr -d '\r' || echo '{"items":[]}')
  APIMANAGER_COUNT=$(echo "$AM_JSON" | jq '.items | length')
  echo "[$(date +%H:%M:%S)] [$LABEL] Found $APIMANAGER_COUNT APIManager instance(s)"

  if [ "$APIMANAGER_COUNT" -gt 0 ]; then
    echo "$AM_JSON" | jq -c '.items[]' | while IFS= read -r item; do
      AM_NAME=$(echo "$item" | jq -r '.metadata.name // ""')
      AM_NS=$(echo "$item" | jq -r '.metadata.namespace // ""')
      AM_WILDCARD=$(echo "$item" | jq -r '.spec.wildcardDomain // ""')
      AM_APICAST=$(echo "$item" | jq -r '
        if .spec.apicast then
          "staging:" + (.spec.apicast.stagingSpec.replicas // "default" | tostring) +
          ";production:" + (.spec.apicast.productionSpec.replicas // "default" | tostring)
        else "default" end')
      AM_STATUS=$(echo "$item" | jq -r '
        [.status.conditions[]? | select(.status=="True") | .type] | join(";") // ""')

      write_row "threescale_api_manager" "$AM_NAME" "deployed" "$AM_NS" \
        "wildcardDomain:${AM_WILDCARD}" "apicast:${AM_APICAST}" \
        "conditions:${AM_STATUS}" ""
    done
  else
    write_row "threescale_api_manager" "none" "crd_present_no_instances" "" \
      "crd:apimanagers.apps.3scale.net" "" "" ""
  fi
else
  echo "[$(date +%H:%M:%S)] [$LABEL] 3scale APIManager CRD not found"
  write_row "threescale_api_manager" "none" "crd_not_found" "" "" "" "" ""
fi

# APIcast (standalone) CRD
if oc get crd apicasts.apps.3scale.net > /dev/null 2>&1; then
  APICAST_CRD="true"
  AC_JSON=$(oc get apicasts -A -o json 2>/dev/null | tr -d '\r' || echo '{"items":[]}')
  AC_COUNT=$(echo "$AC_JSON" | jq '.items | length')
  echo "[$(date +%H:%M:%S)] [$LABEL] Found $AC_COUNT standalone APIcast instance(s)"

  if [ "$AC_COUNT" -gt 0 ]; then
    echo "$AC_JSON" | jq -c '.items[]' | while IFS= read -r item; do
      AC_NAME=$(echo "$item" | jq -r '.metadata.name // ""')
      AC_NS=$(echo "$item" | jq -r '.metadata.namespace // ""')
      AC_REPLICAS=$(echo "$item" | jq -r '.spec.replicas // "default"')
      AC_ADMIN_PORTAL=$(echo "$item" | jq -r '.spec.adminPortalCredentialsRef.name // ""')

      write_row "apicast_instance" "$AC_NAME" "deployed" "$AC_NS" \
        "replicas:${AC_REPLICAS}" "adminPortalRef:${AC_ADMIN_PORTAL}" "" ""
    done
  fi
else
  echo "[$(date +%H:%M:%S)] [$LABEL] APIcast CRD not found"
fi

# Check for Gateway API resources (may indicate API gateway usage)
GATEWAY_API_CRD="false"
GATEWAY_COUNT=0
if oc get crd gateways.gateway.networking.k8s.io > /dev/null 2>&1; then
  GATEWAY_API_CRD="true"
  GW_JSON=$(oc get gateways -A -o json 2>/dev/null | tr -d '\r' || echo '{"items":[]}')
  GATEWAY_COUNT=$(echo "$GW_JSON" | jq '.items | length')
  echo "[$(date +%H:%M:%S)] [$LABEL] Gateway API: $GATEWAY_COUNT gateway(s) found"

  if [ "$GATEWAY_COUNT" -gt 0 ]; then
    echo "$GW_JSON" | jq -c '.items[]' | while IFS= read -r item; do
      GW_NAME=$(echo "$item" | jq -r '.metadata.name // ""')
      GW_NS=$(echo "$item" | jq -r '.metadata.namespace // ""')
      GW_CLASS=$(echo "$item" | jq -r '.spec.gatewayClassName // ""')
      GW_LISTENERS=$(echo "$item" | jq '[.spec.listeners[]?] | length')

      write_row "gateway_api_instance" "$GW_NAME" "deployed" "$GW_NS" \
        "gatewayClass:${GW_CLASS}" "listeners:${GW_LISTENERS}" "" ""
    done
  fi
else
  echo "[$(date +%H:%M:%S)] [$LABEL] Gateway API CRD not found"
fi

write_row "api_gateway_summary" "cluster" "" "" \
  "threescaleCRD:${THREESCALE_CRD}" "apicastCRD:${APICAST_CRD}" \
  "gatewayAPICRD:${GATEWAY_API_CRD}" "apiManagers:${APIMANAGER_COUNT};gateways:${GATEWAY_COUNT}"

echo "[$(date +%H:%M:%S)] [$LABEL] API Gateway / 3scale detection done."

###############################################################################
# Section 4 — Internal Service Exposure Audit (OCP.37)
###############################################################################
echo "[$(date +%H:%M:%S)] [$LABEL] Fetching all services for internal exposure audit..."

SVC_JSON=$(oc get services -A -o json 2>/dev/null | tr -d '\r' || echo '{"items":[]}')
TOTAL_SVC_COUNT=$(echo "$SVC_JSON" | jq '.items | length')
echo "[$(date +%H:%M:%S)] [$LABEL] Found $TOTAL_SVC_COUNT total service(s)"

# --- ClusterIP count (internal-only, expected majority) ---
CLUSTERIP_COUNT=$(echo "$SVC_JSON" | jq '[.items[] | select(.spec.type == "ClusterIP" or .spec.type == null)] | length')
NODEPORT_COUNT=$(echo "$SVC_JSON" | jq '[.items[] | select(.spec.type == "NodePort")] | length')
LB_COUNT=$(echo "$SVC_JSON" | jq '[.items[] | select(.spec.type == "LoadBalancer")] | length')

# --- ExternalName services (DNS rebinding risk) ---
echo "[$(date +%H:%M:%S)] [$LABEL] Checking ExternalName services..."
EXTNAME_JSON=$(echo "$SVC_JSON" | jq -c '[.items[] | select(.spec.type == "ExternalName")]')
EXTERNAL_NAME_COUNT=$(echo "$EXTNAME_JSON" | jq 'length')
echo "[$(date +%H:%M:%S)] [$LABEL] Found $EXTERNAL_NAME_COUNT ExternalName service(s)"

if [ "$EXTERNAL_NAME_COUNT" -gt 0 ]; then
  echo "[$(date +%H:%M:%S)] [$LABEL] Processing $EXTERNAL_NAME_COUNT ExternalName service(s)..."
  echo "$EXTNAME_JSON" | jq -c '.[]' | while IFS= read -r item; do
    EN_NAME=$(echo "$item" | jq -r '.metadata.name // ""')
    EN_NS=$(echo "$item" | jq -r '.metadata.namespace // ""')
    EN_TARGET=$(echo "$item" | jq -r '.spec.externalName // ""')

    write_row "service_external_name" "$EN_NAME" "external_name" "$EN_NS" \
      "target:${EN_TARGET}" "" "" ""
  done
fi

# --- Services with externalIPs set (bypasses ingress controls) ---
echo "[$(date +%H:%M:%S)] [$LABEL] Checking services with externalIPs..."
EXTIP_JSON=$(echo "$SVC_JSON" | jq -c '[.items[] | select(.spec.externalIPs != null and (.spec.externalIPs | length) > 0)]')
EXTERNAL_IP_SVC_COUNT=$(echo "$EXTIP_JSON" | jq 'length')
echo "[$(date +%H:%M:%S)] [$LABEL] Found $EXTERNAL_IP_SVC_COUNT service(s) with externalIPs"

if [ "$EXTERNAL_IP_SVC_COUNT" -gt 0 ]; then
  echo "[$(date +%H:%M:%S)] [$LABEL] Processing $EXTERNAL_IP_SVC_COUNT service(s) with externalIPs..."
  echo "$EXTIP_JSON" | jq -c '.[]' | while IFS= read -r item; do
    EI_NAME=$(echo "$item" | jq -r '.metadata.name // ""')
    EI_NS=$(echo "$item" | jq -r '.metadata.namespace // ""')
    EI_TYPE=$(echo "$item" | jq -r '.spec.type // ""')
    EI_IPS=$(echo "$item" | jq -r '[.spec.externalIPs[]] | join(";") // ""')
    EI_PORTS=$(echo "$item" | jq -r '[.spec.ports[]? | "\(.port)/\(.protocol // "TCP")"] | join(";") // ""')

    write_row "service_external_ip" "$EI_NAME" "external_ip_set" "$EI_NS" \
      "type:${EI_TYPE}" "externalIPs:${EI_IPS}" "ports:${EI_PORTS}" ""
  done
fi

# --- Endpoints with external (non-pod) targets ---
echo "[$(date +%H:%M:%S)] [$LABEL] Checking endpoints with external targets..."
EP_JSON=$(oc get endpoints -A -o json 2>/dev/null | tr -d '\r' || echo '{"items":[]}')
EP_TOTAL=$(echo "$EP_JSON" | jq '.items | length')
echo "[$(date +%H:%M:%S)] [$LABEL] Found $EP_TOTAL endpoint(s), scanning for external targets..."

# Endpoints where addresses have no targetRef (manual/external endpoints)
EXTERNAL_EP_JSON=$(echo "$EP_JSON" | jq -c '
  [.items[] |
    select(.subsets != null) |
    {
      name: .metadata.name,
      namespace: .metadata.namespace,
      externalAddresses: [.subsets[]? | .addresses[]? | select(.targetRef == null) | .ip]
    } |
    select((.externalAddresses | length) > 0)
  ]')
EXTERNAL_ENDPOINT_COUNT=$(echo "$EXTERNAL_EP_JSON" | jq 'length')
echo "[$(date +%H:%M:%S)] [$LABEL] Found $EXTERNAL_ENDPOINT_COUNT endpoint(s) with external targets"

if [ "$EXTERNAL_ENDPOINT_COUNT" -gt 0 ]; then
  echo "[$(date +%H:%M:%S)] [$LABEL] Processing $EXTERNAL_ENDPOINT_COUNT endpoint(s) with external targets..."
  echo "$EXTERNAL_EP_JSON" | jq -c '.[]' | while IFS= read -r item; do
    EP_NAME=$(echo "$item" | jq -r '.name // ""')
    EP_NS=$(echo "$item" | jq -r '.namespace // ""')
    EP_ADDRS=$(echo "$item" | jq -r '[.externalAddresses[]] | join(";") // ""')
    EP_ADDR_COUNT=$(echo "$item" | jq '.externalAddresses | length')

    write_row "endpoint_external_target" "$EP_NAME" "external_target" "$EP_NS" \
      "externalIPs:${EP_ADDRS}" "count:${EP_ADDR_COUNT}" "" ""
  done
fi

echo "[$(date +%H:%M:%S)] [$LABEL] Internal service exposure audit done."

###############################################################################
# Section 5 — Summary & Critical Warnings
###############################################################################
echo "[$(date +%H:%M:%S)] [$LABEL] Writing summary..."

write_row "service_type_summary" "cluster" "total:${TOTAL_SVC_COUNT}" "" \
  "clusterIP:${CLUSTERIP_COUNT};nodePort:${NODEPORT_COUNT}" \
  "loadBalancer:${LB_COUNT};externalName:${EXTERNAL_NAME_COUNT}" \
  "externalIPSvcs:${EXTERNAL_IP_SVC_COUNT}" \
  "externalEndpoints:${EXTERNAL_ENDPOINT_COUNT}"

write_row "boundary_protection_summary" "cluster" "" "" \
  "routeWAFAnnotations:${ROUTE_WAF_ANNOTATION_COUNT}" \
  "ipWhitelistRoutes:${IP_WHITELIST_COUNT}" \
  "threescale:${THREESCALE_CRD};apicast:${APICAST_CRD}" \
  "gatewayAPI:${GATEWAY_API_CRD};apiManagers:${APIMANAGER_COUNT}"

echo ""
echo "┌──────────────────────────────────────────────────────┐"
echo "│ Ingress Boundary Protection Summary                  │"
echo "├──────────────────────────────────────────────────────┤"
echo "│ IngressControllers        : $IC_COUNT"
echo "│ Routes (total)            : $TOTAL_ROUTES"
echo "│ Routes w/ WAF annotations : $ROUTE_WAF_ANNOTATION_COUNT"
echo "│ Routes w/ IP whitelist    : $IP_WHITELIST_COUNT"
echo "│ 3scale APIManager CRD     : $THREESCALE_CRD"
echo "│ APIcast CRD               : $APICAST_CRD"
echo "│ APIManager instances      : $APIMANAGER_COUNT"
echo "│ Gateway API CRD           : $GATEWAY_API_CRD"
echo "│ Gateway instances         : $GATEWAY_COUNT"
echo "├──────────────────────────────────────────────────────┤"
echo "│ Internal Service Exposure                            │"
echo "├──────────────────────────────────────────────────────┤"
echo "│ Total services            : $TOTAL_SVC_COUNT"
echo "│ ClusterIP (internal)      : $CLUSTERIP_COUNT"
echo "│ NodePort                  : $NODEPORT_COUNT"
echo "│ LoadBalancer              : $LB_COUNT"
echo "│ ExternalName              : $EXTERNAL_NAME_COUNT"
echo "│ Services w/ externalIPs   : $EXTERNAL_IP_SVC_COUNT"
echo "│ Endpoints w/ ext targets  : $EXTERNAL_ENDPOINT_COUNT"
echo "└──────────────────────────────────────────────────────┘"
echo ""

# ── Critical warnings ────────────────────────────────────────────────────────
if [ "$ROUTE_WAF_ANNOTATION_COUNT" -eq 0 ] && [ "$THREESCALE_CRD" = "false" ] && [ "$GATEWAY_API_CRD" = "false" ]; then
  echo -e "${RED}[$LABEL] WARNING: No WAF annotations, API gateway, or 3scale detected — external traffic has no application-layer protection (OCP.35)${NC}"
fi

if [ "$EXTERNAL_NAME_COUNT" -gt 0 ]; then
  echo -e "${RED}[$LABEL] WARNING: ${EXTERNAL_NAME_COUNT} ExternalName service(s) found — DNS rebinding risk, verify each is authorized (OCP.37)${NC}"
fi

if [ "$EXTERNAL_IP_SVC_COUNT" -gt 0 ]; then
  echo -e "${RED}[$LABEL] WARNING: ${EXTERNAL_IP_SVC_COUNT} service(s) have externalIPs set — bypasses normal ingress controls, verify each is authorized (OCP.37)${NC}"
fi

if [ "$EXTERNAL_ENDPOINT_COUNT" -gt 0 ]; then
  echo -e "${RED}[$LABEL] WARNING: ${EXTERNAL_ENDPOINT_COUNT} endpoint(s) have external (non-pod) targets — traffic may leave the cluster without ingress controls (OCP.37)${NC}"
fi

# ── Finish ───────────────────────────────────────────────────────────────────
ELAPSED=$(( SECONDS - SCRIPT_START_SECONDS ))
echo "[$(date +%H:%M:%S)] [$LABEL] Completed at $(date) — total time: ${ELAPSED}s"
echo "Created: $OUTPUT_FILE"
