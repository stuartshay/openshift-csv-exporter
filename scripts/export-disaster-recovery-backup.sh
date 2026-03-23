#!/usr/bin/env bash
# Description: Exports disaster recovery and backup readiness data — etcd member health, control plane operator status, OADP/Velero detection, and volume snapshot readiness
# Audit Area:  Disaster Recovery & Cluster Backup
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

OUTPUT_FILE="$OUTPUT_DIR/disaster-recovery-backup-${CLUSTER_NAME_SAFE}-$TIMESTAMP.csv"

LABEL="disaster-recovery-backup"
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

SCRIPT_START_SECONDS=$SECONDS
NOW_EPOCH=$(date +%s)

echo "[$LABEL] Starting export at $(date)"
echo "[$LABEL] Output file: $OUTPUT_FILE"

# CSV header
echo "cluster_name,cluster_context,cluster_server,record_type,resource_name,namespace,condition_available,condition_degraded,condition_progressing,detail,message,last_transition,age_days" > "$OUTPUT_FILE"

# =============================================================================
# 1) etcd Member Health — oc get etcd cluster
# =============================================================================
echo "[$LABEL] Fetching etcd cluster resource..."

ETCD_JSON=""
ETCD_OK=true
if ! ETCD_JSON=$(oc get etcd cluster -o json 2>/dev/null | tr -d '\r'); then
  echo -e "${RED}[$LABEL] ERROR: Failed to fetch etcd cluster resource — permission denied or resource unavailable${NC}"
  echo -e "${RED}[$LABEL] Hint: oc auth can-i get etcd.operator.openshift.io/cluster${NC}"
  ETCD_OK=false
fi

ETCD_AVAILABLE=""
ETCD_DEGRADED=""
ETCD_PROGRESSING=""
ETCD_MEMBER_COUNT=0
ETCD_MESSAGE=""
ETCD_LAST_TRANSITION=""

if [ "$ETCD_OK" = true ] && [ -n "$ETCD_JSON" ]; then
  # Extract conditions
  ETCD_AVAILABLE=$(echo "$ETCD_JSON" | jq -r '
    [.status.conditions // [] | .[] | select(.type=="Available")] | first | .status // ""
  ' | tr -d '\r')
  ETCD_DEGRADED=$(echo "$ETCD_JSON" | jq -r '
    [.status.conditions // [] | .[] | select(.type=="Degraded")] | first | .status // ""
  ' | tr -d '\r')
  ETCD_PROGRESSING=$(echo "$ETCD_JSON" | jq -r '
    [.status.conditions // [] | .[] | select(.type=="Progressing")] | first | .status // ""
  ' | tr -d '\r')
  ETCD_MESSAGE=$(echo "$ETCD_JSON" | jq -r '
    [.status.conditions // [] | .[] | select(.type=="Degraded")] | first | .message // ""
  ' | tr -d '\r')
  ETCD_LAST_TRANSITION=$(echo "$ETCD_JSON" | jq -r '
    [.status.conditions // [] | .[] | select(.type=="Available")] | first | .lastTransitionTime // ""
  ' | tr -d '\r')

  # Count etcd members from nodeStatuses
  ETCD_MEMBER_COUNT=$(echo "$ETCD_JSON" | jq '
    [.status.nodeStatuses // [] | .[] ] | length
  ' | tr -d '\r')

  # Compute age
  ETCD_CREATED=$(echo "$ETCD_JSON" | jq -r '.metadata.creationTimestamp // ""' | tr -d '\r')
  ETCD_AGE=""
  if [ -n "$ETCD_CREATED" ]; then
    ETCD_EPOCH=$(date -d "$ETCD_CREATED" +%s 2>/dev/null || echo "")
    if [ -n "$ETCD_EPOCH" ]; then
      ETCD_AGE=$(( (NOW_EPOCH - ETCD_EPOCH) / 86400 ))
    fi
  fi

  # Write etcd cluster row
  echo "$ETCD_JSON" | jq -r \
    --arg cn "$CLUSTER_NAME" --arg cc "$CLUSTER_CONTEXT" --arg cs "$CLUSTER_SERVER" \
    --arg avail "$ETCD_AVAILABLE" --arg deg "$ETCD_DEGRADED" --arg prog "$ETCD_PROGRESSING" \
    --arg detail "members=$ETCD_MEMBER_COUNT" --arg msg "$ETCD_MESSAGE" \
    --arg lt "$ETCD_LAST_TRANSITION" --arg age "$ETCD_AGE" '
    [
      $cn, $cc, $cs,
      "etcd_member",
      "etcd-cluster",
      "",
      $avail,
      $deg,
      $prog,
      $detail,
      $msg,
      $lt,
      $age
    ] | @csv
  ' >> "$OUTPUT_FILE"

  # Write per-node etcd member rows
  echo "$ETCD_JSON" | jq -c '.status.nodeStatuses // [] | .[]' | tr -d '\r' | while IFS= read -r node; do
    NODE_NAME=$(echo "$node" | jq -r '.nodeName // ""')
    CURRENT_REV=$(echo "$node" | jq -r '.currentRevision // 0')
    TARGET_REV=$(echo "$node" | jq -r '.targetRevision // 0')

    echo "$node" | jq -r \
      --arg cn "$CLUSTER_NAME" --arg cc "$CLUSTER_CONTEXT" --arg cs "$CLUSTER_SERVER" \
      --arg nn "$NODE_NAME" --arg detail "currentRevision=$CURRENT_REV;targetRevision=$TARGET_REV" \
      --arg avail "$ETCD_AVAILABLE" --arg age "$ETCD_AGE" '
      [
        $cn, $cc, $cs,
        "etcd_member",
        $nn,
        "openshift-etcd",
        $avail,
        "",
        "",
        $detail,
        "",
        "",
        $age
      ] | @csv
    '
  done >> "$OUTPUT_FILE"

  echo "[$LABEL] etcd cluster: Available=$ETCD_AVAILABLE, Degraded=$ETCD_DEGRADED, Members=$ETCD_MEMBER_COUNT"
else
  echo "[$LABEL] Skipping etcd member details (fetch failed)."
fi
echo "[$LABEL] etcd section done."

# =============================================================================
# 2) Control Plane Operator Readiness — kubeapiserver, kubecontrollermanager, kubescheduler
# =============================================================================
CP_OPERATORS=("kubeapiserver" "kubecontrollermanager" "kubescheduler")
CP_DEGRADED_COUNT=0

echo "[$LABEL] Fetching control plane operator status..."

for OP in "${CP_OPERATORS[@]}"; do
  echo "[$LABEL] Fetching $OP cluster..."
  OP_JSON=""
  if ! OP_JSON=$(oc get "$OP" cluster -o json 2>/dev/null | tr -d '\r'); then
    echo -e "${RED}[$LABEL] ERROR: Failed to fetch $OP — skipping${NC}"
    continue
  fi

  OP_AVAILABLE=$(echo "$OP_JSON" | jq -r '
    [.status.conditions // [] | .[] | select(.type=="Available")] | first | .status // ""
  ' | tr -d '\r')
  OP_DEGRADED=$(echo "$OP_JSON" | jq -r '
    [.status.conditions // [] | .[] | select(.type=="Degraded")] | first | .status // ""
  ' | tr -d '\r')
  OP_PROGRESSING=$(echo "$OP_JSON" | jq -r '
    [.status.conditions // [] | .[] | select(.type=="Progressing")] | first | .status // ""
  ' | tr -d '\r')
  OP_DEG_MSG=$(echo "$OP_JSON" | jq -r '
    [.status.conditions // [] | .[] | select(.type=="Degraded")] | first | .message // ""
  ' | tr -d '\r')
  OP_LAST_TRANSITION=$(echo "$OP_JSON" | jq -r '
    [.status.conditions // [] | .[] | select(.type=="Available")] | first | .lastTransitionTime // ""
  ' | tr -d '\r')

  # Node revision info
  NODE_REVISIONS=$(echo "$OP_JSON" | jq -r '
    [.status.nodeStatuses // [] | .[] |
     (.nodeName // "unknown") + "=rev" + ((.currentRevision // 0) | tostring)
    ] | join(";")
  ' | tr -d '\r')

  # Age
  OP_CREATED=$(echo "$OP_JSON" | jq -r '.metadata.creationTimestamp // ""' | tr -d '\r')
  OP_AGE=""
  if [ -n "$OP_CREATED" ]; then
    OP_EPOCH=$(date -d "$OP_CREATED" +%s 2>/dev/null || echo "")
    if [ -n "$OP_EPOCH" ]; then
      OP_AGE=$(( (NOW_EPOCH - OP_EPOCH) / 86400 ))
    fi
  fi

  echo "$OP_JSON" | jq -r \
    --arg cn "$CLUSTER_NAME" --arg cc "$CLUSTER_CONTEXT" --arg cs "$CLUSTER_SERVER" \
    --arg op "$OP" --arg avail "$OP_AVAILABLE" --arg deg "$OP_DEGRADED" \
    --arg prog "$OP_PROGRESSING" --arg detail "$NODE_REVISIONS" \
    --arg msg "$OP_DEG_MSG" --arg lt "$OP_LAST_TRANSITION" --arg age "$OP_AGE" '
    [
      $cn, $cc, $cs,
      "cp_operator",
      $op,
      "",
      $avail,
      $deg,
      $prog,
      $detail,
      $msg,
      $lt,
      $age
    ] | @csv
  ' >> "$OUTPUT_FILE"

  if [ "$OP_DEGRADED" = "True" ]; then
    CP_DEGRADED_COUNT=$((CP_DEGRADED_COUNT + 1))
  fi

  echo "[$LABEL]   $OP: Available=$OP_AVAILABLE, Degraded=$OP_DEGRADED"
done
echo "[$LABEL] Control plane operators done."

# =============================================================================
# 3) OADP / Velero Detection
# =============================================================================
echo "[$LABEL] Checking for OADP/Velero backup infrastructure..."

OADP_INSTALLED=false
BSL_COUNT=0
BACKUP_COUNT=0

# Check if openshift-adp namespace exists
if oc get namespace openshift-adp -o json 2>/dev/null | tr -d '\r' | jq -e '.metadata.name' > /dev/null 2>&1; then
  OADP_INSTALLED=true
  echo "[$LABEL] OADP namespace (openshift-adp) detected."

  # BackupStorageLocations
  echo "[$LABEL] Fetching BackupStorageLocations..."
  BSL_JSON=""
  if BSL_JSON=$(oc get backupstoragelocations -n openshift-adp -o json 2>/dev/null | tr -d '\r'); then
    BSL_COUNT=$(echo "$BSL_JSON" | jq '.items | length' | tr -d '\r')
    echo "[$LABEL] Found $BSL_COUNT BackupStorageLocations."

    if [ "$BSL_COUNT" -gt 0 ]; then
      echo "$BSL_JSON" | jq -c '.items[]' | while IFS= read -r bsl; do
        BSL_NAME=$(echo "$bsl" | jq -r '.metadata.name // ""')
        BSL_PHASE=$(echo "$bsl" | jq -r '.status.phase // ""')
        BSL_BUCKET=$(echo "$bsl" | jq -r '.spec.objectStorage.bucket // ""')
        BSL_PROVIDER=$(echo "$bsl" | jq -r '.spec.provider // ""')
        BSL_LAST=$(echo "$bsl" | jq -r '.status.lastValidationTime // ""')

        BSL_CREATED=$(echo "$bsl" | jq -r '.metadata.creationTimestamp // ""')
        BSL_AGE=""
        if [ -n "$BSL_CREATED" ]; then
          BSL_EPOCH=$(date -d "$BSL_CREATED" +%s 2>/dev/null || echo "")
          if [ -n "$BSL_EPOCH" ]; then
            BSL_AGE=$(( (NOW_EPOCH - BSL_EPOCH) / 86400 ))
          fi
        fi

        echo "$bsl" | jq -r \
          --arg cn "$CLUSTER_NAME" --arg cc "$CLUSTER_CONTEXT" --arg cs "$CLUSTER_SERVER" \
          --arg name "$BSL_NAME" --arg detail "provider=$BSL_PROVIDER;bucket=$BSL_BUCKET" \
          --arg msg "phase=$BSL_PHASE" --arg lt "$BSL_LAST" --arg age "$BSL_AGE" '
          [
            $cn, $cc, $cs,
            "oadp_backup",
            $name,
            "openshift-adp",
            "",
            "",
            "",
            $detail,
            $msg,
            $lt,
            $age
          ] | @csv
        '
      done >> "$OUTPUT_FILE"
    fi
  else
    echo "[$LABEL] Could not fetch BackupStorageLocations (CRD may not exist)."
  fi

  # Velero Backups
  echo "[$LABEL] Fetching Velero Backups..."
  BACKUP_JSON=""
  if BACKUP_JSON=$(oc get backups.velero.io -n openshift-adp -o json 2>/dev/null | tr -d '\r'); then
    BACKUP_COUNT=$(echo "$BACKUP_JSON" | jq '.items | length' | tr -d '\r')
    echo "[$LABEL] Found $BACKUP_COUNT Velero Backups."

    if [ "$BACKUP_COUNT" -gt 0 ]; then
      # Export the 10 most recent backups
      echo "$BACKUP_JSON" | jq -c '[.items[] | {name: .metadata.name, ns: .metadata.namespace, created: .metadata.creationTimestamp, phase: (.status.phase // ""), expiration: (.status.expiration // ""), errors: ((.status.errors // 0) | tostring), warnings: ((.status.warnings // 0) | tostring)}] | sort_by(.created) | reverse | .[:10][]' | tr -d '\r' | while IFS= read -r bk; do
        BK_NAME=$(echo "$bk" | jq -r '.name // ""')
        BK_PHASE=$(echo "$bk" | jq -r '.phase // ""')
        BK_ERRORS=$(echo "$bk" | jq -r '.errors // "0"')
        BK_WARNINGS=$(echo "$bk" | jq -r '.warnings // "0"')
        BK_EXPIRATION=$(echo "$bk" | jq -r '.expiration // ""')

        BK_CREATED=$(echo "$bk" | jq -r '.created // ""')
        BK_AGE=""
        if [ -n "$BK_CREATED" ]; then
          BK_EPOCH=$(date -d "$BK_CREATED" +%s 2>/dev/null || echo "")
          if [ -n "$BK_EPOCH" ]; then
            BK_AGE=$(( (NOW_EPOCH - BK_EPOCH) / 86400 ))
          fi
        fi

        echo "$bk" | jq -r \
          --arg cn "$CLUSTER_NAME" --arg cc "$CLUSTER_CONTEXT" --arg cs "$CLUSTER_SERVER" \
          --arg name "$BK_NAME" --arg detail "errors=$BK_ERRORS;warnings=$BK_WARNINGS;expiration=$BK_EXPIRATION" \
          --arg msg "phase=$BK_PHASE" --arg lt "$BK_CREATED" --arg age "$BK_AGE" '
          [
            $cn, $cc, $cs,
            "oadp_backup",
            $name,
            "openshift-adp",
            "",
            "",
            "",
            $detail,
            $msg,
            $lt,
            $age
          ] | @csv
        '
      done >> "$OUTPUT_FILE"
    fi
  else
    echo "[$LABEL] Could not fetch Velero Backups (CRD may not exist)."
  fi
else
  echo -e "${YELLOW}[$LABEL] OADP namespace not found — no external backup tooling detected${NC}"

  # Write a marker row so CSV shows the check was performed
  jq -rn \
    --arg cn "$CLUSTER_NAME" --arg cc "$CLUSTER_CONTEXT" --arg cs "$CLUSTER_SERVER" '
    [
      $cn, $cc, $cs,
      "oadp_backup",
      "not-installed",
      "",
      "",
      "",
      "",
      "OADP/Velero not detected on this cluster",
      "",
      "",
      ""
    ] | @csv
  ' >> "$OUTPUT_FILE"
fi
echo "[$LABEL] OADP/Velero section done."

# =============================================================================
# 4) Volume Snapshot Readiness
# =============================================================================
echo "[$LABEL] Checking volume snapshot infrastructure..."

VSC_COUNT=0
VS_COUNT=0

# VolumeSnapshotClasses
echo "[$LABEL] Fetching VolumeSnapshotClasses..."
VSC_JSON=""
if VSC_JSON=$(oc get volumesnapshotclasses -o json 2>/dev/null | tr -d '\r'); then
  VSC_COUNT=$(echo "$VSC_JSON" | jq '.items | length' | tr -d '\r')
  echo "[$LABEL] Found $VSC_COUNT VolumeSnapshotClasses."

  if [ "$VSC_COUNT" -gt 0 ]; then
    echo "$VSC_JSON" | jq -c '.items[]' | while IFS= read -r vsc; do
      VSC_NAME=$(echo "$vsc" | jq -r '.metadata.name // ""')
      VSC_DRIVER=$(echo "$vsc" | jq -r '.driver // ""')
      VSC_POLICY=$(echo "$vsc" | jq -r '.deletionPolicy // ""')

      VSC_CREATED=$(echo "$vsc" | jq -r '.metadata.creationTimestamp // ""')
      VSC_AGE=""
      if [ -n "$VSC_CREATED" ]; then
        VSC_EPOCH=$(date -d "$VSC_CREATED" +%s 2>/dev/null || echo "")
        if [ -n "$VSC_EPOCH" ]; then
          VSC_AGE=$(( (NOW_EPOCH - VSC_EPOCH) / 86400 ))
        fi
      fi

      echo "$vsc" | jq -r \
        --arg cn "$CLUSTER_NAME" --arg cc "$CLUSTER_CONTEXT" --arg cs "$CLUSTER_SERVER" \
        --arg name "$VSC_NAME" --arg detail "driver=$VSC_DRIVER;deletionPolicy=$VSC_POLICY" \
        --arg age "$VSC_AGE" '
        [
          $cn, $cc, $cs,
          "volume_snapshot",
          $name,
          "",
          "",
          "",
          "",
          $detail,
          "snapshot_class",
          "",
          $age
        ] | @csv
      '
    done >> "$OUTPUT_FILE"
  fi
else
  echo "[$LABEL] VolumeSnapshotClass CRD not available — skipping."
fi

# VolumeSnapshots across all namespaces
echo "[$LABEL] Fetching VolumeSnapshots..."
VS_JSON=""
if VS_JSON=$(oc get volumesnapshots -A -o json 2>/dev/null | tr -d '\r'); then
  VS_COUNT=$(echo "$VS_JSON" | jq '.items | length' | tr -d '\r')
  echo "[$LABEL] Found $VS_COUNT VolumeSnapshots."

  if [ "$VS_COUNT" -gt 0 ]; then
    echo "$VS_JSON" | jq -c '.items[]' | while IFS= read -r vs; do
      VS_NAME=$(echo "$vs" | jq -r '.metadata.name // ""')
      VS_NS=$(echo "$vs" | jq -r '.metadata.namespace // ""')
      VS_READY=$(echo "$vs" | jq -r '.status.readyToUse // ""')
      VS_SIZE=$(echo "$vs" | jq -r '.status.restoreSize // ""')
      VS_CLASS=$(echo "$vs" | jq -r '.spec.volumeSnapshotClassName // ""')

      VS_CREATED=$(echo "$vs" | jq -r '.metadata.creationTimestamp // ""')
      VS_AGE=""
      if [ -n "$VS_CREATED" ]; then
        VS_EPOCH=$(date -d "$VS_CREATED" +%s 2>/dev/null || echo "")
        if [ -n "$VS_EPOCH" ]; then
          VS_AGE=$(( (NOW_EPOCH - VS_EPOCH) / 86400 ))
        fi
      fi

      echo "$vs" | jq -r \
        --arg cn "$CLUSTER_NAME" --arg cc "$CLUSTER_CONTEXT" --arg cs "$CLUSTER_SERVER" \
        --arg name "$VS_NAME" --arg ns "$VS_NS" \
        --arg detail "class=$VS_CLASS;size=$VS_SIZE" \
        --arg ready "$VS_READY" --arg age "$VS_AGE" '
        [
          $cn, $cc, $cs,
          "volume_snapshot",
          $name,
          $ns,
          $ready,
          "",
          "",
          $detail,
          "snapshot",
          "",
          $age
        ] | @csv
      '
    done >> "$OUTPUT_FILE"
  fi
else
  echo "[$LABEL] VolumeSnapshot CRD not available — skipping."
fi
echo "[$LABEL] Volume snapshot section done."

# =============================================================================
# Console summary
# =============================================================================
echo "[$LABEL] --- Summary ---"

# etcd health
if [ "$ETCD_OK" = true ]; then
  if [ "$ETCD_DEGRADED" = "True" ]; then
    echo -e "${RED}[$LABEL]   etcd: DEGRADED — $ETCD_MESSAGE${NC}"
  else
    echo "[$LABEL]   etcd: Available=$ETCD_AVAILABLE, Members=$ETCD_MEMBER_COUNT"
  fi
  if [ "$ETCD_MEMBER_COUNT" -lt 3 ] 2>/dev/null; then
    echo -e "${RED}[$LABEL]   WARNING: etcd has fewer than 3 members — quorum at risk${NC}"
  fi
else
  echo -e "${RED}[$LABEL]   etcd: UNKNOWN (could not fetch resource)${NC}"
fi

# Control plane operators
CP_TOTAL=${#CP_OPERATORS[@]}
CP_HEALTHY=$((CP_TOTAL - CP_DEGRADED_COUNT))
if [ "$CP_DEGRADED_COUNT" -gt 0 ]; then
  echo -e "${RED}[$LABEL]   Control plane operators: $CP_HEALTHY/$CP_TOTAL healthy — $CP_DEGRADED_COUNT DEGRADED (unsafe backup window)${NC}"
else
  echo "[$LABEL]   Control plane operators: $CP_HEALTHY/$CP_TOTAL healthy"
fi

# OADP/Velero
if [ "$OADP_INSTALLED" = true ]; then
  echo "[$LABEL]   OADP/Velero: installed (${BSL_COUNT} storage locations, ${BACKUP_COUNT} backups)"
  if [ "$BSL_COUNT" -eq 0 ]; then
    echo -e "${YELLOW}[$LABEL]   WARNING: OADP installed but no BackupStorageLocations configured${NC}"
  fi
  if [ "$BACKUP_COUNT" -eq 0 ]; then
    echo -e "${YELLOW}[$LABEL]   WARNING: OADP installed but no Velero Backups found${NC}"
  fi
else
  echo -e "${YELLOW}[$LABEL]   OADP/Velero: NOT detected — no external backup tooling on this cluster${NC}"
fi

# Volume snapshots
echo "[$LABEL]   Volume snapshots: $VSC_COUNT classes, $VS_COUNT snapshots"
if [ "$VSC_COUNT" -eq 0 ]; then
  echo -e "${YELLOW}[$LABEL]   NOTE: No VolumeSnapshotClasses — cloud-native PV snapshots not available${NC}"
fi

ELAPSED=$(( SECONDS - SCRIPT_START_SECONDS ))
echo "[$LABEL] Completed at $(date) — total time: ${ELAPSED}s"
echo "Created: $OUTPUT_FILE"
