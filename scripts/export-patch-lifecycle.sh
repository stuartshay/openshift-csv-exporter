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

SCRIPT_START_SECONDS=$SECONDS
NOW_EPOCH=$(date +%s)

echo "[patch-lifecycle] Starting export at $(date)"
echo "[patch-lifecycle] Output file: $OUTPUT_FILE"

echo "cluster_name,cluster_context,cluster_server,check_category,resource_name,current_version,desired_version,versions_match,update_channel,available_updates,update_state,age_days,details" > "$OUTPUT_FILE"

# Pure-bash CSV writer — avoids spawning jq per row. Uses only parameter
# expansion so each row is fork-free; on clusters with many nodes this is
# dramatically faster than calling jq -rn per row.
write_row() {
  local row f esc
  esc="${CLUSTER_NAME//\"/\"\"}";    row="\"$esc\""
  esc="${CLUSTER_CONTEXT//\"/\"\"}"; row+=",\"$esc\""
  esc="${CLUSTER_SERVER//\"/\"\"}";  row+=",\"$esc\""
  for f in "$@"; do
    esc="${f//\"/\"\"}"
    row+=",\"$esc\""
  done
  printf '%s\n' "$row"
}

# =============================================================================
# 1) Cluster Version — current OCP version, channel, available updates
# =============================================================================
echo "[patch-lifecycle] Fetching clusterversion..."
CV_ERR=$(mktemp)
if ! CV_JSON=$(oc get clusterversion version -o json 2>"$CV_ERR"); then
  echo "[patch-lifecycle] WARNING: oc get clusterversion failed:" >&2
  cat "$CV_ERR" >&2
  CV_JSON='{}'
fi
rm -f "$CV_ERR"
echo "[patch-lifecycle] Clusterversion fetched."

CURRENT_VERSION=$(echo "$CV_JSON" | jq -r '.status.desired.version // ""')
UPDATE_CHANNEL=$(echo "$CV_JSON" | jq -r '.spec.channel // ""')
UPDATE_STATE=$(echo "$CV_JSON" | jq -r '.status.history[0].state // ""')
AVAILABLE_UPDATES=$(echo "$CV_JSON" | jq -r '[(.status.availableUpdates // [])[] | .version] | join(";")')
AVAILABLE_COUNT=$(echo "$CV_JSON" | jq '[(.status.availableUpdates // [])] | .[0] | length')

echo "[patch-lifecycle] Cluster version=$CURRENT_VERSION channel=$UPDATE_CHANNEL state=$UPDATE_STATE"

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

# Update history — each version that was applied (single jq pass, no per-item loop)
HIST_COUNT=$(echo "$CV_JSON" | jq '[.status.history // [] | .[]] | length' | tr -d '\r')
echo "[patch-lifecycle] Processing $HIST_COUNT update history entries..."

echo "$CV_JSON" | jq -r '.status.history // [] |
  .[] | [(.version // ""), (.state // ""), (.completionTime // "")] | @tsv
' | {
  while IFS=$'\t' read -r HIST_VERSION HIST_STATE HIST_COMPLETED; do
    HIST_AGE=""
    if [ -n "$HIST_COMPLETED" ]; then
      HIST_EPOCH=$(date -d "$HIST_COMPLETED" +%s 2>/dev/null || echo "")
      if [ -n "$HIST_EPOCH" ]; then
        HIST_AGE=$(( (NOW_EPOCH - HIST_EPOCH) / 86400 ))
      fi
    fi
    write_row "update_history" "$HIST_VERSION" "$HIST_VERSION" "" "" "$HIST_STATE" "" "$HIST_STATE" "$HIST_AGE" ""
  done
} >> "$OUTPUT_FILE"

echo "[patch-lifecycle] Update history done."

# =============================================================================
# 2) ClusterOperator versions — each operator and its current version
# =============================================================================
echo "[patch-lifecycle] Fetching clusteroperators..."
CO_ERR=$(mktemp)
if ! CO_JSON=$(oc get clusteroperators -o json 2>"$CO_ERR"); then
  echo "[patch-lifecycle] WARNING: oc get clusteroperators failed:" >&2
  cat "$CO_ERR" >&2
  CO_JSON='{"items":[]}'
fi
rm -f "$CO_ERR"
CO_COUNT=$(echo "$CO_JSON" | jq '.items | length' | tr -d '\r')
echo "[patch-lifecycle] Processing $CO_COUNT clusteroperators..."
if [ "$CO_COUNT" -eq 0 ]; then
  echo "[patch-lifecycle] WARNING: 0 clusteroperators found — possible auth or permission issue"
fi

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

echo "[patch-lifecycle] ClusterOperators done."

# =============================================================================
# 3) MachineConfigPool rollout status — are nodes up to date with config?
# =============================================================================
echo "[patch-lifecycle] Fetching machineconfigpools..."
MCP_ERR=$(mktemp)
if ! MCP_JSON=$(oc get machineconfigpools -o json 2>"$MCP_ERR"); then
  echo "[patch-lifecycle] WARNING: oc get machineconfigpools failed:" >&2
  cat "$MCP_ERR" >&2
  MCP_JSON='{"items":[]}'
fi
rm -f "$MCP_ERR"
MCP_COUNT=$(echo "$MCP_JSON" | jq '.items | length' | tr -d '\r')
echo "[patch-lifecycle] Processing $MCP_COUNT machineconfigpools..."
if [ "$MCP_COUNT" -eq 0 ]; then
  echo "[patch-lifecycle] WARNING: 0 machineconfigpools found — possible auth or permission issue"
fi

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

echo "[patch-lifecycle] MachineConfigPools done."

# =============================================================================
# 4) Node OS and kubelet versions — per-node version tracking
# =============================================================================
echo "[patch-lifecycle] Fetching nodes..."
NODES_ERR=$(mktemp)
if ! NODES_JSON=$(oc get nodes -o json 2>"$NODES_ERR"); then
  echo "[patch-lifecycle] WARNING: oc get nodes failed:" >&2
  cat "$NODES_ERR" >&2
  NODES_JSON='{"items":[]}'
fi
rm -f "$NODES_ERR"
NODE_COUNT=$(echo "$NODES_JSON" | jq '.items | length' | tr -d '\r')
echo "[patch-lifecycle] Processing $NODE_COUNT nodes..."
if [ "$NODE_COUNT" -eq 0 ]; then
  echo "[patch-lifecycle] WARNING: 0 nodes found — possible auth or permission issue"
fi

# Single jq pass emits one TSV line per node; shell loop only handles
# date math + CSV emit. Avoids ~11 jq invocations per node.
NODE_LOOP_START=$SECONDS
echo "$NODES_JSON" | jq -r '.items[] |
  [
    (.metadata.name // ""),
    (.status.nodeInfo.kubeletVersion // ""),
    (.status.nodeInfo.osImage // ""),
    (.status.nodeInfo.kernelVersion // ""),
    (.status.nodeInfo.containerRuntimeVersion // ""),
    (.metadata.annotations["machineconfiguration.openshift.io/currentConfig"] // ""),
    (.metadata.annotations["machineconfiguration.openshift.io/desiredConfig"] // ""),
    (.metadata.annotations["machineconfiguration.openshift.io/state"] // ""),
    ([.metadata.labels // {} | to_entries[] | select(.key | startswith("node-role.kubernetes.io/")) | .key | ltrimstr("node-role.kubernetes.io/")] | join(";")),
    (.metadata.creationTimestamp // "")
  ] | @tsv
' | {
  NODE_IDX=0
  while IFS=$'\t' read -r NODE_NAME KUBELET_VERSION OS_IMAGE KERNEL_VERSION CONTAINER_RUNTIME CURRENT_CONFIG DESIRED_CONFIG MC_STATE ROLES CREATED; do
    NODE_IDX=$((NODE_IDX + 1))

    CONFIGS_MATCH="false"
    if [ "$CURRENT_CONFIG" = "$DESIRED_CONFIG" ] && [ -n "$CURRENT_CONFIG" ]; then
      CONFIGS_MATCH="true"
    fi

    NODE_AGE=""
    if [ -n "$CREATED" ]; then
      CREATED_EPOCH=$(date -d "$CREATED" +%s 2>/dev/null || echo "")
      if [ -n "$CREATED_EPOCH" ]; then
        NODE_AGE=$(( (NOW_EPOCH - CREATED_EPOCH) / 86400 ))
      fi
    fi

    DETAILS="os=$OS_IMAGE;kernel=$KERNEL_VERSION;runtime=$CONTAINER_RUNTIME;roles=$ROLES;current_config=$CURRENT_CONFIG;desired_config=$DESIRED_CONFIG"
    write_row "node_version" "$NODE_NAME" "$KUBELET_VERSION" "$DESIRED_CONFIG" "$CONFIGS_MATCH" "" "$MC_STATE" "" "$NODE_AGE" "$DETAILS"

    if [ $((NODE_IDX % 25)) -eq 0 ] || [ "$NODE_IDX" = "$NODE_COUNT" ]; then
      LOOP_ELAPSED=$(( SECONDS - NODE_LOOP_START ))
      echo "[patch-lifecycle]   Processed $NODE_IDX/$NODE_COUNT nodes (last: $NODE_NAME) — elapsed: ${LOOP_ELAPSED}s" >&2
    fi
  done
} >> "$OUTPUT_FILE"

NODE_LOOP_ELAPSED=$(( SECONDS - NODE_LOOP_START ))
echo "[patch-lifecycle] Nodes done — $NODE_COUNT nodes processed in ${NODE_LOOP_ELAPSED}s."

ELAPSED=$(( SECONDS - SCRIPT_START_SECONDS ))
echo "[patch-lifecycle] Completed at $(date) — total time: ${ELAPSED}s"
echo "Created: $OUTPUT_FILE"
