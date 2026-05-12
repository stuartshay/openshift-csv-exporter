#!/usr/bin/env bash
# Description: Exports admission controller hardening posture — APIServer admission plugin enable/disable list, ValidatingWebhookConfiguration and MutatingWebhookConfiguration entries with failurePolicy / sideEffects / timeoutSeconds / namespaceSelector / scope — for OCP-50 Admission Controller Hardening auditing
# Audit Area:  Admission Controller Hardening
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./common.sh
source "$SCRIPT_DIR/common.sh"

SCRIPT_START_SECONDS=$SECONDS
LABEL="admission-hardening"
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

OUTPUT_FILE="$OUTPUT_DIR/admission-controller-hardening-${CLUSTER_NAME_SAFE}-$TIMESTAMP.csv"
echo "cluster_name,cluster_context,cluster_server,record_type,name,namespace,detail_1,detail_2,detail_3,detail_4,detail_5,detail_6" > "$OUTPUT_FILE"

write_row() {
  jq -nr \
    --arg cluster_name "$CLUSTER_NAME" \
    --arg cluster_context "$CLUSTER_CONTEXT" \
    --arg cluster_server "$CLUSTER_SERVER" \
    --arg record_type "$1" \
    --arg name "$2" \
    --arg namespace "$3" \
    --arg d1 "$4" \
    --arg d2 "$5" \
    --arg d3 "$6" \
    --arg d4 "$7" \
    --arg d5 "$8" \
    --arg d6 "$9" \
    '[$cluster_name,$cluster_context,$cluster_server,$record_type,$name,$namespace,$d1,$d2,$d3,$d4,$d5,$d6] | @csv' >> "$OUTPUT_FILE"
}

# ── Section 1: APIServer admission plugin config ───────────────────────────
echo "[$(date +%H:%M:%S)] [$LABEL] Fetching apiserver/cluster..."
APISERVER=$(oc get apiserver cluster -o json 2>/dev/null || echo '{}')
if [ "$(echo "$APISERVER" | jq 'length')" -gt 0 ]; then
  ADDITIONAL=$(echo "$APISERVER" | jq -r '[.spec.audit.profile // "Default"] | join(";")')
  TLS_PROFILE=$(echo "$APISERVER" | jq -r '.spec.tlsSecurityProfile.type // "Intermediate"')
  write_row "apiserver_config" "cluster" "" "$ADDITIONAL" "$TLS_PROFILE" "" "" "" ""
fi

# ── Section 2: kube-apiserver default-on admission plugins (from operator) ─
echo "[$(date +%H:%M:%S)] [$LABEL] Fetching kube-apiserver operator config..."
KAS=$(oc get kubeapiserver cluster -o json 2>/dev/null || echo '{}')
if [ "$(echo "$KAS" | jq 'length')" -gt 0 ]; then
  ENABLED=$(echo "$KAS" | jq -r '
    .spec.observedConfig.apiServerArguments["enable-admission-plugins"] // [] | join(";")')
  DISABLED=$(echo "$KAS" | jq -r '
    .spec.observedConfig.apiServerArguments["disable-admission-plugins"] // [] | join(";")')
  write_row "apiserver_admission_plugin" "kube-apiserver" "" "$ENABLED" "$DISABLED" "" "" "" ""
fi

# Always emit a synthetic row per default-on hardening plugin so notebooks
# can verify presence. OCP 4.18 defaults include LimitRanger, ResourceQuota,
# PodSecurity, NodeRestriction, MutatingAdmissionWebhook, ValidatingAdmissionWebhook.
for plugin in LimitRanger ResourceQuota PodSecurity NodeRestriction MutatingAdmissionWebhook ValidatingAdmissionWebhook; do
  PRESENT="unknown"
  if [ "$(echo "$KAS" | jq 'length')" -gt 0 ]; then
    if echo "$KAS" | jq -e --arg p "$plugin" '
      (.spec.observedConfig.apiServerArguments["enable-admission-plugins"] // []) | index($p)
    ' >/dev/null 2>&1; then
      PRESENT="enabled"
    elif echo "$KAS" | jq -e --arg p "$plugin" '
      (.spec.observedConfig.apiServerArguments["disable-admission-plugins"] // []) | index($p)
    ' >/dev/null 2>&1; then
      PRESENT="disabled"
    else
      PRESENT="default"
    fi
  fi
  write_row "default_admission_plugin" "$plugin" "" "$PRESENT" "" "" "" "" ""
done

# ── Section 3: ValidatingWebhookConfigurations ─────────────────────────────
echo "[$(date +%H:%M:%S)] [$LABEL] Fetching ValidatingWebhookConfigurations..."
VWC=$(oc get validatingwebhookconfigurations -o json 2>/dev/null || echo '{"items":[]}')
VWC_COUNT=$(echo "$VWC" | jq '[.items[].webhooks[]?] | length')
echo "[$(date +%H:%M:%S)] [$LABEL] Processing $VWC_COUNT validating webhooks..."

# Single jq pass emitting TSV avoids spawning multiple jq.exe processes per
# row, which triggers the `wargc == argc` assertion on jq for Windows under
# Git Bash when used inside nested while-read loops. The program is loaded
# from a temp file via `jq -f` because passing a multi-line program string
# through argv hits the same Windows-only MSYS arg-conversion assertion
# (src/main.c:256) when stdin is non-trivial.
WEBHOOK_JQ_FILE="$(mktemp)"
trap 'rm -f "$WEBHOOK_JQ_FILE"' EXIT
cat >"$WEBHOOK_JQ_FILE" <<'JQ'
.items[] as $cfg | $cfg.webhooks[]? as $w |
[
  $cfg.metadata.name,
  ($w.name // ""),
  ($w.failurePolicy // "Fail"),
  ($w.timeoutSeconds // 30 | tostring),
  ($w.sideEffects // "Unknown"),
  ([$w.rules[]?.scope] | unique | join(";")),
  ([$w.rules[]?.resources[]?] | unique | join(";")),
  (
    ($w.namespaceSelector // {}) as $ns |
    if (($ns.matchLabels // {}) | length) == 0
      and (($ns.matchExpressions // []) | length) == 0
    then "" else ($ns | tostring) end
  )
] | @tsv
JQ

echo "$VWC" | jq -rf "$WEBHOOK_JQ_FILE" | while IFS=$'\t' read -r CFG WNAME FAIL TIMEOUT SIDE SCOPE RES NS_SEL; do
  [ -z "$CFG" ] && continue
  write_row "validating_webhook" "${CFG}/${WNAME}" "" "$FAIL" "$TIMEOUT" "$SIDE" "$SCOPE" "$RES" "$NS_SEL"
done

# ── Section 4: MutatingWebhookConfigurations ───────────────────────────────
echo "[$(date +%H:%M:%S)] [$LABEL] Fetching MutatingWebhookConfigurations..."
MWC=$(oc get mutatingwebhookconfigurations -o json 2>/dev/null || echo '{"items":[]}')
MWC_COUNT=$(echo "$MWC" | jq '[.items[].webhooks[]?] | length')
echo "[$(date +%H:%M:%S)] [$LABEL] Processing $MWC_COUNT mutating webhooks..."

echo "$MWC" | jq -rf "$WEBHOOK_JQ_FILE" | while IFS=$'\t' read -r CFG WNAME FAIL TIMEOUT SIDE SCOPE RES NS_SEL; do
  [ -z "$CFG" ] && continue
  write_row "mutating_webhook" "${CFG}/${WNAME}" "" "$FAIL" "$TIMEOUT" "$SIDE" "$SCOPE" "$RES" "$NS_SEL"
done

ELAPSED=$(( SECONDS - SCRIPT_START_SECONDS ))
echo "[$(date +%H:%M:%S)] [$LABEL] Completed at $(date) — total time: ${ELAPSED}s"
echo "Created: $OUTPUT_FILE"
