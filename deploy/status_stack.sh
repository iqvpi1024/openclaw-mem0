#!/usr/bin/env bash
set -euo pipefail

echo "== services =="
systemctl is-active openclaw-gateway.service mem0-local.service
echo

echo "== listeners =="
ss -lntp | grep -E ':18789|:8765' || true
echo

echo "== health checks =="
curl -sS http://127.0.0.1:18789/health || true
echo
curl -sS http://127.0.0.1:8765/health || true
echo

echo "== recent logs =="
journalctl -u openclaw-gateway.service -u mem0-local.service -n 20 --no-pager
