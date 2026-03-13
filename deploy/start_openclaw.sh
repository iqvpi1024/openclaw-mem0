#!/usr/bin/env bash
set -euo pipefail

systemctl daemon-reload
systemctl start openclaw-gateway.service
systemctl is-active --quiet openclaw-gateway.service
echo "openclaw-gateway.service is active"
