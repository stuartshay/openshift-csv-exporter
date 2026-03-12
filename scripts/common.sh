#!/usr/bin/env bash
set -euo pipefail

OUTPUT_DIR="${OUTPUT_DIR:-./output}"
TIMESTAMP="$(date +"%Y-%m-%d-%H-%M")"

mkdir -p "$OUTPUT_DIR"

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "ERROR: required command not found: $1" >&2
    exit 1
  fi
}

require_oc_login() {
  if ! oc whoami >/dev/null 2>&1; then
    echo "ERROR: not authenticated to OpenShift" >&2
    exit 1
  fi
}

detect_cluster_info() {
  CLUSTER_CONTEXT="$(oc config current-context 2>/dev/null || true)"
  CLUSTER_SERVER="$(oc whoami --show-server 2>/dev/null || true)"

  local server_host=""
  server_host="$(printf '%s' "$CLUSTER_SERVER" | sed -E 's#https?://([^/:]+).*#\1#')"

  if [ -n "${CLUSTER_CONTEXT:-}" ]; then
    CLUSTER_NAME="$CLUSTER_CONTEXT"
  elif [ -n "$server_host" ]; then
    CLUSTER_NAME="$server_host"
  else
    CLUSTER_NAME="unknown-cluster"
  fi

  CLUSTER_NAME_SAFE="$(printf '%s' "$CLUSTER_NAME" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9._-]/-/g')"
}

require_command oc
require_command jq
require_oc_login
detect_cluster_info