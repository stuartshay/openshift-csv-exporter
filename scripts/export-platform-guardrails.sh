#!/usr/bin/env bash
# Description: Exports platform guardrails to detect unapproved distributions and misconfigured components
# Audit Area:  Platform Usage Guardrails
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

OUTPUT_FILE="$OUTPUT_DIR/platform-guardrails-${CLUSTER_NAME_SAFE}-$TIMESTAMP.csv"

# Gather cluster version info
CLUSTERVERSION_JSON=$(oc get clusterversion version -o json 2>/dev/null || echo '{}')

# Gather infrastructure info
INFRA_JSON=$(oc get infrastructure cluster -o json 2>/dev/null || echo '{}')

# Gather cluster operators to detect misconfigured components
CLUSTEROPERATORS_JSON=$(oc get clusteroperators -o json 2>/dev/null || echo '{"items":[]}')

# Count degraded and unavailable operators
DEGRADED_COUNT=$(echo "$CLUSTEROPERATORS_JSON" | jq '[.items[] | select((.status.conditions[]? | select(.type=="Degraded") | .status) == "True")] | length')
UNAVAILABLE_COUNT=$(echo "$CLUSTEROPERATORS_JSON" | jq '[.items[] | select((.status.conditions[]? | select(.type=="Available") | .status) == "False")] | length')
TOTAL_OPERATORS=$(echo "$CLUSTEROPERATORS_JSON" | jq '.items | length')

# List degraded operator names
DEGRADED_OPERATORS=$(echo "$CLUSTEROPERATORS_JSON" | jq -r '[.items[] | select((.status.conditions[]? | select(.type=="Degraded") | .status) == "True") | .metadata.name] | join(";")')

# List unavailable operator names
UNAVAILABLE_OPERATORS=$(echo "$CLUSTEROPERATORS_JSON" | jq -r '[.items[] | select((.status.conditions[]? | select(.type=="Available") | .status) == "False") | .metadata.name] | join(";")')

echo "cluster_name,cluster_context,cluster_server,ocp_version,cluster_id,update_channel,update_state,platform,control_plane_topology,infrastructure_topology,total_operators,degraded_count,unavailable_count,degraded_operators,unavailable_operators" > "$OUTPUT_FILE"

echo "$CLUSTERVERSION_JSON" | jq -r \
  --arg cluster_name "$CLUSTER_NAME" \
  --arg cluster_context "$CLUSTER_CONTEXT" \
  --arg cluster_server "$CLUSTER_SERVER" \
  --arg platform "$(echo "$INFRA_JSON" | jq -r '.status.platformStatus.type // .status.platform // ""')" \
  --arg cp_topology "$(echo "$INFRA_JSON" | jq -r '.status.controlPlaneTopology // ""')" \
  --arg infra_topology "$(echo "$INFRA_JSON" | jq -r '.status.infrastructureTopology // ""')" \
  --arg total_operators "$TOTAL_OPERATORS" \
  --arg degraded_count "$DEGRADED_COUNT" \
  --arg unavailable_count "$UNAVAILABLE_COUNT" \
  --arg degraded_operators "$DEGRADED_OPERATORS" \
  --arg unavailable_operators "$UNAVAILABLE_OPERATORS" '
  [
    $cluster_name,
    $cluster_context,
    $cluster_server,
    (.status.desired.version // ""),
    (.spec.clusterID // ""),
    (.spec.channel // ""),
    (.status.history[0].state // ""),
    $platform,
    $cp_topology,
    $infra_topology,
    $total_operators,
    $degraded_count,
    $unavailable_count,
    $degraded_operators,
    $unavailable_operators
  ] | @csv
' >> "$OUTPUT_FILE"

echo "Created: $OUTPUT_FILE"
