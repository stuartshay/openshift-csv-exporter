#!/usr/bin/env bash
# Description: Cluster connectivity and diagnostics helper — not an export script, for operator troubleshooting
# Usage:       ./scripts/debug-cluster-diagnostics.sh
#              ./scripts/debug-cluster-diagnostics.sh --check-processes
#              ./scripts/debug-cluster-diagnostics.sh --api-requests
# NOTE: no set -e — diagnostics must continue through failures
set -uo pipefail

BOLD=$'\033[1m'
GREEN=$'\033[32m'
YELLOW=$'\033[33m'
RED=$'\033[31m'
RESET=$'\033[0m'

ok()   { echo "  ${GREEN}✔${RESET} $*"; }
warn() { echo "  ${YELLOW}⚠${RESET} $*"; }
fail() { echo "  ${RED}✘${RESET} $*"; }
hdr()  { echo ""; echo "${BOLD}=== $* ===${RESET}"; }

MODE="${1:-}"

# ─────────────────────────────────────────────────────────────────────────────
# --check-processes: look for lingering export script processes
# ─────────────────────────────────────────────────────────────────────────────
if [ "$MODE" = "--check-processes" ]; then
  hdr "Checking for lingering export processes"
  MATCHES=$(ps aux | grep -E 'export-.*\.sh|oc get .* -o json' | grep -v grep || true)
  if [ -z "$MATCHES" ]; then
    ok "No lingering export or oc processes found"
  else
    warn "Found running processes:"
    echo "$MATCHES"
    echo ""
    echo "To kill them:  pkill -f 'export-.*\\.sh'"
  fi
  exit 0
fi

# ─────────────────────────────────────────────────────────────────────────────
# Pre-flight: required commands
# ─────────────────────────────────────────────────────────────────────────────
hdr "Pre-flight checks"

for cmd in oc jq date; do
  if command -v "$cmd" >/dev/null 2>&1; then
    VER=$("$cmd" version --client 2>/dev/null | head -1 || "$cmd" --version 2>/dev/null | head -1 || echo "installed")
    ok "$cmd — $VER"
  else
    fail "$cmd — NOT FOUND"
  fi
done

# ─────────────────────────────────────────────────────────────────────────────
# Authentication & session
# ─────────────────────────────────────────────────────────────────────────────
hdr "Authentication"

if OC_USER=$(oc whoami 2>&1); then
  ok "Logged in as: $OC_USER"
else
  fail "Not authenticated: $OC_USER"
  echo ""
  echo "Run:  oc login <server-url>"
  exit 1
fi

if OC_TOKEN_EXP=$(oc whoami --show-token 2>/dev/null); then
  ok "Token present (starts with ${OC_TOKEN_EXP:0:10}...)"
else
  warn "Could not retrieve token — may be using certificate auth"
fi

# ─────────────────────────────────────────────────────────────────────────────
# Context & cluster info
# ─────────────────────────────────────────────────────────────────────────────
hdr "Cluster connection"

CONTEXT=$(oc config current-context 2>/dev/null || echo "unknown")
SERVER=$(oc whoami --show-server 2>/dev/null || echo "unknown")
echo "  Context:  $CONTEXT"
echo "  Server:   $SERVER"

# API server health — try multiple endpoints (older clusters may not expose all)
HEALTH_OK=false
for ENDPOINT in /healthz /readyz /livez /api; do
  if HEALTH=$(oc get --raw "$ENDPOINT" 2>&1 | tr -d '\r'); then
    ok "API server health ($ENDPOINT): $HEALTH"
    HEALTH_OK=true
    break
  fi
done
if [ "$HEALTH_OK" = false ]; then
  fail "API health check failed on /healthz, /readyz, /livez, /api"
  warn "Last error: $HEALTH"
fi

# Latency test — time a lightweight API call
START_MS=$(date +%s%N)
oc get --raw /api 2>/dev/null >/dev/null || true
END_MS=$(date +%s%N)
LATENCY_MS=$(( (END_MS - START_MS) / 1000000 ))
if [ "$LATENCY_MS" -lt 500 ]; then
  ok "API latency: ${LATENCY_MS}ms"
elif [ "$LATENCY_MS" -lt 2000 ]; then
  warn "API latency: ${LATENCY_MS}ms (slow)"
else
  fail "API latency: ${LATENCY_MS}ms (very slow — expect long script runtimes)"
fi

# ─────────────────────────────────────────────────────────────────────────────
# Cluster version summary
# ─────────────────────────────────────────────────────────────────────────────
hdr "Cluster version"

if CV_JSON=$(oc get clusterversion version -o json 2>&1 | tr -d '\r'); then
  if echo "$CV_JSON" | jq empty 2>/dev/null; then
    CV_VER=$(echo "$CV_JSON" | jq -r '.status.desired.version // "unknown"')
    CV_CHANNEL=$(echo "$CV_JSON" | jq -r '.spec.channel // "unknown"')
    CV_STATE=$(echo "$CV_JSON" | jq -r '.status.history[0].state // "unknown"')
    echo "  Version:  $CV_VER"
    echo "  Channel:  $CV_CHANNEL"
    echo "  State:    $CV_STATE"
  else
    fail "clusterversion returned invalid JSON"
    warn "Raw output (first 200 chars): ${CV_JSON:0:200}"
  fi
else
  warn "Could not fetch clusterversion: $CV_JSON"
fi

# ─────────────────────────────────────────────────────────────────────────────
# Resource counts (quick sanity check)
# ─────────────────────────────────────────────────────────────────────────────
hdr "Resource counts"

for RESOURCE in nodes clusteroperators machineconfigpools; do
  if COUNT_JSON=$(oc get "$RESOURCE" -o json 2>&1 | tr -d '\r'); then
    if echo "$COUNT_JSON" | jq empty 2>/dev/null; then
      COUNT=$(echo "$COUNT_JSON" | jq '.items | length' | tr -d '\r')
      ok "$RESOURCE: $COUNT"
    else
      fail "$RESOURCE: invalid JSON response"
    fi
  else
    fail "$RESOURCE: FAILED — ${COUNT_JSON:0:200}"
  fi
done

# ─────────────────────────────────────────────────────────────────────────────
# RBAC / permissions quick check
# ─────────────────────────────────────────────────────────────────────────────
hdr "Permission checks (can-i)"

CHECKS=(
  "get nodes"
  "get clusterversion"
  "get clusteroperators"
  "get machineconfigpools"
  "get clusterrolebindings"
  "get secrets -n openshift-etcd"
  "get oauth cluster"
)

FAILED_CHECKS=()
for CHECK in "${CHECKS[@]}"; do
  if oc auth can-i $CHECK >/dev/null 2>&1; then
    ok "can $CHECK"
  else
    fail "CANNOT $CHECK"
    FAILED_CHECKS+=("$CHECK")
  fi
done

# ─────────────────────────────────────────────────────────────────────────────
# Deep diagnostic for any failed permissions
# ─────────────────────────────────────────────────────────────────────────────
if [ ${#FAILED_CHECKS[@]} -gt 0 ]; then
  hdr "Permission failure diagnostics"

  # Show the user's identity and group memberships
  echo "  ${BOLD}Your identity:${RESET}"
  OC_USER=$(oc whoami 2>/dev/null || echo "unknown")
  echo "    User:   $OC_USER"

  # Try to get groups — may fail without permission
  if USER_GROUPS=$(oc get groups -o json 2>/dev/null | tr -d '\r' | jq -r --arg u "$OC_USER" '.items[] | select(.users[]? == $u) | .metadata.name' 2>/dev/null); then
    if [ -n "$USER_GROUPS" ]; then
      echo "    Groups: $USER_GROUPS"
    else
      echo "    Groups: (none found, or user not in any group)"
    fi
  else
    echo "    Groups: (cannot list groups)"
  fi

  # Show clusterrolebindings that include this user
  echo ""
  echo "  ${BOLD}Your cluster role bindings:${RESET}"
  if CRB_JSON=$(oc get clusterrolebindings -o json 2>/dev/null | tr -d '\r'); then
    BINDINGS=$(echo "$CRB_JSON" | jq -r --arg u "$OC_USER" '
      .items[] |
      select(
        (.subjects[]? | select(.kind == "User" and .name == $u)) or
        (.subjects[]? | select(.kind == "Group" and (.name == "system:cluster-admins" or .name == "cluster-admin")))
      ) |
      "    \(.metadata.name) → \(.roleRef.name)"
    ' 2>/dev/null)
    if [ -n "$BINDINGS" ]; then
      echo "$BINDINGS"
    else
      echo "    (no cluster-level bindings found for $OC_USER)"
    fi
  else
    echo "    (cannot list clusterrolebindings)"
  fi

  # Detailed check for each failed permission
  for FCHECK in "${FAILED_CHECKS[@]}"; do
    echo ""
    echo "  ${BOLD}Diagnosing: $FCHECK${RESET}"

    # Show the specific error message
    ERR=$(oc auth can-i $FCHECK 2>&1 || true)
    echo "    can-i result: $ERR"

    # Check if the API resource exists at all
    RESOURCE_WORD=$(echo "$FCHECK" | awk '{print $2}')
    if oc api-resources 2>/dev/null | grep -qi "\\b${RESOURCE_WORD}\\b"; then
      ok "  API resource '$RESOURCE_WORD' exists on this cluster"
    else
      fail "  API resource '$RESOURCE_WORD' NOT found — may not be available on this cluster version"
    fi

    # Try the actual command to show the real error
    ERR2=$(oc $FCHECK 2>&1 || true)
    echo "    actual error: ${ERR2:0:300}"
  done

  echo ""
  echo "  ${BOLD}Remediation:${RESET}"
  echo "    To grant read access, a cluster-admin can run:"
  echo "      oc adm policy add-cluster-role-to-user cluster-reader $OC_USER"
  echo "    Or for full admin:"
  echo "      oc adm policy add-cluster-role-to-user cluster-admin $OC_USER"
fi

# ─────────────────────────────────────────────────────────────────────────────
# --api-requests: show top API request counts (optional)
# ─────────────────────────────────────────────────────────────────────────────
if [ "$MODE" = "--api-requests" ]; then
  hdr "Top API request counts (current hour)"
  if oc get apirequestcounts --sort-by='.status.currentHour.requestCount' 2>/dev/null | head -20; then
    true
  else
    warn "apirequestcounts not available or no permission"
  fi
fi

# ─────────────────────────────────────────────────────────────────────────────
# Estimate: how long will node processing take?
# ─────────────────────────────────────────────────────────────────────────────
hdr "Node processing estimate"

NODE_COUNT=$(oc get nodes -o json 2>/dev/null | tr -d '\r' | jq '.items | length' 2>/dev/null | tr -d '\r' || echo 0)
if [ "$NODE_COUNT" -gt 0 ]; then
  # Benchmark: process one node through jq to estimate per-node time
  SAMPLE=$(oc get nodes -o json 2>/dev/null | tr -d '\r' | jq -c '.items[0] | {
    name: .metadata.name,
    kubelet: .status.nodeInfo.kubeletVersion,
    os: .status.nodeInfo.osImage,
    created: .metadata.creationTimestamp
  }')
  BENCH_START=$(date +%s%N)
  for _ in 1 2 3; do
    echo "$SAMPLE" | jq -r '.name' >/dev/null
    echo "$SAMPLE" | jq -r '.kubelet' >/dev/null
    echo "$SAMPLE" | jq -r '.os' >/dev/null
    echo "$SAMPLE" | jq -r '.created' >/dev/null
  done
  BENCH_END=$(date +%s%N)
  BENCH_MS=$(( (BENCH_END - BENCH_START) / 1000000 ))
  # 3 iterations × 4 jq calls = 12 calls; script does ~11 jq calls per node
  PER_NODE_MS=$(( BENCH_MS * 11 / 12 ))
  TOTAL_EST_S=$(( NODE_COUNT * PER_NODE_MS / 1000 ))
  TOTAL_EST_M=$(( TOTAL_EST_S / 60 ))

  echo "  Nodes:            $NODE_COUNT"
  echo "  Est. per node:    ~${PER_NODE_MS}ms"
  echo "  Est. total:       ~${TOTAL_EST_S}s (~${TOTAL_EST_M}m)"
  if [ "$TOTAL_EST_S" -gt 300 ]; then
    warn "Node loop will take over 5 minutes — consider running in background"
  fi
else
  warn "Could not determine node count"
fi

# ─────────────────────────────────────────────────────────────────────────────
# Output directory check
# ─────────────────────────────────────────────────────────────────────────────
hdr "Output directory"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEFAULT_OUTPUT="$SCRIPT_DIR/../output"
echo "  Default path: $DEFAULT_OUTPUT"
if [ -d "$DEFAULT_OUTPUT" ]; then
  FILE_COUNT=$(find "$DEFAULT_OUTPUT" -name '*.csv' -type f 2>/dev/null | wc -l | tr -d ' ')
  DISK=$(du -sh "$DEFAULT_OUTPUT" 2>/dev/null | cut -f1)
  ok "Exists — $FILE_COUNT CSV files, $DISK used"
else
  warn "Directory does not exist yet (will be created on first run)"
fi

echo ""
echo "${BOLD}Diagnostics complete.${RESET}"
