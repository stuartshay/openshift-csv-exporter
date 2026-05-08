#!/usr/bin/env bash
# Description: Exports Build / Source-to-Image (S2I) policy posture — BuildConfigs (strategy, base image, source secrets, push secrets, run-as / privileged hints), Build cluster defaults (build.config.openshift.io/cluster), and ImageStream policy (lookupPolicy.local) — for OCP-47 Build/S2I Policy auditing
# Audit Area:  Build / Source-to-Image (S2I) Policy
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./common.sh
source "$SCRIPT_DIR/common.sh"

SCRIPT_START_SECONDS=$SECONDS
LABEL="build-s2i"
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

OUTPUT_FILE="$OUTPUT_DIR/build-s2i-policy-${CLUSTER_NAME_SAFE}-$TIMESTAMP.csv"
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

# ── Section 1: Build cluster default (build.config.openshift.io/cluster) ───
echo "[$(date +%H:%M:%S)] [$LABEL] Fetching build.config.openshift.io/cluster..."
BUILD_CFG=$(oc get build.config.openshift.io cluster -o json 2>/dev/null || echo '{}')
if [ "$(echo "$BUILD_CFG" | jq 'length')" -gt 0 ]; then
  DEFAULT_PROXY=$(echo "$BUILD_CFG" | jq -r '.spec.buildDefaults.gitProxy // .spec.buildDefaults.gitHTTPSProxy // ""')
  IMAGE_LABELS=$(echo "$BUILD_CFG" | jq -r '[.spec.buildDefaults.imageLabels[]?.name] | join(";")')
  RESOURCE_LIMITS=$(echo "$BUILD_CFG" | jq -r '.spec.buildDefaults.resources.limits // {} | to_entries | map("\(.key)=\(.value)") | join(";")')
  RESOURCE_REQUESTS=$(echo "$BUILD_CFG" | jq -r '.spec.buildDefaults.resources.requests // {} | to_entries | map("\(.key)=\(.value)") | join(";")')
  ENFORCE_POLICY=$(echo "$BUILD_CFG" | jq -r '.spec.buildOverrides.imageLabels // [] | length | tostring')
  write_row "build_default_config" "cluster" "" "$DEFAULT_PROXY" "$IMAGE_LABELS" "$RESOURCE_LIMITS" "$RESOURCE_REQUESTS" "$ENFORCE_POLICY" ""
else
  write_row "build_default_config" "(none)" "" "" "" "" "" "" ""
fi

# ── Section 2: BuildConfigs ─────────────────────────────────────────────────
echo "[$(date +%H:%M:%S)] [$LABEL] Fetching BuildConfigs..."
BC_JSON=$(oc get buildconfigs -A -o json 2>/dev/null || echo '{"items":[]}')
BC_COUNT=$(echo "$BC_JSON" | jq '.items | length')
echo "[$(date +%H:%M:%S)] [$LABEL] Processing $BC_COUNT BuildConfigs..."

echo "$BC_JSON" | jq -c '.items[]' | while IFS= read -r bc; do
  NAME=$(echo "$bc" | jq -r '.metadata.name // ""')
  NS=$(echo "$bc" | jq -r '.metadata.namespace // ""')
  STRATEGY=$(echo "$bc" | jq -r '
    .spec.strategy.type //
    (if .spec.strategy.dockerStrategy then "Docker"
     elif .spec.strategy.sourceStrategy then "Source"
     elif .spec.strategy.customStrategy then "Custom"
     elif .spec.strategy.jenkinsPipelineStrategy then "JenkinsPipeline"
     else "" end)')
  BASE_IMAGE=$(echo "$bc" | jq -r '
    .spec.strategy.sourceStrategy.from.name //
    .spec.strategy.dockerStrategy.from.name //
    .spec.strategy.customStrategy.from.name // ""')
  SOURCE_SECRET=$(echo "$bc" | jq -r '.spec.source.sourceSecret.name // ""')
  PUSH_SECRET=$(echo "$bc" | jq -r '.spec.output.pushSecret.name // ""')
  FORCE_PULL=$(echo "$bc" | jq -r '
    .spec.strategy.dockerStrategy.forcePull //
    .spec.strategy.sourceStrategy.forcePull //
    .spec.strategy.customStrategy.forcePull // false | tostring')
  NO_CACHE=$(echo "$bc" | jq -r '.spec.strategy.dockerStrategy.noCache // false | tostring')
  PRIVILEGED=$(echo "$bc" | jq -r '
    .spec.strategy.customStrategy.exposeDockerSocket // false | tostring')
  write_row "build_config" "$NAME" "$NS" "$STRATEGY" "$BASE_IMAGE" "$SOURCE_SECRET" "$PUSH_SECRET" "$FORCE_PULL" "$PRIVILEGED|$NO_CACHE"
done

# ── Section 3: ImageStream policy ───────────────────────────────────────────
echo "[$(date +%H:%M:%S)] [$LABEL] Fetching ImageStreams (lookupPolicy)..."
IS_JSON=$(oc get imagestreams -A -o json 2>/dev/null || echo '{"items":[]}')
IS_COUNT=$(echo "$IS_JSON" | jq '.items | length')
echo "[$(date +%H:%M:%S)] [$LABEL] Processing $IS_COUNT ImageStreams..."

echo "$IS_JSON" | jq -c '.items[]' | while IFS= read -r is; do
  NAME=$(echo "$is" | jq -r '.metadata.name // ""')
  NS=$(echo "$is" | jq -r '.metadata.namespace // ""')
  LOOKUP_LOCAL=$(echo "$is" | jq -r '.spec.lookupPolicy.local // false | tostring')
  TAG_COUNT=$(echo "$is" | jq -r '[.spec.tags[]?] | length | tostring')
  INSECURE_TAGS=$(echo "$is" | jq -r '
    [.spec.tags[]? | select(.importPolicy.insecure == true) | .name] | join(";")')
  REFERENCE_POLICY=$(echo "$is" | jq -r '
    [.spec.tags[]? | .referencePolicy.type // ""] | unique | join(";")')
  write_row "image_stream_policy" "$NAME" "$NS" "$LOOKUP_LOCAL" "$TAG_COUNT" "$INSECURE_TAGS" "$REFERENCE_POLICY" "" ""
done

ELAPSED=$(( SECONDS - SCRIPT_START_SECONDS ))
echo "[$(date +%H:%M:%S)] [$LABEL] Completed at $(date) — total time: ${ELAPSED}s"
echo "Created: $OUTPUT_FILE"
