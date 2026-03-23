#!/usr/bin/env bash
# Description: Exports TLS secrets and certificate signing requests (CSRs) across control-plane namespaces to assess certificate rotation health
# Audit Area:  Secrets & Certificate Rotation
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./common.sh
source "$SCRIPT_DIR/common.sh"

: "${CLUSTER_NAME_SAFE:?CLUSTER_NAME_SAFE is not set}"
: "${CLUSTER_NAME:?CLUSTER_NAME is not set}"
: "${CLUSTER_CONTEXT:?CLUSTER_CONTEXT is not set}"
: "${CLUSTER_SERVER:?CLUSTER_SERVER is not set}"
: "${OUTPUT_DIR:?OUTPUT_DIR is not set}"
: "${TIMESTAMP:?TIMESTAMP is not set}"

OUTPUT_FILE="$OUTPUT_DIR/secrets-cert-rotation-${CLUSTER_NAME_SAFE}-$TIMESTAMP.csv"

LABEL="secrets-cert-rotation"
RED='\033[0;31m'
NC='\033[0m' # No Color

SCRIPT_START_SECONDS=$SECONDS
NOW_EPOCH=$(date +%s)

echo "[$LABEL] Starting export at $(date)"
echo "[$LABEL] Output file: $OUTPUT_FILE"

# CSV header
echo "cluster_name,cluster_context,cluster_server,record_type,namespace,resource_name,secret_type,creation_timestamp,age_days,signer_name,requestor,condition,annotations_rotation" > "$OUTPUT_FILE"

# =============================================================================
# 1) TLS Secrets — scan control-plane namespaces
# =============================================================================
TLS_NAMESPACES=(
  openshift-etcd
  openshift-kube-apiserver
  openshift-kube-controller-manager
  openshift-ingress
  openshift-authentication
  openshift-monitoring
  openshift-service-ca
)

TOTAL_TLS=0
echo "[$LABEL] Scanning ${#TLS_NAMESPACES[@]} control-plane namespaces for TLS secrets..."

for NS in "${TLS_NAMESPACES[@]}"; do
  echo "[$LABEL] Fetching TLS secrets from $NS..."
  SECRETS_JSON=""
  if ! SECRETS_JSON=$(oc get secrets -n "$NS" --field-selector type=kubernetes.io/tls -o json 2>/dev/null | tr -d '\r'); then
    echo -e "${RED}[$LABEL] ERROR: Failed to fetch secrets from $NS — skipping namespace${NC}"
    continue
  fi

  NS_COUNT=$(echo "$SECRETS_JSON" | jq '.items | length' | tr -d '\r')
  echo "[$LABEL] Found $NS_COUNT TLS secrets in $NS"
  TOTAL_TLS=$((TOTAL_TLS + NS_COUNT))

  if [ "$NS_COUNT" -eq 0 ]; then
    continue
  fi

  echo "$SECRETS_JSON" | jq -c '.items[]' | while IFS= read -r item; do
    CREATED=$(echo "$item" | jq -r '.metadata.creationTimestamp // ""')

    AGE_DAYS=""
    if [ -n "$CREATED" ]; then
      CREATED_EPOCH=$(date -d "$CREATED" +%s 2>/dev/null || echo "")
      if [ -n "$CREATED_EPOCH" ]; then
        AGE_DAYS=$(( (NOW_EPOCH - CREATED_EPOCH) / 86400 ))
      fi
    fi

    # Extract rotation-related annotations
    ROTATION_ANNOTATIONS=$(echo "$item" | jq -r '
      [.metadata.annotations // {} | to_entries[] |
       select(.key | test("certificate|cert|rotation|not-after|not-before|expiry"; "i")) |
       (.key + "=" + .value)] | join(";")
    ')

    echo "$item" | jq -r \
      --arg cn "$CLUSTER_NAME" --arg cc "$CLUSTER_CONTEXT" --arg cs "$CLUSTER_SERVER" \
      --arg ns "$NS" \
      --arg age "$AGE_DAYS" \
      --arg rot "$ROTATION_ANNOTATIONS" '
      [
        $cn, $cc, $cs,
        "tls_secret",
        $ns,
        (.metadata.name // ""),
        (.type // ""),
        (.metadata.creationTimestamp // ""),
        $age,
        "",
        "",
        "",
        $rot
      ] | @csv
    '
  done >> "$OUTPUT_FILE"

  echo "[$LABEL] $NS done."
done

echo "[$LABEL] TLS secrets complete — $TOTAL_TLS total across ${#TLS_NAMESPACES[@]} namespaces."

# =============================================================================
# 2) Certificate Signing Requests (CSRs) — cluster-wide
# =============================================================================
echo "[$LABEL] Fetching certificate signing requests..."

CSR_JSON=""
if ! CSR_JSON=$(oc get csr -o json 2>/dev/null | tr -d '\r'); then
  echo -e "${RED}[$LABEL] ERROR: Failed to fetch CSRs — possible permission issue${NC}"
  echo -e "${RED}[$LABEL] Hint: oc auth can-i list certificatesigningrequests --all-namespaces${NC}"
  echo -e "${RED}[$LABEL] Skipping CSR section — TLS secrets still exported above${NC}"
  CSR_JSON='{"items":[]}'
fi

CSR_COUNT=$(echo "$CSR_JSON" | jq '.items | length' | tr -d '\r')
echo "[$LABEL] Found $CSR_COUNT CSRs"

if [ "$CSR_COUNT" -gt 0 ]; then
  CSR_IDX=0
  echo "$CSR_JSON" | jq -c '.items[]' | while IFS= read -r csr; do
    CSR_IDX=$((CSR_IDX + 1))
    CREATED=$(echo "$csr" | jq -r '.metadata.creationTimestamp // ""')

    AGE_DAYS=""
    if [ -n "$CREATED" ]; then
      CREATED_EPOCH=$(date -d "$CREATED" +%s 2>/dev/null || echo "")
      if [ -n "$CREATED_EPOCH" ]; then
        AGE_DAYS=$(( (NOW_EPOCH - CREATED_EPOCH) / 86400 ))
      fi
    fi

    echo "$csr" | jq -r \
      --arg cn "$CLUSTER_NAME" --arg cc "$CLUSTER_CONTEXT" --arg cs "$CLUSTER_SERVER" \
      --arg age "$AGE_DAYS" '
      # Determine condition from status.conditions
      ((.status.conditions // []) | map(.type) | join(";")) as $cond |
      (if ($cond | length) == 0 then "Pending" else $cond end) as $condition |
      [
        $cn, $cc, $cs,
        "csr",
        "",
        (.metadata.name // ""),
        "",
        (.metadata.creationTimestamp // ""),
        $age,
        (.spec.signerName // ""),
        (.spec.username // ""),
        $condition,
        ""
      ] | @csv
    '
  done >> "$OUTPUT_FILE"

  echo "[$LABEL] CSRs done — $CSR_COUNT processed."
else
  echo "[$LABEL] No CSRs found (this may be normal if node cert rotation recently completed)."
fi

# =============================================================================
# Console summary
# =============================================================================
echo "[$LABEL] --- Summary ---"
echo "[$LABEL]   TLS secrets:  $TOTAL_TLS (across ${#TLS_NAMESPACES[@]} namespaces)"
echo "[$LABEL]   CSRs:         $CSR_COUNT"

# Count any pending CSRs
PENDING_COUNT=$(echo "$CSR_JSON" | jq '[.items[] | select((.status.conditions // []) | length == 0)] | length' | tr -d '\r')
if [ "$PENDING_COUNT" -gt 0 ]; then
  echo -e "${RED}[$LABEL]   WARNING: $PENDING_COUNT CSRs are PENDING — certificate rotation may be stalled${NC}"

  # Breakdown by signer name
  echo "[$LABEL]   Pending CSRs by signer:"
  echo "$CSR_JSON" | jq -r '
    [.items[] | select((.status.conditions // []) | length == 0)] |
    group_by(.spec.signerName) |
    map({ signer: (.[0].spec.signerName // "unknown"), count: length }) |
    sort_by(-.count)[] |
    "      \(.signer): \(.count)"
  ' | tr -d '\r' | while IFS= read -r line; do
    echo "[$LABEL] $line"
  done

  # Top 5 oldest pending CSRs
  echo "[$LABEL]   Top 5 oldest pending CSRs:"
  echo "$CSR_JSON" | jq -c '
    [.items[] | select((.status.conditions // []) | length == 0)] |
    sort_by(.metadata.creationTimestamp)[:5][]
  ' | tr -d '\r' | while IFS= read -r csr; do
    P_NAME=$(echo "$csr" | jq -r '.metadata.name // ""')
    P_CREATED=$(echo "$csr" | jq -r '.metadata.creationTimestamp // ""')
    P_REQUESTOR=$(echo "$csr" | jq -r '.spec.username // ""')
    P_SIGNER=$(echo "$csr" | jq -r '.spec.signerName // ""')
    P_AGE=""
    if [ -n "$P_CREATED" ]; then
      P_EPOCH=$(date -d "$P_CREATED" +%s 2>/dev/null || echo "")
      if [ -n "$P_EPOCH" ]; then
        P_AGE="$(( (NOW_EPOCH - P_EPOCH) / 86400 ))d"
      fi
    fi
    echo "[$LABEL]     ${P_NAME}  age=${P_AGE}  requestor=${P_REQUESTOR}  signer=${P_SIGNER}"
  done
else
  echo "[$LABEL]   Pending CSRs: 0 (healthy)"
fi

# Flag stale TLS secrets (age > 365 days) from the CSV
STALE_COUNT=0
if [ -f "$OUTPUT_FILE" ]; then
  STALE_COUNT=$(awk -F',' '$4 ~ /tls_secret/ && $9 != "" && $9+0 > 365 { count++ } END { print count+0 }' "$OUTPUT_FILE")
fi
if [ "$STALE_COUNT" -gt 0 ]; then
  echo -e "${RED}[$LABEL]   WARNING: $STALE_COUNT TLS secrets are older than 365 days — rotation may not be active${NC}"
else
  echo "[$LABEL]   Stale TLS secrets (>365d): 0"
fi

ELAPSED=$(( SECONDS - SCRIPT_START_SECONDS ))
echo "[$LABEL] Completed at $(date) — total time: ${ELAPSED}s"
echo "Created: $OUTPUT_FILE"
