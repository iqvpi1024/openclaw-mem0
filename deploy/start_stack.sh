#!/usr/bin/env bash
set -euo pipefail

DEPLOY_DIR="$(cd "$(dirname "$0")" && pwd)"

systemctl start ensure-swap-4g.service
"$DEPLOY_DIR/start_openclaw.sh"
"$DEPLOY_DIR/start_mem0.sh"
"$DEPLOY_DIR/status_stack.sh"
