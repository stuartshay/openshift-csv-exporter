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
NS_JSON=$(oc get ns -o json 2>/dev/null || echo '{"items":[]}')
LR_JSON=$(oc get limitranges -A -o json 2>/dev/null || echo '{"items":[]}')
RQ_JSON=$(oc get resourcequotas -A -o json 2>/dev/null || echo '{"items":[]}')
POD_JSON=$(oc get pods -A -o json 2>/dev/null || echo '{"items":[]}')

TOTAL=$(echo "$NS_JSON" | jq '.items | length')
echo "[$(date +%H:%M:%S)] [$LABEL] Processing $TOTAL namespaces..."

echo "$NS_JSON" | jq -c '.items[]' | while IFS= read -r ns_item; do
  NS=$(echo "$ns_item" | jq -r '.metadata.name // ""')
  IS_SYS="false"
  if echo "$NS" | grep -Eq '^(openshift|kube)' || [ "$NS" = "default" ]; then
    IS_SYS="true"
  fi

  LR_DEF_REQ=$(echo "$LR_JSON" | jq -r --arg ns "$NS" '
    [.items[] | select(.metadata.namespace == $ns) | .spec.limits[]? |
      select(.type == "Container" or .type == "Pod") |
      .defaultRequest["ephemeral-storage"] // empty
    ] | first // ""')
  LR_DEF_LIM=$(echo "$LR_JSON" | jq -r --arg ns "$NS" '
    [.items[] | select(.metadata.namespace == $ns) | .spec.limits[]? |
      select(.type == "Container" or .type == "Pod") |
      .default["ephemeral-storage"] // empty
    ] | first // ""')
  LR_MAX=$(echo "$LR_JSON" | jq -r --arg ns "$NS" '
    [.items[] | select(.metadata.namespace == $ns) | .spec.limits[]? |
      .max["ephemeral-storage"] // empty
    ] | first // ""')

  HAS_LR_DEF_REQ=$([ -n "$LR_DEF_REQ" ] && echo "true" || echo "false")
  HAS_LR_DEF_LIM=$([ -n "$LR_DEF_LIM" ] && echo "true" || echo "false")
  HAS_LR_MAX=$([ -n "$LR_MAX" ] && echo "true" || echo "false")

  Q_REQ=$(echo "$RQ_JSON" | jq -r --arg ns "$NS" '
    [.items[] | select(.metadata.namespace == $ns) |
      .spec.hard["requests.ephemeral-storage"] // empty
    ] | first // ""')
  Q_LIM=$(echo "$RQ_JSON" | jq -r --arg ns "$NS" '
    [.items[] | select(.metadata.namespace == $ns) |
      .spec.hard["limits.ephemeral-storage"] // empty
    ] | first // ""')
  HAS_Q_REQ=$([ -n "$Q_REQ" ] && echo "true" || echo "false")
  HAS_Q_LIM=$([ -n "$Q_LIM" ] && echo "true" || echo "false")

  EMPTY_TOTAL=$(echo "$POD_JSON" | jq --arg ns "$NS" '
    [.items[] | select(.metadata.namespace == $ns) |
      select(.spec.volumes // [] | map(.emptyDir) | map(select(. != null)) | length > 0)
    ] | length')
  EMPTY_NO_SIZE=$(echo "$POD_JSON" | jq --arg ns "$NS" '
    [.items[] | select(.metadata.namespace == $ns) |
      select(.spec.volumes // [] |
        map(select(.emptyDir != null and (.emptyDir.sizeLimit // "") == "")) |
        length > 0)
    ] | length')

  jq -nr \
    --arg cluster_name "$CLUSTER_NAME" \
    --arg cluster_context "$CLUSTER_CONTEXT" \
    --arg cluster_server "$CLUSTER_SERVER" \
    --arg ns "$NS" \
    --arg is_sys "$IS_SYS" \
    --arg has_lr_def_req "$HAS_LR_DEF_REQ" \
    --arg has_lr_def_lim "$HAS_LR_DEF_LIM" \
    --arg has_lr_max "$HAS_LR_MAX" \
    --arg lr_def_req "$LR_DEF_REQ" \
    --arg lr_def_lim "$LR_DEF_LIM" \
    --arg lr_max "$LR_MAX" \
    --arg has_q_req "$HAS_Q_REQ" \
    --arg has_q_lim "$HAS_Q_LIM" \
    --arg q_req "$Q_REQ" \
    --arg q_lim "$Q_LIM" \
    --arg empty_total "$EMPTY_TOTAL" \
    --arg empty_no_size "$EMPTY_NO_SIZE" '
    [$cluster_name,$cluster_context,$cluster_server,$ns,$is_sys,
     $has_lr_def_req,$has_lr_def_lim,$has_lr_max,
     $lr_def_req,$lr_def_lim,$lr_max,
     $has_q_req,$has_q_lim,$q_req,$q_lim,
     $empty_total,$empty_no_size] | @csv
  ' >> "$OUTPUT_FILE"
done

ELAPSED=$(( SECONDS - SCRIPT_START_SECONDS ))
echo "[$(date +%H:%M:%S)] [$LABEL] Completed at $(date) — total time: ${ELAPSED}s"
echo "Created: $OUTPUT_FILE"
