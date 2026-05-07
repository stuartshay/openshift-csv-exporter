#!/usr/bin/env bash
# Description: Exports trusted image enforcement posture — image.config.openshift.io/cluster registry sources, ClusterImagePolicy / ImagePolicy signature requirements, ImageContentSourcePolicy / ImageDigestMirrorSet mirrors, and image admission plugin status (OCP-42)
# Audit Area:  Trusted Image Enforcement
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./common.sh
source "$SCRIPT_DIR/common.sh"

SCRIPT_START_SECONDS=$SECONDS
LABEL="trusted-image"
RED='\033[0;31m'
NC='\033[0m' # No Color

: "${CLUSTER_NAME_SAFE:?CLUSTER_NAME_SAFE is not set}"
: "${CLUSTER_NAME:?CLUSTER_NAME is not set}"
: "${CLUSTER_CONTEXT:?CLUSTER_CONTEXT is not set}"
: "${CLUSTER_SERVER:?CLUSTER_SERVER is not set}"
: "${OUTPUT_DIR:?OUTPUT_DIR is not set}"
: "${TIMESTAMP:?TIMESTAMP is not set}"

echo "[$(date +%H:%M:%S)] [$LABEL] Starting export at $(date)"

OUTPUT_FILE="$OUTPUT_DIR/trusted-image-enforcement-${CLUSTER_NAME_SAFE}-$TIMESTAMP.csv"

echo "cluster_name,cluster_context,cluster_server,record_type,name,namespace,detail_1,detail_2,detail_3,detail_4,detail_5,detail_6" > "$OUTPUT_FILE"

write_row() {
  local record_type="$1" name="$2" namespace="$3" d1="$4" d2="$5" d3="$6" d4="$7" d5="$8" d6="$9"
  jq -rn \
    --arg cluster_name "$CLUSTER_NAME" \
    --arg cluster_context "$CLUSTER_CONTEXT" \
    --arg cluster_server "$CLUSTER_SERVER" \
    --arg record_type "$record_type" \
    --arg name "$name" \
    --arg namespace "$namespace" \
    --arg d1 "$d1" --arg d2 "$d2" --arg d3 "$d3" \
    --arg d4 "$d4" --arg d5 "$d5" --arg d6 "$d6" \
    '[$cluster_name,$cluster_context,$cluster_server,$record_type,$name,$namespace,$d1,$d2,$d3,$d4,$d5,$d6] | @csv' \
    >> "$OUTPUT_FILE"
}

###############################################################################
# Section 1 — image.config.openshift.io/cluster
###############################################################################
echo "[$(date +%H:%M:%S)] [$LABEL] Fetching image.config/cluster..."
if IMG_CFG=$(oc get image.config.openshift.io/cluster -o json 2>/dev/null); then
  ALLOWED=$(echo "$IMG_CFG" | jq -r '(.spec.registrySources.allowedRegistries // []) | join(";")')
  BLOCKED=$(echo "$IMG_CFG" | jq -r '(.spec.registrySources.blockedRegistries // []) | join(";")')
  INSECURE=$(echo "$IMG_CFG" | jq -r '(.spec.registrySources.insecureRegistries // []) | join(";")')
  ALLOWED_IMPORT=$(echo "$IMG_CFG" | jq -r '(.spec.allowedRegistriesForImport // []) | map(.domainName) | join(";")')
  CA_NAME=$(echo "$IMG_CFG" | jq -r '.spec.additionalTrustedCA.name // ""')
  RS_SET=$(echo "$IMG_CFG" | jq -r 'if (.spec.registrySources // null) then "true" else "false" end')
  write_row "image_config" "cluster" "" "$ALLOWED" "$BLOCKED" "$INSECURE" "$ALLOWED_IMPORT" "$CA_NAME" "$RS_SET"
else
  echo -e "${RED}[$(date +%H:%M:%S)] [$LABEL] ERROR: cannot read image.config/cluster${NC}"
  write_row "image_config" "cluster" "" "" "" "" "" "" "false"
fi

###############################################################################
# Section 2 — ClusterImagePolicy / ImagePolicy
###############################################################################
echo "[$(date +%H:%M:%S)] [$LABEL] Fetching ClusterImagePolicy / ImagePolicy..."
for KIND in clusterimagepolicies.config.openshift.io imagepolicies.config.openshift.io; do
  if oc get crd "$KIND" >/dev/null 2>&1; then
    POLICIES=$(oc get "$KIND" -A -o json 2>/dev/null || echo '{"items":[]}')
    COUNT=$(echo "$POLICIES" | jq '.items | length')
    echo "[$(date +%H:%M:%S)] [$LABEL] Processing $COUNT $KIND..."
    echo "$POLICIES" | jq -c '.items[]' | while IFS= read -r item; do
      NAME=$(echo "$item" | jq -r '.metadata.name // ""')
      NS=$(echo "$item" | jq -r '.metadata.namespace // ""')
      SCOPES=$(echo "$item" | jq -r '(.spec.scopes // []) | join(";")')
      SIG_REQ=$(echo "$item" | jq -r '
        (.spec.policy.rootOfTrust.policyType // "") as $pt |
        if ($pt == "PublicKey" or $pt == "FulcioCAWithRekor") then "true" else "false" end')
      PUBKEY=$(echo "$item" | jq -r 'if (.spec.policy.rootOfTrust.publicKey.keyData // "") != "" then "true" else "false" end')
      TLOG=$(echo "$item" | jq -r '.spec.policy.rootOfTrust.fulcioCAWithRekor.rekorKeyData // "" | if . != "" then "true" else "false" end')
      write_row "cluster_image_policy" "$NAME" "$NS" "$SCOPES" "$SIG_REQ" "$PUBKEY" "$TLOG" "" ""
    done
  fi
done

###############################################################################
# Section 3 — ImageContentSourcePolicy / ImageDigestMirrorSet / ImageTagMirrorSet
###############################################################################
echo "[$(date +%H:%M:%S)] [$LABEL] Fetching image mirror policies..."
for KIND in imagecontentsourcepolicies.operator.openshift.io imagedigestmirrorsets.config.openshift.io imagetagmirrorsets.config.openshift.io; do
  if oc get crd "$KIND" >/dev/null 2>&1; then
    POLICIES=$(oc get "$KIND" -o json 2>/dev/null || echo '{"items":[]}')
    echo "$POLICIES" | jq -c '.items[]' | while IFS= read -r item; do
      NAME=$(echo "$item" | jq -r '.metadata.name // ""')
      MCOUNT=$(echo "$item" | jq -r '
        ((.spec.repositoryDigestMirrors // []) | length) +
        ((.spec.imageDigestMirrors // []) | length) +
        ((.spec.imageTagMirrors // []) | length)')
      SOURCES=$(echo "$item" | jq -r '
        ((.spec.repositoryDigestMirrors // []) + (.spec.imageDigestMirrors // []) + (.spec.imageTagMirrors // []))
        | map(.source // "") | join(";")')
      MIRRORS=$(echo "$item" | jq -r '
        ((.spec.repositoryDigestMirrors // []) + (.spec.imageDigestMirrors // []) + (.spec.imageTagMirrors // []))
        | map(.mirrors // []) | flatten | unique | join(";")')
      write_row "image_content_source_policy" "$NAME" "" "$MCOUNT" "$SOURCES" "$MIRRORS" "" "" ""
    done
  fi
done

###############################################################################
# Section 4 — Admission plugin / image policy webhook detection
###############################################################################
echo "[$(date +%H:%M:%S)] [$LABEL] Detecting image admission plugins..."
WEBHOOK_PRESENT="false"
if oc get validatingwebhookconfigurations -o json 2>/dev/null | \
    jq -e '[.items[] | select((.metadata.name // "") | test("image.?policy"; "i"))] | length > 0' >/dev/null; then
  WEBHOOK_PRESENT="true"
fi
write_row "admission_plugin" "ImagePolicyWebhook" "" "$WEBHOOK_PRESENT" "" "" "" "" ""

ELAPSED=$(( SECONDS - SCRIPT_START_SECONDS ))
echo "[$(date +%H:%M:%S)] [$LABEL] Completed at $(date) — total time: ${ELAPSED}s"
echo "Created: $OUTPUT_FILE"
