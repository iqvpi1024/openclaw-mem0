#!/usr/bin/env bash
set -euo pipefail

systemctl stop mem0-local.service openclaw-gateway.service || true
echo "stopped: mem0-local.service, openclaw-gateway.service"
