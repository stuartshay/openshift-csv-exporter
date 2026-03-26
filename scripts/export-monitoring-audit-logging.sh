#!/usr/bin/env bash
# Description: Exports observability and audit logging configuration — cluster monitoring, user workload monitoring, Datadog, log forwarding, audit policy, and alerting rules
# Audit Area:  OpenShift Usage Monitoring
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

LABEL="monitoring-audit"
SCRIPT_START_SECONDS=$SECONDS

RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "[$(date +%H:%M:%S)] [$LABEL] Starting export at $(date)"

OUTPUT_FILE="$OUTPUT_DIR/monitoring-audit-logging-${CLUSTER_NAME_SAFE}-$TIMESTAMP.csv"

echo "cluster_name,cluster_context,cluster_server,record_type,component_name,status,namespace,detail_1,detail_2,detail_3,detail_4" > "$OUTPUT_FILE"

# ── Helper: write a CSV row ──────────────────────────────────────────────────
write_row() {
  local record_type="$1" component_name="$2" status="$3" namespace="$4" detail_1="$5" detail_2="$6" detail_3="$7" detail_4="$8"
  jq -rn \
    --arg cluster_name "$CLUSTER_NAME" \
    --arg cluster_context "$CLUSTER_CONTEXT" \
    --arg cluster_server "$CLUSTER_SERVER" \
    --arg record_type "$record_type" \
    --arg component_name "$component_name" \
    --arg status "$status" \
    --arg namespace "$namespace" \
    --arg detail_1 "$detail_1" \
    --arg detail_2 "$detail_2" \
    --arg detail_3 "$detail_3" \
    --arg detail_4 "$detail_4" \
    '[$cluster_name,$cluster_context,$cluster_server,$record_type,$component_name,$status,$namespace,$detail_1,$detail_2,$detail_3,$detail_4] | @csv' \
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

SECTIONS_OK=0
SECTIONS_WARN=0

# ═══════════════════════════════════════════════════════════════════════════════
# Section 1: Monitoring ClusterOperator Health
# ═══════════════════════════════════════════════════════════════════════════════
echo "[$(date +%H:%M:%S)] [$LABEL] Checking monitoring ClusterOperator..."

MON_CO=$(oc get clusteroperator monitoring -o json 2>/dev/null | tr -d '\r' || echo '{}')
MON_AVAILABLE=$(echo "$MON_CO" | jq -r '[.status.conditions[]? | select(.type == "Available")] | first | .status // ""' 2>/dev/null || echo "")
MON_DEGRADED=$(echo "$MON_CO" | jq -r '[.status.conditions[]? | select(.type == "Degraded")] | first | .status // ""' 2>/dev/null || echo "")
MON_PROGRESSING=$(echo "$MON_CO" | jq -r '[.status.conditions[]? | select(.type == "Progressing")] | first | .status // ""' 2>/dev/null || echo "")
MON_VERSION=$(echo "$MON_CO" | jq -r '[.status.versions[]? | select(.name == "operator")] | first | .version // ""' 2>/dev/null || echo "")

if [ "$MON_AVAILABLE" = "True" ] && [ "$MON_DEGRADED" = "False" ]; then
  MON_STATUS="Healthy"
  SECTIONS_OK=$((SECTIONS_OK + 1))
  echo "[$(date +%H:%M:%S)] [$LABEL]   Monitoring operator: Healthy (v$MON_VERSION)"
elif [ -z "$MON_AVAILABLE" ]; then
  MON_STATUS="NotFound"
  SECTIONS_WARN=$((SECTIONS_WARN + 1))
  echo -e "${RED}[$(date +%H:%M:%S)] [$LABEL] ERROR: Monitoring ClusterOperator not found${NC}"
else
  MON_STATUS="Degraded"
  SECTIONS_WARN=$((SECTIONS_WARN + 1))
  echo -e "${YELLOW}[$(date +%H:%M:%S)] [$LABEL] WARNING: Monitoring operator is degraded — Available=$MON_AVAILABLE Degraded=$MON_DEGRADED${NC}"
fi

write_row "cluster_operator" "monitoring" "$MON_STATUS" "openshift-monitoring" \
  "version:$MON_VERSION" "available:$MON_AVAILABLE" "degraded:$MON_DEGRADED" "progressing:$MON_PROGRESSING"

echo "[$(date +%H:%M:%S)] [$LABEL] Monitoring operator done."

# ═══════════════════════════════════════════════════════════════════════════════
# Section 2: Cluster Monitoring Configuration
# ═══════════════════════════════════════════════════════════════════════════════
echo "[$(date +%H:%M:%S)] [$LABEL] Checking cluster monitoring config..."

CMC_EXISTS="false"
CMC_RETENTION=""
CMC_STORAGE_CLASS=""
CMC_STORAGE_SIZE=""

CMC_DATA=$(oc get configmap cluster-monitoring-config -n openshift-monitoring -o json 2>/dev/null | tr -d '\r' || echo '{}')
CMC_CONFIG_YAML=$(echo "$CMC_DATA" | jq -r '.data["config.yaml"] // ""' 2>/dev/null || echo "")

if [ -n "$CMC_CONFIG_YAML" ]; then
  CMC_EXISTS="true"
  # Extract key values — config.yaml is YAML but we can grep for common patterns
  CMC_RETENTION=$(echo "$CMC_CONFIG_YAML" | grep -oP 'retention:\s*\K\S+' 2>/dev/null | head -1 || echo "")
  CMC_STORAGE_CLASS=$(echo "$CMC_CONFIG_YAML" | grep -oP 'storageClassName:\s*\K\S+' 2>/dev/null | head -1 || echo "")
  CMC_STORAGE_SIZE=$(echo "$CMC_CONFIG_YAML" | grep -oP 'storage:\s*\K\S+' 2>/dev/null | head -1 || echo "")

  # Check if user workload monitoring is enabled via this config
  UWM_ENABLED_VIA_CMC=$(echo "$CMC_CONFIG_YAML" | grep -c 'enableUserWorkload.*true' 2>/dev/null || echo "0")

  echo "[$(date +%H:%M:%S)] [$LABEL]   cluster-monitoring-config exists"
  echo "[$(date +%H:%M:%S)] [$LABEL]   Retention: ${CMC_RETENTION:-(default 15d)}"
  echo "[$(date +%H:%M:%S)] [$LABEL]   Persistent storage: ${CMC_STORAGE_CLASS:-(not configured)}"
  SECTIONS_OK=$((SECTIONS_OK + 1))
else
  echo -e "${YELLOW}[$(date +%H:%M:%S)] [$LABEL] WARNING: No cluster-monitoring-config ConfigMap — using all defaults${NC}"
  UWM_ENABLED_VIA_CMC="0"
  SECTIONS_WARN=$((SECTIONS_WARN + 1))
fi

write_row "monitoring_config" "cluster-monitoring-config" "${CMC_EXISTS}" "openshift-monitoring" \
  "retention:${CMC_RETENTION:-(default)}" "storage_class:${CMC_STORAGE_CLASS}" \
  "storage_size:${CMC_STORAGE_SIZE}" "uwm_enabled_here:${UWM_ENABLED_VIA_CMC}"

echo "[$(date +%H:%M:%S)] [$LABEL] Cluster monitoring config done."

# ═══════════════════════════════════════════════════════════════════════════════
# Section 3: User Workload Monitoring
# ═══════════════════════════════════════════════════════════════════════════════
echo "[$(date +%H:%M:%S)] [$LABEL] Checking user workload monitoring..."

UWM_STATUS="disabled"
UWM_RETENTION=""
UWM_STORAGE=""

# Check if the namespace exists (it only exists when UWM is enabled)
if oc get namespace openshift-user-workload-monitoring >/dev/null 2>&1; then
  # Check if pods are running
  UWM_PODS=$(oc get pods -n openshift-user-workload-monitoring --no-headers 2>/dev/null | tr -d '\r' | wc -l || echo "0")
  UWM_PODS=$(echo "$UWM_PODS" | tr -d '[:space:]')
  if [ "$UWM_PODS" -gt 0 ] 2>/dev/null; then
    UWM_STATUS="enabled"
    echo "[$(date +%H:%M:%S)] [$LABEL]   User workload monitoring: ENABLED ($UWM_PODS pods running)"
    SECTIONS_OK=$((SECTIONS_OK + 1))

    # Check for custom config
    UWM_CM=$(oc get configmap user-workload-monitoring-config -n openshift-user-workload-monitoring -o json 2>/dev/null | tr -d '\r' || echo '{}')
    UWM_CONFIG_YAML=$(echo "$UWM_CM" | jq -r '.data["config.yaml"] // ""' 2>/dev/null || echo "")
    if [ -n "$UWM_CONFIG_YAML" ]; then
      UWM_RETENTION=$(echo "$UWM_CONFIG_YAML" | grep -oP 'retention:\s*\K\S+' 2>/dev/null | head -1 || echo "")
      UWM_STORAGE=$(echo "$UWM_CONFIG_YAML" | grep -oP 'storageClassName:\s*\K\S+' 2>/dev/null | head -1 || echo "")
    fi
  else
    UWM_STATUS="namespace_exists_no_pods"
    echo -e "${YELLOW}[$(date +%H:%M:%S)] [$LABEL] WARNING: UWM namespace exists but no pods running${NC}"
    SECTIONS_WARN=$((SECTIONS_WARN + 1))
  fi
else
  echo -e "${YELLOW}[$(date +%H:%M:%S)] [$LABEL] WARNING: User workload monitoring is DISABLED — tenant workloads cannot emit custom metrics${NC}"
  SECTIONS_WARN=$((SECTIONS_WARN + 1))
fi

write_row "user_workload_monitoring" "user-workload-monitoring" "$UWM_STATUS" \
  "openshift-user-workload-monitoring" \
  "pods:${UWM_PODS:-0}" "retention:${UWM_RETENTION:-(default)}" \
  "storage:${UWM_STORAGE}" ""

echo "[$(date +%H:%M:%S)] [$LABEL] User workload monitoring done."

# ═══════════════════════════════════════════════════════════════════════════════
# Section 4: Audit Log Policy
# ═══════════════════════════════════════════════════════════════════════════════
echo "[$(date +%H:%M:%S)] [$LABEL] Checking audit log policy..."

APISERVER_CFG=$(oc get apiserver.config.openshift.io/cluster -o json 2>/dev/null | tr -d '\r' || echo '{}')
AUDIT_PROFILE=$(echo "$APISERVER_CFG" | jq -r '.spec.audit.profile // "Default"' 2>/dev/null || echo "Default")

# Custom rules (OCP 4.18 supports customRules for per-group audit levels)
CUSTOM_RULES_COUNT=$(echo "$APISERVER_CFG" | jq '[.spec.audit.customRules // [] | .[] ] | length' 2>/dev/null || echo "0")

echo "[$(date +%H:%M:%S)] [$LABEL]   Audit profile: $AUDIT_PROFILE"
echo "[$(date +%H:%M:%S)] [$LABEL]   Custom audit rules: $CUSTOM_RULES_COUNT"

if [ "$AUDIT_PROFILE" = "Default" ]; then
  echo -e "${YELLOW}[$(date +%H:%M:%S)] [$LABEL] WARNING: Audit profile is 'Default' — request bodies are NOT logged. Consider 'WriteRequestBodies' or 'AllRequestBodies' for compliance${NC}"
  SECTIONS_WARN=$((SECTIONS_WARN + 1))
else
  SECTIONS_OK=$((SECTIONS_OK + 1))
fi

write_row "audit_policy" "apiserver-audit" "$AUDIT_PROFILE" "(cluster)" \
  "profile:$AUDIT_PROFILE" "custom_rules:$CUSTOM_RULES_COUNT" "" ""

# Also check OAuth server audit config
OAUTH_CFG=$(oc get oauthserver.config.openshift.io/cluster -o json 2>/dev/null | tr -d '\r' || echo '{}')
OAUTH_AUDIT=$(echo "$OAUTH_CFG" | jq -r '.spec.audit.profile // "same-as-apiserver"' 2>/dev/null || echo "same-as-apiserver")

write_row "audit_policy" "oauth-audit" "$OAUTH_AUDIT" "(cluster)" \
  "profile:$OAUTH_AUDIT" "" "" ""

echo "[$(date +%H:%M:%S)] [$LABEL] Audit log policy done."

# ═══════════════════════════════════════════════════════════════════════════════
# Section 5: Datadog Integration
# ═══════════════════════════════════════════════════════════════════════════════
echo "[$(date +%H:%M:%S)] [$LABEL] Checking Datadog integration..."

DD_INSTALLED="false"
DD_NS=""
DD_VERSION=""
DD_AGENT_COUNT="0"
DD_CLUSTER_AGENT="false"
DD_LOG_ENABLED=""
DD_APM_ENABLED=""
DD_PROCESS_ENABLED=""

# Detect Datadog Operator via CRD
if oc get crd datadogagents.datadoghq.com >/dev/null 2>&1; then
  DD_INSTALLED="true"
  echo "[$(date +%H:%M:%S)] [$LABEL]   Datadog Operator CRD found"

  # Find the DatadogAgent CR
  DD_CR=$(oc get datadogagents.datadoghq.com -A -o json 2>/dev/null | tr -d '\r' || echo '{"items":[]}')
  DD_CR_COUNT=$(echo "$DD_CR" | jq '.items | length' 2>/dev/null || echo "0")

  if [ "$DD_CR_COUNT" -gt 0 ]; then
    DD_NS=$(echo "$DD_CR" | jq -r '.items[0].metadata.namespace // ""' 2>/dev/null || echo "")
    DD_CR_NAME=$(echo "$DD_CR" | jq -r '.items[0].metadata.name // ""' 2>/dev/null || echo "")

    # Extract feature flags from the DatadogAgent spec
    DD_LOG_ENABLED=$(echo "$DD_CR" | jq -r '.items[0].spec.features.logCollection.enabled // .items[0].spec.agent.log.enabled // ""' 2>/dev/null || echo "")
    DD_APM_ENABLED=$(echo "$DD_CR" | jq -r '.items[0].spec.features.apm.enabled // .items[0].spec.agent.apm.enabled // ""' 2>/dev/null || echo "")
    DD_PROCESS_ENABLED=$(echo "$DD_CR" | jq -r '.items[0].spec.features.liveProcessCollection.enabled // .items[0].spec.agent.process.enabled // ""' 2>/dev/null || echo "")
    DD_CLUSTER_AGENT=$(echo "$DD_CR" | jq -r 'if .items[0].spec.features.clusterChecks.enabled // .items[0].spec.clusterAgent then "true" else "false" end' 2>/dev/null || echo "false")

    # Get operator version
    DD_VERSION=$(get_operator_csv_version "$DD_NS" "datadog")

    echo "[$(date +%H:%M:%S)] [$LABEL]   DatadogAgent CR: $DD_CR_NAME in $DD_NS"
    echo "[$(date +%H:%M:%S)] [$LABEL]   Log collection: ${DD_LOG_ENABLED:-unknown}"
    echo "[$(date +%H:%M:%S)] [$LABEL]   APM: ${DD_APM_ENABLED:-unknown}"
    echo "[$(date +%H:%M:%S)] [$LABEL]   Process monitoring: ${DD_PROCESS_ENABLED:-unknown}"
    echo "[$(date +%H:%M:%S)] [$LABEL]   Cluster Agent: $DD_CLUSTER_AGENT"
  fi
else
  echo "[$(date +%H:%M:%S)] [$LABEL]   Datadog Operator CRD not found"
fi

# Fallback: check for Datadog Agent DaemonSet even without operator
if [ "$DD_INSTALLED" = "false" ]; then
  for NS in datadog datadog-agent datadog-system monitoring; do
    if oc get daemonset -n "$NS" -o json 2>/dev/null | tr -d '\r' | \
       jq -e '.items[] | select(.metadata.name | test("datadog"; "i"))' >/dev/null 2>&1; then
      DD_INSTALLED="true"
      DD_NS="$NS"
      echo "[$(date +%H:%M:%S)] [$LABEL]   Datadog Agent DaemonSet found in $NS (non-operator install)"
      break
    fi
  done
fi

# Count running Datadog agent pods
if [ -n "$DD_NS" ]; then
  DD_AGENT_COUNT=$(oc get pods -n "$DD_NS" --no-headers 2>/dev/null | tr -d '\r' | grep -ci "datadog" || echo "0")
  echo "[$(date +%H:%M:%S)] [$LABEL]   Datadog pods running: $DD_AGENT_COUNT"
fi

if [ "$DD_INSTALLED" = "true" ]; then
  SECTIONS_OK=$((SECTIONS_OK + 1))
else
  echo "[$(date +%H:%M:%S)] [$LABEL]   Datadog not installed"
fi

write_row "external_monitoring" "Datadog" "$DD_INSTALLED" "${DD_NS:-(none)}" \
  "version:${DD_VERSION};agent_pods:${DD_AGENT_COUNT}" \
  "log_collection:${DD_LOG_ENABLED:-unknown};apm:${DD_APM_ENABLED:-unknown}" \
  "process_monitoring:${DD_PROCESS_ENABLED:-unknown};cluster_agent:${DD_CLUSTER_AGENT}" ""

echo "[$(date +%H:%M:%S)] [$LABEL] Datadog integration done."

# ═══════════════════════════════════════════════════════════════════════════════
# Section 6: Cluster Logging & Log Forwarding
# ═══════════════════════════════════════════════════════════════════════════════
echo "[$(date +%H:%M:%S)] [$LABEL] Checking cluster logging and log forwarding..."

LOGGING_INSTALLED="false"
LOGGING_NS="openshift-logging"
LOGGING_VERSION=""
CLF_OUTPUTS=""

# Check ClusterLogging operator
LOGGING_CO=$(oc get clusteroperator cluster-logging -o json 2>/dev/null | tr -d '\r' || echo '{}')
LOGGING_CO_AVAILABLE=$(echo "$LOGGING_CO" | jq -r '[.status.conditions[]? | select(.type == "Available")] | first | .status // ""' 2>/dev/null || echo "")

if [ "$LOGGING_CO_AVAILABLE" = "True" ]; then
  LOGGING_INSTALLED="true"
  LOGGING_VERSION=$(echo "$LOGGING_CO" | jq -r '[.status.versions[]? | select(.name == "operator")] | first | .version // ""' 2>/dev/null || echo "")
  echo "[$(date +%H:%M:%S)] [$LABEL]   Cluster Logging operator: Available (v$LOGGING_VERSION)"
else
  echo "[$(date +%H:%M:%S)] [$LABEL]   Cluster Logging operator: not found via ClusterOperator"
  # Fallback: check for CRD
  if oc get crd clusterloggings.logging.openshift.io >/dev/null 2>&1; then
    LOGGING_INSTALLED="true"
    LOGGING_VERSION=$(get_operator_csv_version "$LOGGING_NS" "cluster-logging")
    echo "[$(date +%H:%M:%S)] [$LABEL]   Cluster Logging CRD found (v$LOGGING_VERSION)"
  fi
fi

# ClusterLogging CR details
CL_STATUS="not_configured"
CL_COLLECTION=""
CL_LOG_STORE=""
if [ "$LOGGING_INSTALLED" = "true" ]; then
  CL_JSON=$(oc get clusterlogging instance -n "$LOGGING_NS" -o json 2>/dev/null | tr -d '\r' || echo '{}')
  CL_COLLECTION=$(echo "$CL_JSON" | jq -r '.spec.collection.type // .spec.collection.logs.type // ""' 2>/dev/null || echo "")
  CL_LOG_STORE=$(echo "$CL_JSON" | jq -r '.spec.logStore.type // ""' 2>/dev/null || echo "")
  if [ -n "$CL_COLLECTION" ] || [ -n "$CL_LOG_STORE" ]; then
    CL_STATUS="configured"
    echo "[$(date +%H:%M:%S)] [$LABEL]   Collection: ${CL_COLLECTION:-(default)}"
    echo "[$(date +%H:%M:%S)] [$LABEL]   Log store: ${CL_LOG_STORE:-(none)}"
  fi
fi

write_row "cluster_logging" "ClusterLogging" "${LOGGING_INSTALLED}" "$LOGGING_NS" \
  "version:${LOGGING_VERSION}" "collection:${CL_COLLECTION}" \
  "log_store:${CL_LOG_STORE}" "status:${CL_STATUS}"

# ClusterLogForwarder — where are logs being sent?
echo "[$(date +%H:%M:%S)] [$LABEL] Checking ClusterLogForwarder..."

# Check for the singleton "instance" CLF
CLF_INSTANCE=$(oc get clusterlogforwarder instance -n "$LOGGING_NS" -o json 2>/dev/null | tr -d '\r' || echo '{}')

CLF_FOUND="false"
if echo "$CLF_INSTANCE" | jq -e '.metadata.name' >/dev/null 2>&1; then
  CLF_FOUND="true"

  # Extract outputs (destination types and URLs)
  CLF_OUTPUTS=$(echo "$CLF_INSTANCE" | jq -r '[.spec.outputs[]? | "\(.type):\(.name)"] | join(";")' 2>/dev/null || echo "")
  CLF_PIPELINES=$(echo "$CLF_INSTANCE" | jq -r '[.spec.pipelines[]? | "\(.name)→\(.outputRefs | join(","))"] | join(";")' 2>/dev/null || echo "")
  CLF_INPUT_TYPES=$(echo "$CLF_INSTANCE" | jq -r '[.spec.pipelines[]?.inputRefs[]?] | unique | join(";")' 2>/dev/null || echo "")

  # Status conditions
  CLF_READY=$(echo "$CLF_INSTANCE" | jq -r '[.status.conditions[]? | select(.type == "Ready")] | first | .status // ""' 2>/dev/null || echo "")

  echo "[$(date +%H:%M:%S)] [$LABEL]   ClusterLogForwarder found"
  echo "[$(date +%H:%M:%S)] [$LABEL]   Outputs: ${CLF_OUTPUTS:-(none)}"
  echo "[$(date +%H:%M:%S)] [$LABEL]   Pipelines: ${CLF_PIPELINES:-(none)}"
  echo "[$(date +%H:%M:%S)] [$LABEL]   Input types: ${CLF_INPUT_TYPES:-(none)}"
  echo "[$(date +%H:%M:%S)] [$LABEL]   Ready: ${CLF_READY:-unknown}"
  SECTIONS_OK=$((SECTIONS_OK + 1))

  write_row "log_forwarder" "ClusterLogForwarder" "${CLF_READY:-unknown}" "$LOGGING_NS" \
    "outputs:${CLF_OUTPUTS}" "pipelines:${CLF_PIPELINES}" \
    "input_types:${CLF_INPUT_TYPES}" ""
else
  echo "[$(date +%H:%M:%S)] [$LABEL]   No ClusterLogForwarder configured"
  SECTIONS_WARN=$((SECTIONS_WARN + 1))
fi

echo "[$(date +%H:%M:%S)] [$LABEL] Cluster logging done."

# ═══════════════════════════════════════════════════════════════════════════════
# Section 7: Alerting Rules Summary
# ═══════════════════════════════════════════════════════════════════════════════
echo "[$(date +%H:%M:%S)] [$LABEL] Fetching PrometheusRules..."

PR_JSON=$(oc get prometheusrules -A -o json 2>/dev/null | tr -d '\r' || echo '{"items":[]}')
PR_TOTAL=$(echo "$PR_JSON" | jq '.items | length' 2>/dev/null || echo "0")

echo "[$(date +%H:%M:%S)] [$LABEL]   Total PrometheusRule objects: $PR_TOTAL"

# Count alert rules by severity
ALERT_CRITICAL=$(echo "$PR_JSON" | jq '[.items[].spec.groups[].rules[] | select(.alert) | select(.labels.severity == "critical")] | length' 2>/dev/null || echo "0")
ALERT_WARNING=$(echo "$PR_JSON" | jq '[.items[].spec.groups[].rules[] | select(.alert) | select(.labels.severity == "warning")] | length' 2>/dev/null || echo "0")
ALERT_INFO=$(echo "$PR_JSON" | jq '[.items[].spec.groups[].rules[] | select(.alert) | select(.labels.severity == "info" or .labels.severity == "none" or .labels.severity == null)] | length' 2>/dev/null || echo "0")
ALERT_TOTAL=$(echo "$PR_JSON" | jq '[.items[].spec.groups[].rules[] | select(.alert)] | length' 2>/dev/null || echo "0")
RECORD_TOTAL=$(echo "$PR_JSON" | jq '[.items[].spec.groups[].rules[] | select(.record)] | length' 2>/dev/null || echo "0")

echo "[$(date +%H:%M:%S)] [$LABEL]   Alert rules: $ALERT_TOTAL (critical:$ALERT_CRITICAL warning:$ALERT_WARNING info:$ALERT_INFO)"
echo "[$(date +%H:%M:%S)] [$LABEL]   Recording rules: $RECORD_TOTAL"

# Namespaces with PrometheusRules (shows which teams define custom alerts)
PR_NS_COUNT=$(echo "$PR_JSON" | jq '[.items[].metadata.namespace] | unique | length' 2>/dev/null || echo "0")

echo "[$(date +%H:%M:%S)] [$LABEL]   Namespaces with PrometheusRules: $PR_NS_COUNT"

write_row "alerting_rules" "PrometheusRules" "total:$ALERT_TOTAL" "(cluster)" \
  "critical:$ALERT_CRITICAL;warning:$ALERT_WARNING;info:$ALERT_INFO" \
  "recording_rules:$RECORD_TOTAL" "rule_objects:$PR_TOTAL" "namespaces:$PR_NS_COUNT"

if [ "$ALERT_TOTAL" -eq 0 ]; then
  echo -e "${RED}[$(date +%H:%M:%S)] [$LABEL] ERROR: No alert rules found — cluster has no alerting configuration${NC}"
  SECTIONS_WARN=$((SECTIONS_WARN + 1))
else
  SECTIONS_OK=$((SECTIONS_OK + 1))
fi

echo "[$(date +%H:%M:%S)] [$LABEL] Alerting rules done."

# ═══════════════════════════════════════════════════════════════════════════════
# Section 8: Alertmanager Receiver Configuration
# ═══════════════════════════════════════════════════════════════════════════════
echo "[$(date +%H:%M:%S)] [$LABEL] Checking Alertmanager receivers..."

# Alertmanager config is stored as a secret
AM_SECRET=$(oc get secret alertmanager-main -n openshift-monitoring -o json 2>/dev/null | tr -d '\r' || echo '{}')
AM_EXISTS=$(echo "$AM_SECRET" | jq -e '.metadata.name' >/dev/null 2>&1 && echo "true" || echo "false")

AM_RECEIVER_COUNT="0"
AM_RECEIVER_TYPES=""
AM_ROUTES=""

if [ "$AM_EXISTS" = "true" ]; then
  # Decode the alertmanager.yaml — extract receiver names and types (not the secrets)
  AM_YAML=$(echo "$AM_SECRET" | jq -r '.data["alertmanager.yaml"] // ""' 2>/dev/null | base64 -d 2>/dev/null || echo "")

  if [ -n "$AM_YAML" ]; then
    # Count receivers (grep for "- name:" lines under receivers)
    AM_RECEIVER_COUNT=$(echo "$AM_YAML" | grep -cP '^\s*-\s*name:' 2>/dev/null || echo "0")

    # Detect receiver types by looking for known integration keys
    TYPES_FOUND=""
    for TYPE in pagerduty_configs slack_configs webhook_configs email_configs opsgenie_configs victorops_configs sns_configs wechat_configs; do
      if echo "$AM_YAML" | grep -q "$TYPE" 2>/dev/null; then
        SHORT_TYPE="${TYPE%_configs}"
        TYPES_FOUND="${TYPES_FOUND:+${TYPES_FOUND};}${SHORT_TYPE}"
      fi
    done
    AM_RECEIVER_TYPES="${TYPES_FOUND:-(default-only)}"

    # Count routes
    AM_ROUTES=$(echo "$AM_YAML" | grep -cP '^\s*-\s*match|^\s*-\s*matchers' 2>/dev/null || echo "0")

    echo "[$(date +%H:%M:%S)] [$LABEL]   Alertmanager receivers: $AM_RECEIVER_COUNT"
    echo "[$(date +%H:%M:%S)] [$LABEL]   Receiver types: $AM_RECEIVER_TYPES"
    echo "[$(date +%H:%M:%S)] [$LABEL]   Alert routes: $AM_ROUTES"
    SECTIONS_OK=$((SECTIONS_OK + 1))
  else
    echo -e "${YELLOW}[$(date +%H:%M:%S)] [$LABEL] WARNING: Could not decode alertmanager.yaml — may lack permissions${NC}"
    SECTIONS_WARN=$((SECTIONS_WARN + 1))
  fi
else
  echo -e "${YELLOW}[$(date +%H:%M:%S)] [$LABEL] WARNING: alertmanager-main secret not found — Alertmanager may not be configured${NC}"
  SECTIONS_WARN=$((SECTIONS_WARN + 1))
fi

write_row "alertmanager" "alertmanager-main" "${AM_EXISTS}" "openshift-monitoring" \
  "receivers:${AM_RECEIVER_COUNT}" "receiver_types:${AM_RECEIVER_TYPES}" \
  "routes:${AM_ROUTES}" ""

echo "[$(date +%H:%M:%S)] [$LABEL] Alertmanager receivers done."

# ═══════════════════════════════════════════════════════════════════════════════
# Summary & Console Warnings
# ═══════════════════════════════════════════════════════════════════════════════
echo ""
echo "[$(date +%H:%M:%S)] [$LABEL] ┌──────────────────────────────────────────────────────┐"
echo "[$(date +%H:%M:%S)] [$LABEL] │       Monitoring & Audit Logging Summary              │"
echo "[$(date +%H:%M:%S)] [$LABEL] ├──────────────────────────────────────────────────────┤"
printf "[$(date +%H:%M:%S)] [$LABEL] │  Monitoring operator   : %-27s│\n" "$MON_STATUS (v${MON_VERSION:-?})"
printf "[$(date +%H:%M:%S)] [$LABEL] │  Monitoring config     : %-27s│\n" "${CMC_EXISTS}"
printf "[$(date +%H:%M:%S)] [$LABEL] │  User workload mon.    : %-27s│\n" "$UWM_STATUS"
printf "[$(date +%H:%M:%S)] [$LABEL] │  Audit profile         : %-27s│\n" "$AUDIT_PROFILE"
printf "[$(date +%H:%M:%S)] [$LABEL] │  Datadog               : %-27s│\n" "installed:${DD_INSTALLED} (${DD_AGENT_COUNT} pods)"
printf "[$(date +%H:%M:%S)] [$LABEL] │  Cluster logging       : %-27s│\n" "${LOGGING_INSTALLED}"
printf "[$(date +%H:%M:%S)] [$LABEL] │  Log forwarder         : %-27s│\n" "${CLF_FOUND}"
printf "[$(date +%H:%M:%S)] [$LABEL] │  Alert rules           : %-27s│\n" "${ALERT_TOTAL} (crit:${ALERT_CRITICAL} warn:${ALERT_WARNING})"
printf "[$(date +%H:%M:%S)] [$LABEL] │  Alertmanager rcvrs    : %-27s│\n" "${AM_RECEIVER_COUNT} (${AM_RECEIVER_TYPES})"
echo "[$(date +%H:%M:%S)] [$LABEL] └──────────────────────────────────────────────────────┘"
echo ""

# Critical: no external monitoring AND no log forwarding AND no Datadog
if [ "$DD_INSTALLED" = "false" ] && [ "$CLF_FOUND" = "false" ] && [ "$LOGGING_INSTALLED" = "false" ]; then
  echo -e "${RED}[$(date +%H:%M:%S)] [$LABEL] CRITICAL: No external monitoring (Datadog), no cluster logging, and no log forwarding detected — usage is NOT being monitored${NC}"
  echo -e "${RED}[$(date +%H:%M:%S)] [$LABEL]   Remediation: Deploy Datadog Agent or Cluster Logging with ClusterLogForwarder to a SIEM${NC}"
fi

if [ "$AUDIT_PROFILE" = "Default" ] && [ "$DD_INSTALLED" = "false" ] && [ "$CLF_FOUND" = "false" ]; then
  echo -e "${RED}[$(date +%H:%M:%S)] [$LABEL] CRITICAL: Audit profile is 'Default' with no external log aggregation — unapproved usage cannot be detected${NC}"
fi

ELAPSED=$(( SECONDS - SCRIPT_START_SECONDS ))
echo "[$(date +%H:%M:%S)] [$LABEL] Completed at $(date) — total time: ${ELAPSED}s"
echo "Created: $OUTPUT_FILE"
