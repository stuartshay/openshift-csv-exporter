#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

echo "CLUSTER_CONTEXT=$CLUSTER_CONTEXT"
echo "CLUSTER_SERVER=$CLUSTER_SERVER"
echo "CLUSTER_NAME=$CLUSTER_NAME"
echo "CLUSTER_NAME_SAFE=$CLUSTER_NAME_SAFE"
echo "OUTPUT_DIR=$OUTPUT_DIR"
echo "TIMESTAMP=$TIMESTAMP"
