#!/usr/bin/env bash
# Description: Runs export scripts against all authenticated OpenShift clusters
#              found in the current kubeconfig. Authenticate to each cluster
#              before running this script (e.g., oc login <server1>, oc login <server2>).
#
# Usage:
#   ./run-multi-cluster.sh                          # run ALL export scripts on every context
#   ./run-multi-cluster.sh scripts/export-cluster-overview.sh  # run a single script on every context
#   CONTEXTS="ctx1,ctx2" ./run-multi-cluster.sh     # limit to specific contexts
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

LABEL="multi-cluster"
TOTAL_START=$SECONDS

###############################################################################
# Determine which script(s) to run
###############################################################################
if [ $# -ge 1 ]; then
  RUN_TARGET="$1"
  if [ ! -f "$RUN_TARGET" ]; then
    echo -e "${RED}[$LABEL] ERROR: script not found: $RUN_TARGET${NC}"
    exit 1
  fi
else
  RUN_TARGET="$SCRIPT_DIR/run-all.sh"
fi

###############################################################################
# Collect contexts to iterate
###############################################################################
if [ -n "${CONTEXTS:-}" ]; then
  # User supplied a comma-separated list
  IFS=',' read -ra CTX_LIST <<< "$CONTEXTS"
else
  # Discover all contexts in kubeconfig
  mapfile -t CTX_LIST < <(oc config get-contexts -o name 2>/dev/null)
fi

if [ ${#CTX_LIST[@]} -eq 0 ]; then
  echo -e "${RED}[$LABEL] ERROR: No OpenShift contexts found in kubeconfig.${NC}"
  echo "  Hint: oc login <server> to add cluster contexts."
  exit 1
fi

echo "[$LABEL] Found ${#CTX_LIST[@]} context(s): ${CTX_LIST[*]}"
echo "[$LABEL] Target: $RUN_TARGET"
echo ""

###############################################################################
# Save original context so we can restore it afterwards
###############################################################################
ORIGINAL_CTX="$(oc config current-context 2>/dev/null || true)"

###############################################################################
# Run exports for each context
###############################################################################
PASS=0
FAIL=0
SKIPPED=0

for CTX in "${CTX_LIST[@]}"; do
  echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${YELLOW}[$LABEL] Switching to context: $CTX${NC}"
  echo -e "${YELLOW}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"

  if ! oc config use-context "$CTX" >/dev/null 2>&1; then
    echo -e "${RED}[$LABEL] ERROR: Failed to switch to context '$CTX' — skipping${NC}"
    SKIPPED=$((SKIPPED + 1))
    continue
  fi

  # Verify the context is still authenticated
  if ! oc whoami >/dev/null 2>&1; then
    echo -e "${RED}[$LABEL] ERROR: Context '$CTX' is not authenticated (token expired?) — skipping${NC}"
    SKIPPED=$((SKIPPED + 1))
    continue
  fi

  SERVER="$(oc whoami --show-server 2>/dev/null || echo "unknown")"
  USER="$(oc whoami 2>/dev/null || echo "unknown")"
  echo "[$LABEL] Server : $SERVER"
  echo "[$LABEL] User   : $USER"
  echo ""

  if bash "$RUN_TARGET"; then
    echo -e "${GREEN}[$LABEL] ✓ Completed: $CTX${NC}"
    PASS=$((PASS + 1))
  else
    echo -e "${RED}[$LABEL] ✗ Failed: $CTX${NC}"
    FAIL=$((FAIL + 1))
  fi
  echo ""
done

###############################################################################
# Restore original context
###############################################################################
if [ -n "${ORIGINAL_CTX:-}" ]; then
  oc config use-context "$ORIGINAL_CTX" >/dev/null 2>&1 || true
  echo "[$LABEL] Restored original context: $ORIGINAL_CTX"
fi

###############################################################################
# Summary
###############################################################################
ELAPSED=$(( SECONDS - TOTAL_START ))
echo ""
echo "[$LABEL] ═══════════════════════════════════════════════════"
echo "[$LABEL] Summary: ${PASS} passed, ${FAIL} failed, ${SKIPPED} skipped (of ${#CTX_LIST[@]} total)"
echo "[$LABEL] Output directory: ${OUTPUT_DIR:-./output}"
echo "[$LABEL] Total time: ${ELAPSED}s"
echo "[$LABEL] ═══════════════════════════════════════════════════"

if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
