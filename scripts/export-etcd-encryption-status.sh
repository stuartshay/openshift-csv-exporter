#!/usr/bin/env bash
# Description: Exports etcd encryption at rest status — global encryption config, kubeapiserver and openshiftapiserver operator health, and per-resource encryption migration conditions
# Audit Area:  Etcd Encryption At Rest
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

OUTPUT_FILE="$OUTPUT_DIR/etcd-encryption-status-${CLUSTER_NAME_SAFE}-$TIMESTAMP.csv"

LABEL="etcd-encryption-status"
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

SCRIPT_START_SECONDS=$SECONDS

echo "[$LABEL] Starting export at $(date)"
echo "[$LABEL] Output file: $OUTPUT_FILE"

# CSV header
echo "cluster_name,cluster_context,cluster_server,record_type,resource_name,encryption_type,encryption_enabled,condition_available,condition_degraded,condition_progressing,condition_type,condition_reason,message" > "$OUTPUT_FILE"

# =============================================================================
# 1) Global Encryption Configuration — oc get apiserver cluster
# =============================================================================
echo "[$LABEL] Fetching APIServer encryption configuration..."

APISERVER_JSON=""
APISERVER_OK=true
if ! APISERVER_JSON=$(oc get apiserver cluster -o json 2>/dev/null | tr -d '\r'); then
  echo -e "${RED}[$LABEL] ERROR: Failed to fetch apiserver cluster — permission denied or resource unavailable${NC}"
  echo -e "${RED}[$LABEL] Hint: oc auth can-i get apiservers.config.openshift.io/cluster${NC}"
  APISERVER_OK=false
fi

ENCRYPTION_TYPE=""
ENCRYPTION_ENABLED="false"

if [ "$APISERVER_OK" = true ] && [ -n "$APISERVER_JSON" ]; then
  ENCRYPTION_TYPE=$(echo "$APISERVER_JSON" | jq -r '.spec.encryption.type // ""' | tr -d '\r')

  # identity or empty = not encrypted; aescbc / aesgcm = encrypted
  if [ -n "$ENCRYPTION_TYPE" ] && [ "$ENCRYPTION_TYPE" != "identity" ]; then
    ENCRYPTION_ENABLED="true"
  fi

  jq -rn \
    --arg cn "$CLUSTER_NAME" --arg cc "$CLUSTER_CONTEXT" --arg cs "$CLUSTER_SERVER" \
    --arg etype "$ENCRYPTION_TYPE" --arg enabled "$ENCRYPTION_ENABLED" '
    [
      $cn, $cc, $cs,
      "encryption_config",
      "apiserver-cluster",
      $etype,
      $enabled,
      "",
      "",
      "",
      "",
      "",
      ""
    ] | @csv
  ' >> "$OUTPUT_FILE"

  # Console output
  if [ "$ENCRYPTION_ENABLED" = "true" ]; then
    echo "[$LABEL] Encryption type: $ENCRYPTION_TYPE (ENABLED)"
  else
    DISPLAY_TYPE="${ENCRYPTION_TYPE:-identity}"
    echo -e "${RED}[$LABEL] WARNING: Encryption type: $DISPLAY_TYPE — etcd data is NOT encrypted at rest${NC}"
    echo -e "${RED}[$LABEL] Hint: oc edit apiserver cluster — set .spec.encryption.type to aescbc or aesgcm${NC}"
  fi
else
  echo "[$LABEL] Skipping encryption config (fetch failed)."
fi
echo "[$LABEL] Encryption config section done."

# =============================================================================
# Helper function — export operator encryption status + conditions
# =============================================================================
export_operator_encryption_status() {
  local OPERATOR_NAME="$1"
  local OC_RESOURCE="$2"

  echo "[$LABEL] Fetching $OPERATOR_NAME encryption status..."

  local OP_JSON=""
  local OP_OK=true
  if ! OP_JSON=$(oc get "$OC_RESOURCE" cluster -o json 2>/dev/null | tr -d '\r'); then
    echo -e "${RED}[$LABEL] ERROR: Failed to fetch $OC_RESOURCE cluster — permission denied${NC}"
    echo -e "${RED}[$LABEL] Hint: oc auth can-i get $OC_RESOURCE/cluster${NC}"
    OP_OK=false
  fi

  if [ "$OP_OK" = true ] && [ -n "$OP_JSON" ]; then
    # Extract top-level operator conditions
    local OP_AVAILABLE
    OP_AVAILABLE=$(echo "$OP_JSON" | jq -r '
      [.status.conditions // [] | .[] | select(.type=="Available")] | first | .status // ""
    ' | tr -d '\r')
    local OP_DEGRADED
    OP_DEGRADED=$(echo "$OP_JSON" | jq -r '
      [.status.conditions // [] | .[] | select(.type=="Degraded")] | first | .status // ""
    ' | tr -d '\r')
    local OP_PROGRESSING
    OP_PROGRESSING=$(echo "$OP_JSON" | jq -r '
      [.status.conditions // [] | .[] | select(.type=="Progressing")] | first | .status // ""
    ' | tr -d '\r')
    local OP_DEGRADED_MSG
    OP_DEGRADED_MSG=$(echo "$OP_JSON" | jq -r '
      [.status.conditions // [] | .[] | select(.type=="Degraded")] | first | .message // ""
    ' | tr -d '\r')

    # Write operator status row
    jq -rn \
      --arg cn "$CLUSTER_NAME" --arg cc "$CLUSTER_CONTEXT" --arg cs "$CLUSTER_SERVER" \
      --arg name "$OPERATOR_NAME" --arg etype "$ENCRYPTION_TYPE" --arg enabled "$ENCRYPTION_ENABLED" \
      --arg avail "$OP_AVAILABLE" --arg deg "$OP_DEGRADED" --arg prog "$OP_PROGRESSING" \
      --arg msg "$OP_DEGRADED_MSG" '
      [
        $cn, $cc, $cs,
        "operator_status",
        $name,
        $etype,
        $enabled,
        $avail,
        $deg,
        $prog,
        "",
        "",
        $msg
      ] | @csv
    ' >> "$OUTPUT_FILE"

    echo "[$LABEL] $OPERATOR_NAME: Available=$OP_AVAILABLE, Degraded=$OP_DEGRADED, Progressing=$OP_PROGRESSING"

    if [ "$OP_DEGRADED" = "True" ]; then
      echo -e "${RED}[$LABEL] WARNING: $OPERATOR_NAME is DEGRADED — $OP_DEGRADED_MSG${NC}"
    fi
    if [ "$OP_PROGRESSING" = "True" ]; then
      echo -e "${YELLOW}[$LABEL] INFO: $OPERATOR_NAME is progressing (possible encryption migration in progress)${NC}"
    fi

    # Extract encryption-related conditions (reason contains Encrypted or Encryption)
    local ENC_COND_COUNT
    ENC_COND_COUNT=$(echo "$OP_JSON" | jq '
      [.status.conditions // [] | .[] | select(
        (.reason // "" | test("(?i)encrypt")) or
        (.type // "" | test("(?i)encrypt"))
      )] | length
    ' | tr -d '\r')

    if [ "$ENC_COND_COUNT" -gt 0 ]; then
      echo "[$LABEL] Found $ENC_COND_COUNT encryption-related condition(s) on $OPERATOR_NAME"

      echo "$OP_JSON" | jq -c '
        .status.conditions // [] | .[] | select(
          (.reason // "" | test("(?i)encrypt")) or
          (.type // "" | test("(?i)encrypt"))
        )
      ' | tr -d '\r' | while IFS= read -r cond; do
        local COND_TYPE COND_STATUS COND_REASON COND_MSG
        COND_TYPE=$(echo "$cond" | jq -r '.type // ""')
        COND_STATUS=$(echo "$cond" | jq -r '.status // ""')
        COND_REASON=$(echo "$cond" | jq -r '.reason // ""')
        COND_MSG=$(echo "$cond" | jq -r '.message // ""')

        jq -rn \
          --arg cn "$CLUSTER_NAME" --arg cc "$CLUSTER_CONTEXT" --arg cs "$CLUSTER_SERVER" \
          --arg name "$OPERATOR_NAME" --arg etype "$ENCRYPTION_TYPE" --arg enabled "$ENCRYPTION_ENABLED" \
          --arg ctype "$COND_TYPE" --arg creason "$COND_REASON" --arg cmsg "$COND_MSG" \
          --arg cstatus "$COND_STATUS" '
          [
            $cn, $cc, $cs,
            "encryption_condition",
            $name,
            $etype,
            $enabled,
            "",
            "",
            "",
            ($ctype + "=" + $cstatus),
            $creason,
            $cmsg
          ] | @csv
        ' >> "$OUTPUT_FILE"

        echo "[$LABEL]   Condition: $COND_TYPE=$COND_STATUS (reason=$COND_REASON)"
      done
    else
      echo "[$LABEL] No encryption-specific conditions found on $OPERATOR_NAME"
    fi
  else
    echo "[$LABEL] Skipping $OPERATOR_NAME details (fetch failed)."
  fi
  echo "[$LABEL] $OPERATOR_NAME section done."
}

# =============================================================================
# 2) Kube-APIServer Encryption Status
# =============================================================================
export_operator_encryption_status "kubeapiserver" "kubeapiserver"

# =============================================================================
# 3) OpenShift-APIServer Encryption Status
# =============================================================================
export_operator_encryption_status "openshiftapiserver" "openshiftapiserver"

# =============================================================================
# Encryption Summary
# =============================================================================
echo ""
echo "[$LABEL] === Etcd Encryption At Rest Summary ==="
if [ "$APISERVER_OK" = true ]; then
  if [ "$ENCRYPTION_ENABLED" = "true" ]; then
    echo "[$LABEL]   Encryption: ENABLED (type=$ENCRYPTION_TYPE)"
  else
    echo -e "${RED}[$LABEL]   Encryption: DISABLED (type=${ENCRYPTION_TYPE:-identity})${NC}"
  fi
fi
echo "[$LABEL] ==================================="
echo ""

ELAPSED=$(( SECONDS - SCRIPT_START_SECONDS ))
echo "[$LABEL] Completed at $(date) — total time: ${ELAPSED}s"
echo "Created: $OUTPUT_FILE"
