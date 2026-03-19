#!/usr/bin/env bash
# Description: Exports secrets from critical namespaces to audit credential management
# Audit Area:  Cluster Admin/SRE Credential Management
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

OUTPUT_FILE="$OUTPUT_DIR/credential-management-${CLUSTER_NAME_SAFE}-$TIMESTAMP.csv"

# Check if kubeadmin secret still exists
KUBEADMIN_EXISTS="false"
if oc get secret kubeadmin -n kube-system >/dev/null 2>&1; then
  KUBEADMIN_EXISTS="true"
fi

# Namespaces where cluster admin / infrastructure credentials are stored
CRITICAL_NS="kube-system openshift-config openshift-config-managed"

echo "cluster_name,cluster_context,cluster_server,kubeadmin_exists,namespace,secret_name,secret_type,creation_timestamp,age_days,service_account" > "$OUTPUT_FILE"

for NS in $CRITICAL_NS; do
  oc get secrets -n "$NS" -o json 2>/dev/null | jq -r \
    --arg cluster_name "$CLUSTER_NAME" \
    --arg cluster_context "$CLUSTER_CONTEXT" \
    --arg cluster_server "$CLUSTER_SERVER" \
    --arg kubeadmin_exists "$KUBEADMIN_EXISTS" \
    --arg ns "$NS" '
    def age_days:
      (now - (. | fromdateiso8601)) / 86400 | floor;
    .items[] |
    [
      $cluster_name,
      $cluster_context,
      $cluster_server,
      $kubeadmin_exists,
      $ns,
      (.metadata.name // ""),
      (.type // ""),
      (.metadata.creationTimestamp // ""),
      ((.metadata.creationTimestamp // "" | if . != "" then age_days else "" end) // ""),
      (.metadata.annotations["kubernetes.io/service-account.name"] // "")
    ] | @csv
  ' >> "$OUTPUT_FILE"
done

echo "Created: $OUTPUT_FILE"
