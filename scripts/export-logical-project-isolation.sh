#!/usr/bin/env bash
# Description: Exports per-namespace logical isolation evidence — NetworkPolicy default-deny presence, ResourceQuota / LimitRange enforcement, ownership labels, RoleBinding count, and distinct ServiceAccount count — for OCP-45 Logical Project Isolation auditing
# Audit Area:  Logical Project Isolation
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./common.sh
source "$SCRIPT_DIR/common.sh"

SCRIPT_START_SECONDS=$SECONDS
LABEL="logical-isolation"
# shellcheck disable=SC2034
RED='\033[0;31m'
# shellcheck disable=SC2034
NC='\033[0m'

: "${CLUSTER_NAME_SAFE:?CLUSTER_NAME_SAFE is not set}"
: "${CLUSTER_NAME:?CLUSTER_NAME is not set}"
: "${CLUSTER_CONTEXT:?CLUSTER_CONTEXT is not set}"
: "${CLUSTER_SERVER:?CLUSTER_SERVER is not set}"
: "${OUTPUT_DIR:?OUTPUT_DIR is not set}"
: "${TIMESTAMP:?TIMESTAMP is not set}"

echo "[$(date +%H:%M:%S)] [$LABEL] Starting export at $(date)"

OUTPUT_FILE="$OUTPUT_DIR/logical-project-isolation-${CLUSTER_NAME_SAFE}-$TIMESTAMP.csv"
echo "cluster_name,cluster_context,cluster_server,namespace,is_system_namespace,has_default_deny_netpol,netpol_count,has_resourcequota,has_limitrange,has_owner_label,rolebinding_count,distinct_serviceaccounts" > "$OUTPUT_FILE"

echo "[$(date +%H:%M:%S)] [$LABEL] Fetching namespaces, networkpolicies, resourcequotas, limitranges, rolebindings, serviceaccounts..."
NS_JSON=$(oc get ns -o json 2>/dev/null || echo '{"items":[]}')
NETPOL_JSON=$(oc get networkpolicies -A -o json 2>/dev/null || echo '{"items":[]}')
RQ_JSON=$(oc get resourcequotas -A -o json 2>/dev/null || echo '{"items":[]}')
LR_JSON=$(oc get limitranges -A -o json 2>/dev/null || echo '{"items":[]}')
RB_JSON=$(oc get rolebindings -A -o json 2>/dev/null || echo '{"items":[]}')
SA_JSON=$(oc get serviceaccounts -A -o json 2>/dev/null || echo '{"items":[]}')

TOTAL=$(echo "$NS_JSON" | jq '.items | length')
echo "[$(date +%H:%M:%S)] [$LABEL] Processing $TOTAL namespaces..."

echo "$NS_JSON" | jq -c '.items[]' | while IFS= read -r ns_item; do
  NS=$(echo "$ns_item" | jq -r '.metadata.name // ""')
  IS_SYS="false"
  if echo "$NS" | grep -Eq '^(openshift|kube)' || [ "$NS" = "default" ]; then
    IS_SYS="true"
  fi
  LABELS_JSON=$(echo "$ns_item" | jq -c '.metadata.labels // {}')
  HAS_OWNER="false"
  if echo "$LABELS_JSON" | jq -e '
      ."app.kubernetes.io/owner" //
      ."owner" //
      ."team" //
      ."app.kubernetes.io/managed-by"
    ' >/dev/null 2>&1; then
    HAS_OWNER="true"
  fi

  NETPOL_COUNT=$(echo "$NETPOL_JSON" | jq --arg ns "$NS" '[.items[] | select(.metadata.namespace == $ns)] | length')
  HAS_DENY=$(echo "$NETPOL_JSON" | jq -r --arg ns "$NS" '
    [.items[] |
      select(.metadata.namespace == $ns) |
      select((.spec.podSelector // {}) == {}) |
      select((.spec.policyTypes // []) | index("Ingress"))
    ] | (length > 0) | tostring')
  RQ_COUNT=$(echo "$RQ_JSON" | jq --arg ns "$NS" '[.items[] | select(.metadata.namespace == $ns)] | length')
  HAS_RQ=$([ "$RQ_COUNT" -gt 0 ] && echo "true" || echo "false")
  LR_COUNT=$(echo "$LR_JSON" | jq --arg ns "$NS" '[.items[] | select(.metadata.namespace == $ns)] | length')
  HAS_LR=$([ "$LR_COUNT" -gt 0 ] && echo "true" || echo "false")
  RB_COUNT=$(echo "$RB_JSON" | jq --arg ns "$NS" '[.items[] | select(.metadata.namespace == $ns)] | length')
  SA_COUNT=$(echo "$SA_JSON" | jq --arg ns "$NS" '[.items[] | select(.metadata.namespace == $ns)] | length')

  jq -nr \
    --arg cluster_name "$CLUSTER_NAME" \
    --arg cluster_context "$CLUSTER_CONTEXT" \
    --arg cluster_server "$CLUSTER_SERVER" \
    --arg ns "$NS" \
    --arg is_sys "$IS_SYS" \
    --arg has_deny "$HAS_DENY" \
    --arg netpol_count "$NETPOL_COUNT" \
    --arg has_rq "$HAS_RQ" \
    --arg has_lr "$HAS_LR" \
    --arg has_owner "$HAS_OWNER" \
    --arg rb_count "$RB_COUNT" \
    --arg sa_count "$SA_COUNT" '
    [$cluster_name,$cluster_context,$cluster_server,$ns,$is_sys,$has_deny,$netpol_count,$has_rq,$has_lr,$has_owner,$rb_count,$sa_count] | @csv
  ' >> "$OUTPUT_FILE"
done

echo "[$(date +%H:%M:%S)] [$LABEL] Namespace iteration done."

USER_NS=$(echo "$NS_JSON" | jq '[.items[] | select((.metadata.name // "") | test("^(openshift|kube|default$)") | not)] | length')
echo ""
echo "┌──────────────────────────────────────────────────────┐"
echo "│ Logical Project Isolation Summary                    │"
echo "├──────────────────────────────────────────────────────┤"
echo "│ Total namespaces        : $TOTAL"
echo "│ User namespaces         : $USER_NS"
echo "└──────────────────────────────────────────────────────┘"
echo ""

ELAPSED=$(( SECONDS - SCRIPT_START_SECONDS ))
echo "[$(date +%H:%M:%S)] [$LABEL] Completed at $(date) — total time: ${ELAPSED}s"
echo "Created: $OUTPUT_FILE"
