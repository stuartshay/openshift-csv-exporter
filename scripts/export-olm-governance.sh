#!/usr/bin/env bash
# Description: Exports Operator Lifecycle Management governance data — OperatorHub config, CatalogSources, Subscriptions approval policies, InstallPlans, and OperatorGroup scopes
# Audit Area:  Operator Lifecycle Management (OLM) Control
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

OUTPUT_FILE="$OUTPUT_DIR/olm-governance-${CLUSTER_NAME_SAFE}-$TIMESTAMP.csv"

LABEL="olm-governance"
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

SCRIPT_START_SECONDS=$SECONDS

echo "[$LABEL] Starting export at $(date)"
echo "[$LABEL] Output file: $OUTPUT_FILE"

# CSV header
echo "cluster_name,cluster_context,cluster_server,record_type,name,namespace,detail_1,detail_2,detail_3,detail_4,detail_5,detail_6,detail_7" > "$OUTPUT_FILE"

# =============================================================================
# 1) OperatorHub Configuration — oc get operatorhub cluster
# =============================================================================
echo "[$LABEL] Fetching OperatorHub configuration..."

OPHUB_JSON=""
OPHUB_OK=true
if ! OPHUB_JSON=$(oc get operatorhub cluster -o json 2>/dev/null | tr -d '\r'); then
  echo -e "${RED}[$LABEL] ERROR: Failed to fetch OperatorHub config — permission denied or resource unavailable${NC}"
  echo -e "${RED}[$LABEL] Hint: oc auth can-i get operatorhub.config.openshift.io/cluster${NC}"
  OPHUB_OK=false
fi

if [ "$OPHUB_OK" = true ] && [ -n "$OPHUB_JSON" ]; then
  DISABLE_ALL=$(echo "$OPHUB_JSON" | jq -r '.spec.disableAllDefaultSources // "false"' | tr -d '\r')

  # Write cluster-level row
  echo "$OPHUB_JSON" | jq -r \
    --arg cn "$CLUSTER_NAME" --arg cc "$CLUSTER_CONTEXT" --arg cs "$CLUSTER_SERVER" \
    --arg disableAll "$DISABLE_ALL" '
    [
      $cn, $cc, $cs,
      "operatorhub_config",
      "cluster",
      "",
      ("disableAllDefaultSources=" + $disableAll),
      "",
      "",
      "",
      "",
      "",
      ""
    ] | @csv
  ' >> "$OUTPUT_FILE"

  # Write per-source rows
  SOURCE_COUNT=$(echo "$OPHUB_JSON" | jq '[.spec.sources // [] | .[]] | length' | tr -d '\r')
  if [ "$SOURCE_COUNT" -gt 0 ]; then
    echo "$OPHUB_JSON" | jq -c '.spec.sources // [] | .[]' | tr -d '\r' | while IFS= read -r src; do
      echo "$src" | jq -r \
        --arg cn "$CLUSTER_NAME" --arg cc "$CLUSTER_CONTEXT" --arg cs "$CLUSTER_SERVER" '
        [
          $cn, $cc, $cs,
          "operatorhub_config",
          (.name // ""),
          "",
          ("disabled=" + ((.disabled // false) | tostring)),
          "",
          "",
          "",
          "",
          "",
          ""
        ] | @csv
      ' >> "$OUTPUT_FILE"
    done
  fi

  # Console summary
  ENABLED_SOURCES=$(echo "$OPHUB_JSON" | jq '[.spec.sources // [] | .[] | select(.disabled != true)] | length' | tr -d '\r')
  DISABLED_SOURCES=$(echo "$OPHUB_JSON" | jq '[.spec.sources // [] | .[] | select(.disabled == true)] | length' | tr -d '\r')
  echo "[$LABEL] OperatorHub: disableAllDefaultSources=$DISABLE_ALL, enabled_sources=$ENABLED_SOURCES, disabled_sources=$DISABLED_SOURCES"

  if [ "$DISABLE_ALL" != "true" ]; then
    # Check if community-operators is enabled
    COMMUNITY_ENABLED=$(echo "$OPHUB_JSON" | jq '[.spec.sources // [] | .[] | select(.name == "community-operators" and .disabled != true)] | length' | tr -d '\r')
    if [ "$COMMUNITY_ENABLED" -gt 0 ]; then
      echo -e "${RED}[$LABEL] WARNING: community-operators catalog is ENABLED — untrusted operators may be installable${NC}"
    fi
  fi
else
  echo "[$LABEL] Skipping OperatorHub details (fetch failed)."
fi
echo "[$LABEL] OperatorHub section done."

# =============================================================================
# 2) CatalogSources — oc get catalogsources -A
# =============================================================================
echo "[$LABEL] Fetching CatalogSources..."

CATSRC_JSON=""
CATSRC_OK=true
if ! CATSRC_JSON=$(oc get catalogsources -A -o json 2>/dev/null | tr -d '\r'); then
  echo -e "${RED}[$LABEL] ERROR: Failed to fetch CatalogSources — permission denied${NC}"
  echo -e "${RED}[$LABEL] Hint: oc auth can-i get catalogsources --all-namespaces${NC}"
  CATSRC_OK=false
fi

if [ "$CATSRC_OK" = true ] && [ -n "$CATSRC_JSON" ]; then
  CATSRC_COUNT=$(echo "$CATSRC_JSON" | jq '[.items // [] | .[]] | length' | tr -d '\r')
  echo "[$LABEL] Processing $CATSRC_COUNT CatalogSources..."

  echo "$CATSRC_JSON" | jq -c '.items // [] | .[]' | tr -d '\r' | while IFS= read -r item; do
    echo "$item" | jq -r \
      --arg cn "$CLUSTER_NAME" --arg cc "$CLUSTER_CONTEXT" --arg cs "$CLUSTER_SERVER" '
      [
        $cn, $cc, $cs,
        "catalog_source",
        (.metadata.name // ""),
        (.metadata.namespace // ""),
        (.spec.displayName // ""),
        (.spec.sourceType // ""),
        (.spec.image // .spec.address // ""),
        (.status.connectionState.lastObservedState // ""),
        (.spec.grpcPodConfig.securityContextConfig // ""),
        (.spec.updateStrategy.registryPoll.interval // ""),
        ""
      ] | @csv
    ' >> "$OUTPUT_FILE"
  done

  # Console summary
  READY_COUNT=$(echo "$CATSRC_JSON" | jq '[.items // [] | .[] | select(.status.connectionState.lastObservedState == "READY")] | length' | tr -d '\r')
  NOT_READY=$((CATSRC_COUNT - READY_COUNT))
  echo "[$LABEL] CatalogSources: total=$CATSRC_COUNT, READY=$READY_COUNT, not-ready=$NOT_READY"
  if [ "$NOT_READY" -gt 0 ]; then
    echo -e "${YELLOW}[$LABEL] WARNING: $NOT_READY CatalogSource(s) not in READY state${NC}"
  fi
else
  echo "[$LABEL] Skipping CatalogSource details (fetch failed)."
fi
echo "[$LABEL] CatalogSources section done."

# =============================================================================
# 3) Subscriptions — oc get subscriptions.operators.coreos.com -A (PRIMARY AUDIT)
# =============================================================================
echo "[$LABEL] Fetching Subscriptions..."

SUB_JSON=""
SUB_OK=true
if ! SUB_JSON=$(oc get subscriptions.operators.coreos.com -A -o json 2>/dev/null | tr -d '\r'); then
  echo -e "${RED}[$LABEL] ERROR: Failed to fetch Subscriptions — permission denied${NC}"
  echo -e "${RED}[$LABEL] Hint: oc auth can-i get subscriptions.operators.coreos.com --all-namespaces${NC}"
  SUB_OK=false
fi

if [ "$SUB_OK" = true ] && [ -n "$SUB_JSON" ]; then
  SUB_COUNT=$(echo "$SUB_JSON" | jq '[.items // [] | .[]] | length' | tr -d '\r')
  echo "[$LABEL] Processing $SUB_COUNT Subscriptions..."

  echo "$SUB_JSON" | jq -c '.items // [] | .[]' | tr -d '\r' | while IFS= read -r item; do
    echo "$item" | jq -r \
      --arg cn "$CLUSTER_NAME" --arg cc "$CLUSTER_CONTEXT" --arg cs "$CLUSTER_SERVER" '
      [
        $cn, $cc, $cs,
        "subscription",
        (.metadata.name // ""),
        (.metadata.namespace // ""),
        (.spec.installPlanApproval // "Unknown"),
        (.spec.source // ""),
        (.spec.sourceNamespace // ""),
        (.spec.channel // ""),
        (.status.currentCSV // ""),
        (.status.installedCSV // ""),
        (.status.state // "")
      ] | @csv
    ' >> "$OUTPUT_FILE"
  done

  # Console summary — approval policy breakdown
  AUTO_COUNT=$(echo "$SUB_JSON" | jq '[.items // [] | .[] | select(.spec.installPlanApproval == "Automatic")] | length' | tr -d '\r')
  MANUAL_COUNT=$(echo "$SUB_JSON" | jq '[.items // [] | .[] | select(.spec.installPlanApproval == "Manual")] | length' | tr -d '\r')
  OTHER_COUNT=$(echo "$SUB_JSON" | jq '[.items // [] | .[] | select(.spec.installPlanApproval != "Automatic" and .spec.installPlanApproval != "Manual")] | length' | tr -d '\r')

  echo "[$LABEL] Subscriptions: total=$SUB_COUNT, Automatic=$AUTO_COUNT, Manual=$MANUAL_COUNT, other/unknown=$OTHER_COUNT"

  if [ "$AUTO_COUNT" -gt 0 ]; then
    echo -e "${YELLOW}[$LABEL] WARNING: $AUTO_COUNT subscription(s) use Automatic approval — no manual threshold enforced:${NC}"
    echo "$SUB_JSON" | jq -r '.items // [] | .[] | select(.spec.installPlanApproval == "Automatic") | "  - \(.metadata.namespace)/\(.metadata.name) (source=\(.spec.source // "unknown"), channel=\(.spec.channel // "unknown"))"' | tr -d '\r'
  fi
else
  echo "[$LABEL] Skipping Subscription details (fetch failed)."
fi
echo "[$LABEL] Subscriptions section done."

# =============================================================================
# 4) InstallPlans — oc get installplans -A
# =============================================================================
echo "[$LABEL] Fetching InstallPlans..."

IP_JSON=""
IP_OK=true
if ! IP_JSON=$(oc get installplans -A -o json 2>/dev/null | tr -d '\r'); then
  echo -e "${RED}[$LABEL] ERROR: Failed to fetch InstallPlans — permission denied${NC}"
  echo -e "${RED}[$LABEL] Hint: oc auth can-i get installplans --all-namespaces${NC}"
  IP_OK=false
fi

if [ "$IP_OK" = true ] && [ -n "$IP_JSON" ]; then
  IP_COUNT=$(echo "$IP_JSON" | jq '[.items // [] | .[]] | length' | tr -d '\r')
  echo "[$LABEL] Processing $IP_COUNT InstallPlans..."

  echo "$IP_JSON" | jq -c '.items // [] | .[]' | tr -d '\r' | while IFS= read -r item; do
    echo "$item" | jq -r \
      --arg cn "$CLUSTER_NAME" --arg cc "$CLUSTER_CONTEXT" --arg cs "$CLUSTER_SERVER" '
      [
        $cn, $cc, $cs,
        "install_plan",
        (.metadata.name // ""),
        (.metadata.namespace // ""),
        ((.spec.approved // false) | tostring),
        (.status.phase // ""),
        ([.spec.clusterServiceVersionNames // [] | .[]] | join(";")),
        "",
        "",
        "",
        ""
      ] | @csv
    ' >> "$OUTPUT_FILE"
  done

  # Console summary — phase breakdown
  COMPLETE_COUNT=$(echo "$IP_JSON" | jq '[.items // [] | .[] | select(.status.phase == "Complete")] | length' | tr -d '\r')
  FAILED_COUNT=$(echo "$IP_JSON" | jq '[.items // [] | .[] | select(.status.phase == "Failed")] | length' | tr -d '\r')
  PENDING_COUNT=$(echo "$IP_JSON" | jq '[.items // [] | .[] | select(.spec.approved == false)] | length' | tr -d '\r')
  INSTALLING_COUNT=$(echo "$IP_JSON" | jq '[.items // [] | .[] | select(.status.phase == "Installing")] | length' | tr -d '\r')

  echo "[$LABEL] InstallPlans: total=$IP_COUNT, Complete=$COMPLETE_COUNT, Failed=$FAILED_COUNT, Pending(unapproved)=$PENDING_COUNT, Installing=$INSTALLING_COUNT"

  if [ "$PENDING_COUNT" -gt 0 ]; then
    echo -e "${YELLOW}[$LABEL] WARNING: $PENDING_COUNT InstallPlan(s) awaiting approval${NC}"
  fi
  if [ "$FAILED_COUNT" -gt 0 ]; then
    echo -e "${RED}[$LABEL] WARNING: $FAILED_COUNT InstallPlan(s) in Failed state${NC}"
  fi
else
  echo "[$LABEL] Skipping InstallPlan details (fetch failed)."
fi
echo "[$LABEL] InstallPlans section done."

# =============================================================================
# 5) OperatorGroups — oc get operatorgroups -A
# =============================================================================
echo "[$LABEL] Fetching OperatorGroups..."

OG_JSON=""
OG_OK=true
if ! OG_JSON=$(oc get operatorgroups -A -o json 2>/dev/null | tr -d '\r'); then
  echo -e "${RED}[$LABEL] ERROR: Failed to fetch OperatorGroups — permission denied${NC}"
  echo -e "${RED}[$LABEL] Hint: oc auth can-i get operatorgroups --all-namespaces${NC}"
  OG_OK=false
fi

if [ "$OG_OK" = true ] && [ -n "$OG_JSON" ]; then
  OG_COUNT=$(echo "$OG_JSON" | jq '[.items // [] | .[]] | length' | tr -d '\r')
  echo "[$LABEL] Processing $OG_COUNT OperatorGroups..."

  echo "$OG_JSON" | jq -c '.items // [] | .[]' | tr -d '\r' | while IFS= read -r item; do
    # Determine scope
    TARGET_NS=$(echo "$item" | jq -r '[.spec.targetNamespaces // [] | .[]] | join(";")' | tr -d '\r')
    if [ -z "$TARGET_NS" ]; then
      SCOPE="AllNamespaces"
    else
      NS_COUNT=$(echo "$item" | jq '[.spec.targetNamespaces // [] | .[]] | length' | tr -d '\r')
      if [ "$NS_COUNT" -eq 1 ]; then
        SCOPE="SingleNamespace"
      else
        SCOPE="MultiNamespace"
      fi
    fi

    echo "$item" | jq -r \
      --arg cn "$CLUSTER_NAME" --arg cc "$CLUSTER_CONTEXT" --arg cs "$CLUSTER_SERVER" \
      --arg targetNs "$TARGET_NS" --arg scope "$SCOPE" '
      [
        $cn, $cc, $cs,
        "operator_group",
        (.metadata.name // ""),
        (.metadata.namespace // ""),
        $targetNs,
        $scope,
        "",
        "",
        "",
        "",
        ""
      ] | @csv
    ' >> "$OUTPUT_FILE"
  done

  # Console summary
  ALL_NS_COUNT=$(echo "$OG_JSON" | jq '[.items // [] | .[] | select((.spec.targetNamespaces // []) | length == 0)] | length' | tr -d '\r')
  SCOPED_COUNT=$((OG_COUNT - ALL_NS_COUNT))
  echo "[$LABEL] OperatorGroups: total=$OG_COUNT, AllNamespaces=$ALL_NS_COUNT, scoped=$SCOPED_COUNT"
  if [ "$ALL_NS_COUNT" -gt 0 ]; then
    echo -e "${YELLOW}[$LABEL] INFO: $ALL_NS_COUNT OperatorGroup(s) target AllNamespaces:${NC}"
    echo "$OG_JSON" | jq -r '.items // [] | .[] | select((.spec.targetNamespaces // []) | length == 0) | "  - \(.metadata.namespace)/\(.metadata.name)"' | tr -d '\r'
  fi
else
  echo "[$LABEL] Skipping OperatorGroup details (fetch failed)."
fi
echo "[$LABEL] OperatorGroups section done."

# =============================================================================
# Governance Summary
# =============================================================================
echo ""
echo "[$LABEL] === OLM Governance Summary ==="
if [ "$OPHUB_OK" = true ] && [ -n "$OPHUB_JSON" ]; then
  echo "[$LABEL]   OperatorHub default sources disabled: $DISABLE_ALL"
fi
if [ "$SUB_OK" = true ] && [ -n "$SUB_JSON" ]; then
  echo "[$LABEL]   Subscriptions: $SUB_COUNT total — $AUTO_COUNT Automatic, $MANUAL_COUNT Manual"
fi
if [ "$IP_OK" = true ] && [ -n "$IP_JSON" ]; then
  echo "[$LABEL]   InstallPlans: $IP_COUNT total — $PENDING_COUNT pending approval"
fi
if [ "$OG_OK" = true ] && [ -n "$OG_JSON" ]; then
  echo "[$LABEL]   OperatorGroups: $OG_COUNT total — $ALL_NS_COUNT AllNamespaces"
fi
echo "[$LABEL] =============================="
echo ""

ELAPSED=$(( SECONDS - SCRIPT_START_SECONDS ))
echo "[$LABEL] Completed at $(date) — total time: ${ELAPSED}s"
echo "Created: $OUTPUT_FILE"
