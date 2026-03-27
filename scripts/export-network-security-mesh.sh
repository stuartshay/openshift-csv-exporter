#!/usr/bin/env bash
# Description: Exports network security posture — cluster network config, egress firewalls, exposed services (NodePort/LoadBalancer), IngressControllers, Route TLS summary, Gateway API, and service mesh (OSSM/Istio) with mTLS and sidecar injection detection
# Audit Area:  Network Port Restriction / Service Mesh Enforcement
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

LABEL="network-mesh"
SCRIPT_START_SECONDS=$SECONDS

RED='\033[0;31m'
NC='\033[0m' # No Color

echo "[$(date +%H:%M:%S)] [$LABEL] Starting export at $(date)"

OUTPUT_FILE="$OUTPUT_DIR/network-security-mesh-${CLUSTER_NAME_SAFE}-$TIMESTAMP.csv"

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

MESH_INSTALLED="false"
EGRESS_FIREWALL_COUNT=0
EXPOSED_SVC_COUNT=0
NODEPORT_COUNT=0
LB_COUNT=0

###############################################################################
# Section 1 — Cluster Network Configuration
###############################################################################
echo "[$(date +%H:%M:%S)] [$LABEL] Fetching cluster network configuration..."

NET_CONFIG=$(oc get network.config.openshift.io cluster -o json 2>/dev/null | tr -d '\r' || echo '{}')
NET_TYPE=$(echo "$NET_CONFIG" | jq -r '.spec.networkType // ""')
CLUSTER_CIDRS=$(echo "$NET_CONFIG" | jq -r '[.spec.clusterNetwork[]? | .cidr] | join(";") // ""')
CLUSTER_HOST_PREFIXES=$(echo "$NET_CONFIG" | jq -r '[.spec.clusterNetwork[]? | .hostPrefix | tostring] | join(";") // ""')
SERVICE_CIDRS=$(echo "$NET_CONFIG" | jq -r '[.spec.serviceNetwork[]?] | join(";") // ""')
EXTERNAL_IP_POLICY=$(echo "$NET_CONFIG" | jq -r 'if .spec.externalIP.policy then "configured" else "none" end')
EXTERNAL_IP_AUTOASSIGN=$(echo "$NET_CONFIG" | jq -r '.spec.externalIP.autoAssignCIDRs // [] | join(";") // ""')

write_row "cluster_network" "cluster" "type:${NET_TYPE}" "" \
  "clusterCIDRs:${CLUSTER_CIDRS}" \
  "hostPrefixes:${CLUSTER_HOST_PREFIXES}" \
  "serviceCIDRs:${SERVICE_CIDRS}" \
  "externalIP:${EXTERNAL_IP_POLICY}"

if [ -n "$EXTERNAL_IP_AUTOASSIGN" ]; then
  write_row "cluster_network" "externalIP_autoAssign" "configured" "" "autoAssignCIDRs:${EXTERNAL_IP_AUTOASSIGN}" "" "" ""
fi

# Network operator
echo "[$(date +%H:%M:%S)] [$LABEL] Fetching network operator configuration..."
NET_OPERATOR=$(oc get network.operator.openshift.io cluster -o json 2>/dev/null | tr -d '\r' || echo '{}')
DEFAULT_NET_TYPE=$(echo "$NET_OPERATOR" | jq -r '.spec.defaultNetwork.type // ""')
ADDITIONAL_NETS=$(echo "$NET_OPERATOR" | jq '[.spec.additionalNetworks[]?] | length')
OPERATOR_CONDITIONS=$(echo "$NET_OPERATOR" | jq -r '[.status.conditions[]? | select(.status=="True") | .type] | join(";") // ""')

write_row "network_operator" "cluster" "conditions:${OPERATOR_CONDITIONS}" "" \
  "defaultNetType:${DEFAULT_NET_TYPE}" \
  "additionalNetworks:${ADDITIONAL_NETS}" "" ""

echo "[$(date +%H:%M:%S)] [$LABEL] Cluster network config done."

###############################################################################
# Section 2 — EgressFirewall / EgressNetworkPolicy
###############################################################################
echo "[$(date +%H:%M:%S)] [$LABEL] Checking egress firewall rules..."

# OVN-Kubernetes: EgressFirewall
EGRESS_FW_CRD="false"
if oc get crd egressfirewalls.k8s.ovn.org > /dev/null 2>&1; then
  EGRESS_FW_CRD="true"
fi

if [ "$EGRESS_FW_CRD" = "true" ]; then
  echo "[$(date +%H:%M:%S)] [$LABEL] Fetching EgressFirewalls (OVN-Kubernetes)..."
  EFW_JSON=$(oc get egressfirewalls.k8s.ovn.org -A -o json 2>/dev/null | tr -d '\r' || echo '{"items":[]}')
  EFW_COUNT=$(echo "$EFW_JSON" | jq '.items | length')
  EGRESS_FIREWALL_COUNT=$EFW_COUNT
  echo "[$(date +%H:%M:%S)] [$LABEL] Found $EFW_COUNT EgressFirewall(s)"

  if [ "$EFW_COUNT" -gt 0 ]; then
    echo "$EFW_JSON" | jq -c '.items[]' | while IFS= read -r item; do
      EFW_NAME=$(echo "$item" | jq -r '.metadata.name // ""')
      EFW_NS=$(echo "$item" | jq -r '.metadata.namespace // ""')
      RULE_COUNT=$(echo "$item" | jq '[.spec.egress[]?] | length')
      ALLOW_COUNT=$(echo "$item" | jq '[.spec.egress[]? | select(.type=="Allow")] | length')
      DENY_COUNT=$(echo "$item" | jq '[.spec.egress[]? | select(.type=="Deny")] | length')
      DNS_RULES=$(echo "$item" | jq '[.spec.egress[]? | select(.to.dnsName != null)] | length')
      EFW_STATUS=$(echo "$item" | jq -r '.status.status // "unknown"')

      write_row "egress_firewall" "$EFW_NAME" "$EFW_STATUS" "$EFW_NS" \
        "rules:${RULE_COUNT}" "allow:${ALLOW_COUNT};deny:${DENY_COUNT}" "dnsRules:${DNS_RULES}" ""
    done
  fi
else
  echo "[$(date +%H:%M:%S)] [$LABEL] EgressFirewall CRD not found (OVN-Kubernetes)"
fi

# Legacy SDN: EgressNetworkPolicy
EGRESS_NP_CRD="false"
if oc get crd egressnetworkpolicies.network.openshift.io > /dev/null 2>&1; then
  EGRESS_NP_CRD="true"
fi

if [ "$EGRESS_NP_CRD" = "true" ]; then
  echo "[$(date +%H:%M:%S)] [$LABEL] Fetching EgressNetworkPolicies (OpenShift SDN)..."
  ENP_JSON=$(oc get egressnetworkpolicies.network.openshift.io -A -o json 2>/dev/null | tr -d '\r' || echo '{"items":[]}')
  ENP_COUNT=$(echo "$ENP_JSON" | jq '.items | length')
  echo "[$(date +%H:%M:%S)] [$LABEL] Found $ENP_COUNT EgressNetworkPolicy(ies)"

  if [ "$ENP_COUNT" -gt 0 ]; then
    EGRESS_FIREWALL_COUNT=$((EGRESS_FIREWALL_COUNT + ENP_COUNT))
    echo "$ENP_JSON" | jq -c '.items[]' | while IFS= read -r item; do
      ENP_NAME=$(echo "$item" | jq -r '.metadata.name // ""')
      ENP_NS=$(echo "$item" | jq -r '.metadata.namespace // ""')
      RULE_COUNT=$(echo "$item" | jq '[.spec.egress[]?] | length')
      ALLOW_COUNT=$(echo "$item" | jq '[.spec.egress[]? | select(.type=="Allow")] | length')
      DENY_COUNT=$(echo "$item" | jq '[.spec.egress[]? | select(.type=="Deny")] | length')

      write_row "egress_network_policy" "$ENP_NAME" "configured" "$ENP_NS" \
        "rules:${RULE_COUNT}" "allow:${ALLOW_COUNT};deny:${DENY_COUNT}" "type:legacy_sdn" ""
    done
  fi
else
  echo "[$(date +%H:%M:%S)] [$LABEL] EgressNetworkPolicy CRD not found (legacy SDN)"
fi

if [ "$EGRESS_FW_CRD" = "false" ] && [ "$EGRESS_NP_CRD" = "false" ]; then
  write_row "egress_firewall" "none" "no_crd_found" "" "" "" "" ""
fi

echo "[$(date +%H:%M:%S)] [$LABEL] Egress firewall section done."

###############################################################################
# Section 3 — Exposed Services (NodePort + LoadBalancer)
###############################################################################
echo "[$(date +%H:%M:%S)] [$LABEL] Fetching exposed services (NodePort + LoadBalancer)..."

SVC_JSON=$(oc get services -A -o json 2>/dev/null | tr -d '\r' || echo '{"items":[]}')

# NodePort services
NODEPORT_JSON=$(echo "$SVC_JSON" | jq '{"items": [.items[] | select(.spec.type == "NodePort")]}')
NODEPORT_COUNT=$(echo "$NODEPORT_JSON" | jq '.items | length')
echo "[$(date +%H:%M:%S)] [$LABEL] Found $NODEPORT_COUNT NodePort service(s)"

if [ "$NODEPORT_COUNT" -gt 0 ]; then
  echo "$NODEPORT_JSON" | jq -c '.items[]' | while IFS= read -r item; do
    SVC_NAME=$(echo "$item" | jq -r '.metadata.name // ""')
    SVC_NS=$(echo "$item" | jq -r '.metadata.namespace // ""')
    PORTS=$(echo "$item" | jq -r '[.spec.ports[]? | "\(.port):\(.nodePort // "auto")/\(.protocol // "TCP")"] | join(";") // ""')
    SELECTOR=$(echo "$item" | jq -r '[.spec.selector // {} | to_entries[] | "\(.key)=\(.value)"] | join(";") // ""')
    EXTERNAL_IPS=$(echo "$item" | jq -r '[.spec.externalIPs[]?] | join(";") // ""')

    write_row "service_nodeport" "$SVC_NAME" "NodePort" "$SVC_NS" \
      "ports:${PORTS}" "selector:${SELECTOR}" "externalIPs:${EXTERNAL_IPS:-none}" ""
  done
fi

# LoadBalancer services
LB_JSON=$(echo "$SVC_JSON" | jq '{"items": [.items[] | select(.spec.type == "LoadBalancer")]}')
LB_COUNT=$(echo "$LB_JSON" | jq '.items | length')
echo "[$(date +%H:%M:%S)] [$LABEL] Found $LB_COUNT LoadBalancer service(s)"

if [ "$LB_COUNT" -gt 0 ]; then
  echo "$LB_JSON" | jq -c '.items[]' | while IFS= read -r item; do
    SVC_NAME=$(echo "$item" | jq -r '.metadata.name // ""')
    SVC_NS=$(echo "$item" | jq -r '.metadata.namespace // ""')
    PORTS=$(echo "$item" | jq -r '[.spec.ports[]? | "\(.port)/\(.protocol // "TCP")"] | join(";") // ""')
    LB_IP=$(echo "$item" | jq -r '.status.loadBalancer.ingress[0].ip // .status.loadBalancer.ingress[0].hostname // ""')
    EXTERNAL_TRAFFIC=$(echo "$item" | jq -r '.spec.externalTrafficPolicy // ""')

    write_row "service_loadbalancer" "$SVC_NAME" "LoadBalancer" "$SVC_NS" \
      "ports:${PORTS}" "loadBalancerIP:${LB_IP}" "externalTrafficPolicy:${EXTERNAL_TRAFFIC}" ""
  done
fi

EXPOSED_SVC_COUNT=$((NODEPORT_COUNT + LB_COUNT))

# Summary row for exposed services
write_row "exposed_services_summary" "cluster" "nodePort:${NODEPORT_COUNT};loadBalancer:${LB_COUNT}" "" \
  "total_exposed:${EXPOSED_SVC_COUNT}" "" "" ""

echo "[$(date +%H:%M:%S)] [$LABEL] Exposed services section done."

###############################################################################
# Section 4 — IngressControllers
###############################################################################
echo "[$(date +%H:%M:%S)] [$LABEL] Fetching IngressControllers..."

IC_JSON=$(oc get ingresscontrollers -n openshift-ingress-operator -o json 2>/dev/null | tr -d '\r' || echo '{"items":[]}')
IC_COUNT=$(echo "$IC_JSON" | jq '.items | length')
echo "[$(date +%H:%M:%S)] [$LABEL] Found $IC_COUNT IngressController(s)"

if [ "$IC_COUNT" -gt 0 ]; then
  echo "$IC_JSON" | jq -c '.items[]' | while IFS= read -r item; do
    IC_NAME=$(echo "$item" | jq -r '.metadata.name // ""')
    IC_DOMAIN=$(echo "$item" | jq -r '.spec.domain // ""')
    IC_PUBLISH=$(echo "$item" | jq -r '.spec.endpointPublishingStrategy.type // ""')
    IC_REPLICAS=$(echo "$item" | jq -r '.spec.replicas // "default"')
    IC_TLS_PROFILE=$(echo "$item" | jq -r '.spec.tlsSecurityProfile.type // "default"')
    IC_TLS_MIN=$(echo "$item" | jq -r '.spec.tlsSecurityProfile.minTLSVersion // ""')
    IC_ROUTE_ADMISSION=$(echo "$item" | jq -r '.spec.routeAdmission.namespaceOwnership // "default"')
    IC_WILDCARD=$(echo "$item" | jq -r '.spec.routeAdmission.wildcardPolicy // "default"')
    IC_CONDITIONS=$(echo "$item" | jq -r '[.status.conditions[]? | select(.status=="True") | .type] | join(";") // ""')

    write_row "ingress_controller" "$IC_NAME" "conditions:${IC_CONDITIONS}" "openshift-ingress-operator" \
      "domain:${IC_DOMAIN};publish:${IC_PUBLISH}" \
      "tls:${IC_TLS_PROFILE};minVersion:${IC_TLS_MIN}" \
      "replicas:${IC_REPLICAS};routeAdmission:${IC_ROUTE_ADMISSION}" \
      "wildcardPolicy:${IC_WILDCARD}"
  done
else
  write_row "ingress_controller" "none" "not_found" "openshift-ingress-operator" "" "" "" ""
fi

echo "[$(date +%H:%M:%S)] [$LABEL] IngressControllers done."

###############################################################################
# Section 5 — Route TLS summary
###############################################################################
echo "[$(date +%H:%M:%S)] [$LABEL] Fetching Route TLS summary..."

ROUTES_JSON=$(oc get routes -A -o json 2>/dev/null | tr -d '\r' || echo '{"items":[]}')
TOTAL_ROUTES=$(echo "$ROUTES_JSON" | jq '.items | length')
echo "[$(date +%H:%M:%S)] [$LABEL] Found $TOTAL_ROUTES route(s)"

EDGE_COUNT=$(echo "$ROUTES_JSON" | jq '[.items[] | select(.spec.tls.termination == "edge")] | length')
PASSTHROUGH_COUNT=$(echo "$ROUTES_JSON" | jq '[.items[] | select(.spec.tls.termination == "passthrough")] | length')
REENCRYPT_COUNT=$(echo "$ROUTES_JSON" | jq '[.items[] | select(.spec.tls.termination == "reencrypt")] | length')
NO_TLS_COUNT=$(echo "$ROUTES_JSON" | jq '[.items[] | select(.spec.tls == null)] | length')
INSECURE_ALLOW=$(echo "$ROUTES_JSON" | jq '[.items[] | select(.spec.tls.insecureEdgeTerminationPolicy == "Allow")] | length')
INSECURE_REDIRECT=$(echo "$ROUTES_JSON" | jq '[.items[] | select(.spec.tls.insecureEdgeTerminationPolicy == "Redirect")] | length')
INSECURE_NONE=$(echo "$ROUTES_JSON" | jq '[.items[] | select(.spec.tls != null) | select(.spec.tls.insecureEdgeTerminationPolicy == null or .spec.tls.insecureEdgeTerminationPolicy == "None" or .spec.tls.insecureEdgeTerminationPolicy == "")] | length')

write_row "route_tls_summary" "cluster" "total:${TOTAL_ROUTES}" "" \
  "edge:${EDGE_COUNT};passthrough:${PASSTHROUGH_COUNT};reencrypt:${REENCRYPT_COUNT}" \
  "noTLS:${NO_TLS_COUNT}" \
  "insecureAllow:${INSECURE_ALLOW};insecureRedirect:${INSECURE_REDIRECT};insecureNone:${INSECURE_NONE}" ""

# Emit individual routes with no TLS (security concern)
if [ "$NO_TLS_COUNT" -gt 0 ]; then
  echo "[$(date +%H:%M:%S)] [$LABEL] Listing $NO_TLS_COUNT route(s) with no TLS..."
  echo "$ROUTES_JSON" | jq -c '[.items[] | select(.spec.tls == null)][]' | while IFS= read -r item; do
    RT_NAME=$(echo "$item" | jq -r '.metadata.name // ""')
    RT_NS=$(echo "$item" | jq -r '.metadata.namespace // ""')
    RT_HOST=$(echo "$item" | jq -r '.spec.host // ""')

    write_row "route_no_tls" "$RT_NAME" "no_tls" "$RT_NS" "host:${RT_HOST}" "" "" ""
  done
fi

# Emit routes allowing insecure traffic
if [ "$INSECURE_ALLOW" -gt 0 ]; then
  echo "[$(date +%H:%M:%S)] [$LABEL] Listing $INSECURE_ALLOW route(s) allowing insecure traffic..."
  echo "$ROUTES_JSON" | jq -c '[.items[] | select(.spec.tls.insecureEdgeTerminationPolicy == "Allow")][]' | while IFS= read -r item; do
    RT_NAME=$(echo "$item" | jq -r '.metadata.name // ""')
    RT_NS=$(echo "$item" | jq -r '.metadata.namespace // ""')
    RT_HOST=$(echo "$item" | jq -r '.spec.host // ""')
    RT_TERM=$(echo "$item" | jq -r '.spec.tls.termination // ""')

    write_row "route_insecure_allow" "$RT_NAME" "insecure_allowed" "$RT_NS" \
      "host:${RT_HOST}" "termination:${RT_TERM}" "" ""
  done
fi

echo "[$(date +%H:%M:%S)] [$LABEL] Route TLS summary done."

###############################################################################
# Section 6 — Gateway API
###############################################################################
echo "[$(date +%H:%M:%S)] [$LABEL] Checking Gateway API..."

GATEWAY_CRD="false"
if oc get crd gateways.gateway.networking.k8s.io > /dev/null 2>&1; then
  GATEWAY_CRD="true"
fi

if [ "$GATEWAY_CRD" = "true" ]; then
  echo "[$(date +%H:%M:%S)] [$LABEL] Fetching Gateways..."
  GW_JSON=$(oc get gateways.gateway.networking.k8s.io -A -o json 2>/dev/null | tr -d '\r' || echo '{"items":[]}')
  GW_COUNT=$(echo "$GW_JSON" | jq '.items | length')
  echo "[$(date +%H:%M:%S)] [$LABEL] Found $GW_COUNT Gateway(s)"

  if [ "$GW_COUNT" -gt 0 ]; then
    echo "$GW_JSON" | jq -c '.items[]' | while IFS= read -r item; do
      GW_NAME=$(echo "$item" | jq -r '.metadata.name // ""')
      GW_NS=$(echo "$item" | jq -r '.metadata.namespace // ""')
      GW_CLASS=$(echo "$item" | jq -r '.spec.gatewayClassName // ""')
      LISTENER_COUNT=$(echo "$item" | jq '[.spec.listeners[]?] | length')
      TLS_LISTENERS=$(echo "$item" | jq '[.spec.listeners[]? | select(.tls != null)] | length')
      GW_CONDITIONS=$(echo "$item" | jq -r '[.status.conditions[]? | select(.status=="True") | .type] | join(";") // ""')

      write_row "gateway" "$GW_NAME" "conditions:${GW_CONDITIONS}" "$GW_NS" \
        "class:${GW_CLASS}" "listeners:${LISTENER_COUNT};tls:${TLS_LISTENERS}" "" ""
    done
  else
    write_row "gateway" "GatewayAPI" "no_gateways" "" "crd:true" "" "" ""
  fi

  # HTTPRoutes
  HTTPROUTE_CRD="false"
  if oc get crd httproutes.gateway.networking.k8s.io > /dev/null 2>&1; then
    HTTPROUTE_CRD="true"
  fi

  if [ "$HTTPROUTE_CRD" = "true" ]; then
    echo "[$(date +%H:%M:%S)] [$LABEL] Fetching HTTPRoutes..."
    HR_JSON=$(oc get httproutes.gateway.networking.k8s.io -A -o json 2>/dev/null | tr -d '\r' || echo '{"items":[]}')
    HR_COUNT=$(echo "$HR_JSON" | jq '.items | length')
    echo "[$(date +%H:%M:%S)] [$LABEL] Found $HR_COUNT HTTPRoute(s)"

    write_row "gateway_httproute_summary" "cluster" "count:${HR_COUNT}" "" "" "" "" ""
  fi
else
  echo "[$(date +%H:%M:%S)] [$LABEL] Gateway API CRD not found — skipping"
  write_row "gateway" "GatewayAPI" "not_installed" "" "" "" "" ""
fi

echo "[$(date +%H:%M:%S)] [$LABEL] Gateway API section done."

###############################################################################
# Section 7 — Service Mesh (OSSM / Istio)
###############################################################################
echo "[$(date +%H:%M:%S)] [$LABEL] Checking Service Mesh..."

# ── ServiceMeshControlPlane ──────────────────────────────────────────────────
SMCP_CRD="false"
if oc get crd servicemeshcontrolplanes.maistra.io > /dev/null 2>&1; then
  SMCP_CRD="true"
fi

SMCP_COUNT=0
if [ "$SMCP_CRD" = "true" ]; then
  echo "[$(date +%H:%M:%S)] [$LABEL] Fetching ServiceMeshControlPlanes..."
  SMCP_JSON=$(oc get servicemeshcontrolplanes.maistra.io -A -o json 2>/dev/null | tr -d '\r' || echo '{"items":[]}')
  SMCP_COUNT=$(echo "$SMCP_JSON" | jq '.items | length')
  echo "[$(date +%H:%M:%S)] [$LABEL] Found $SMCP_COUNT ServiceMeshControlPlane(s)"

  if [ "$SMCP_COUNT" -gt 0 ]; then
    MESH_INSTALLED="true"
    echo "$SMCP_JSON" | jq -c '.items[]' | while IFS= read -r item; do
      SMCP_NAME=$(echo "$item" | jq -r '.metadata.name // ""')
      SMCP_NS=$(echo "$item" | jq -r '.metadata.namespace // ""')
      SMCP_VERSION=$(echo "$item" | jq -r '.spec.version // ""')
      DATA_PLANE_MTLS=$(echo "$item" | jq -r '.spec.security.dataPlane.mtls // ""')
      CONTROL_PLANE_MTLS=$(echo "$item" | jq -r '.spec.security.controlPlane.mtls // ""')
      SMCP_READY=$(echo "$item" | jq -r '[.status.conditions[]? | select(.type=="Ready")] | .[0].status // ""')
      SMCP_REASON=$(echo "$item" | jq -r '[.status.conditions[]? | select(.type=="Ready")] | .[0].reason // ""')

      write_row "service_mesh_control_plane" "$SMCP_NAME" "ready:${SMCP_READY}" "$SMCP_NS" \
        "version:${SMCP_VERSION}" \
        "dataPlane_mTLS:${DATA_PLANE_MTLS};controlPlane_mTLS:${CONTROL_PLANE_MTLS}" \
        "readyReason:${SMCP_REASON}" ""
    done
  fi
else
  echo "[$(date +%H:%M:%S)] [$LABEL] ServiceMeshControlPlane CRD not found"
  write_row "service_mesh_control_plane" "OSSM" "not_installed" "" "" "" "" ""
fi

# ── ServiceMeshMemberRoll ────────────────────────────────────────────────────
SMMR_CRD="false"
if oc get crd servicemeshmemberrolls.maistra.io > /dev/null 2>&1; then
  SMMR_CRD="true"
fi

SMMR_MEMBER_COUNT=0
if [ "$SMMR_CRD" = "true" ]; then
  echo "[$(date +%H:%M:%S)] [$LABEL] Fetching ServiceMeshMemberRolls..."
  SMMR_JSON=$(oc get servicemeshmemberrolls.maistra.io -A -o json 2>/dev/null | tr -d '\r' || echo '{"items":[]}')
  SMMR_COUNT=$(echo "$SMMR_JSON" | jq '.items | length')

  if [ "$SMMR_COUNT" -gt 0 ]; then
    echo "$SMMR_JSON" | jq -c '.items[]' | while IFS= read -r item; do
      SMMR_NAME=$(echo "$item" | jq -r '.metadata.name // ""')
      SMMR_NS=$(echo "$item" | jq -r '.metadata.namespace // ""')
      SPEC_MEMBERS=$(echo "$item" | jq -r '[.spec.members[]?] | join(";") // ""')
      CONFIGURED_MEMBERS=$(echo "$item" | jq -r '[.status.configuredMembers[]?] | join(";") // ""')
      SPEC_COUNT=$(echo "$item" | jq '[.spec.members[]?] | length')
      CONFIGURED_COUNT=$(echo "$item" | jq '[.status.configuredMembers[]?] | length')
      SMMR_MEMBER_COUNT=$((SMMR_MEMBER_COUNT + CONFIGURED_COUNT))

      write_row "service_mesh_member_roll" "$SMMR_NAME" "spec:${SPEC_COUNT};configured:${CONFIGURED_COUNT}" "$SMMR_NS" \
        "specMembers:${SPEC_MEMBERS}" "configuredMembers:${CONFIGURED_MEMBERS}" "" ""
    done
  fi
fi

# ── PeerAuthentication (mTLS enforcement) ────────────────────────────────────
PA_CRD="false"
if oc get crd peerauthentications.security.istio.io > /dev/null 2>&1; then
  PA_CRD="true"
fi

PA_STRICT_COUNT=0
if [ "$PA_CRD" = "true" ]; then
  echo "[$(date +%H:%M:%S)] [$LABEL] Fetching PeerAuthentications..."
  PA_JSON=$(oc get peerauthentications.security.istio.io -A -o json 2>/dev/null | tr -d '\r' || echo '{"items":[]}')
  PA_COUNT=$(echo "$PA_JSON" | jq '.items | length')
  echo "[$(date +%H:%M:%S)] [$LABEL] Found $PA_COUNT PeerAuthentication(s)"

  if [ "$PA_COUNT" -gt 0 ]; then
    PA_STRICT_COUNT=$(echo "$PA_JSON" | jq '[.items[] | select(.spec.mtls.mode == "STRICT")] | length')
    PA_PERMISSIVE_COUNT=$(echo "$PA_JSON" | jq '[.items[] | select(.spec.mtls.mode == "PERMISSIVE")] | length')
    PA_DISABLE_COUNT=$(echo "$PA_JSON" | jq '[.items[] | select(.spec.mtls.mode == "DISABLE")] | length')

    write_row "peer_authentication_summary" "cluster" "total:${PA_COUNT}" "" \
      "STRICT:${PA_STRICT_COUNT};PERMISSIVE:${PA_PERMISSIVE_COUNT};DISABLE:${PA_DISABLE_COUNT}" "" "" ""

    # Emit individual non-STRICT PeerAuthentications as audit findings
    echo "$PA_JSON" | jq -c '[.items[] | select(.spec.mtls.mode != "STRICT")][]' | while IFS= read -r item; do
      PA_NAME=$(echo "$item" | jq -r '.metadata.name // ""')
      PA_NS=$(echo "$item" | jq -r '.metadata.namespace // ""')
      PA_MODE=$(echo "$item" | jq -r '.spec.mtls.mode // "unset"')

      write_row "peer_authentication" "$PA_NAME" "mode:${PA_MODE}" "$PA_NS" "" "" "" ""
    done
  fi
fi

# ── DestinationRule mTLS ─────────────────────────────────────────────────────
DR_CRD="false"
if oc get crd destinationrules.networking.istio.io > /dev/null 2>&1; then
  DR_CRD="true"
fi

if [ "$DR_CRD" = "true" ]; then
  echo "[$(date +%H:%M:%S)] [$LABEL] Fetching DestinationRules..."
  DR_JSON=$(oc get destinationrules.networking.istio.io -A -o json 2>/dev/null | tr -d '\r' || echo '{"items":[]}')
  DR_COUNT=$(echo "$DR_JSON" | jq '.items | length')
  echo "[$(date +%H:%M:%S)] [$LABEL] Found $DR_COUNT DestinationRule(s)"

  if [ "$DR_COUNT" -gt 0 ]; then
    DR_ISTIO_MUTUAL=$(echo "$DR_JSON" | jq '[.items[] | select(.spec.trafficPolicy.tls.mode == "ISTIO_MUTUAL")] | length')
    DR_MUTUAL=$(echo "$DR_JSON" | jq '[.items[] | select(.spec.trafficPolicy.tls.mode == "MUTUAL")] | length')
    DR_SIMPLE=$(echo "$DR_JSON" | jq '[.items[] | select(.spec.trafficPolicy.tls.mode == "SIMPLE")] | length')
    DR_DISABLE=$(echo "$DR_JSON" | jq '[.items[] | select(.spec.trafficPolicy.tls.mode == "DISABLE")] | length')
    DR_UNSET=$(echo "$DR_JSON" | jq "[.items[] | select(.spec.trafficPolicy.tls.mode == null)] | length")

    write_row "destination_rule_summary" "cluster" "total:${DR_COUNT}" "" \
      "ISTIO_MUTUAL:${DR_ISTIO_MUTUAL};MUTUAL:${DR_MUTUAL}" \
      "SIMPLE:${DR_SIMPLE};DISABLE:${DR_DISABLE};unset:${DR_UNSET}" "" ""
  fi
fi

# ── Sidecar injection detection (namespace labels) ──────────────────────────
echo "[$(date +%H:%M:%S)] [$LABEL] Checking sidecar injection labels on namespaces..."
NS_JSON=$(oc get namespaces -o json 2>/dev/null | tr -d '\r' || echo '{"items":[]}')

INJECT_ENABLED=$(echo "$NS_JSON" | jq '[.items[] | select(.metadata.labels["istio-injection"] == "enabled")] | length')
INJECT_DISABLED=$(echo "$NS_JSON" | jq '[.items[] | select(.metadata.labels["istio-injection"] == "disabled")] | length')
INJECT_UNLABELED=$(echo "$NS_JSON" | jq "[.items[] | select(.metadata.labels[\"istio-injection\"] == null)] | length")

write_row "sidecar_injection" "namespaces" "enabled:${INJECT_ENABLED};disabled:${INJECT_DISABLED};unlabeled:${INJECT_UNLABELED}" "" "" "" "" ""

# List namespaces with injection enabled
if [ "$INJECT_ENABLED" -gt 0 ]; then
  INJECT_NS_LIST=$(echo "$NS_JSON" | jq -r '[.items[] | select(.metadata.labels["istio-injection"] == "enabled") | .metadata.name] | join(";") // ""')
  write_row "sidecar_injection" "enabled_namespaces" "count:${INJECT_ENABLED}" "" "namespaces:${INJECT_NS_LIST}" "" "" ""
fi

# ── Kiali / Jaeger observability ─────────────────────────────────────────────
echo "[$(date +%H:%M:%S)] [$LABEL] Checking Kiali and Jaeger..."

KIALI_CRD="false"
if oc get crd kialis.kiali.io > /dev/null 2>&1; then
  KIALI_CRD="true"
  KIALI_JSON=$(oc get kialis.kiali.io -A -o json 2>/dev/null | tr -d '\r' || echo '{"items":[]}')
  KIALI_COUNT=$(echo "$KIALI_JSON" | jq '.items | length')
  write_row "mesh_observability" "Kiali" "instances:${KIALI_COUNT}" "" "crd:true" "" "" ""
else
  write_row "mesh_observability" "Kiali" "not_installed" "" "" "" "" ""
fi

JAEGER_CRD="false"
if oc get crd jaegers.jaegertracing.io > /dev/null 2>&1; then
  JAEGER_CRD="true"
  JAEGER_JSON=$(oc get jaegers.jaegertracing.io -A -o json 2>/dev/null | tr -d '\r' || echo '{"items":[]}')
  JAEGER_COUNT=$(echo "$JAEGER_JSON" | jq '.items | length')
  write_row "mesh_observability" "Jaeger" "instances:${JAEGER_COUNT}" "" "crd:true" "" "" ""
else
  write_row "mesh_observability" "Jaeger" "not_installed" "" "" "" "" ""
fi

echo "[$(date +%H:%M:%S)] [$LABEL] Service Mesh section done."

###############################################################################
# Section 8 — Summary & critical warnings
###############################################################################
echo "[$(date +%H:%M:%S)] [$LABEL] Writing summary..."

write_row "summary" "network_security" "complete" "" \
  "networkType:${NET_TYPE}" \
  "egressFirewalls:${EGRESS_FIREWALL_COUNT}" \
  "exposedServices:${EXPOSED_SVC_COUNT}" \
  "meshInstalled:${MESH_INSTALLED}"

echo ""
echo "┌──────────────────────────────────────────────────────┐"
echo "│ Network Security & Service Mesh Summary              │"
echo "├──────────────────────────────────────────────────────┤"
echo "│ Network type              : $NET_TYPE"
echo "│ Egress firewalls          : $EGRESS_FIREWALL_COUNT"
echo "│ NodePort services         : $NODEPORT_COUNT"
echo "│ LoadBalancer services     : $LB_COUNT"
echo "│ IngressControllers        : $IC_COUNT"
echo "│ Total routes              : $TOTAL_ROUTES"
echo "│ Routes with no TLS        : $NO_TLS_COUNT"
echo "│ Routes allowing insecure  : $INSECURE_ALLOW"
echo "│ Gateway API               : $GATEWAY_CRD"
echo "│ Service Mesh (OSSM)       : $MESH_INSTALLED"
echo "│ SMCP count                : $SMCP_COUNT"
echo "│ PeerAuth STRICT           : $PA_STRICT_COUNT"
echo "│ Sidecar injection enabled : $INJECT_ENABLED namespace(s)"
echo "│ Kiali                     : $KIALI_CRD"
echo "│ Jaeger                    : $JAEGER_CRD"
echo "└──────────────────────────────────────────────────────┘"
echo ""

# ── Critical warnings ────────────────────────────────────────────────────────
if [ "$NO_TLS_COUNT" -gt 0 ]; then
  echo -e "${RED}[$LABEL] WARNING: ${NO_TLS_COUNT} route(s) have NO TLS configured — traffic is unencrypted${NC}"
fi

if [ "$INSECURE_ALLOW" -gt 0 ]; then
  echo -e "${RED}[$LABEL] WARNING: ${INSECURE_ALLOW} route(s) allow insecure (HTTP) traffic${NC}"
fi

if [ "$EGRESS_FIREWALL_COUNT" -eq 0 ]; then
  echo -e "${RED}[$LABEL] WARNING: No EgressFirewall or EgressNetworkPolicy found — egress traffic is unrestricted${NC}"
fi

if [ "$MESH_INSTALLED" = "false" ]; then
  echo -e "${RED}[$LABEL] WARNING: No service mesh (OSSM/Istio) detected — no mTLS enforcement between services${NC}"
fi

if [ "$EXTERNAL_IP_POLICY" = "none" ]; then
  echo -e "${RED}[$LABEL] WARNING: No ExternalIP policy configured — external IPs may be assignable without restriction${NC}"
fi

# ── Finish ───────────────────────────────────────────────────────────────────
ELAPSED=$(( SECONDS - SCRIPT_START_SECONDS ))
echo "[$(date +%H:%M:%S)] [$LABEL] Completed at $(date) — total time: ${ELAPSED}s"
echo "Created: $OUTPUT_FILE"
