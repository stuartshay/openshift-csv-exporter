#!/usr/bin/env bash
# Description: Discovers enterprise secrets integration — External Secrets Operator, Secrets Store CSI Driver, HashiCorp Vault, CyberArk Conjur, and native secrets summary
# Audit Area:  Enterprise Secrets Integration
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

LABEL="secrets-integration"
SCRIPT_START_SECONDS=$SECONDS

RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "[$LABEL] Starting export at $(date)"

OUTPUT_FILE="$OUTPUT_DIR/secrets-integration-${CLUSTER_NAME_SAFE}-$TIMESTAMP.csv"

echo "cluster_name,cluster_context,cluster_server,record_type,product_name,installed,namespace,operator_version,detail_1,detail_2,detail_3" > "$OUTPUT_FILE"

PRODUCTS_DETECTED=0
PRODUCTS_CHECKED=0

# ── Helper: write a CSV row ──────────────────────────────────────────────────
write_row() {
  local record_type="$1" product_name="$2" installed="$3" namespace="$4" operator_version="$5" detail_1="$6" detail_2="$7" detail_3="$8"
  jq -rn \
    --arg cluster_name "$CLUSTER_NAME" \
    --arg cluster_context "$CLUSTER_CONTEXT" \
    --arg cluster_server "$CLUSTER_SERVER" \
    --arg record_type "$record_type" \
    --arg product_name "$product_name" \
    --arg installed "$installed" \
    --arg namespace "$namespace" \
    --arg operator_version "$operator_version" \
    --arg detail_1 "$detail_1" \
    --arg detail_2 "$detail_2" \
    --arg detail_3 "$detail_3" \
    '[$cluster_name,$cluster_context,$cluster_server,$record_type,$product_name,$installed,$namespace,$operator_version,$detail_1,$detail_2,$detail_3] | @csv' \
    >> "$OUTPUT_FILE"
}

# ── Helper: find operator CSV version in a namespace ─────────────────────────
get_operator_csv_version() {
  local ns="$1" name_pattern="$2"
  local csv_version=""
  csv_version=$(oc get csv -n "$ns" -o json 2>/dev/null | tr -d '\r' | \
    jq -r --arg pattern "$name_pattern" '
      [.items[] | select(.metadata.name | test($pattern; "i"))] |
      sort_by(.metadata.creationTimestamp) | last |
      .spec.version // ""
    ' 2>/dev/null || echo "")
  echo "$csv_version"
}

# ═══════════════════════════════════════════════════════════════════════════════
# Section 1: External Secrets Operator (ESO)
# ═══════════════════════════════════════════════════════════════════════════════
PRODUCTS_CHECKED=$((PRODUCTS_CHECKED + 1))
echo "[$LABEL] Checking External Secrets Operator..."

ESO_INSTALLED="false"
ESO_NS=""
ESO_VERSION=""
ESO_SECRET_STORES="0"
ESO_CLUSTER_STORES="0"
ESO_EXTERNAL_SECRETS="0"
ESO_SYNC_STATUS=""

if oc get crd externalsecrets.external-secrets.io >/dev/null 2>&1; then
  # Find ESO namespace
  for NS in external-secrets openshift-external-secrets external-secrets-operator; do
    if oc get namespace "$NS" >/dev/null 2>&1; then
      ESO_NS="$NS"
      break
    fi
  done
  ESO_INSTALLED="true"
  PRODUCTS_DETECTED=$((PRODUCTS_DETECTED + 1))
  ESO_VERSION=$(get_operator_csv_version "${ESO_NS:-external-secrets}" "external.secrets")

  echo "[$LABEL] Fetching SecretStores..."
  # Count SecretStores (namespace-scoped)
  ESO_SECRET_STORES=$(oc get secretstores.external-secrets.io -A -o json 2>/dev/null | tr -d '\r' | \
    jq '.items | length' 2>/dev/null || echo "0")

  echo "[$LABEL] Fetching ClusterSecretStores..."
  # Count ClusterSecretStores (cluster-scoped)
  ESO_CLUSTER_STORES=$(oc get clustersecretstores.external-secrets.io -o json 2>/dev/null | tr -d '\r' | \
    jq '.items | length' 2>/dev/null || echo "0")

  echo "[$LABEL] Fetching ExternalSecrets..."
  # Count ExternalSecrets and sync status
  ESO_JSON=$(oc get externalsecrets.external-secrets.io -A -o json 2>/dev/null | tr -d '\r' || echo '{"items":[]}')
  ESO_EXTERNAL_SECRETS=$(echo "$ESO_JSON" | jq '.items | length' 2>/dev/null || echo "0")
  SYNCED=$(echo "$ESO_JSON" | jq '[.items[] | select(.status.conditions[]? | select(.type == "Ready" and .status == "True"))] | length' 2>/dev/null || echo "0")
  NOT_SYNCED=$(( ESO_EXTERNAL_SECRETS - SYNCED ))
  ESO_SYNC_STATUS="synced:${SYNCED};not_synced:${NOT_SYNCED}"

  echo "[$LABEL]   ESO found in ${ESO_NS} — $ESO_SECRET_STORES stores, $ESO_CLUSTER_STORES cluster stores, $ESO_EXTERNAL_SECRETS external secrets"
else
  echo "[$LABEL]   External Secrets Operator not detected"
fi

write_row "external_secrets" "external-secrets-operator" "$ESO_INSTALLED" "$ESO_NS" "$ESO_VERSION" \
  "secret_stores:${ESO_SECRET_STORES};cluster_stores:${ESO_CLUSTER_STORES}" "external_secrets:$ESO_EXTERNAL_SECRETS" "$ESO_SYNC_STATUS"
echo "[$LABEL] External Secrets Operator done."

# ═══════════════════════════════════════════════════════════════════════════════
# Section 2: Secrets Store CSI Driver
# ═══════════════════════════════════════════════════════════════════════════════
PRODUCTS_CHECKED=$((PRODUCTS_CHECKED + 1))
echo "[$LABEL] Checking Secrets Store CSI Driver..."

CSI_INSTALLED="false"
CSI_NS=""
CSI_VERSION=""
CSI_CLASSES="0"
CSI_PROVIDERS=""
CSI_POD_COUNT="0"

if oc get crd secretproviderclasses.secrets-store.csi.x-k8s.io >/dev/null 2>&1; then
  CSI_INSTALLED="true"
  PRODUCTS_DETECTED=$((PRODUCTS_DETECTED + 1))

  # Find CSI driver namespace
  for NS in openshift-cluster-csi-drivers kube-system csi-secrets-store; do
    if oc get pods -n "$NS" -l "app=secrets-store-csi-driver" --no-headers 2>/dev/null | tr -d '\r' | grep -q .; then
      CSI_NS="$NS"
      break
    fi
    if oc get pods -n "$NS" -l "app.kubernetes.io/name=secrets-store-csi-driver" --no-headers 2>/dev/null | tr -d '\r' | grep -q .; then
      CSI_NS="$NS"
      break
    fi
  done
  CSI_VERSION=$(get_operator_csv_version "${CSI_NS:-openshift-cluster-csi-drivers}" "secrets-store")

  echo "[$LABEL] Fetching SecretProviderClasses..."
  CSI_JSON=$(oc get secretproviderclasses.secrets-store.csi.x-k8s.io -A -o json 2>/dev/null | tr -d '\r' || echo '{"items":[]}')
  CSI_CLASSES=$(echo "$CSI_JSON" | jq '.items | length' 2>/dev/null || echo "0")

  # Unique provider types (vault, azure, aws, gcp)
  CSI_PROVIDERS=$(echo "$CSI_JSON" | jq -r '[.items[].spec.provider // "unknown"] | unique | join(";")' 2>/dev/null || echo "")

  # Count running driver pods
  if [ -n "$CSI_NS" ]; then
    CSI_POD_COUNT=$(oc get pods -n "$CSI_NS" -o json 2>/dev/null | tr -d '\r' | \
      jq '[.items[] | select(.metadata.name | test("secrets-store"; "i")) | select(.status.phase == "Running")] | length' 2>/dev/null || echo "0")
  fi

  echo "[$LABEL]   CSI Secrets Store found — $CSI_CLASSES classes, providers: ${CSI_PROVIDERS:-none}"
else
  echo "[$LABEL]   Secrets Store CSI Driver not detected"
fi

write_row "csi_secrets" "secrets-store-csi-driver" "$CSI_INSTALLED" "$CSI_NS" "$CSI_VERSION" \
  "provider_classes:$CSI_CLASSES" "providers:${CSI_PROVIDERS:-none}" "driver_pods:$CSI_POD_COUNT"
echo "[$LABEL] Secrets Store CSI Driver done."

# ═══════════════════════════════════════════════════════════════════════════════
# Section 3: HashiCorp Vault
# ═══════════════════════════════════════════════════════════════════════════════
PRODUCTS_CHECKED=$((PRODUCTS_CHECKED + 1))
echo "[$LABEL] Checking HashiCorp Vault..."

VAULT_INSTALLED="false"
VAULT_NS=""
VAULT_VERSION=""
VAULT_INSTANCES=""
VAULT_AGENT_INJECTOR=""
VAULT_SEALED=""

# Check for Vault CRD (Vault Secrets Operator)
VAULT_CRD="false"
if oc get crd vaultconnections.secrets.hashicorp.com >/dev/null 2>&1; then
  VAULT_CRD="true"
fi

# Detect Vault namespace by looking for vault pods
for NS in vault hashicorp hashicorp-vault openshift-vault; do
  if oc get namespace "$NS" >/dev/null 2>&1; then
    VAULT_PODS=$(oc get pods -n "$NS" -o json 2>/dev/null | tr -d '\r' | \
      jq '[.items[] | select(.metadata.name | test("vault"; "i"))] | length' 2>/dev/null || echo "0")
    if [ "$VAULT_PODS" -gt 0 ]; then
      VAULT_NS="$NS"
      VAULT_INSTALLED="true"
      PRODUCTS_DETECTED=$((PRODUCTS_DETECTED + 1))
      break
    fi
  fi
done

# Also check if Vault Secrets Operator is deployed even without vault server pods
if [ "$VAULT_INSTALLED" = "false" ] && [ "$VAULT_CRD" = "true" ]; then
  VAULT_INSTALLED="true"
  PRODUCTS_DETECTED=$((PRODUCTS_DETECTED + 1))
  # Find VSO namespace
  for NS in vault-secrets-operator openshift-vault-secrets-operator hashicorp; do
    if oc get namespace "$NS" >/dev/null 2>&1; then
      VAULT_NS="$NS"
      break
    fi
  done
fi

if [ "$VAULT_INSTALLED" = "true" ]; then
  # Get Vault operator version
  VAULT_VERSION=$(get_operator_csv_version "${VAULT_NS:-vault}" "vault")

  # Count Vault server pods (StatefulSet replicas named vault-N)
  if [ -n "$VAULT_NS" ]; then
    echo "[$LABEL] Fetching Vault pods in $VAULT_NS..."
    VAULT_SERVER_JSON=$(oc get pods -n "$VAULT_NS" -o json 2>/dev/null | tr -d '\r' || echo '{"items":[]}')

    # Vault server instances (typically named vault-0, vault-1, etc.)
    VAULT_SERVER_COUNT=$(echo "$VAULT_SERVER_JSON" | \
      jq '[.items[] | select(.metadata.name | test("^vault-[0-9]+$"))] | length' 2>/dev/null || echo "0")
    VAULT_RUNNING=$(echo "$VAULT_SERVER_JSON" | \
      jq '[.items[] | select(.metadata.name | test("^vault-[0-9]+$")) | select(.status.phase == "Running")] | length' 2>/dev/null || echo "0")
    VAULT_INSTANCES="total:${VAULT_SERVER_COUNT};running:${VAULT_RUNNING}"

    # Agent injector pods
    INJECTOR_COUNT=$(echo "$VAULT_SERVER_JSON" | \
      jq '[.items[] | select(.metadata.name | test("vault-agent-injector"; "i")) | select(.status.phase == "Running")] | length' 2>/dev/null || echo "0")
    VAULT_AGENT_INJECTOR="injector_pods:$INJECTOR_COUNT"

    # Check seal status via labels/annotations (if available)
    SEALED_COUNT=$(echo "$VAULT_SERVER_JSON" | \
      jq '[.items[] | select(.metadata.name | test("^vault-[0-9]+$")) | select(.metadata.labels["vault-sealed"] == "true" or .metadata.annotations["vault.hashicorp.com/sealed"] == "true")] | length' 2>/dev/null || echo "unknown")
    VAULT_SEALED="sealed:$SEALED_COUNT"
  fi

  # If Vault Secrets Operator CRD exists, count VaultConnection and VaultStaticSecret resources
  if [ "$VAULT_CRD" = "true" ]; then
    echo "[$LABEL] Fetching Vault Secrets Operator resources..."
    VSO_CONNECTIONS=$(oc get vaultconnections.secrets.hashicorp.com -A -o json 2>/dev/null | tr -d '\r' | \
      jq '.items | length' 2>/dev/null || echo "0")
    VSO_STATIC=$(oc get vaultstaticsecrets.secrets.hashicorp.com -A -o json 2>/dev/null | tr -d '\r' | \
      jq '.items | length' 2>/dev/null || echo "0")
    VSO_DYNAMIC=$(oc get vaultdynamicsecrets.secrets.hashicorp.com -A -o json 2>/dev/null | tr -d '\r' | \
      jq '.items | length' 2>/dev/null || echo "0")
    VAULT_INSTANCES="${VAULT_INSTANCES:+${VAULT_INSTANCES};}vso_connections:${VSO_CONNECTIONS};static_secrets:${VSO_STATIC};dynamic_secrets:${VSO_DYNAMIC}"
  fi

  echo "[$LABEL]   Vault found in ${VAULT_NS} — CRD: $VAULT_CRD, ${VAULT_INSTANCES}"
else
  echo "[$LABEL]   HashiCorp Vault not detected"
fi

write_row "vault" "hashicorp-vault" "$VAULT_INSTALLED" "$VAULT_NS" "$VAULT_VERSION" \
  "$VAULT_INSTANCES" "$VAULT_AGENT_INJECTOR" "$VAULT_SEALED"
echo "[$LABEL] HashiCorp Vault done."

# ═══════════════════════════════════════════════════════════════════════════════
# Section 4: CyberArk Conjur
# ═══════════════════════════════════════════════════════════════════════════════
PRODUCTS_CHECKED=$((PRODUCTS_CHECKED + 1))
echo "[$LABEL] Checking CyberArk Conjur..."

CONJUR_INSTALLED="false"
CONJUR_NS=""
CONJUR_VERSION=""
CONJUR_FOLLOWERS=""
CONJUR_AUTHENTICATORS=""

# Detect CyberArk namespace
for NS in cyberark conjur cyberark-conjur openshift-cyberark; do
  if oc get namespace "$NS" >/dev/null 2>&1; then
    CONJUR_PODS=$(oc get pods -n "$NS" -o json 2>/dev/null | tr -d '\r' | \
      jq '[.items[] | select(.metadata.name | test("conjur"; "i"))] | length' 2>/dev/null || echo "0")
    if [ "$CONJUR_PODS" -gt 0 ]; then
      CONJUR_NS="$NS"
      CONJUR_INSTALLED="true"
      PRODUCTS_DETECTED=$((PRODUCTS_DETECTED + 1))
      break
    fi
  fi
done

# Also check for Conjur Secrets Provider (init container / sidecar approach)
if [ "$CONJUR_INSTALLED" = "false" ]; then
  # Look for conjur-related configmaps across namespaces as a signal
  CONJUR_CONFIGS=$(oc get configmaps -A -o json 2>/dev/null | tr -d '\r' | \
    jq '[.items[] | select(.metadata.name | test("conjur"; "i"))] | length' 2>/dev/null || echo "0")
  if [ "$CONJUR_CONFIGS" -gt 0 ]; then
    CONJUR_INSTALLED="true"
    PRODUCTS_DETECTED=$((PRODUCTS_DETECTED + 1))
    CONJUR_NS="(sidecar-mode)"
  fi
fi

if [ "$CONJUR_INSTALLED" = "true" ] && [ "$CONJUR_NS" != "(sidecar-mode)" ]; then
  CONJUR_VERSION=$(get_operator_csv_version "$CONJUR_NS" "conjur")

  echo "[$LABEL] Fetching Conjur pods in $CONJUR_NS..."
  CONJUR_JSON=$(oc get pods -n "$CONJUR_NS" -o json 2>/dev/null | tr -d '\r' || echo '{"items":[]}')

  # Follower pods
  FOLLOWER_COUNT=$(echo "$CONJUR_JSON" | \
    jq '[.items[] | select(.metadata.name | test("conjur-follower|conjur-oss"; "i")) | select(.status.phase == "Running")] | length' 2>/dev/null || echo "0")
  CONJUR_FOLLOWERS="followers:$FOLLOWER_COUNT"

  # Authenticator containers (init containers named conjur-authn-k8s or similar)
  CONJUR_AUTHENTICATORS="configmaps_detected:${CONJUR_CONFIGS:-0}"
elif [ "$CONJUR_NS" = "(sidecar-mode)" ]; then
  CONJUR_FOLLOWERS="sidecar_mode"
  CONJUR_AUTHENTICATORS="configmaps:${CONJUR_CONFIGS}"
fi

if [ "$CONJUR_INSTALLED" = "true" ]; then
  echo "[$LABEL]   CyberArk Conjur found — ns: ${CONJUR_NS}, ${CONJUR_FOLLOWERS}"
else
  echo "[$LABEL]   CyberArk Conjur not detected"
fi

write_row "conjur" "cyberark-conjur" "$CONJUR_INSTALLED" "$CONJUR_NS" "$CONJUR_VERSION" \
  "$CONJUR_FOLLOWERS" "$CONJUR_AUTHENTICATORS" ""
echo "[$LABEL] CyberArk Conjur done."

# ═══════════════════════════════════════════════════════════════════════════════
# Section 5: Native Secrets Summary
# ═══════════════════════════════════════════════════════════════════════════════
# NOTE: We use custom-columns instead of -o json to avoid downloading the full
# base64-encoded secret data payloads, which can be gigabytes on large clusters.
echo "[$LABEL] Fetching native secrets summary (lightweight — metadata only)..."

TOTAL_SECRETS="0"
OPAQUE_COUNT="0"
TLS_COUNT="0"
SA_TOKEN_COUNT="0"
DOCKERCFG_COUNT="0"
OTHER_COUNT="0"
NS_WITH_SECRETS="0"

# Permission pre-check: try listing secrets in a known namespace first
echo "[$LABEL]   Checking RBAC access to list secrets cluster-wide..."
if ! oc auth can-i list secrets --all-namespaces 2>/dev/null | tr -d '\r' | grep -qi "yes"; then
  echo -e "${RED}[$LABEL] ERROR: Permission denied — cannot list secrets cluster-wide (oc auth can-i list secrets --all-namespaces = no)${NC}"
  echo -e "${RED}[$LABEL]   Remediation: Grant cluster-reader or a custom role with 'list' on secrets to the service account${NC}"
  write_row "native_summary" "kubernetes-secrets" "permission_denied" "(all-namespaces)" "" \
    "error:rbac_denied" "" ""
else
  echo "[$LABEL]   RBAC check passed — fetching secret types and namespaces..."
  echo "[$LABEL]   Running: oc get secrets -A --no-headers -o custom-columns=TYPE:.type,NS:.metadata.namespace"

  FETCH_START=$SECONDS
  # Fetch only type and namespace — no secret data payloads
  SECRETS_RAW=$(oc get secrets -A --no-headers \
    -o custom-columns=TYPE:.type,NS:.metadata.namespace 2>/dev/null | tr -d '\r' || echo "")
  FETCH_ELAPSED=$(( SECONDS - FETCH_START ))
  echo "[$LABEL]   oc get secrets completed in ${FETCH_ELAPSED}s"

  if [ -z "$SECRETS_RAW" ]; then
    echo -e "${YELLOW}[$LABEL] WARNING: oc get secrets returned empty output — cluster may have no secrets or access was silently denied${NC}"
    write_row "native_summary" "kubernetes-secrets" "true" "(all-namespaces)" "" \
      "total:0;opaque:0;tls:0" "sa_token:0;dockercfg:0;other:0" "namespaces_with_secrets:0"
  else
    echo "[$LABEL]   Counting secrets by type..."
    TOTAL_SECRETS=$(echo "$SECRETS_RAW" | wc -l | tr -d ' ')
    echo "[$LABEL]   Total secrets found: $TOTAL_SECRETS"

    echo "[$LABEL]   Counting Opaque secrets..."
    OPAQUE_COUNT=$(echo "$SECRETS_RAW" | grep -c "^Opaque " || echo "0")
    echo "[$LABEL]   Opaque: $OPAQUE_COUNT"

    echo "[$LABEL]   Counting TLS secrets..."
    TLS_COUNT=$(echo "$SECRETS_RAW" | grep -c "^kubernetes.io/tls " || echo "0")
    echo "[$LABEL]   TLS: $TLS_COUNT"

    echo "[$LABEL]   Counting service-account-token secrets..."
    SA_TOKEN_COUNT=$(echo "$SECRETS_RAW" | grep -c "^kubernetes.io/service-account-token " || echo "0")
    echo "[$LABEL]   SA tokens: $SA_TOKEN_COUNT"

    echo "[$LABEL]   Counting docker config secrets..."
    DOCKERCFG_COUNT=$(echo "$SECRETS_RAW" | grep -c "^kubernetes.io/docker" || echo "0")
    echo "[$LABEL]   Docker config: $DOCKERCFG_COUNT"

    OTHER_COUNT=$(( TOTAL_SECRETS - OPAQUE_COUNT - TLS_COUNT - SA_TOKEN_COUNT - DOCKERCFG_COUNT ))
    echo "[$LABEL]   Other: $OTHER_COUNT"

    echo "[$LABEL]   Counting unique namespaces..."
    NS_WITH_SECRETS=$(echo "$SECRETS_RAW" | awk '{print $NF}' | sort -u | wc -l | tr -d ' ')
    echo "[$LABEL]   Namespaces with secrets: $NS_WITH_SECRETS"

    write_row "native_summary" "kubernetes-secrets" "true" "(all-namespaces)" "" \
      "total:${TOTAL_SECRETS};opaque:${OPAQUE_COUNT};tls:${TLS_COUNT}" \
      "sa_token:${SA_TOKEN_COUNT};dockercfg:${DOCKERCFG_COUNT};other:${OTHER_COUNT}" \
      "namespaces_with_secrets:$NS_WITH_SECRETS"
  fi
fi
echo "[$LABEL] Native secrets summary done."

# ═══════════════════════════════════════════════════════════════════════════════
# Summary & Console Warnings
# ═══════════════════════════════════════════════════════════════════════════════
echo ""
echo "[$LABEL] ┌──────────────────────────────────────────────┐"
echo "[$LABEL] │        Enterprise Secrets Integration         │"
echo "[$LABEL] ├──────────────────────────────────────────────┤"
printf "[$LABEL] │  Products checked  : %-24s│\n" "$PRODUCTS_CHECKED"
printf "[$LABEL] │  Products detected : %-24s│\n" "$PRODUCTS_DETECTED"
printf "[$LABEL] │  Native secrets    : %-24s│\n" "$TOTAL_SECRETS"
echo "[$LABEL] └──────────────────────────────────────────────┘"
echo ""

if [ "$PRODUCTS_DETECTED" -eq 0 ]; then
  echo -e "${RED}[$LABEL] CRITICAL: No external secrets provider detected — all secrets are stored natively in etcd${NC}"
  echo -e "${RED}[$LABEL]   Remediation: Deploy an external secrets provider (External Secrets Operator, Vault, Secrets Store CSI) to integrate with enterprise secret management${NC}"
fi

if [ "$OPAQUE_COUNT" -gt 0 ] && [ "$PRODUCTS_DETECTED" -eq 0 ]; then
  echo -e "${YELLOW}[$LABEL] WARNING: $OPAQUE_COUNT Opaque secrets with no external provider — secrets may contain manually managed credentials${NC}"
fi

# Warn if ESO is deployed but has zero ExternalSecrets
if [ "$ESO_INSTALLED" = "true" ] && [ "$ESO_EXTERNAL_SECRETS" -eq 0 ]; then
  echo -e "${YELLOW}[$LABEL] WARNING: External Secrets Operator installed but zero ExternalSecrets defined — operator may be unused${NC}"
fi

# Warn if CSI driver is deployed but has zero SecretProviderClasses
if [ "$CSI_INSTALLED" = "true" ] && [ "$CSI_CLASSES" -eq 0 ]; then
  echo -e "${YELLOW}[$LABEL] WARNING: Secrets Store CSI Driver installed but zero SecretProviderClasses defined — driver may be unused${NC}"
fi

ELAPSED=$(( SECONDS - SCRIPT_START_SECONDS ))
echo "[$LABEL] Completed at $(date) — total time: ${ELAPSED}s"
echo "Created: $OUTPUT_FILE"
