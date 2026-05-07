#!/usr/bin/env bash
# Description: Exports image signing and verification posture — ClusterImagePolicy / ImagePolicy signature requirements (cosign / sigstore), BuildConfigs and their push-secret / sign configuration, Tekton signing tasks, and registry signature-store configuration — for OCP-47 Image Signing & Verification auditing
# Audit Area:  Image Signing and Verification
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./common.sh
source "$SCRIPT_DIR/common.sh"

SCRIPT_START_SECONDS=$SECONDS
LABEL="image-signing"
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

OUTPUT_FILE="$OUTPUT_DIR/image-signing-verification-${CLUSTER_NAME_SAFE}-$TIMESTAMP.csv"
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

# ── Section 1: ClusterImagePolicy signatures ────────────────────────────────
echo "[$(date +%H:%M:%S)] [$LABEL] Fetching ClusterImagePolicy / ImagePolicy..."
CIP_JSON=$(oc get clusterimagepolicies.config.openshift.io -A -o json 2>/dev/null || echo '{"items":[]}')
IP_JSON=$(oc get imagepolicies.config.openshift.io -A -o json 2>/dev/null || echo '{"items":[]}')
ALL_POLICIES=$(jq -s '{items: ((.[0].items // []) + (.[1].items // []))}' <(echo "$CIP_JSON") <(echo "$IP_JSON"))
POLICY_COUNT=$(echo "$ALL_POLICIES" | jq '.items | length')
echo "[$(date +%H:%M:%S)] [$LABEL] Processing $POLICY_COUNT image policies..."

if [ "$POLICY_COUNT" -eq 0 ]; then
  write_row "cluster_image_policy_signature" "(none)" "" "" "false" "false" "" "" ""
fi

echo "$ALL_POLICIES" | jq -c '.items[]' | while IFS= read -r pol; do
  NAME=$(echo "$pol" | jq -r '.metadata.name // ""')
  NS=$(echo "$pol" | jq -r '.metadata.namespace // ""')
  ROOT_TYPE=$(echo "$pol" | jq -r '[.spec.policy.rootOfTrust.policyType // ""] | first // ""')
  SIG_REQUIRED="false"
  if echo "$ROOT_TYPE" | grep -Eq '^(PublicKey|FulcioCAWithRekor)$'; then
    SIG_REQUIRED="true"
  fi
  PUBKEY_PRESENT=$(echo "$pol" | jq -r '
    if (.spec.policy.rootOfTrust.publicKey.keyData // "") != "" then "true" else "false" end')
  REKOR_URL=$(echo "$pol" | jq -r '.spec.policy.rootOfTrust.fulcioCAWithRekor.rekorKeyData // ""')
  SCOPES=$(echo "$pol" | jq -r '[.spec.scopes[]?] | join(";")')
  write_row "cluster_image_policy_signature" "$NAME" "$NS" "$ROOT_TYPE" "$SIG_REQUIRED" "$PUBKEY_PRESENT" "$REKOR_URL" "$SCOPES" ""
done

# ── Section 2: BuildConfigs ──────────────────────────────────────────────────
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
     else "" end)')
  OUTPUT_IMG=$(echo "$bc" | jq -r '.spec.output.to.name // ""')
  PUSH_SECRET=$(echo "$bc" | jq -r '.spec.output.pushSecret.name // ""')
  # Heuristic: signing enabled if there is a sign-related output annotation/label or
  # imageLabels/dockerStrategy env that references cosign/notation.
  SIGNING_ENABLED=$(echo "$bc" | jq -r '
    if (.metadata.annotations["build.openshift.io/sign"] // "") == "true" then "true"
    elif ([(.spec.strategy.dockerStrategy.env // []),(.spec.strategy.sourceStrategy.env // [])]
          | flatten | map(.name // "") | map(ascii_downcase)
          | any(. == "cosign_password" or . == "cosign_key" or . == "notation_key")) then "true"
    else "false" end')
  TOOL=$(echo "$bc" | jq -r '
    [(.spec.strategy.dockerStrategy.env // []),(.spec.strategy.sourceStrategy.env // [])]
    | flatten | map((.name // "") | ascii_downcase)
    | if any(startswith("cosign")) then "cosign"
      elif any(startswith("notation")) then "notation"
      else "" end')
  write_row "build_config" "$NAME" "$NS" "$STRATEGY" "$OUTPUT_IMG" "$PUSH_SECRET" "$SIGNING_ENABLED" "$TOOL" ""
done

# ── Section 3: Tekton signing tasks ──────────────────────────────────────────
echo "[$(date +%H:%M:%S)] [$LABEL] Looking for Tekton signing tasks (cosign/notation)..."
TASK_JSON=$(oc get tasks.tekton.dev,clustertasks.tekton.dev -A -o json 2>/dev/null || echo '{"items":[]}')
echo "$TASK_JSON" | jq -c '
  .items[] |
  select(((.metadata.name // "") | ascii_downcase) | test("cosign|notation|sigstore|sign-image"))
' | while IFS= read -r tk; do
  NAME=$(echo "$tk" | jq -r '.metadata.name // ""')
  NS=$(echo "$tk" | jq -r '.metadata.namespace // ""')
  KIND=$(echo "$tk" | jq -r '.kind // ""')
  TOOL=$(echo "$tk" | jq -r '
    (.metadata.name // "") | ascii_downcase |
    if test("cosign") then "cosign"
    elif test("notation") then "notation"
    else "sigstore" end')
  KEY_REF=$(echo "$tk" | jq -r '
    [.spec.params[]? | select((.name // "") | ascii_downcase | test("key|kms"))][0].default // ""')
  write_row "tekton_signing_task" "$NAME" "$NS" "$KIND" "$TOOL" "$KEY_REF" "" "" ""
done

# ── Section 4: Registry signature-store config ──────────────────────────────
echo "[$(date +%H:%M:%S)] [$LABEL] Fetching image registry config (sigstore stores)..."
IMG_CFG=$(oc get image.config.openshift.io/cluster -o json 2>/dev/null || echo '{}')
echo "$IMG_CFG" | jq -c '
  (.spec.registrySources.containerRuntimeSearchRegistries // []) +
  (.spec.allowedRegistriesForImport // [] | map(.domainName))
  | unique | .[]?
' | while IFS= read -r reg; do
  REG=$(echo "$reg" | jq -r '. // ""')
  [ -z "$REG" ] && continue
  write_row "registry_signature_config" "$REG" "" "$REG" "" "" "" "" ""
done

ELAPSED=$(( SECONDS - SCRIPT_START_SECONDS ))
echo "[$(date +%H:%M:%S)] [$LABEL] Completed at $(date) — total time: ${ELAPSED}s"
echo "Created: $OUTPUT_FILE"
