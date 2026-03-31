#!/usr/bin/env bash
# Description: Exports ResourceQuotas and LimitRanges across all namespaces for workload resource enforcement auditing
# Audit Area:  Workload Resource Quotas
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./common.sh
source "$SCRIPT_DIR/common.sh"

SCRIPT_START_SECONDS=$SECONDS
LABEL="workload-quotas"
RED='\033[0;31m'
NC='\033[0m' # No Color

: "${CLUSTER_NAME_SAFE:?CLUSTER_NAME_SAFE is not set}"
: "${CLUSTER_NAME:?CLUSTER_NAME is not set}"
: "${CLUSTER_CONTEXT:?CLUSTER_CONTEXT is not set}"
: "${CLUSTER_SERVER:?CLUSTER_SERVER is not set}"
: "${OUTPUT_DIR:?OUTPUT_DIR is not set}"
: "${TIMESTAMP:?TIMESTAMP is not set}"

echo "[$(date +%H:%M:%S)] [$LABEL] Starting export at $(date)"

OUTPUT_FILE="$OUTPUT_DIR/workload-resource-quotas-${CLUSTER_NAME_SAFE}-$TIMESTAMP.csv"

echo "cluster_name,cluster_context,cluster_server,record_type,namespace,name,resource_key,hard_limit,used,limit_type,default_value,default_request,max_value,min_value" > "$OUTPUT_FILE"

# ── Section 1: ResourceQuotas ────────────────────────────────────────────────
echo "[$(date +%H:%M:%S)] [$LABEL] Fetching ResourceQuotas across all namespaces..."
RQ_JSON=$(oc get resourcequotas --all-namespaces -o json | tr -d '\r')
RQ_COUNT=$(echo "$RQ_JSON" | jq '[.items[]] | length')
RQ_NS_COUNT=$(echo "$RQ_JSON" | jq '[.items[] | .metadata.namespace] | unique | length')
echo "[$(date +%H:%M:%S)] [$LABEL] Processing $RQ_COUNT ResourceQuotas across $RQ_NS_COUNT namespaces..."

echo "$RQ_JSON" | jq -r \
  --arg cluster_name "$CLUSTER_NAME" \
  --arg cluster_context "$CLUSTER_CONTEXT" \
  --arg cluster_server "$CLUSTER_SERVER" '
  .items[] |
  .metadata.namespace as $ns |
  .metadata.name as $rq_name |
  (.spec.hard // {}) as $hard |
  (.status.used // {}) as $used |
  ($hard | keys[]) as $key |
  [
    $cluster_name,
    $cluster_context,
    $cluster_server,
    "resource_quota",
    $ns,
    $rq_name,
    $key,
    ($hard[$key] // ""),
    ($used[$key] // ""),
    "",
    "",
    "",
    "",
    ""
  ] | @csv
' >> "$OUTPUT_FILE"

echo "[$(date +%H:%M:%S)] [$LABEL] ResourceQuotas done."

# ── Section 2: LimitRanges ──────────────────────────────────────────────────
echo "[$(date +%H:%M:%S)] [$LABEL] Fetching LimitRanges across all namespaces..."
LR_JSON=$(oc get limitranges --all-namespaces -o json | tr -d '\r')
LR_COUNT=$(echo "$LR_JSON" | jq '[.items[]] | length')
LR_NS_COUNT=$(echo "$LR_JSON" | jq '[.items[] | .metadata.namespace] | unique | length')
echo "[$(date +%H:%M:%S)] [$LABEL] Processing $LR_COUNT LimitRanges across $LR_NS_COUNT namespaces..."

echo "$LR_JSON" | jq -r \
  --arg cluster_name "$CLUSTER_NAME" \
  --arg cluster_context "$CLUSTER_CONTEXT" \
  --arg cluster_server "$CLUSTER_SERVER" '
  .items[] |
  .metadata.namespace as $ns |
  .metadata.name as $lr_name |
  (.spec.limits // [])[] |
  .type as $limit_type |
  ((.default // {}) | to_entries[]) as $def |
  [
    $cluster_name,
    $cluster_context,
    $cluster_server,
    "limit_range",
    $ns,
    $lr_name,
    $def.key,
    "",
    "",
    $limit_type,
    ($def.value // ""),
    ((.defaultRequest // {})[$def.key] // ""),
    ((.max // {})[$def.key] // ""),
    ((.min // {})[$def.key] // "")
  ] | @csv
' >> "$OUTPUT_FILE"

# Also capture limit range entries that have max/min but no defaults
echo "$LR_JSON" | jq -r \
  --arg cluster_name "$CLUSTER_NAME" \
  --arg cluster_context "$CLUSTER_CONTEXT" \
  --arg cluster_server "$CLUSTER_SERVER" '
  .items[] |
  .metadata.namespace as $ns |
  .metadata.name as $lr_name |
  (.spec.limits // [])[] |
  .type as $limit_type |
  . as $limit |
  (if (.default // {} | length) == 0 then
    (((.max // {}) + (.min // {})) | keys | unique)[] as $key |
    [
      $cluster_name,
      $cluster_context,
      $cluster_server,
      "limit_range",
      $ns,
      $lr_name,
      $key,
      "",
      "",
      $limit_type,
      "",
      ((.defaultRequest // {})[$key] // ""),
      ((.max // {})[$key] // ""),
      ((.min // {})[$key] // "")
    ] | @csv
  else
    empty
  end)
' >> "$OUTPUT_FILE"

echo "[$(date +%H:%M:%S)] [$LABEL] LimitRanges done."

# ── Section 3: Namespace coverage check ──────────────────────────────────────
echo "[$(date +%H:%M:%S)] [$LABEL] Checking namespace coverage..."
ALL_NS_JSON=$(oc get namespaces -o json | tr -d '\r')
TOTAL_NS=$(echo "$ALL_NS_JSON" | jq '[.items[]] | length')

# Exclude openshift-* and kube-* system namespaces for the coverage check
USER_NS=$(echo "$ALL_NS_JSON" | jq '[.items[] | select(.metadata.name | test("^(openshift-|kube-|default$)") | not)] | length')
USER_NS_WITH_RQ=$(echo "$RQ_JSON" | jq --argjson all_ns "$ALL_NS_JSON" '
  [.items[] | .metadata.namespace] | unique |
  map(select(test("^(openshift-|kube-|default$)") | not)) | length
')
USER_NS_WITH_LR=$(echo "$LR_JSON" | jq --argjson all_ns "$ALL_NS_JSON" '
  [.items[] | .metadata.namespace] | unique |
  map(select(test("^(openshift-|kube-|default$)") | not)) | length
')

echo "[$(date +%H:%M:%S)] [$LABEL] Namespace coverage done."

# ── Summary ──────────────────────────────────────────────────────────────────
echo "[$(date +%H:%M:%S)] [$LABEL] Processing done."
echo ""
echo "┌──────────────────────────────────────────────────────┐"
echo "│ Workload Resource Quotas Summary                     │"
echo "├──────────────────────────────────────────────────────┤"
echo "│ Total namespaces               : $TOTAL_NS"
echo "│ User namespaces (non-system)   : $USER_NS"
echo "│ ResourceQuotas                 : $RQ_COUNT (in $RQ_NS_COUNT namespaces)"
echo "│ LimitRanges                    : $LR_COUNT (in $LR_NS_COUNT namespaces)"
echo "│ User NS with ResourceQuota     : $USER_NS_WITH_RQ / $USER_NS"
echo "│ User NS with LimitRange        : $USER_NS_WITH_LR / $USER_NS"
echo "└──────────────────────────────────────────────────────┘"
echo ""

# ── Critical warnings ────────────────────────────────────────────────────────
if [ "$USER_NS" -gt 0 ]; then
  NS_WITHOUT_RQ=$(( USER_NS - USER_NS_WITH_RQ ))
  NS_WITHOUT_LR=$(( USER_NS - USER_NS_WITH_LR ))

  if [ "$NS_WITHOUT_RQ" -gt 0 ]; then
    echo -e "${RED}[$(date +%H:%M:%S)] [$LABEL] WARNING: $NS_WITHOUT_RQ user namespace(s) have no ResourceQuota — workloads can consume unlimited cluster resources${NC}"
  fi

  if [ "$NS_WITHOUT_LR" -gt 0 ]; then
    echo -e "${RED}[$(date +%H:%M:%S)] [$LABEL] WARNING: $NS_WITHOUT_LR user namespace(s) have no LimitRange — pods may run without resource requests or limits${NC}"
  fi
fi

if [ "$RQ_COUNT" -eq 0 ]; then
  echo -e "${RED}[$(date +%H:%M:%S)] [$LABEL] WARNING: No ResourceQuotas found in the entire cluster — resource consumption is uncontrolled${NC}"
fi

if [ "$LR_COUNT" -eq 0 ]; then
  echo -e "${RED}[$(date +%H:%M:%S)] [$LABEL] WARNING: No LimitRanges found in the entire cluster — containers have no default resource limits${NC}"
fi

ELAPSED=$(( SECONDS - SCRIPT_START_SECONDS ))
echo "[$(date +%H:%M:%S)] [$LABEL] Completed at $(date) — total time: ${ELAPSED}s"
echo "Created: $OUTPUT_FILE"
