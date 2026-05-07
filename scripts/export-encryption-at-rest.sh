#!/usr/bin/env bash
# Description: Exports cluster-wide encryption-at-rest posture — etcd encryption type, StorageClass encryption parameters, MachineConfig LUKS / Tang / Clevis configuration, and PV encryption status — for OCP-46 Encryption at Rest auditing
# Audit Area:  Encryption at Rest
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./common.sh
source "$SCRIPT_DIR/common.sh"

SCRIPT_START_SECONDS=$SECONDS
LABEL="encryption-at-rest"
RED='\033[0;31m'
NC='\033[0m'

: "${CLUSTER_NAME_SAFE:?CLUSTER_NAME_SAFE is not set}"
: "${CLUSTER_NAME:?CLUSTER_NAME is not set}"
: "${CLUSTER_CONTEXT:?CLUSTER_CONTEXT is not set}"
: "${CLUSTER_SERVER:?CLUSTER_SERVER is not set}"
: "${OUTPUT_DIR:?OUTPUT_DIR is not set}"
: "${TIMESTAMP:?TIMESTAMP is not set}"

echo "[$(date +%H:%M:%S)] [$LABEL] Starting export at $(date)"

OUTPUT_FILE="$OUTPUT_DIR/encryption-at-rest-${CLUSTER_NAME_SAFE}-$TIMESTAMP.csv"
echo "cluster_name,cluster_context,cluster_server,record_type,name,namespace,detail_1,detail_2,detail_3,detail_4,detail_5,detail_6" > "$OUTPUT_FILE"

write_row() {
  jq -nr \
    --arg cluster_name "$CLUSTER_NAME" \
    --arg cluster_context "$CLUSTER_CONTEXT" \
    --arg cluster_server "$CLUSTER_SERVER" \
    --arg record_type "$1" \
    --arg name "$2" \
    --arg namespace "$3" \
    --arg d1 "$4" \
    --arg d2 "$5" \
    --arg d3 "$6" \
    --arg d4 "$7" \
    --arg d5 "$8" \
    --arg d6 "$9" \
    '[$cluster_name,$cluster_context,$cluster_server,$record_type,$name,$namespace,$d1,$d2,$d3,$d4,$d5,$d6] | @csv' >> "$OUTPUT_FILE"
}

# ── Section 1: etcd encryption ───────────────────────────────────────────────
echo "[$(date +%H:%M:%S)] [$LABEL] Fetching apiserver.config.openshift.io/cluster..."
APISERVER_JSON=$(oc get apiserver.config.openshift.io/cluster -o json 2>/dev/null || echo '{}')
ETCD_TYPE=$(echo "$APISERVER_JSON" | jq -r '.spec.encryption.type // ""')
ETCD_ENABLED="false"
if [ "$ETCD_TYPE" = "aescbc" ] || [ "$ETCD_TYPE" = "aesgcm" ]; then
  ETCD_ENABLED="true"
fi
write_row "etcd_encryption" "cluster" "" "$ETCD_TYPE" "" "" "secrets;configmaps" "$ETCD_ENABLED" ""

if [ "$ETCD_ENABLED" != "true" ]; then
  echo -e "${RED}[$(date +%H:%M:%S)] [$LABEL] WARNING: etcd encryption is not enabled (type='$ETCD_TYPE')${NC}"
fi

# ── Section 2: StorageClasses ────────────────────────────────────────────────
echo "[$(date +%H:%M:%S)] [$LABEL] Fetching storageclasses..."
SC_JSON=$(oc get storageclasses -o json 2>/dev/null || echo '{"items":[]}')
SC_COUNT=$(echo "$SC_JSON" | jq '.items | length')
echo "[$(date +%H:%M:%S)] [$LABEL] Processing $SC_COUNT storageclasses..."

echo "$SC_JSON" | jq -c '.items[]' | while IFS= read -r sc; do
  NAME=$(echo "$sc" | jq -r '.metadata.name // ""')
  PROVISIONER=$(echo "$sc" | jq -r '.provisioner // ""')
  ENCRYPTED=$(echo "$sc" | jq -r '.parameters.encrypted // .parameters.csi_encryption // ""')
  KMS=$(echo "$sc" | jq -r '.parameters.kmsKeyId // .parameters["csi.storage.k8s.io/encryption-key-id"] // ""')
  IS_DEFAULT=$(echo "$sc" | jq -r '.metadata.annotations["storageclass.kubernetes.io/is-default-class"] // "false"')
  RECLAIM=$(echo "$sc" | jq -r '.reclaimPolicy // ""')
  BINDING=$(echo "$sc" | jq -r '.volumeBindingMode // ""')
  write_row "storage_class" "$NAME" "" "$PROVISIONER" "$ENCRYPTED" "$KMS" "$IS_DEFAULT" "$RECLAIM" "$BINDING"
done

# ── Section 3: MachineConfigs LUKS ───────────────────────────────────────────
echo "[$(date +%H:%M:%S)] [$LABEL] Fetching machineconfigs (LUKS)..."
MC_JSON=$(oc get machineconfigs -o json 2>/dev/null || echo '{"items":[]}')
echo "$MC_JSON" | jq -c '.items[] | select((.spec.config.storage.luks // []) | length > 0)' | while IFS= read -r mc; do
  NAME=$(echo "$mc" | jq -r '.metadata.name // ""')
  TANG_URL=$(echo "$mc" | jq -r '[.spec.config.storage.luks[]?.clevis.tang[]?.url] | join(";")')
  PIN_TYPE=$(echo "$mc" | jq -r '
    if (.spec.config.storage.luks[]?.clevis.tang // []) | length > 0 then "tang"
    elif (.spec.config.storage.luks[]?.clevis.tpm2 // false) then "tpm2"
    else "" end' | head -1)
  OPTIONS=$(echo "$mc" | jq -r '[.spec.config.storage.luks[]?.options[]?] | join(",")')
  write_row "machine_config_luks" "$NAME" "" "$TANG_URL" "$PIN_TYPE" "true" "$OPTIONS" "" ""
done

# ── Section 4: PersistentVolumes (sample) ───────────────────────────────────
echo "[$(date +%H:%M:%S)] [$LABEL] Fetching persistentvolumes..."
PV_JSON=$(oc get pv -o json 2>/dev/null || echo '{"items":[]}')
echo "$PV_JSON" | jq -c '.items[]' | while IFS= read -r pv; do
  NAME=$(echo "$pv" | jq -r '.metadata.name // ""')
  SC=$(echo "$pv" | jq -r '.spec.storageClassName // ""')
  CAPACITY=$(echo "$pv" | jq -r '.spec.capacity.storage // ""')
  ACCESS=$(echo "$pv" | jq -r '[.spec.accessModes[]?] | join(";")')
  CLAIM_NS=$(echo "$pv" | jq -r '.spec.claimRef.namespace // ""')
  ENCRYPTED=""
  if [ -n "$SC" ]; then
    ENCRYPTED=$(echo "$SC_JSON" | jq -r --arg sc "$SC" '
      .items[] | select(.metadata.name == $sc) |
      (.parameters.encrypted // .parameters.csi_encryption // "")' | head -1)
  fi
  write_row "persistent_volume" "$NAME" "$CLAIM_NS" "$SC" "$ENCRYPTED" "$CAPACITY" "$ACCESS" "" ""
done

ELAPSED=$(( SECONDS - SCRIPT_START_SECONDS ))
echo "[$(date +%H:%M:%S)] [$LABEL] Completed at $(date) — total time: ${ELAPSED}s"
echo "Created: $OUTPUT_FILE"
