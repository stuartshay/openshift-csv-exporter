#!/usr/bin/env bash
# Description: Exports per-namespace ephemeral storage governance — LimitRange default request/limit and max for ephemeral-storage, ResourceQuota hard caps for requests.ephemeral-storage and limits.ephemeral-storage, and a count of pods using emptyDir without sizeLimit — for OCP-49 Ephemeral Storage Limits auditing
# Audit Area:  Ephemeral Storage Limits
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./common.sh
source "$SCRIPT_DIR/common.sh"

SCRIPT_START_SECONDS=$SECONDS
LABEL="ephemeral-storage"
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

OUTPUT_FILE="$OUTPUT_DIR/ephemeral-storage-limits-${CLUSTER_NAME_SAFE}-$TIMESTAMP.csv"
echo "cluster_name,cluster_context,cluster_server,namespace,is_system_namespace,has_lr_default_request,has_lr_default_limit,has_lr_max,lr_default_request,lr_default_limit,lr_max,has_quota_request,has_quota_limit,quota_request_hard,quota_limit_hard,emptydir_pods_total,emptydir_pods_without_sizelimit" > "$OUTPUT_FILE"

echo "[$(date +%H:%M:%S)] [$LABEL] Fetching namespaces, limitranges, resourcequotas, pods..."

# Stage all JSON to temp files. Pods JSON on large clusters can exceed argv
# size limits (and shell-variable practical limits), so we never assign it to
# a shell variable — we project it down with jq while streaming from `oc`
# straight to disk, keeping only the fields this report needs.
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT
NS_FILE="$TMP_DIR/ns.json"
LR_FILE="$TMP_DIR/lr.json"
RQ_FILE="$TMP_DIR/rq.json"
POD_FILE="$TMP_DIR/pods.json"

oc get ns             -o json 2>/dev/null > "$NS_FILE" || echo '{"items":[]}' > "$NS_FILE"
oc get limitranges -A -o json 2>/dev/null > "$LR_FILE" || echo '{"items":[]}' > "$LR_FILE"
oc get resourcequotas -A -o json 2>/dev/null > "$RQ_FILE" || echo '{"items":[]}' > "$RQ_FILE"

# Project pods to just (namespace, emptyDir sizeLimit per volume). This drops
# 95%+ of the payload before any further processing.
if ! oc get pods -A -o json 2>/dev/null \
    | jq -c '{items: [.items[] | {ns: .metadata.namespace, eds: [(.spec.volumes // [])[] | select(.emptyDir != null) | (.emptyDir.sizeLimit // "")]}]}' \
        > "$POD_FILE" 2>/dev/null; then
  echo -e "${RED}[$LABEL] WARNING: failed to fetch/project pods — emptydir counts will be 0${NC}"
  echo '{"items":[]}' > "$POD_FILE"
fi

TOTAL=$(jq '.items | length' "$NS_FILE")
echo "[$(date +%H:%M:%S)] [$LABEL] Processing $TOTAL namespaces (single jq pass)..."

# Build per-namespace indexes once and emit all CSV rows in a single jq
# invocation. This avoids the previous O(N_namespaces × N_pods) cost of
# re-filtering pod JSON for every namespace, which is the dominant slowdown
# on clusters with >1000 namespaces.
JQ_PROGRAM_FILE="$TMP_DIR/program.jq"
cat >"$JQ_PROGRAM_FILE" <<'JQ'
  ($lr[0].items   | group_by(.metadata.namespace) | map({key: .[0].metadata.namespace, value: .}) | from_entries) as $lr_by_ns |
  ($rq[0].items   | group_by(.metadata.namespace) | map({key: .[0].metadata.namespace, value: .}) | from_entries) as $rq_by_ns |
  ($pods[0].items | group_by(.ns)                 | map({key: .[0].ns,                 value: .}) | from_entries) as $pod_by_ns |
  .items[] |
  .metadata.name as $ns |
  ((($ns | test("^(openshift|kube)")) or $ns == "default") | tostring) as $is_sys |
  (($lr_by_ns[$ns]  // [])) as $lrs |
  (($rq_by_ns[$ns]  // [])) as $rqs |
  (($pod_by_ns[$ns] // [])) as $pds |
  ( [ $lrs[].spec.limits[]? | select(.type == "Container" or .type == "Pod") | .defaultRequest["ephemeral-storage"] // empty ] | (.[0] // "") ) as $lr_def_req |
  ( [ $lrs[].spec.limits[]? | select(.type == "Container" or .type == "Pod") | .default["ephemeral-storage"] // empty ]        | (.[0] // "") ) as $lr_def_lim |
  ( [ $lrs[].spec.limits[]? | .max["ephemeral-storage"] // empty ]                                                              | (.[0] // "") ) as $lr_max |
  ( [ $rqs[].spec.hard["requests.ephemeral-storage"] // empty ] | (.[0] // "") ) as $q_req |
  ( [ $rqs[].spec.hard["limits.ephemeral-storage"]   // empty ] | (.[0] // "") ) as $q_lim |
  ( [ $pds[] | select((.eds | length) > 0) ] | length ) as $empty_total |
  ( [ $pds[] | select(any(.eds[]?; . == "")) ] | length ) as $empty_no_size |
  [
    $cluster_name, $cluster_context, $cluster_server,
    $ns, $is_sys,
    (($lr_def_req | length > 0) | tostring),
    (($lr_def_lim | length > 0) | tostring),
    (($lr_max     | length > 0) | tostring),
    $lr_def_req, $lr_def_lim, $lr_max,
    (($q_req | length > 0) | tostring),
    (($q_lim | length > 0) | tostring),
    $q_req, $q_lim,
    ($empty_total   | tostring),
    ($empty_no_size | tostring)
  ] | @csv
JQ

jq -rf "$JQ_PROGRAM_FILE" \
  --arg cluster_name    "$CLUSTER_NAME" \
  --arg cluster_context "$CLUSTER_CONTEXT" \
  --arg cluster_server  "$CLUSTER_SERVER" \
  --slurpfile lr   "$LR_FILE" \
  --slurpfile rq   "$RQ_FILE" \
  --slurpfile pods "$POD_FILE" \
  "$NS_FILE" \
  >> "$OUTPUT_FILE"

ELAPSED=$(( SECONDS - SCRIPT_START_SECONDS ))
echo "[$(date +%H:%M:%S)] [$LABEL] Completed at $(date) — total time: ${ELAPSED}s"
echo "Created: $OUTPUT_FILE"
