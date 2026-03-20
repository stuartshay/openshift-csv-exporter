#!/usr/bin/env bash
# Description: Exports patch and version lifecycle data — OCP version, available updates, node OS versions, operator versions, and MachineConfigPool rollout status
# Audit Area:  Patch & Version Lifecycle Management
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

OUTPUT_FILE="$OUTPUT_DIR/patch-lifecycle-${CLUSTER_NAME_SAFE}-$TIMESTAMP.csv"

NOW_EPOCH=$(date +%s)

echo "cluster_name,cluster_context,cluster_server,check_category,resource_name,current_version,desired_version,versions_match,update_channel,available_updates,update_state,age_days,details" > "$OUTPUT_FILE"

# =============================================================================
# 1) Cluster Version — current OCP version, channel, available updates
# =============================================================================
CV_JSON=$(oc get clusterversion version -o json 2>/dev/null || echo '{}')

CURRENT_VERSION=$(echo "$CV_JSON" | jq -r '.status.desired.version // ""')
UPDATE_CHANNEL=$(echo "$CV_JSON" | jq -r '.spec.channel // ""')
UPDATE_STATE=$(echo "$CV_JSON" | jq -r '.status.history[0].state // ""')
AVAILABLE_UPDATES=$(echo "$CV_JSON" | jq -r '[(.status.availableUpdates // [])[] | .version] | join(";")')
AVAILABLE_COUNT=$(echo "$CV_JSON" | jq '[(.status.availableUpdates // [])] | .[0] | length')

# Compute cluster age from first history entry
CLUSTER_COMPLETED=$(echo "$CV_JSON" | jq -r '.status.history[-1].completionTime // ""')
CLUSTER_AGE_DAYS=""
if [ -n "$CLUSTER_COMPLETED" ]; then
  COMPLETED_EPOCH=$(date -d "$CLUSTER_COMPLETED" +%s 2>/dev/null || echo "")
  if [ -n "$COMPLETED_EPOCH" ]; then
    CLUSTER_AGE_DAYS=$(( (NOW_EPOCH - COMPLETED_EPOCH) / 86400 ))
  fi
fi

jq -rn \
  --arg cn "$CLUSTER_NAME" --arg cc "$CLUSTER_CONTEXT" --arg cs "$CLUSTER_SERVER" \
  --arg ver "$CURRENT_VERSION" \
  --arg channel "$UPDATE_CHANNEL" \
  --arg avail "$AVAILABLE_UPDATES" \
  --arg avail_count "$AVAILABLE_COUNT" \
  --arg state "$UPDATE_STATE" \
  --arg age "$CLUSTER_AGE_DAYS" '
  [$cn,$cc,$cs,"cluster_version","clusterversion/version",$ver,$ver,"true",$channel,$avail,$state,$age,
   ("available_update_count=" + $avail_count)] | @csv
' >> "$OUTPUT_FILE"

# Update history — each version that was applied
echo "$CV_JSON" | jq -c '.status.history // [] | .[]' | while IFS= read -r entry; do
  HIST_VERSION=$(echo "$entry" | jq -r '.version // ""')
  HIST_STATE=$(echo "$entry" | jq -r '.state // ""')
  HIST_COMPLETED=$(echo "$entry" | jq -r '.completionTime // ""')
  HIST_AGE=""
  if [ -n "$HIST_COMPLETED" ]; then
    HIST_EPOCH=$(date -d "$HIST_COMPLETED" +%s 2>/dev/null || echo "")
    if [ -n "$HIST_EPOCH" ]; then
      HIST_AGE=$(( (NOW_EPOCH - HIST_EPOCH) / 86400 ))
    fi
  fi

  echo "$entry" | jq -rn \
    --arg cn "$CLUSTER_NAME" --arg cc "$CLUSTER_CONTEXT" --arg cs "$CLUSTER_SERVER" \
    --arg ver "$HIST_VERSION" \
    --arg state "$HIST_STATE" \
    --arg age "$HIST_AGE" '
    [$cn,$cc,$cs,"update_history",$ver,$ver,"","",$state,"",$state,$age,""] | @csv
  ' >> "$OUTPUT_FILE"
done

# =============================================================================
# 2) ClusterOperator versions — each operator and its current version
# =============================================================================
CO_JSON=$(oc get clusteroperators -o json 2>/dev/null || echo '{"items":[]}')

echo "$CO_JSON" | jq -r \
  --arg cn "$CLUSTER_NAME" --arg cc "$CLUSTER_CONTEXT" --arg cs "$CLUSTER_SERVER" '
  .items[] |
  (.status.versions // []) as $versions |
  ($versions | map(select(.name == "operator")) | .[0].version // "") as $op_ver |
  [
    $cn,$cc,$cs,
    "operator_version",
    .metadata.name,
    $op_ver,
    $op_ver,
    "true",
    "",
    "",
    ((.status.conditions // []) | map(select(.type == "Degraded" and .status == "True")) | if length > 0 then "Degraded" else "Healthy" end),
    "",
    ("available=" + (((.status.conditions // []) | map(select(.type == "Available")) | .[0].status) // "") +
     ";progressing=" + (((.status.conditions // []) | map(select(.type == "Progressing")) | .[0].status) // "") +
     ";upgradeable=" + (((.status.conditions // []) | map(select(.type == "Upgradeable")) | .[0].status) // ""))
  ] | @csv
' >> "$OUTPUT_FILE"

# =============================================================================
# 3) MachineConfigPool rollout status — are nodes up to date with config?
# =============================================================================
MCP_JSON=$(oc get machineconfigpools -o json 2>/dev/null || echo '{"items":[]}')

echo "$MCP_JSON" | jq -r \
  --arg cn "$CLUSTER_NAME" --arg cc "$CLUSTER_CONTEXT" --arg cs "$CLUSTER_SERVER" '
  .items[] |
  (.status.machineCount // 0) as $total |
  (.status.readyMachineCount // 0) as $ready |
  (.status.updatedMachineCount // 0) as $updated |
  (.status.degradedMachineCount // 0) as $degraded |
  ($total == $updated and $degraded == 0) as $match |
  [
    $cn,$cc,$cs,
    "machineconfig_pool",
    .metadata.name,
    (.spec.configuration.name // ""),
    (.spec.configuration.name // ""),
    (if $match then "true" else "false" end),
    "",
    "",
    (if $degraded > 0 then "Degraded" elif $total != $updated then "Updating" else "Updated" end),
    "",
    ("total=" + ($total | tostring) +
     ";ready=" + ($ready | tostring) +
     ";updated=" + ($updated | tostring) +
     ";degraded=" + ($degraded | tostring) +
     ";paused=" + (if .spec.paused then "true" else "false" end))
  ] | @csv
' >> "$OUTPUT_FILE"

# =============================================================================
# 4) Node OS and kubelet versions — per-node version tracking
# =============================================================================
NODES_JSON=$(oc get nodes -o json 2>/dev/null || echo '{"items":[]}')

echo "$NODES_JSON" | jq -c '.items[]' | while IFS= read -r node; do
  NODE_NAME=$(echo "$node" | jq -r '.metadata.name // ""')
  KUBELET_VERSION=$(echo "$node" | jq -r '.status.nodeInfo.kubeletVersion // ""')
  OS_IMAGE=$(echo "$node" | jq -r '.status.nodeInfo.osImage // ""')
  KERNEL_VERSION=$(echo "$node" | jq -r '.status.nodeInfo.kernelVersion // ""')
  CONTAINER_RUNTIME=$(echo "$node" | jq -r '.status.nodeInfo.containerRuntimeVersion // ""')
  CURRENT_CONFIG=$(echo "$node" | jq -r '.metadata.annotations["machineconfiguration.openshift.io/currentConfig"] // ""')
  DESIRED_CONFIG=$(echo "$node" | jq -r '.metadata.annotations["machineconfiguration.openshift.io/desiredConfig"] // ""')
  MC_STATE=$(echo "$node" | jq -r '.metadata.annotations["machineconfiguration.openshift.io/state"] // ""')
  ROLES=$(echo "$node" | jq -r '[.metadata.labels // {} | to_entries[] | select(.key | startswith("node-role.kubernetes.io/")) | .key | ltrimstr("node-role.kubernetes.io/")] | join(";")')

  CONFIGS_MATCH="false"
  if [ "$CURRENT_CONFIG" = "$DESIRED_CONFIG" ] && [ -n "$CURRENT_CONFIG" ]; then
    CONFIGS_MATCH="true"
  fi

  CREATED=$(echo "$node" | jq -r '.metadata.creationTimestamp // ""')
  NODE_AGE=""
  if [ -n "$CREATED" ]; then
    CREATED_EPOCH=$(date -d "$CREATED" +%s 2>/dev/null || echo "")
    if [ -n "$CREATED_EPOCH" ]; then
      NODE_AGE=$(( (NOW_EPOCH - CREATED_EPOCH) / 86400 ))
    fi
  fi

  jq -rn \
    --arg cn "$CLUSTER_NAME" --arg cc "$CLUSTER_CONTEXT" --arg cs "$CLUSTER_SERVER" \
    --arg name "$NODE_NAME" \
    --arg kubelet "$KUBELET_VERSION" \
    --arg desired "$DESIRED_CONFIG" \
    --arg match "$CONFIGS_MATCH" \
    --arg state "$MC_STATE" \
    --arg age "$NODE_AGE" \
    --arg details "os=$OS_IMAGE;kernel=$KERNEL_VERSION;runtime=$CONTAINER_RUNTIME;roles=$ROLES;current_config=$CURRENT_CONFIG;desired_config=$DESIRED_CONFIG" '
    [$cn,$cc,$cs,"node_version",$name,$kubelet,$desired,$match,"",$state,"",$age,$details] | @csv
  ' >> "$OUTPUT_FILE"
done

echo "Created: $OUTPUT_FILE"
