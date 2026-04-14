#!/usr/bin/env bash
# Description: Manage kubeconfig contexts for multi-cluster OpenShift exports.
#              Creates isolated credential entries per cluster so tokens don't
#              overwrite each other — the root cause of "token expired" errors
#              when using run-multi-cluster.sh.
#
# Works on Git Bash (Windows), macOS, and Linux.
#
# Usage:
#   ./setup-contexts.sh add    <context-name> <server-url> <token>
#   ./setup-contexts.sh list
#   ./setup-contexts.sh test   [context-name ...]
#   ./setup-contexts.sh remove <context-name>
#   ./setup-contexts.sh reset
#
# Examples:
#   ./setup-contexts.sh add aws-useast1-apps-dev-1 https://api.dev1.example.com:6443 sha256~abc...
#   ./setup-contexts.sh add aws-useast1-apps-dev-2 https://api.dev2.example.com:6443 sha256~xyz...
#   ./setup-contexts.sh list
#   ./setup-contexts.sh test
#   ./setup-contexts.sh test aws-useast1-apps-dev-1
#   ./setup-contexts.sh remove aws-useast1-apps-dev-1
#   ./setup-contexts.sh reset    # wipe kubeconfig and start fresh
set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

LABEL="setup-contexts"

usage() {
  echo "Usage:"
  echo "  $0 login                                        # interactive — walks you through each cluster"
  echo "  $0 add    <context-name> <server-url> <token>   # non-interactive — add one cluster"
  echo "  $0 list"
  echo "  $0 test   [context-name ...]"
  echo "  $0 remove <context-name>"
  echo "  $0 reset"
  echo ""
  echo "Commands:"
  echo "  login   Interactive mode — prompts for each cluster, you paste the oc login command"
  echo "  add     Register a cluster with an isolated credential entry"
  echo "  list    Show all contexts and their connection status"
  echo "  test    Verify authentication for all (or specified) contexts"
  echo "  remove  Delete a context and its associated cluster/credential entries"
  echo "  reset   Back up and remove ~/.kube/config to start fresh"
}

###############################################################################
# add — register a cluster with a unique credential entry
###############################################################################
cmd_add() {
  if [ $# -lt 3 ]; then
    echo -e "${RED}[$LABEL] ERROR: add requires <context-name> <server-url> <token>${NC}"
    echo "  Example: $0 add ocp-dev https://api.dev.example.com:6443 sha256~abc..."
    exit 1
  fi

  local ctx_name="$1"
  local server_url="$2"
  local token="$3"

  # Use context name as cluster and credential identifiers to keep them unique
  local cluster_name="cluster-${ctx_name}"
  local cred_name="user-${ctx_name}"

  echo "[$LABEL] Adding context: $ctx_name"
  echo "[$LABEL]   Server : $server_url"
  echo "[$LABEL]   Cluster: $cluster_name"
  echo "[$LABEL]   Creds  : $cred_name"

  # Set cluster entry (skip TLS verify — common for internal OCP clusters)
  oc config set-cluster "$cluster_name" --server="$server_url" --insecure-skip-tls-verify=true >/dev/null

  # Set credential entry with the token — unique per context
  oc config set-credentials "$cred_name" --token="$token" >/dev/null

  # Create the context linking cluster + credential
  oc config set-context "$ctx_name" --cluster="$cluster_name" --user="$cred_name" >/dev/null

  echo -e "${GREEN}[$LABEL] ✓ Context '$ctx_name' added successfully${NC}"

  # Quick auth test
  echo "[$LABEL] Testing authentication..."
  if oc --context="$ctx_name" whoami >/dev/null 2>&1; then
    local user
    user="$(oc --context="$ctx_name" whoami 2>/dev/null)"
    echo -e "${GREEN}[$LABEL] ✓ Authenticated as: $user${NC}"
  else
    echo -e "${RED}[$LABEL] ✗ Authentication failed — check token and server URL${NC}"
    exit 1
  fi
}

###############################################################################
# list — show all contexts
###############################################################################
cmd_list() {
  echo "[$LABEL] Current contexts:"
  echo ""
  oc config get-contexts 2>/dev/null || echo "  (no contexts found)"
  echo ""

  local current
  current="$(oc config current-context 2>/dev/null || echo "(none)")"
  echo "[$LABEL] Active context: $current"
}

###############################################################################
# test — verify authentication on contexts
###############################################################################
cmd_test() {
  local contexts=()

  if [ $# -gt 0 ]; then
    contexts=("$@")
  else
    mapfile -t contexts < <(oc config get-contexts -o name 2>/dev/null)
  fi

  if [ ${#contexts[@]} -eq 0 ]; then
    echo -e "${YELLOW}[$LABEL] No contexts found in kubeconfig${NC}"
    exit 0
  fi

  echo "[$LABEL] Testing ${#contexts[@]} context(s)..."
  echo ""

  local pass=0
  local fail=0

  for ctx in "${contexts[@]}"; do
    local server
    server="$(oc config view -o jsonpath="{.contexts[?(@.name==\"$ctx\")].context.cluster}" 2>/dev/null || echo "")"
    server_url="$(oc config view -o jsonpath="{.clusters[?(@.name==\"$server\")].cluster.server}" 2>/dev/null || echo "unknown")"

    if oc --context="$ctx" whoami >/dev/null 2>&1; then
      local user
      user="$(oc --context="$ctx" whoami 2>/dev/null)"
      echo -e "  ${GREEN}✓${NC} $ctx  →  $user  ($server_url)"
      pass=$((pass + 1))
    else
      echo -e "  ${RED}✗${NC} $ctx  →  AUTH FAILED  ($server_url)"
      fail=$((fail + 1))
    fi
  done

  echo ""
  echo "[$LABEL] Results: $pass passed, $fail failed"

  if [ "$fail" -gt 0 ]; then
    echo -e "${YELLOW}[$LABEL] Hint: Re-add failed contexts with a fresh token:${NC}"
    echo "  $0 add <context-name> <server-url> <new-token>"
    exit 1
  fi
}

###############################################################################
# remove — delete a context and its associated entries
###############################################################################
cmd_remove() {
  if [ $# -lt 1 ]; then
    echo -e "${RED}[$LABEL] ERROR: remove requires <context-name>${NC}"
    exit 1
  fi

  local ctx_name="$1"
  local cluster_name="cluster-${ctx_name}"
  local cred_name="user-${ctx_name}"

  echo "[$LABEL] Removing context: $ctx_name"

  oc config delete-context "$ctx_name" 2>/dev/null && \
    echo "  Deleted context: $ctx_name" || \
    echo -e "  ${YELLOW}Context '$ctx_name' not found${NC}"

  oc config delete-cluster "$cluster_name" 2>/dev/null && \
    echo "  Deleted cluster: $cluster_name" || \
    echo -e "  ${YELLOW}Cluster '$cluster_name' not found${NC}"

  oc config unset "users.${cred_name}" 2>/dev/null && \
    echo "  Deleted credentials: $cred_name" || \
    echo -e "  ${YELLOW}Credentials '$cred_name' not found${NC}"

  echo -e "${GREEN}[$LABEL] ✓ Removed '$ctx_name'${NC}"
}

###############################################################################
# reset — backup and wipe kubeconfig
###############################################################################
cmd_reset() {
  local kubeconfig="${KUBECONFIG:-$HOME/.kube/config}"

  if [ ! -f "$kubeconfig" ]; then
    echo "[$LABEL] No kubeconfig found at $kubeconfig — already clean"
    exit 0
  fi

  local backup
  backup="${kubeconfig}.backup-$(date +%Y%m%d-%H%M%S)"
  cp "$kubeconfig" "$backup"
  echo "[$LABEL] Backed up to: $backup"

  rm "$kubeconfig"
  echo -e "${GREEN}[$LABEL] ✓ Kubeconfig removed — start fresh with:${NC}"
  echo "  $0 login"
}

###############################################################################
# login — interactive mode: walk through clusters one at a time
###############################################################################
cmd_login() {
  echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo -e "${CYAN}[$LABEL] Interactive cluster setup${NC}"
  echo -e "${CYAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
  echo ""
  echo "For each cluster you'll provide:"
  echo "  1. A context name (e.g., aws-useast1-apps-dev-1)"
  echo "  2. The server URL"
  echo "  3. The token"
  echo ""
  echo "Type 'done' for the context name when finished."
  echo ""

  local count=0

  while true; do
    echo -e "${YELLOW}--- Cluster $((count + 1)) ---${NC}"
    printf "Context name (or 'done'): "
    read -r ctx_name

    if [ "$ctx_name" = "done" ] || [ -z "$ctx_name" ]; then
      break
    fi

    printf "Server URL: "
    read -r server_url

    if [ -z "$server_url" ]; then
      echo -e "${RED}[$LABEL] ERROR: Server URL cannot be empty — skipping${NC}"
      continue
    fi

    printf "Token: "
    read -r token

    if [ -z "$token" ]; then
      echo -e "${RED}[$LABEL] ERROR: Token cannot be empty — skipping${NC}"
      continue
    fi

    echo ""
    cmd_add "$ctx_name" "$server_url" "$token"
    count=$((count + 1))
    echo ""
  done

  echo ""
  if [ "$count" -eq 0 ]; then
    echo "[$LABEL] No clusters added."
  else
    echo -e "${GREEN}[$LABEL] ✓ Added $count cluster(s)${NC}"
    echo ""
    cmd_list
    echo ""
    echo "[$LABEL] Ready to run: ./run-multi-cluster.sh"
  fi
}

###############################################################################
# Main
###############################################################################
if [ $# -lt 1 ]; then
  usage
  exit 1
fi

COMMAND="$1"
shift

case "$COMMAND" in
  login)  cmd_login ;;
  add)    cmd_add "$@" ;;
  list)   cmd_list ;;
  test)   cmd_test "$@" ;;
  remove) cmd_remove "$@" ;;
  reset)  cmd_reset ;;
  -h|--help|help) usage ;;
  *)
    echo -e "${RED}[$LABEL] Unknown command: $COMMAND${NC}"
    usage
    exit 1
    ;;
esac
