#!/usr/bin/env bash
# Description: Exports namespace-level tenant boundary controls — project request template, namespace ownership, ResourceQuotas, LimitRanges, NetworkPolicies, and namespace RoleBindings
# Audit Area:  Shared Responsibility Model
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

LABEL="shared-responsibility"
SCRIPT_START_SECONDS=$SECONDS

RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "[$LABEL] Starting export at $(date)"

OUTPUT_FILE="$OUTPUT_DIR/shared-responsibility-model-${CLUSTER_NAME_SAFE}-$TIMESTAMP.csv"

echo "cluster_name,cluster_context,cluster_server,record_type,namespace,name,detail_1,detail_2,detail_3,detail_4" > "$OUTPUT_FILE"

# ── Helper: write a CSV row ──────────────────────────────────────────────────
write_row() {
  local record_type="$1" namespace="$2" name="$3" detail_1="$4" detail_2="$5" detail_3="$6" detail_4="$7"
  jq -rn \
    --arg cluster_name "$CLUSTER_NAME" \
    --arg cluster_context "$CLUSTER_CONTEXT" \
    --arg cluster_server "$CLUSTER_SERVER" \
    --arg record_type "$record_type" \
    --arg namespace "$namespace" \
    --arg name "$name" \
    --arg detail_1 "$detail_1" \
    --arg detail_2 "$detail_2" \
    --arg detail_3 "$detail_3" \
    --arg detail_4 "$detail_4" \
    '[$cluster_name,$cluster_context,$cluster_server,$record_type,$namespace,$name,$detail_1,$detail_2,$detail_3,$detail_4] | @csv' \
    >> "$OUTPUT_FILE"
}

# ── Helper: filter to tenant (non-system) namespaces ─────────────────────────
# Returns jq filter that excludes openshift-*, kube-*, default, openshift
TENANT_NS_FILTER='select(.metadata.name | test("^(openshift-|kube-|openshift$|default$)") | not)'

# ═══════════════════════════════════════════════════════════════════════════════
# Section 1: Project Request Template
# ═══════════════════════════════════════════════════════════════════════════════
echo "[$LABEL] Checking project request template..."

PROJECT_CFG=$(oc get project.config.openshift.io/cluster -o json 2>/dev/null | tr -d '\r' || echo '{}')
TEMPLATE_NAME=$(echo "$PROJECT_CFG" | jq -r '.spec.projectRequestTemplate.name // ""' 2>/dev/null || echo "")

if [ -n "$TEMPLATE_NAME" ]; then
  echo "[$LABEL]   Project request template configured: $TEMPLATE_NAME"
  # Inspect the template for quota/limitrange/networkpolicy objects
  TEMPLATE_JSON=$(oc get template "$TEMPLATE_NAME" -n openshift-config -o json 2>/dev/null | tr -d '\r' || echo '{}')
  HAS_QUOTA=$(echo "$TEMPLATE_JSON" | jq '[.objects[]? | select(.kind == "ResourceQuota")] | length' 2>/dev/null || echo "0")
  HAS_LIMITRANGE=$(echo "$TEMPLATE_JSON" | jq '[.objects[]? | select(.kind == "LimitRange")] | length' 2>/dev/null || echo "0")
  HAS_NETPOL=$(echo "$TEMPLATE_JSON" | jq '[.objects[]? | select(.kind == "NetworkPolicy")] | length' 2>/dev/null || echo "0")
  OBJECT_KINDS=$(echo "$TEMPLATE_JSON" | jq -r '[.objects[]?.kind // empty] | unique | join(";")' 2>/dev/null || echo "")

  write_row "project_template" "(cluster)" "$TEMPLATE_NAME" \
    "has_quota:$HAS_QUOTA" "has_limitrange:$HAS_LIMITRANGE" "has_networkpolicy:$HAS_NETPOL" "object_kinds:$OBJECT_KINDS"

  if [ "$HAS_QUOTA" -eq 0 ]; then
    echo -e "${YELLOW}[$LABEL] WARNING: Project request template has no ResourceQuota — new projects get no resource limits${NC}"
  fi
  if [ "$HAS_NETPOL" -eq 0 ]; then
    echo -e "${YELLOW}[$LABEL] WARNING: Project request template has no NetworkPolicy — new projects get no network isolation${NC}"
  fi
else
  echo -e "${YELLOW}[$LABEL] WARNING: No project request template configured — new projects get default settings only${NC}"
  write_row "project_template" "(cluster)" "(none)" \
    "has_quota:0" "has_limitrange:0" "has_networkpolicy:0" "object_kinds:"
fi
echo "[$LABEL] Project request template done."

# ═══════════════════════════════════════════════════════════════════════════════
# Section 2: Namespace Inventory with Ownership
# ═══════════════════════════════════════════════════════════════════════════════
echo "[$LABEL] Fetching namespace inventory..."

NS_JSON=$(oc get namespaces -o json 2>/dev/null | tr -d '\r' || echo '{"items":[]}')
TENANT_NS_LIST=$(echo "$NS_JSON" | jq -c ".items[] | $TENANT_NS_FILTER" 2>/dev/null || echo "")
TENANT_COUNT=$(echo "$NS_JSON" | jq "[.items[] | $TENANT_NS_FILTER] | length" 2>/dev/null || echo "0")
TOTAL_NS=$(echo "$NS_JSON" | jq '.items | length' 2>/dev/null || echo "0")

echo "[$LABEL]   Total namespaces: $TOTAL_NS (tenant: $TENANT_COUNT)"
echo "[$LABEL] Processing $TENANT_COUNT tenant namespaces..."

NS_COUNTER=0
NS_NO_OWNER=0
while IFS= read -r NS_ITEM; do
  [ -z "$NS_ITEM" ] && continue
  NS_COUNTER=$((NS_COUNTER + 1))

  NS_NAME=$(echo "$NS_ITEM" | jq -r '.metadata.name' 2>/dev/null)
  NS_STATUS=$(echo "$NS_ITEM" | jq -r '.status.phase // ""' 2>/dev/null)
  CREATED=$(echo "$NS_ITEM" | jq -r '.metadata.creationTimestamp // ""' 2>/dev/null)

  # Ownership labels — common conventions
  OWNER=$(echo "$NS_ITEM" | jq -r '(.metadata.labels["owner"] // .metadata.labels["app.kubernetes.io/owner"] // .metadata.labels["team"] // .metadata.annotations["openshift.io/requester"] // "")' 2>/dev/null)
  TEAM=$(echo "$NS_ITEM" | jq -r '(.metadata.labels["team"] // .metadata.labels["app.kubernetes.io/part-of"] // "")' 2>/dev/null)
  ENVIRONMENT=$(echo "$NS_ITEM" | jq -r '(.metadata.labels["environment"] // .metadata.labels["env"] // "")' 2>/dev/null)
  NODE_SELECTOR=$(echo "$NS_ITEM" | jq -r '(.metadata.annotations["openshift.io/node-selector"] // "")' 2>/dev/null)

  if [ -z "$OWNER" ] && [ -z "$TEAM" ]; then
    NS_NO_OWNER=$((NS_NO_OWNER + 1))
  fi

  if [ $((NS_COUNTER % 25)) -eq 0 ] || [ "$NS_COUNTER" -eq 1 ]; then
    echo "[$LABEL]   Namespace $NS_COUNTER/$TENANT_COUNT: $NS_NAME"
  fi

  write_row "namespace" "$NS_NAME" "$NS_NAME" \
    "owner:$OWNER" "team:$TEAM" "environment:${ENVIRONMENT};status:${NS_STATUS};created:${CREATED}" "node_selector:$NODE_SELECTOR"
done <<< "$TENANT_NS_LIST"

if [ "$NS_NO_OWNER" -gt 0 ]; then
  echo -e "${YELLOW}[$LABEL] WARNING: $NS_NO_OWNER of $TENANT_COUNT tenant namespaces have no owner or team label${NC}"
fi
echo "[$LABEL] Namespace inventory done."

# ═══════════════════════════════════════════════════════════════════════════════
# Section 3: ResourceQuotas per Namespace
# ═══════════════════════════════════════════════════════════════════════════════
echo "[$LABEL] Fetching ResourceQuotas..."

RQ_JSON=$(oc get resourcequotas -A -o json 2>/dev/null | tr -d '\r' || echo '{"items":[]}')
RQ_COUNT=$(echo "$RQ_JSON" | jq '.items | length' 2>/dev/null || echo "0")
echo "[$LABEL]   Total ResourceQuotas found: $RQ_COUNT"

# Track which tenant namespaces have quotas
NS_WITH_QUOTA=0

echo "$RQ_JSON" | jq -c '.items[]' 2>/dev/null | while IFS= read -r RQ_ITEM; do
  [ -z "$RQ_ITEM" ] && continue

  RQ_NS=$(echo "$RQ_ITEM" | jq -r '.metadata.namespace' 2>/dev/null)
  RQ_NAME=$(echo "$RQ_ITEM" | jq -r '.metadata.name' 2>/dev/null)

  # Hard limits — extract key resource limits
  HARD_CPU=$(echo "$RQ_ITEM" | jq -r '.spec.hard["requests.cpu"] // .spec.hard["limits.cpu"] // .spec.hard["cpu"] // ""' 2>/dev/null)
  HARD_MEM=$(echo "$RQ_ITEM" | jq -r '.spec.hard["requests.memory"] // .spec.hard["limits.memory"] // .spec.hard["memory"] // ""' 2>/dev/null)
  HARD_PODS=$(echo "$RQ_ITEM" | jq -r '.spec.hard["pods"] // ""' 2>/dev/null)
  HARD_STORAGE=$(echo "$RQ_ITEM" | jq -r '.spec.hard["requests.storage"] // .spec.hard["persistentvolumeclaims"] // ""' 2>/dev/null)

  # Used values
  USED_CPU=$(echo "$RQ_ITEM" | jq -r '.status.used["requests.cpu"] // .status.used["limits.cpu"] // .status.used["cpu"] // ""' 2>/dev/null)
  USED_MEM=$(echo "$RQ_ITEM" | jq -r '.status.used["requests.memory"] // .status.used["limits.memory"] // .status.used["memory"] // ""' 2>/dev/null)
  USED_PODS=$(echo "$RQ_ITEM" | jq -r '.status.used["pods"] // ""' 2>/dev/null)

  write_row "resource_quota" "$RQ_NS" "$RQ_NAME" \
    "hard_cpu:${HARD_CPU};hard_memory:${HARD_MEM}" \
    "hard_pods:${HARD_PODS};hard_storage:${HARD_STORAGE}" \
    "used_cpu:${USED_CPU};used_memory:${USED_MEM};used_pods:${USED_PODS}" ""
done

# Identify tenant namespaces WITHOUT quotas
echo "[$LABEL]   Checking for tenant namespaces without ResourceQuotas..."
RQ_NS_LIST=$(echo "$RQ_JSON" | jq -r '[.items[].metadata.namespace] | unique | .[]' 2>/dev/null || echo "")
NS_WITHOUT_QUOTA=0
while IFS= read -r NS_ITEM; do
  [ -z "$NS_ITEM" ] && continue
  NS_NAME=$(echo "$NS_ITEM" | jq -r '.metadata.name' 2>/dev/null)
  if ! echo "$RQ_NS_LIST" | grep -qx "$NS_NAME"; then
    NS_WITHOUT_QUOTA=$((NS_WITHOUT_QUOTA + 1))
  fi
done <<< "$TENANT_NS_LIST"
NS_WITH_QUOTA=$((TENANT_COUNT - NS_WITHOUT_QUOTA))

echo "[$LABEL]   Tenant namespaces with quotas: $NS_WITH_QUOTA / $TENANT_COUNT"
if [ "$NS_WITHOUT_QUOTA" -gt 0 ]; then
  echo -e "${YELLOW}[$LABEL] WARNING: $NS_WITHOUT_QUOTA tenant namespaces have no ResourceQuota — resource consumption is unbounded${NC}"
fi
echo "[$LABEL] ResourceQuotas done."

# ═══════════════════════════════════════════════════════════════════════════════
# Section 4: LimitRanges per Namespace
# ═══════════════════════════════════════════════════════════════════════════════
echo "[$LABEL] Fetching LimitRanges..."

LR_JSON=$(oc get limitranges -A -o json 2>/dev/null | tr -d '\r' || echo '{"items":[]}')
LR_COUNT=$(echo "$LR_JSON" | jq '.items | length' 2>/dev/null || echo "0")
echo "[$LABEL]   Total LimitRanges found: $LR_COUNT"

echo "$LR_JSON" | jq -c '.items[]' 2>/dev/null | while IFS= read -r LR_ITEM; do
  [ -z "$LR_ITEM" ] && continue

  LR_NS=$(echo "$LR_ITEM" | jq -r '.metadata.namespace' 2>/dev/null)
  LR_NAME=$(echo "$LR_ITEM" | jq -r '.metadata.name' 2>/dev/null)

  # Extract Container-type limits (most common)
  DEFAULT_CPU=$(echo "$LR_ITEM" | jq -r '[.spec.limits[] | select(.type == "Container") | .default.cpu // ""] | first // ""' 2>/dev/null || echo "")
  DEFAULT_MEM=$(echo "$LR_ITEM" | jq -r '[.spec.limits[] | select(.type == "Container") | .default.memory // ""] | first // ""' 2>/dev/null || echo "")
  DEFAULT_REQ_CPU=$(echo "$LR_ITEM" | jq -r '[.spec.limits[] | select(.type == "Container") | .defaultRequest.cpu // ""] | first // ""' 2>/dev/null || echo "")
  DEFAULT_REQ_MEM=$(echo "$LR_ITEM" | jq -r '[.spec.limits[] | select(.type == "Container") | .defaultRequest.memory // ""] | first // ""' 2>/dev/null || echo "")
  MAX_CPU=$(echo "$LR_ITEM" | jq -r '[.spec.limits[] | select(.type == "Container") | .max.cpu // ""] | first // ""' 2>/dev/null || echo "")
  MAX_MEM=$(echo "$LR_ITEM" | jq -r '[.spec.limits[] | select(.type == "Container") | .max.memory // ""] | first // ""' 2>/dev/null || echo "")
  LIMIT_TYPES=$(echo "$LR_ITEM" | jq -r '[.spec.limits[].type] | unique | join(";")' 2>/dev/null || echo "")

  write_row "limit_range" "$LR_NS" "$LR_NAME" \
    "default_cpu:${DEFAULT_CPU};default_memory:${DEFAULT_MEM}" \
    "default_request_cpu:${DEFAULT_REQ_CPU};default_request_memory:${DEFAULT_REQ_MEM}" \
    "max_cpu:${MAX_CPU};max_memory:${MAX_MEM}" \
    "types:$LIMIT_TYPES"
done

# Identify tenant namespaces WITHOUT limit ranges
LR_NS_LIST=$(echo "$LR_JSON" | jq -r '[.items[].metadata.namespace] | unique | .[]' 2>/dev/null || echo "")
NS_WITHOUT_LR=0
while IFS= read -r NS_ITEM; do
  [ -z "$NS_ITEM" ] && continue
  NS_NAME=$(echo "$NS_ITEM" | jq -r '.metadata.name' 2>/dev/null)
  if ! echo "$LR_NS_LIST" | grep -qx "$NS_NAME"; then
    NS_WITHOUT_LR=$((NS_WITHOUT_LR + 1))
  fi
done <<< "$TENANT_NS_LIST"

echo "[$LABEL]   Tenant namespaces with LimitRanges: $((TENANT_COUNT - NS_WITHOUT_LR)) / $TENANT_COUNT"
if [ "$NS_WITHOUT_LR" -gt 0 ]; then
  echo -e "${YELLOW}[$LABEL] WARNING: $NS_WITHOUT_LR tenant namespaces have no LimitRange — pods without resource requests get no defaults${NC}"
fi
echo "[$LABEL] LimitRanges done."

# ═══════════════════════════════════════════════════════════════════════════════
# Section 5: NetworkPolicies per Namespace
# ═══════════════════════════════════════════════════════════════════════════════
echo "[$LABEL] Fetching NetworkPolicies..."

NP_JSON=$(oc get networkpolicies -A -o json 2>/dev/null | tr -d '\r' || echo '{"items":[]}')
NP_COUNT=$(echo "$NP_JSON" | jq '.items | length' 2>/dev/null || echo "0")
echo "[$LABEL]   Total NetworkPolicies found: $NP_COUNT"

echo "$NP_JSON" | jq -c '.items[]' 2>/dev/null | while IFS= read -r NP_ITEM; do
  [ -z "$NP_ITEM" ] && continue

  NP_NS=$(echo "$NP_ITEM" | jq -r '.metadata.namespace' 2>/dev/null)
  NP_NAME=$(echo "$NP_ITEM" | jq -r '.metadata.name' 2>/dev/null)

  # Policy types
  POLICY_TYPES=$(echo "$NP_ITEM" | jq -r '(.spec.policyTypes // []) | join(";")' 2>/dev/null || echo "")
  [ -z "$POLICY_TYPES" ] && POLICY_TYPES="Ingress"

  # Pod selector (empty = applies to all pods = default deny candidate)
  POD_SELECTOR=$(echo "$NP_ITEM" | jq -r '.spec.podSelector.matchLabels // {} | to_entries | map("\(.key)=\(.value)") | join(";")' 2>/dev/null || echo "")
  [ -z "$POD_SELECTOR" ] && POD_SELECTOR="(all-pods)"

  # Count ingress/egress rules
  INGRESS_RULES=$(echo "$NP_ITEM" | jq '.spec.ingress // [] | length' 2>/dev/null || echo "0")
  EGRESS_RULES=$(echo "$NP_ITEM" | jq '.spec.egress // [] | length' 2>/dev/null || echo "0")

  # Detect default-deny pattern (podSelector: {}, no ingress/egress rules)
  IS_DEFAULT_DENY="false"
  if [ "$POD_SELECTOR" = "(all-pods)" ] && [ "$INGRESS_RULES" -eq 0 ] && [ "$EGRESS_RULES" -eq 0 ]; then
    IS_DEFAULT_DENY="true"
  fi

  write_row "network_policy" "$NP_NS" "$NP_NAME" \
    "policy_types:$POLICY_TYPES" "pod_selector:$POD_SELECTOR" \
    "ingress_rules:${INGRESS_RULES};egress_rules:${EGRESS_RULES}" "default_deny:$IS_DEFAULT_DENY"
done

# Identify tenant namespaces WITHOUT any network policies
NP_NS_LIST=$(echo "$NP_JSON" | jq -r '[.items[].metadata.namespace] | unique | .[]' 2>/dev/null || echo "")
NS_WITHOUT_NP=0
while IFS= read -r NS_ITEM; do
  [ -z "$NS_ITEM" ] && continue
  NS_NAME=$(echo "$NS_ITEM" | jq -r '.metadata.name' 2>/dev/null)
  if ! echo "$NP_NS_LIST" | grep -qx "$NS_NAME"; then
    NS_WITHOUT_NP=$((NS_WITHOUT_NP + 1))
  fi
done <<< "$TENANT_NS_LIST"

echo "[$LABEL]   Tenant namespaces with NetworkPolicies: $((TENANT_COUNT - NS_WITHOUT_NP)) / $TENANT_COUNT"
if [ "$NS_WITHOUT_NP" -gt 0 ]; then
  echo -e "${YELLOW}[$LABEL] WARNING: $NS_WITHOUT_NP tenant namespaces have no NetworkPolicy — flat network, no isolation${NC}"
fi
echo "[$LABEL] NetworkPolicies done."

# ═══════════════════════════════════════════════════════════════════════════════
# Section 6: Namespace-level RoleBindings (tenant namespaces only)
# ═══════════════════════════════════════════════════════════════════════════════
echo "[$LABEL] Fetching namespace-level RoleBindings..."

# Only fetch for tenant namespaces to keep output manageable
RB_TOTAL=0
while IFS= read -r NS_ITEM; do
  [ -z "$NS_ITEM" ] && continue
  NS_NAME=$(echo "$NS_ITEM" | jq -r '.metadata.name' 2>/dev/null)
  [ -z "$NS_NAME" ] && continue

  RB_JSON=$(oc get rolebindings -n "$NS_NAME" -o json 2>/dev/null | tr -d '\r' || echo '{"items":[]}')
  RB_COUNT=$(echo "$RB_JSON" | jq '.items | length' 2>/dev/null || echo "0")
  RB_TOTAL=$((RB_TOTAL + RB_COUNT))

  echo "$RB_JSON" | jq -c '.items[]' 2>/dev/null | while IFS= read -r RB_ITEM; do
    [ -z "$RB_ITEM" ] && continue

    RB_NAME=$(echo "$RB_ITEM" | jq -r '.metadata.name' 2>/dev/null)
    ROLE_REF=$(echo "$RB_ITEM" | jq -r '"\(.roleRef.kind)/\(.roleRef.name)"' 2>/dev/null)

    # Subjects — consolidate into semicolon-delimited list
    SUBJECTS=$(echo "$RB_ITEM" | jq -r '(.subjects // []) | map("\(.kind):\(.name)") | join(";")' 2>/dev/null || echo "")
    SUBJECT_COUNT=$(echo "$RB_ITEM" | jq '(.subjects // []) | length' 2>/dev/null || echo "0")

    # Filter: skip system-only bindings (only ServiceAccount subjects in system namespaces)
    IS_SYSTEM_ONLY=$(echo "$RB_ITEM" | jq '(.subjects // []) | if length == 0 then true elif all(.kind == "ServiceAccount" and (.namespace // "" | test("^(openshift-|kube-)"))) then true else false end' 2>/dev/null || echo "false")
    if [ "$IS_SYSTEM_ONLY" = "true" ]; then
      continue
    fi

    write_row "rolebinding" "$NS_NAME" "$RB_NAME" \
      "role_ref:$ROLE_REF" "subjects:$SUBJECTS" "subject_count:$SUBJECT_COUNT" ""
  done
done <<< "$TENANT_NS_LIST"

echo "[$LABEL]   Total RoleBindings across tenant namespaces: $RB_TOTAL"
echo "[$LABEL] Namespace RoleBindings done."

# ═══════════════════════════════════════════════════════════════════════════════
# Summary & Console Warnings
# ═══════════════════════════════════════════════════════════════════════════════
echo ""
echo "[$LABEL] ┌──────────────────────────────────────────────────────┐"
echo "[$LABEL] │          Shared Responsibility Model Summary          │"
echo "[$LABEL] ├──────────────────────────────────────────────────────┤"
printf "[$LABEL] │  Project template     : %-28s│\n" "${TEMPLATE_NAME:-(none)}"
printf "[$LABEL] │  Total namespaces     : %-28s│\n" "$TOTAL_NS (tenant: $TENANT_COUNT)"
printf "[$LABEL] │  No owner/team label  : %-28s│\n" "$NS_NO_OWNER"
printf "[$LABEL] │  ResourceQuotas       : %-28s│\n" "$RQ_COUNT (covering $NS_WITH_QUOTA/$TENANT_COUNT tenant ns)"
printf "[$LABEL] │  LimitRanges          : %-28s│\n" "$LR_COUNT (covering $((TENANT_COUNT - NS_WITHOUT_LR))/$TENANT_COUNT tenant ns)"
printf "[$LABEL] │  NetworkPolicies      : %-28s│\n" "$NP_COUNT (covering $((TENANT_COUNT - NS_WITHOUT_NP))/$TENANT_COUNT tenant ns)"
echo "[$LABEL] └──────────────────────────────────────────────────────┘"
echo ""

# Critical: no project template AND no quotas/limitranges/netpols at all
if [ -z "$TEMPLATE_NAME" ] && [ "$RQ_COUNT" -eq 0 ] && [ "$LR_COUNT" -eq 0 ] && [ "$NP_COUNT" -eq 0 ]; then
  echo -e "${RED}[$LABEL] CRITICAL: No project template, no ResourceQuotas, no LimitRanges, no NetworkPolicies — tenant boundaries are completely unenforced${NC}"
  echo -e "${RED}[$LABEL]   Remediation: Configure a project request template with default quotas, limit ranges, and network policies${NC}"
fi

ELAPSED=$(( SECONDS - SCRIPT_START_SECONDS ))
echo "[$LABEL] Completed at $(date) — total time: ${ELAPSED}s"
echo "Created: $OUTPUT_FILE"
