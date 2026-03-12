#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

"$SCRIPT_DIR/scripts/export-clusterrolebindings.sh"
"$SCRIPT_DIR/scripts/export-clusterrolebinding-self-provisioners.sh"
"$SCRIPT_DIR/scripts/export-clusterversion.sh"
"$SCRIPT_DIR/scripts/export-clusteroperators.sh"
"$SCRIPT_DIR/scripts/export-oauth-cluster.sh"
"$SCRIPT_DIR/scripts/export-infrastructure-cluster.sh"
"$SCRIPT_DIR/scripts/export-scc-privileged.sh"

echo "All reports completed."
