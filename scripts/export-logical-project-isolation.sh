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
# Uses only parameter expansion (no command substitution) so each row is
# fork-free; on large clusters this is ~100x faster than calling a helper
# that wraps each field in $(...).
write_row() {
  local row f esc
  esc="${CLUSTER_NAME//\"/\"\"}";    row="\"$esc\""
  esc="${CLUSTER_CONTEXT//\"/\"\"}"; row+=",\"$esc\""
  esc="${CLUSTER_SERVER//\"/\"\"}";  row+=",\"$esc\""
  for f in "$@"; do
    esc="${f//\"/\"\"}"
    row+=",\"$esc\""
  done
  printf '%s\n' "$row"
}

echo "[$(date +%H:%M:%S)] [$LABEL] Fetching namespaces, networkpolicies, resourcequotas, limitranges, rolebindings, serviceaccounts (in parallel)..."
NS_FILE=$(mktemp)
NETPOL_FILE=$(mktemp)
RQ_FILE=$(mktemp)
LR_FILE=$(mktemp)
RB_FILE=$(mktemp)
SA_FILE=$(mktemp)
JQ_FILE=$(mktemp)
trap 'rm -f "$NS_FILE" "$NETPOL_FILE" "$RQ_FILE" "$LR_FILE" "$RB_FILE" "$SA_FILE" "$JQ_FILE"' EXIT

# Fetch all six resources in parallel. RoleBindings and ServiceAccounts use a
# trimmed jsonpath -> JSON shape because we only need namespace+name for counts;
# this is dramatically smaller than the full object payload on large clusters.
FETCH_START=$SECONDS
(
  oc get ns -o json 2>/dev/null >"$NS_FILE" || echo '{"items":[]}' >"$NS_FILE"
) &
PID_NS=$!
(
  oc get networkpolicies -A -o json 2>/dev/null >"$NETPOL_FILE" || echo '{"items":[]}' >"$NETPOL_FILE"
) &
PID_NP=$!
(
  oc get resourcequotas -A -o json 2>/dev/null >"$RQ_FILE" || echo '{"items":[]}' >"$RQ_FILE"
) &
PID_RQ=$!
(
  oc get limitranges -A -o json 2>/dev/null >"$LR_FILE" || echo '{"items":[]}' >"$LR_FILE"
) &
PID_LR=$!
(
  oc get rolebindings -A -o jsonpath='{range .items[*]}{.metadata.namespace}{"\t"}{.metadata.name}{"\n"}{end}' 2>/dev/null \
    | awk -F'\t' 'BEGIN{print "{\"items\":["; sep=""} NF>=1 {gsub(/\\/,"\\\\",$1); gsub(/"/,"\\\"",$1); printf "%s{\"metadata\":{\"namespace\":\"%s\"}}", sep, $1; sep=","} END{print "]}"}' \
    >"$RB_FILE" || echo '{"items":[]}' >"$RB_FILE"
) &
PID_RB=$!
(
  oc get serviceaccounts -A -o jsonpath='{range .items[*]}{.metadata.namespace}{"\t"}{.metadata.name}{"\n"}{end}' 2>/dev/null \
    | awk -F'\t' 'BEGIN{print "{\"items\":["; sep=""} NF>=1 {gsub(/\\/,"\\\\",$1); gsub(/"/,"\\\"",$1); printf "%s{\"metadata\":{\"namespace\":\"%s\"}}", sep, $1; sep=","} END{print "]}"}' \
    >"$SA_FILE" || echo '{"items":[]}' >"$SA_FILE"
) &
PID_SA=$!

wait "$PID_NS" "$PID_NP" "$PID_RQ" "$PID_LR" "$PID_RB" "$PID_SA"
echo "[$(date +%H:%M:%S)] [$LABEL] Fetch complete in $(( SECONDS - FETCH_START ))s."

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

ITER_START=$SECONDS
PROGRESS_EVERY=50
jq -rf "$JQ_FILE" \
  --slurpfile netpol "$NETPOL_FILE" \
  --slurpfile rq "$RQ_FILE" \
  --slurpfile lr "$LR_FILE" \
  --slurpfile rb "$RB_FILE" \
  --slurpfile sa "$SA_FILE" \
  "$NS_FILE" \
| {
    i=0
    while IFS=$'\t' read -r NS IS_SYS HAS_DENY NETPOL_COUNT HAS_RQ HAS_LR HAS_OWNER RB_COUNT SA_COUNT; do
      write_row "$NS" "$IS_SYS" "$HAS_DENY" "$NETPOL_COUNT" "$HAS_RQ" "$HAS_LR" "$HAS_OWNER" "$RB_COUNT" "$SA_COUNT"
      i=$((i + 1))
      if (( i % PROGRESS_EVERY == 0 )); then
        printf '[%s] [%s]   Processed %d/%d namespaces (last: %s)\n' \
          "$(date +%H:%M:%S)" "$LABEL" "$i" "$TOTAL" "$NS" >&2
      fi
    done
    printf '[%s] [%s]   Processed %d/%d namespaces (final)\n' \
      "$(date +%H:%M:%S)" "$LABEL" "$i" "$TOTAL" >&2
  } >> "$OUTPUT_FILE"

echo "[$(date +%H:%M:%S)] [$LABEL] Namespace iteration done in $(( SECONDS - ITER_START ))s."

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
