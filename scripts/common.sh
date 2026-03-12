#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUTPUT_DIR="$ROOT_DIR/output"
TIMESTAMP="$(date +"%Y-%m-%d-%H-%M")"

require_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "ERROR: required command not found: $1" >&2
    exit 1
  fi
}

check_prereqs() {
  require_cmd oc
  require_cmd jq

  if ! oc whoami >/dev/null 2>&1; then
    echo "ERROR: not authenticated to OpenShift via oc" >&2
    exit 1
  fi

  mkdir -p "$OUTPUT_DIR"
}

announce_output() {
  local file="$1"
  echo "Created: $file"
}
