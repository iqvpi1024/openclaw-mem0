#!/usr/bin/env bash
set -euo pipefail

systemctl daemon-reload
systemctl start mem0-local.service
systemctl is-active --quiet mem0-local.service
echo "mem0-local.service is active"
