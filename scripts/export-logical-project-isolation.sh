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

# Pure-bash CSV writer — avoids spawning jq per row, which trips the jq 1.6
# Windows `wargc == argc` assertion when --arg values include unusual chars.
csv_escape() {
  local v="${1-}"
  printf '"%s"' "${v//\"/\"\"}"
}
write_row() {
  local row
  row="$(csv_escape "$CLUSTER_NAME"),$(csv_escape "$CLUSTER_CONTEXT"),$(csv_escape "$CLUSTER_SERVER")"
  local f
  for f in "$@"; do
    row+=",$(csv_escape "$f")"
  done
  printf '%s\n' "$row" >> "$OUTPUT_FILE"
}

echo "[$(date +%H:%M:%S)] [$LABEL] Fetching namespaces, networkpolicies, resourcequotas, limitranges, rolebindings, serviceaccounts..."
NS_FILE=$(mktemp)
NETPOL_FILE=$(mktemp)
RQ_FILE=$(mktemp)
LR_FILE=$(mktemp)
RB_FILE=$(mktemp)
SA_FILE=$(mktemp)
JQ_FILE=$(mktemp)
trap 'rm -f "$NS_FILE" "$NETPOL_FILE" "$RQ_FILE" "$LR_FILE" "$RB_FILE" "$SA_FILE" "$JQ_FILE"' EXIT

oc get ns -o json                  >"$NS_FILE"     2>/dev/null || echo '{"items":[]}' >"$NS_FILE"
oc get networkpolicies -A -o json  >"$NETPOL_FILE" 2>/dev/null || echo '{"items":[]}' >"$NETPOL_FILE"
oc get resourcequotas -A -o json   >"$RQ_FILE"     2>/dev/null || echo '{"items":[]}' >"$RQ_FILE"
oc get limitranges -A -o json      >"$LR_FILE"     2>/dev/null || echo '{"items":[]}' >"$LR_FILE"
oc get rolebindings -A -o json     >"$RB_FILE"     2>/dev/null || echo '{"items":[]}' >"$RB_FILE"
oc get serviceaccounts -A -o json  >"$SA_FILE"     2>/dev/null || echo '{"items":[]}' >"$SA_FILE"

TOTAL=$(jq '.items | length' "$NS_FILE")
echo "[$(date +%H:%M:%S)] [$LABEL] Processing $TOTAL namespaces..."

# Single jq pass: build {namespace -> items} indexes via group_by from slurpfiles,
# then emit one TSV line per namespace with all derived fields. No per-namespace
# rescans, no per-row jq spawns downstream.
cat > "$JQ_FILE" <<'JQ'
def isSystem($n): ($n | test("^(openshift|kube)")) or ($n == "default");
def hasOwner($l):
  ($l // {}) as $L |
  ($L | has("app.kubernetes.io/owner"))
  or ($L | has("owner"))
  or ($L | has("team"))
  or ($L | has("app.kubernetes.io/managed-by"));
def hasDeny($items):
  any(
    $items[];
    ((.spec.podSelector // {}) == {})
    and ((.spec.policyTypes // []) | index("Ingress"))
  );
def idx($arr):
  ($arr | group_by(.metadata.namespace // ""))
  | map({key: (.[0].metadata.namespace // ""), value: .})
  | from_entries;

(idx($netpol[0].items // [])) as $np |
(idx($rq[0].items     // [])) as $rqI |
(idx($lr[0].items     // [])) as $lrI |
(idx($rb[0].items     // [])) as $rbI |
(idx($sa[0].items     // [])) as $saI |

.items[]
| (.metadata.name // "") as $n
| ($np[$n]  // []) as $nps
| ($rqI[$n] // []) as $rqs
| ($lrI[$n] // []) as $lrs
| ($rbI[$n] // []) as $rbs
| ($saI[$n] // []) as $sas
| [
    $n,
    (isSystem($n) | tostring),
    (hasDeny($nps) | tostring),
    ($nps | length | tostring),
    (($rqs | length) > 0 | tostring),
    (($lrs | length) > 0 | tostring),
    (hasOwner(.metadata.labels) | tostring),
    ($rbs | length | tostring),
    ($sas | length | tostring)
  ]
| @tsv
JQ

jq -rf "$JQ_FILE" \
  --slurpfile netpol "$NETPOL_FILE" \
  --slurpfile rq "$RQ_FILE" \
  --slurpfile lr "$LR_FILE" \
  --slurpfile rb "$RB_FILE" \
  --slurpfile sa "$SA_FILE" \
  "$NS_FILE" \
| while IFS=$'\t' read -r NS IS_SYS HAS_DENY NETPOL_COUNT HAS_RQ HAS_LR HAS_OWNER RB_COUNT SA_COUNT; do
    write_row "$NS" "$IS_SYS" "$HAS_DENY" "$NETPOL_COUNT" "$HAS_RQ" "$HAS_LR" "$HAS_OWNER" "$RB_COUNT" "$SA_COUNT"
  done

echo "[$(date +%H:%M:%S)] [$LABEL] Namespace iteration done."

USER_NS=$(jq '[.items[] | select((.metadata.name // "") | test("^(openshift|kube|default$)") | not)] | length' "$NS_FILE")
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
