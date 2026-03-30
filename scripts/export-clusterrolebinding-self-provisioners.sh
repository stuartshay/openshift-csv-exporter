#!/usr/bin/env bash
# Description: Exports the self-provisioners ClusterRoleBinding
# Audit Area:  Granular Role-Based Access Controls
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./common.sh
source "$SCRIPT_DIR/common.sh"

SCRIPT_START_SECONDS=$SECONDS
LABEL="self-provisioners"
RED='\033[0;31m'
NC='\033[0m' # No Color

: "${CLUSTER_NAME_SAFE:?CLUSTER_NAME_SAFE is not set}"
: "${CLUSTER_NAME:?CLUSTER_NAME is not set}"
: "${CLUSTER_CONTEXT:?CLUSTER_CONTEXT is not set}"
: "${CLUSTER_SERVER:?CLUSTER_SERVER is not set}"
: "${OUTPUT_DIR:?OUTPUT_DIR is not set}"
: "${TIMESTAMP:?TIMESTAMP is not set}"

echo "[$(date +%H:%M:%S)] [$LABEL] Starting export at $(date)"

OUTPUT_FILE="$OUTPUT_DIR/clusterrolebinding-self-provisioners-${CLUSTER_NAME_SAFE}-$TIMESTAMP.csv"

echo "cluster_name,cluster_context,cluster_server,binding_name,role_ref_kind,role_ref_name,subject_kind,subject_name,subject_namespace" > "$OUTPUT_FILE"

echo "[$(date +%H:%M:%S)] [$LABEL] Fetching self-provisioners binding..."
if ! oc get clusterrolebinding self-provisioners >/dev/null 2>&1; then
  echo "[$(date +%H:%M:%S)] [$LABEL] self-provisioners binding does not exist — self-provisioning is disabled"
  BINDING_EXISTS="false"
  SUBJECT_COUNT=0
  HAS_AUTHENTICATED_OAUTH="false"
else
  BINDING_JSON=$(oc get clusterrolebinding self-provisioners -o json | tr -d '\r')
  BINDING_EXISTS="true"

  echo "[$(date +%H:%M:%S)] [$LABEL] Processing self-provisioners binding..."
  echo "$BINDING_JSON" | jq -r \
    --arg cluster_name "$CLUSTER_NAME" \
    --arg cluster_context "$CLUSTER_CONTEXT" \
    --arg cluster_server "$CLUSTER_SERVER" '
    . as $crb
    | if (($crb.subjects // []) | length) > 0 then
        $crb.subjects[] |
        [
          $cluster_name,
          $cluster_context,
          $cluster_server,
          ($crb.metadata.name // ""),
          ($crb.roleRef.kind // ""),
          ($crb.roleRef.name // ""),
          (.kind // ""),
          (.name // ""),
          (.namespace // "")
        ] | @csv
      else
        [
          $cluster_name,
          $cluster_context,
          $cluster_server,
          ($crb.metadata.name // ""),
          ($crb.roleRef.kind // ""),
          ($crb.roleRef.name // ""),
          "",
          "",
          ""
        ] | @csv
      end
  ' >> "$OUTPUT_FILE"

  SUBJECT_COUNT=$(echo "$BINDING_JSON" | jq '[(.subjects // [])[]] | length')
  HAS_AUTHENTICATED_OAUTH=$(echo "$BINDING_JSON" | jq '[(.subjects // [])[] | select(.kind == "Group" and .name == "system:authenticated:oauth")] | length > 0')
fi

# ── Summary ──────────────────────────────────────────────────────────────────
echo "[$(date +%H:%M:%S)] [$LABEL] Processing done."
echo ""
echo "┌──────────────────────────────────────────────────────┐"
echo "│ Self-Provisioners Summary                            │"
echo "├──────────────────────────────────────────────────────┤"
echo "│ Binding exists                 : $BINDING_EXISTS"
echo "│ Subjects bound                 : $SUBJECT_COUNT"
echo "│ system:authenticated:oauth     : $HAS_AUTHENTICATED_OAUTH"
echo "└──────────────────────────────────────────────────────┘"
echo ""

# ── Critical warnings ────────────────────────────────────────────────────────
if [ "$HAS_AUTHENTICATED_OAUTH" = "true" ]; then
  echo -e "${RED}[$(date +%H:%M:%S)] [$LABEL] WARNING: system:authenticated:oauth is bound — ALL authenticated users can create projects${NC}"
fi

if [ "$BINDING_EXISTS" = "false" ]; then
  echo "[$(date +%H:%M:%S)] [$LABEL] INFO: self-provisioners binding removed — project creation requires admin approval"
fi

ELAPSED=$(( SECONDS - SCRIPT_START_SECONDS ))
echo "[$(date +%H:%M:%S)] [$LABEL] Completed at $(date) — total time: ${ELAPSED}s"
echo "Created: $OUTPUT_FILE"
