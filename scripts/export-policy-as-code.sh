#!/usr/bin/env bash
# Description: Exports OPA Gatekeeper policy-as-code enforcement status and constraints
# Audit Area:  Policy-as-Code Enforcement
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

OUTPUT_FILE="$OUTPUT_DIR/policy-as-code-${CLUSTER_NAME_SAFE}-$TIMESTAMP.csv"

echo "cluster_name,cluster_context,cluster_server,gatekeeper_installed,gatekeeper_namespace,constraint_template,constraint_name,enforcement_action,total_violations,match_kinds,match_namespaces" > "$OUTPUT_FILE"

# Detect Gatekeeper namespace
GATEKEEPER_NS=""
for NS in openshift-gatekeeper-system gatekeeper-system; do
  if oc get namespace "$NS" >/dev/null 2>&1; then
    GATEKEEPER_NS="$NS"
    break
  fi
done

if [ -z "$GATEKEEPER_NS" ]; then
  # No Gatekeeper detected — write a single summary row
  jq -rn \
    --arg cluster_name "$CLUSTER_NAME" \
    --arg cluster_context "$CLUSTER_CONTEXT" \
    --arg cluster_server "$CLUSTER_SERVER" '
    [
      $cluster_name,
      $cluster_context,
      $cluster_server,
      "false",
      "",
      "",
      "",
      "",
      "",
      "",
      ""
    ] | @csv
  ' >> "$OUTPUT_FILE"
  echo "Created: $OUTPUT_FILE"
  exit 0
fi

GATEKEEPER_INSTALLED="true"

# Get ConstraintTemplates (if the CRD exists)
TEMPLATES_JSON=$(oc get constrainttemplates -o json 2>/dev/null || echo '{"items":[]}')
TEMPLATE_COUNT=$(echo "$TEMPLATES_JSON" | jq '.items | length')

if [ "$TEMPLATE_COUNT" -eq 0 ]; then
  # Gatekeeper installed but no templates defined
  jq -rn \
    --arg cluster_name "$CLUSTER_NAME" \
    --arg cluster_context "$CLUSTER_CONTEXT" \
    --arg cluster_server "$CLUSTER_SERVER" \
    --arg gk_ns "$GATEKEEPER_NS" '
    [
      $cluster_name,
      $cluster_context,
      $cluster_server,
      "true",
      $gk_ns,
      "",
      "",
      "",
      "",
      "",
      ""
    ] | @csv
  ' >> "$OUTPUT_FILE"
  echo "Created: $OUTPUT_FILE"
  exit 0
fi

# For each ConstraintTemplate, query constraints of that kind
echo "$TEMPLATES_JSON" | jq -r '.items[].metadata.name' | while IFS= read -r TEMPLATE_NAME; do
  # The constraint CRD kind is the template name (lowercase works with oc get)
  CONSTRAINTS_JSON=$(oc get "$TEMPLATE_NAME" -o json 2>/dev/null || echo '{"items":[]}')
  CONSTRAINT_COUNT=$(echo "$CONSTRAINTS_JSON" | jq '.items | length')

  if [ "$CONSTRAINT_COUNT" -eq 0 ]; then
    # Template exists but no constraints instantiated
    jq -rn \
      --arg cluster_name "$CLUSTER_NAME" \
      --arg cluster_context "$CLUSTER_CONTEXT" \
      --arg cluster_server "$CLUSTER_SERVER" \
      --arg gk_ns "$GATEKEEPER_NS" \
      --arg template "$TEMPLATE_NAME" '
      [
        $cluster_name,
        $cluster_context,
        $cluster_server,
        "true",
        $gk_ns,
        $template,
        "",
        "",
        "",
        "",
        ""
      ] | @csv
    ' >> "$OUTPUT_FILE"
  else
    echo "$CONSTRAINTS_JSON" | jq -r \
      --arg cluster_name "$CLUSTER_NAME" \
      --arg cluster_context "$CLUSTER_CONTEXT" \
      --arg cluster_server "$CLUSTER_SERVER" \
      --arg gk_installed "$GATEKEEPER_INSTALLED" \
      --arg gk_ns "$GATEKEEPER_NS" \
      --arg template "$TEMPLATE_NAME" '
      .items[] |
      [
        $cluster_name,
        $cluster_context,
        $cluster_server,
        $gk_installed,
        $gk_ns,
        $template,
        (.metadata.name // ""),
        (.spec.enforcementAction // "deny"),
        (.status.totalViolations // 0 | tostring),
        ([.spec.match.kinds[]?.kinds[]?] | join(";")),
        ([.spec.match.namespaces[]?] | join(";"))
      ] | @csv
    ' >> "$OUTPUT_FILE"
  fi
done

echo "Created: $OUTPUT_FILE"
