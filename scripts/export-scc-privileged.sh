#!/usr/bin/env bash
# Description: Exports all SecurityContextConstraints for least-privilege and SCC enforcement auditing
# Audit Area:  Container Least Privilege / SCC Enforcement
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./common.sh
source "$SCRIPT_DIR/common.sh"

SCRIPT_START_SECONDS=$SECONDS
LABEL="scc-privileged"
RED='\033[0;31m'
NC='\033[0m' # No Color

: "${CLUSTER_NAME_SAFE:?CLUSTER_NAME_SAFE is not set}"
: "${CLUSTER_NAME:?CLUSTER_NAME is not set}"
: "${CLUSTER_CONTEXT:?CLUSTER_CONTEXT is not set}"
: "${CLUSTER_SERVER:?CLUSTER_SERVER is not set}"
: "${OUTPUT_DIR:?OUTPUT_DIR is not set}"
: "${TIMESTAMP:?TIMESTAMP is not set}"

echo "[$(date +%H:%M:%S)] [$LABEL] Starting export at $(date)"

OUTPUT_FILE="$OUTPUT_DIR/scc-privileged-${CLUSTER_NAME_SAFE}-$TIMESTAMP.csv"

echo "cluster_name,cluster_context,cluster_server,name,priority,allow_privileged_container,default_add_capabilities,required_drop_capabilities,allowed_capabilities,allow_host_network,allow_host_ports,allow_host_pid,allow_host_ipc,read_only_root_filesystem,run_as_user_type,se_linux_context_type,fs_group_type,supplemental_groups_type,volumes,allow_privilege_escalation,users_count,groups_count,users,groups" > "$OUTPUT_FILE"

echo "[$(date +%H:%M:%S)] [$LABEL] Fetching all SecurityContextConstraints..."
SCC_JSON=$(oc get scc -o json | tr -d '\r')

TOTAL_SCCS=$(echo "$SCC_JSON" | jq '[.items[]] | length')
echo "[$(date +%H:%M:%S)] [$LABEL] Processing $TOTAL_SCCS SCCs..."

echo "$SCC_JSON" | jq -r \
  --arg cluster_name "$CLUSTER_NAME" \
  --arg cluster_context "$CLUSTER_CONTEXT" \
  --arg cluster_server "$CLUSTER_SERVER" '
  .items[] |
  [
    $cluster_name,
    $cluster_context,
    $cluster_server,
    (.metadata.name // ""),
    (.priority // ""),
    (.allowPrivilegedContainer // false),
    ((.defaultAddCapabilities // []) | join(";")),
    ((.requiredDropCapabilities // []) | join(";")),
    ((.allowedCapabilities // []) | join(";")),
    (.allowHostNetwork // false),
    (.allowHostPorts // false),
    (.allowHostPID // false),
    (.allowHostIPC // false),
    (.readOnlyRootFilesystem // false),
    (.runAsUser.type // ""),
    (.seLinuxContext.type // ""),
    (.fsGroup.type // ""),
    (.supplementalGroups.type // ""),
    ((.volumes // []) | join(";")),
    (if .allowPrivilegeEscalation == null then "true" else .allowPrivilegeEscalation end),
    ((.users // []) | length),
    ((.groups // []) | length),
    ((.users // []) | join(";")),
    ((.groups // []) | join(";"))
  ] | @csv
' >> "$OUTPUT_FILE"

# ── Summary ──────────────────────────────────────────────────────────────────
PRIVILEGED_SCCS=$(echo "$SCC_JSON" | jq '[.items[] | select(.allowPrivilegedContainer == true)] | length')
HOST_NETWORK_SCCS=$(echo "$SCC_JSON" | jq '[.items[] | select(.allowHostNetwork == true)] | length')
HOST_PID_SCCS=$(echo "$SCC_JSON" | jq '[.items[] | select(.allowHostPID == true)] | length')
RUN_AS_ANY=$(echo "$SCC_JSON" | jq '[.items[] | select(.runAsUser.type == "RunAsAny")] | length')
NO_DROP_ALL=$(echo "$SCC_JSON" | jq '[.items[] | select((.requiredDropCapabilities // []) | map(ascii_downcase) | index("all") | not)] | length')
ESCALATION_ALLOWED=$(echo "$SCC_JSON" | jq '[.items[] | select(.allowPrivilegeEscalation != false)] | length')
WITH_USERS=$(echo "$SCC_JSON" | jq '[.items[] | select((.users // []) | length > 0)] | length')
WITH_GROUPS=$(echo "$SCC_JSON" | jq '[.items[] | select((.groups // []) | length > 0)] | length')

echo "[$(date +%H:%M:%S)] [$LABEL] Processing done."
echo ""
echo "┌──────────────────────────────────────────────────────┐"
echo "│ SecurityContextConstraints Summary                   │"
echo "├──────────────────────────────────────────────────────┤"
echo "│ Total SCCs                     : $TOTAL_SCCS"
echo "│ Allow privileged containers    : $PRIVILEGED_SCCS"
echo "│ Allow host network             : $HOST_NETWORK_SCCS"
echo "│ Allow host PID                 : $HOST_PID_SCCS"
echo "│ RunAsUser = RunAsAny           : $RUN_AS_ANY"
echo "│ Missing DROP ALL capabilities  : $NO_DROP_ALL"
echo "│ Allow privilege escalation     : $ESCALATION_ALLOWED"
echo "│ SCCs with direct user grants   : $WITH_USERS"
echo "│ SCCs with group grants         : $WITH_GROUPS"
echo "└──────────────────────────────────────────────────────┘"
echo ""

# ── Critical warnings ────────────────────────────────────────────────────────
if [ "$PRIVILEGED_SCCS" -gt 0 ]; then
  PRIV_NAMES=$(echo "$SCC_JSON" | jq -r '[.items[] | select(.allowPrivilegedContainer == true) | .metadata.name] | join(", ")')
  echo -e "${RED}[$(date +%H:%M:%S)] [$LABEL] WARNING: $PRIVILEGED_SCCS SCC(s) allow privileged containers: $PRIV_NAMES${NC}"
fi

if [ "$RUN_AS_ANY" -gt 0 ]; then
  RAA_NAMES=$(echo "$SCC_JSON" | jq -r '[.items[] | select(.runAsUser.type == "RunAsAny") | .metadata.name] | join(", ")')
  echo -e "${RED}[$(date +%H:%M:%S)] [$LABEL] WARNING: $RUN_AS_ANY SCC(s) allow RunAsAny (containers can run as root): $RAA_NAMES${NC}"
fi

if [ "$NO_DROP_ALL" -gt 0 ]; then
  echo -e "${RED}[$(date +%H:%M:%S)] [$LABEL] WARNING: $NO_DROP_ALL SCC(s) do not require DROP ALL capabilities — containers retain default Linux capabilities${NC}"
fi

if [ "$ESCALATION_ALLOWED" -gt 0 ]; then
  echo -e "${RED}[$(date +%H:%M:%S)] [$LABEL] WARNING: $ESCALATION_ALLOWED SCC(s) allow privilege escalation — containers can gain more privileges than their parent process${NC}"
fi

if [ "$HOST_NETWORK_SCCS" -gt 0 ]; then
  HN_NAMES=$(echo "$SCC_JSON" | jq -r '[.items[] | select(.allowHostNetwork == true) | .metadata.name] | join(", ")')
  echo -e "${RED}[$(date +%H:%M:%S)] [$LABEL] WARNING: $HOST_NETWORK_SCCS SCC(s) allow host network access: $HN_NAMES${NC}"
fi

ELAPSED=$(( SECONDS - SCRIPT_START_SECONDS ))
echo "[$(date +%H:%M:%S)] [$LABEL] Completed at $(date) — total time: ${ELAPSED}s"
echo "Created: $OUTPUT_FILE"
