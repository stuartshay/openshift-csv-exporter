#!/usr/bin/env bash
# Description: Exports control plane protection status — etcd encryption, etcd operator health, control plane node taints, and etcd access RBAC
# Audit Area:  Control Plane Protections
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

OUTPUT_FILE="$OUTPUT_DIR/control-plane-protections-${CLUSTER_NAME_SAFE}-$TIMESTAMP.csv"

echo "cluster_name,cluster_context,cluster_server,check_category,check_name,status,details" > "$OUTPUT_FILE"

# =============================================================================
# 1) etcd Encryption — is etcd data encrypted at rest?
# =============================================================================
APISERVER_JSON=$(oc get apiserver cluster -o json 2>/dev/null || echo '{}')
ENCRYPTION_TYPE=$(echo "$APISERVER_JSON" | jq -r '.spec.encryption.type // "identity"')

# identity = no encryption; aescbc / aesgcm = encrypted
ENCRYPTION_STATUS="false"
if [ "$ENCRYPTION_TYPE" != "identity" ] && [ "$ENCRYPTION_TYPE" != "" ]; then
  ENCRYPTION_STATUS="true"
fi

jq -rn \
  --arg cn "$CLUSTER_NAME" --arg cc "$CLUSTER_CONTEXT" --arg cs "$CLUSTER_SERVER" \
  --arg status "$ENCRYPTION_STATUS" \
  --arg details "encryption_type=$ENCRYPTION_TYPE" '
  [$cn,$cc,$cs,"etcd_encryption","etcd_encryption_at_rest",$status,$details] | @csv
' >> "$OUTPUT_FILE"

# =============================================================================
# 2) etcd Operator Health — is the etcd cluster operator available and not degraded?
# =============================================================================
ETCD_CO_JSON=$(oc get clusteroperator etcd -o json 2>/dev/null || echo '{}')

ETCD_AVAILABLE=$(echo "$ETCD_CO_JSON" | jq -r '(.status.conditions[]? | select(.type=="Available") | .status) // "Unknown"')
ETCD_DEGRADED=$(echo "$ETCD_CO_JSON" | jq -r '(.status.conditions[]? | select(.type=="Degraded") | .status) // "Unknown"')
ETCD_PROGRESSING=$(echo "$ETCD_CO_JSON" | jq -r '(.status.conditions[]? | select(.type=="Progressing") | .status) // "Unknown"')
ETCD_VERSION=$(echo "$ETCD_CO_JSON" | jq -r '(.status.versions[]? | select(.name=="operator") | .version) // ""')

ETCD_HEALTH="true"
if [ "$ETCD_AVAILABLE" != "True" ] || [ "$ETCD_DEGRADED" = "True" ]; then
  ETCD_HEALTH="false"
fi

jq -rn \
  --arg cn "$CLUSTER_NAME" --arg cc "$CLUSTER_CONTEXT" --arg cs "$CLUSTER_SERVER" \
  --arg status "$ETCD_HEALTH" \
  --arg details "available=$ETCD_AVAILABLE;degraded=$ETCD_DEGRADED;progressing=$ETCD_PROGRESSING;version=$ETCD_VERSION" '
  [$cn,$cc,$cs,"etcd_health","etcd_operator_status",$status,$details] | @csv
' >> "$OUTPUT_FILE"

# =============================================================================
# 3) etcd Pod Count — are the expected etcd members running?
# =============================================================================
ETCD_POD_COUNT=$(oc get pods -n openshift-etcd -l app=etcd --no-headers 2>/dev/null | wc -l | tr -d ' ')
ETCD_RUNNING_COUNT=$(oc get pods -n openshift-etcd -l app=etcd --field-selector=status.phase=Running --no-headers 2>/dev/null | wc -l | tr -d ' ')

ETCD_PODS_HEALTHY="true"
if [ "$ETCD_RUNNING_COUNT" -eq 0 ] || [ "$ETCD_RUNNING_COUNT" -ne "$ETCD_POD_COUNT" ]; then
  ETCD_PODS_HEALTHY="false"
fi

jq -rn \
  --arg cn "$CLUSTER_NAME" --arg cc "$CLUSTER_CONTEXT" --arg cs "$CLUSTER_SERVER" \
  --arg status "$ETCD_PODS_HEALTHY" \
  --arg details "total_pods=$ETCD_POD_COUNT;running_pods=$ETCD_RUNNING_COUNT" '
  [$cn,$cc,$cs,"etcd_health","etcd_pod_status",$status,$details] | @csv
' >> "$OUTPUT_FILE"

# =============================================================================
# 4) Control Plane Node Taints — are master nodes tainted to prevent workload scheduling?
# =============================================================================
MASTER_NODES_JSON=$(oc get nodes -l node-role.kubernetes.io/master -o json 2>/dev/null || echo '{"items":[]}')
MASTER_COUNT=$(echo "$MASTER_NODES_JSON" | jq '.items | length')

echo "$MASTER_NODES_JSON" | jq -c '.items[]' | while IFS= read -r node; do
  NODE_NAME=$(echo "$node" | jq -r '.metadata.name // ""')
  HAS_NOSCHEDULE=$(echo "$node" | jq -r '
    if ([(.spec.taints // [])[] | select(.key == "node-role.kubernetes.io/master" and .effect == "NoSchedule")] | length) > 0
    then "true"
    else "false"
    end
  ')
  ALL_TAINTS=$(echo "$node" | jq -r '[(.spec.taints // [])[] | (.key + "=" + (.value // "") + ":" + .effect)] | join(";")')

  jq -rn \
    --arg cn "$CLUSTER_NAME" --arg cc "$CLUSTER_CONTEXT" --arg cs "$CLUSTER_SERVER" \
    --arg status "$HAS_NOSCHEDULE" \
    --arg details "node=$NODE_NAME;taints=$ALL_TAINTS" '
    [$cn,$cc,$cs,"control_plane_isolation","master_node_taint",$status,$details] | @csv
  ' >> "$OUTPUT_FILE"
done

# =============================================================================
# 5) Control Plane Topology — HighlyAvailable vs SingleReplica
# =============================================================================
INFRA_JSON=$(oc get infrastructure cluster -o json 2>/dev/null || echo '{}')
CP_TOPOLOGY=$(echo "$INFRA_JSON" | jq -r '.status.controlPlaneTopology // ""')

CP_HA="true"
if [ "$CP_TOPOLOGY" != "HighlyAvailable" ]; then
  CP_HA="false"
fi

jq -rn \
  --arg cn "$CLUSTER_NAME" --arg cc "$CLUSTER_CONTEXT" --arg cs "$CLUSTER_SERVER" \
  --arg status "$CP_HA" \
  --arg details "topology=$CP_TOPOLOGY;master_node_count=$MASTER_COUNT" '
  [$cn,$cc,$cs,"control_plane_isolation","control_plane_topology",$status,$details] | @csv
' >> "$OUTPUT_FILE"

# =============================================================================
# 6) etcd Namespace RBAC — who has access to the openshift-etcd namespace?
# =============================================================================
ETCD_RB_JSON=$(oc get rolebindings -n openshift-etcd -o json 2>/dev/null || echo '{"items":[]}')

echo "$ETCD_RB_JSON" | jq -r \
  --arg cn "$CLUSTER_NAME" --arg cc "$CLUSTER_CONTEXT" --arg cs "$CLUSTER_SERVER" '
  .items[] |
  . as $binding |
  (.subjects // [])[] |
  [
    $cn,$cc,$cs,
    "etcd_access",
    "etcd_namespace_rolebinding",
    "info",
    ("binding=" + $binding.metadata.name + ";role=" + ($binding.roleRef.name // "") + ";subject_kind=" + (.kind // "") + ";subject_name=" + (.name // "") + ";subject_ns=" + (.namespace // ""))
  ] | @csv
' >> "$OUTPUT_FILE"

# =============================================================================
# 7) etcd-related ClusterRoleBindings — cluster-wide etcd access
# =============================================================================
ETCD_CRB_JSON=$(oc get clusterrolebindings -o json 2>/dev/null || echo '{"items":[]}')

echo "$ETCD_CRB_JSON" | jq -r \
  --arg cn "$CLUSTER_NAME" --arg cc "$CLUSTER_CONTEXT" --arg cs "$CLUSTER_SERVER" '
  .items[] |
  select(.metadata.name | test("etcd"; "i")) |
  . as $binding |
  (.subjects // [])[] |
  [
    $cn,$cc,$cs,
    "etcd_access",
    "etcd_clusterrolebinding",
    "info",
    ("binding=" + $binding.metadata.name + ";role=" + ($binding.roleRef.name // "") + ";subject_kind=" + (.kind // "") + ";subject_name=" + (.name // "") + ";subject_ns=" + (.namespace // ""))
  ] | @csv
' >> "$OUTPUT_FILE"

# =============================================================================
# 8) etcd Serving Certificate — verify certs exist in openshift-etcd
# =============================================================================
ETCD_SECRETS_JSON=$(oc get secrets -n openshift-etcd -o json 2>/dev/null || echo '{"items":[]}')
ETCD_TLS_COUNT=$(echo "$ETCD_SECRETS_JSON" | jq '[.items[] | select(.type == "kubernetes.io/tls")] | length')
ETCD_CERT_NAMES=$(echo "$ETCD_SECRETS_JSON" | jq -r '[.items[] | select(.type == "kubernetes.io/tls") | .metadata.name] | join(";")')

CERTS_PRESENT="true"
if [ "$ETCD_TLS_COUNT" -eq 0 ]; then
  CERTS_PRESENT="false"
fi

jq -rn \
  --arg cn "$CLUSTER_NAME" --arg cc "$CLUSTER_CONTEXT" --arg cs "$CLUSTER_SERVER" \
  --arg status "$CERTS_PRESENT" \
  --arg details "tls_secret_count=$ETCD_TLS_COUNT;cert_names=$ETCD_CERT_NAMES" '
  [$cn,$cc,$cs,"etcd_certificates","etcd_tls_secrets",$status,$details] | @csv
' >> "$OUTPUT_FILE"

echo "Created: $OUTPUT_FILE"
