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

OUTPUT_FILE="$OUTPUT_DIR/worker-node-auth-${CLUSTER_NAME_SAFE}-$TIMESTAMP.csv"

# Collect KubeletConfig overrides (if any exist)
KUBELET_CONFIG_JSON="$(oc get kubeletconfig -o json 2>/dev/null || echo '{"items":[]}')"

# Count KubeletConfig overrides
KUBELET_CONFIG_COUNT=$(echo "$KUBELET_CONFIG_JSON" | jq '.items | length')

# Check if anonymous authentication has been overridden
ANONYMOUS_AUTH_OVERRIDE=$(echo "$KUBELET_CONFIG_JSON" | jq -r '
  [.items[] | .spec.kubeletConfig.authentication.anonymous.enabled // empty]
  | if length > 0 then .[0] | tostring else "default" end
')

# Check if authorization mode has been overridden
AUTHORIZATION_MODE_OVERRIDE=$(echo "$KUBELET_CONFIG_JSON" | jq -r '
  [.items[] | .spec.kubeletConfig.authorization.mode // empty]
  | if length > 0 then .[0] else "default" end
')

echo "cluster_name,cluster_context,cluster_server,node_name,node_roles,kubelet_version,ready_status,internal_ip,creation_timestamp,machine_config_state,current_config,desired_config,configs_match,kubelet_config_count,anonymous_auth,authorization_mode" > "$OUTPUT_FILE"

oc get nodes -o json | jq -r \
  --arg cluster_name "$CLUSTER_NAME" \
  --arg cluster_context "$CLUSTER_CONTEXT" \
  --arg cluster_server "$CLUSTER_SERVER" \
  --arg kc_count "$KUBELET_CONFIG_COUNT" \
  --arg anon_auth "$ANONYMOUS_AUTH_OVERRIDE" \
  --arg authz_mode "$AUTHORIZATION_MODE_OVERRIDE" '
  .items[] |
  [
    $cluster_name,
    $cluster_context,
    $cluster_server,
    .metadata.name,
    ([.metadata.labels // {} | to_entries[] | select(.key | startswith("node-role.kubernetes.io/")) | .key | ltrimstr("node-role.kubernetes.io/")] | join(";")),
    (.status.nodeInfo.kubeletVersion // ""),
    ((.status.conditions // []) | map(select(.type == "Ready")) | .[0].status // ""),
    ((.status.addresses // []) | map(select(.type == "InternalIP")) | .[0].address // ""),
    (.metadata.creationTimestamp // ""),
    (.metadata.annotations["machineconfiguration.openshift.io/state"] // ""),
    (.metadata.annotations["machineconfiguration.openshift.io/currentConfig"] // ""),
    (.metadata.annotations["machineconfiguration.openshift.io/desiredConfig"] // ""),
    (
      (.metadata.annotations["machineconfiguration.openshift.io/currentConfig"] // "") as $cur |
      (.metadata.annotations["machineconfiguration.openshift.io/desiredConfig"] // "") as $des |
      if $cur == $des and $cur != "" then "true" else "false" end
    ),
    $kc_count,
    $anon_auth,
    $authz_mode
  ] | @csv
' >> "$OUTPUT_FILE"

echo "Created: $OUTPUT_FILE"
