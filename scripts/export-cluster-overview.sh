#!/usr/bin/env bash
# Description: Exports cluster identity and configuration overview — OCP version, platform, node counts, network config, and console access
# Audit Area:  Cluster Overview & Prerequisites
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

LABEL="cluster-overview"
SCRIPT_START_SECONDS=$SECONDS

RED='\033[0;31m'
NC='\033[0m' # No Color

echo "[$(date +%H:%M:%S)] [$LABEL] Starting export at $(date)"
echo "[$(date +%H:%M:%S)] [$LABEL] Cluster: $CLUSTER_NAME | Context: $CLUSTER_CONTEXT"
echo "[$(date +%H:%M:%S)] [$LABEL] Server: $CLUSTER_SERVER"
echo "[$(date +%H:%M:%S)] [$LABEL] Output dir: $OUTPUT_DIR"

OUTPUT_FILE="$OUTPUT_DIR/cluster-overview-${CLUSTER_NAME_SAFE}-$TIMESTAMP.csv"
echo "[$(date +%H:%M:%S)] [$LABEL] Output file: $OUTPUT_FILE"

echo "cluster_name,cluster_context,cluster_server,ocp_version,kubernetes_version,cluster_id,install_date,cluster_age_days,platform,control_plane_topology,infrastructure_topology,master_count,worker_count,infra_count,total_node_count,network_type,cluster_cidrs,service_cidrs,default_ingress_domain,console_url,api_server_url,update_channel,available_updates_count,update_state" > "$OUTPUT_FILE"

NOW_EPOCH=$(date +%s)

# =============================================================================
# 1) Cluster Version — OCP version, cluster ID, update channel, install date
# =============================================================================
echo "[$(date +%H:%M:%S)] [$LABEL] Fetching clusterversion..."
CV_JSON=$(oc get clusterversion version -o json 2>/dev/null | tr -d '\r' || echo '{}')
CV_LEN=${#CV_JSON}
echo "[$(date +%H:%M:%S)] [$LABEL] clusterversion response: ${CV_LEN} bytes"
if [ "$CV_LEN" -lt 10 ]; then
  echo -e "${RED}[$LABEL] ERROR: clusterversion response too small (${CV_LEN} bytes) — possibly empty or failed${NC}"
  CV_JSON='{}'
fi
if ! echo "$CV_JSON" | jq empty 2>/dev/null; then
  echo -e "${RED}[$LABEL] ERROR: clusterversion response is not valid JSON — first 200 chars:${NC}"
  echo "${CV_JSON:0:200}"
  CV_JSON='{}'
fi

OCP_VERSION=$(echo "$CV_JSON" | jq -r '.status.desired.version // ""')
CLUSTER_ID=$(echo "$CV_JSON" | jq -r '.spec.clusterID // ""')
UPDATE_CHANNEL=$(echo "$CV_JSON" | jq -r '.spec.channel // ""')
UPDATE_STATE=$(echo "$CV_JSON" | jq -r '.status.history[0].state // ""')
AVAILABLE_UPDATES_COUNT=$(echo "$CV_JSON" | jq '[(.status.availableUpdates // [])[] | .version] | length')

# Install date from oldest history entry (last element in .status.history array)
INSTALL_DATE=$(echo "$CV_JSON" | jq -r '(.status.history // []) | last | .completionTime // ""')
CLUSTER_AGE_DAYS=""
if [ -n "$INSTALL_DATE" ]; then
  INSTALL_EPOCH=$(date -d "$INSTALL_DATE" +%s 2>/dev/null || echo "")
  if [ -n "$INSTALL_EPOCH" ]; then
    CLUSTER_AGE_DAYS=$(( (NOW_EPOCH - INSTALL_EPOCH) / 86400 ))
  fi
fi

echo "[$(date +%H:%M:%S)] [$LABEL] Clusterversion done. version=$OCP_VERSION channel=$UPDATE_CHANNEL cluster_id=$CLUSTER_ID"

# =============================================================================
# 2) Infrastructure — platform, topology, API server URL
# =============================================================================
echo "[$(date +%H:%M:%S)] [$LABEL] Fetching infrastructure..."
INFRA_JSON=$(oc get infrastructure cluster -o json 2>/dev/null | tr -d '\r' || echo '{}')
INFRA_LEN=${#INFRA_JSON}
echo "[$(date +%H:%M:%S)] [$LABEL] infrastructure response: ${INFRA_LEN} bytes"
if ! echo "$INFRA_JSON" | jq empty 2>/dev/null; then
  echo -e "${RED}[$LABEL] ERROR: infrastructure response is not valid JSON — first 200 chars:${NC}"
  echo "${INFRA_JSON:0:200}"
  INFRA_JSON='{}'
fi

PLATFORM=$(echo "$INFRA_JSON" | jq -r '.status.platformStatus.type // .status.platform // ""')
CP_TOPOLOGY=$(echo "$INFRA_JSON" | jq -r '.status.controlPlaneTopology // ""')
INFRA_TOPOLOGY=$(echo "$INFRA_JSON" | jq -r '.status.infrastructureTopology // ""')
API_SERVER_URL=$(echo "$INFRA_JSON" | jq -r '.status.apiServerURL // ""')

echo "[$(date +%H:%M:%S)] [$LABEL] Infrastructure done. platform=$PLATFORM topology=$CP_TOPOLOGY"

# =============================================================================
# 3) Nodes — counts by role, Kubernetes version
# =============================================================================
echo "[$(date +%H:%M:%S)] [$LABEL] Fetching nodes..."
NODES_JSON=$(oc get nodes -o json 2>/dev/null | tr -d '\r' || echo '{"items":[]}')
NODES_LEN=${#NODES_JSON}
echo "[$(date +%H:%M:%S)] [$LABEL] nodes response: ${NODES_LEN} bytes"
if ! echo "$NODES_JSON" | jq empty 2>/dev/null; then
  echo -e "${RED}[$LABEL] ERROR: nodes response is not valid JSON — first 200 chars:${NC}"
  echo "${NODES_JSON:0:200}"
  NODES_JSON='{"items":[]}'
fi

MASTER_COUNT=$(echo "$NODES_JSON" | jq '[.items[] | select(.metadata.labels["node-role.kubernetes.io/master"] != null or .metadata.labels["node-role.kubernetes.io/control-plane"] != null)] | length')
WORKER_COUNT=$(echo "$NODES_JSON" | jq '[.items[] | select(.metadata.labels["node-role.kubernetes.io/worker"] != null)] | length')
INFRA_COUNT=$(echo "$NODES_JSON" | jq '[.items[] | select(.metadata.labels["node-role.kubernetes.io/infra"] != null)] | length')
TOTAL_NODE_COUNT=$(echo "$NODES_JSON" | jq '.items | length')

# Kubernetes version from first master node
K8S_VERSION=$(echo "$NODES_JSON" | jq -r '[.items[] | select(.metadata.labels["node-role.kubernetes.io/master"] != null or .metadata.labels["node-role.kubernetes.io/control-plane"] != null)] | .[0].status.nodeInfo.kubeletVersion // ""')

echo "[$(date +%H:%M:%S)] [$LABEL] Nodes done. master=$MASTER_COUNT worker=$WORKER_COUNT infra=$INFRA_COUNT total=$TOTAL_NODE_COUNT k8s=$K8S_VERSION"

# =============================================================================
# 4) Network configuration — type, CIDRs
# =============================================================================
echo "[$(date +%H:%M:%S)] [$LABEL] Fetching network config..."
NET_JSON=$(oc get network.config.openshift.io cluster -o json 2>/dev/null | tr -d '\r' || echo '{}')
NET_LEN=${#NET_JSON}
echo "[$(date +%H:%M:%S)] [$LABEL] network response: ${NET_LEN} bytes"
if ! echo "$NET_JSON" | jq empty 2>/dev/null; then
  echo -e "${RED}[$LABEL] ERROR: network response is not valid JSON — first 200 chars:${NC}"
  echo "${NET_JSON:0:200}"
  NET_JSON='{}'
fi

NETWORK_TYPE=$(echo "$NET_JSON" | jq -r '.spec.networkType // ""')
CLUSTER_CIDRS=$(echo "$NET_JSON" | jq -r '[.spec.clusterNetwork[]? | .cidr] | join(";") // ""')
SERVICE_CIDRS=$(echo "$NET_JSON" | jq -r '[.spec.serviceNetwork[]?] | join(";") // ""')

echo "[$(date +%H:%M:%S)] [$LABEL] Network config done. type=$NETWORK_TYPE"

# =============================================================================
# 5) Default IngressController — ingress domain
# =============================================================================
echo "[$(date +%H:%M:%S)] [$LABEL] Fetching default ingresscontroller..."
INGRESS_JSON=$(oc get ingresscontroller default -n openshift-ingress-operator -o json 2>/dev/null | tr -d '\r' || echo '{}')
INGRESS_LEN=${#INGRESS_JSON}
echo "[$(date +%H:%M:%S)] [$LABEL] ingresscontroller response: ${INGRESS_LEN} bytes"
if ! echo "$INGRESS_JSON" | jq empty 2>/dev/null; then
  echo -e "${RED}[$LABEL] ERROR: ingresscontroller response is not valid JSON — first 200 chars:${NC}"
  echo "${INGRESS_JSON:0:200}"
  INGRESS_JSON='{}'
fi

DEFAULT_INGRESS_DOMAIN=$(echo "$INGRESS_JSON" | jq -r '.status.domain // .spec.domain // ""')

echo "[$(date +%H:%M:%S)] [$LABEL] IngressController done. domain=$DEFAULT_INGRESS_DOMAIN"

# =============================================================================
# 6) Console URL
# =============================================================================
echo "[$(date +%H:%M:%S)] [$LABEL] Fetching console URL..."
CONSOLE_JSON=$(oc get console cluster -o json 2>/dev/null | tr -d '\r' || echo '{}')
CONSOLE_LEN=${#CONSOLE_JSON}
echo "[$(date +%H:%M:%S)] [$LABEL] console response: ${CONSOLE_LEN} bytes"
if ! echo "$CONSOLE_JSON" | jq empty 2>/dev/null; then
  echo -e "${RED}[$LABEL] ERROR: console response is not valid JSON — first 200 chars:${NC}"
  echo "${CONSOLE_JSON:0:200}"
  CONSOLE_JSON='{}'
fi

CONSOLE_URL=$(echo "$CONSOLE_JSON" | jq -r '.status.consoleURL // ""')

echo "[$(date +%H:%M:%S)] [$LABEL] Console done. url=$CONSOLE_URL"

# =============================================================================
# Write CSV row
# =============================================================================
jq -rn \
  --arg cluster_name "$CLUSTER_NAME" \
  --arg cluster_context "$CLUSTER_CONTEXT" \
  --arg cluster_server "$CLUSTER_SERVER" \
  --arg ocp_version "$OCP_VERSION" \
  --arg kubernetes_version "$K8S_VERSION" \
  --arg cluster_id "$CLUSTER_ID" \
  --arg install_date "$INSTALL_DATE" \
  --arg cluster_age_days "$CLUSTER_AGE_DAYS" \
  --arg platform "$PLATFORM" \
  --arg cp_topology "$CP_TOPOLOGY" \
  --arg infra_topology "$INFRA_TOPOLOGY" \
  --arg master_count "$MASTER_COUNT" \
  --arg worker_count "$WORKER_COUNT" \
  --arg infra_count "$INFRA_COUNT" \
  --arg total_node_count "$TOTAL_NODE_COUNT" \
  --arg network_type "$NETWORK_TYPE" \
  --arg cluster_cidrs "$CLUSTER_CIDRS" \
  --arg service_cidrs "$SERVICE_CIDRS" \
  --arg default_ingress_domain "$DEFAULT_INGRESS_DOMAIN" \
  --arg console_url "$CONSOLE_URL" \
  --arg api_server_url "$API_SERVER_URL" \
  --arg update_channel "$UPDATE_CHANNEL" \
  --arg available_updates_count "$AVAILABLE_UPDATES_COUNT" \
  --arg update_state "$UPDATE_STATE" \
  '[
    $cluster_name,
    $cluster_context,
    $cluster_server,
    $ocp_version,
    $kubernetes_version,
    $cluster_id,
    $install_date,
    $cluster_age_days,
    $platform,
    $cp_topology,
    $infra_topology,
    $master_count,
    $worker_count,
    $infra_count,
    $total_node_count,
    $network_type,
    $cluster_cidrs,
    $service_cidrs,
    $default_ingress_domain,
    $console_url,
    $api_server_url,
    $update_channel,
    $available_updates_count,
    $update_state
  ] | @csv' >> "$OUTPUT_FILE"

ELAPSED=$(( SECONDS - SCRIPT_START_SECONDS ))
echo "[$(date +%H:%M:%S)] [$LABEL] Completed at $(date) — total time: ${ELAPSED}s"
echo "Created: $OUTPUT_FILE"
