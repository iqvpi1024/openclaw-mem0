#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
COMMON_DIR="$REPO_ROOT/deploy/common"
TEMPLATE_DIR="$REPO_ROOT/templates/mem0-hub"

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "[ERROR] missing command: $1" >&2
    exit 1
  }
}

run_root() {
  if [ "${EUID}" -eq 0 ]; then
    "$@"
  else
    sudo "$@"
  fi
}

detect_openclaw_dir() {
  local candidates=(
    "${OPENCLAW_PACKAGE_DIR:-}"
    "$HOME/openclaw-work/extracted/package"
    "/root/openclaw-work/extracted/package"
    "$HOME/openclaw/extracted/package"
    "$PWD/openclaw-work/extracted/package"
  )

  for candidate in "${candidates[@]}"; do
    [ -n "$candidate" ] || continue
    if [ -f "$candidate/openclaw.mjs" ]; then
      echo "$candidate"
      return 0
    fi
  done

  return 1
}

need_cmd node
need_cmd python3
need_cmd curl

echo "[WARN] one_click.sh is not fully validated across all OpenClaw/system combinations."
echo "[WARN] Backup recommended before continue: ~/.openclaw, ~/mem0-local, OpenClaw install dir."

OPENCLAW_PACKAGE_DIR="$(detect_openclaw_dir || true)"
if [ -z "${OPENCLAW_PACKAGE_DIR}" ]; then
  echo "[ERROR] openclaw.mjs not found. Export OPENCLAW_PACKAGE_DIR first." >&2
  exit 1
fi

NODE_BIN="$(command -v node)"
OPENCLAW_HOME="${OPENCLAW_HOME:-$HOME/.openclaw}"
OPENCLAW_CONFIG="${OPENCLAW_CONFIG:-$OPENCLAW_HOME/openclaw.json}"
MEM0_DIR="${MEM0_DIR:-$HOME/mem0-local}"
MEM0_PORT="${MEM0_PORT:-8765}"
OPENCLAW_GATEWAY_PORT="${OPENCLAW_GATEWAY_PORT:-18789}"
MEM0_URL="http://127.0.0.1:${MEM0_PORT}"
MEM0_EXTENSION_PATH="${MEM0_EXTENSION_PATH:-$OPENCLAW_HOME/extensions/mem0-hub}"
KIMI_API_KEY="${KIMI_API_KEY:-<YOUR_KIMI_API_KEY>}"
FEISHU_APP_ID="${FEISHU_APP_ID:-}"
FEISHU_APP_SECRET="${FEISHU_APP_SECRET:-}"
ENABLE_FEISHU="${ENABLE_FEISHU:-0}"

if [ "$ENABLE_FEISHU" = "1" ]; then
  if [ -z "$FEISHU_APP_ID" ] || [ -z "$FEISHU_APP_SECRET" ]; then
    echo "[ERROR] ENABLE_FEISHU=1 requires FEISHU_APP_ID and FEISHU_APP_SECRET" >&2
    exit 1
  fi
fi

echo "[INFO] openclaw dir: $OPENCLAW_PACKAGE_DIR"
echo "[INFO] openclaw config: $OPENCLAW_CONFIG"
echo "[INFO] mem0 dir: $MEM0_DIR"
echo "[INFO] mem0 url: $MEM0_URL"

mkdir -p "$MEM0_DIR" "$MEM0_DIR/data" "$MEM0_EXTENSION_PATH" "$OPENCLAW_HOME"
cp "$COMMON_DIR/mem0_api.py" "$MEM0_DIR/mem0_api.py"
cp "$COMMON_DIR/requirements.txt" "$MEM0_DIR/requirements.txt"
cp "$TEMPLATE_DIR/index.ts" "$MEM0_EXTENSION_PATH/index.ts"

if [ ! -d "$MEM0_DIR/.venv" ]; then
  python3 -m venv "$MEM0_DIR/.venv"
fi

"$MEM0_DIR/.venv/bin/pip" install -U pip
"$MEM0_DIR/.venv/bin/pip" install -r "$MEM0_DIR/requirements.txt"

cat > "$MEM0_DIR/.env" <<ENVEOF
OPENAI_API_KEY=openclaw-local
OPENAI_BASE_URL=http://127.0.0.1:${OPENCLAW_GATEWAY_PORT}/v1

MEM0_LLM_PROVIDER=openai
MEM0_LLM_MODEL=kimicode/kimi-k2.5

MEM0_EMBEDDER_PROVIDER=huggingface
MEM0_EMBEDDER_MODEL=BAAI/bge-large-zh-v1.5
MEM0_EMBEDDING_DIMS=1024
HF_ENDPOINT=https://hf-mirror.com

MEM0_QDRANT_PATH=./data/qdrant-openclaw
MEM0_HISTORY_DB_PATH=./data/history-openclaw.db
MEM0_COLLECTION_NAME=mem0
ENVEOF

export OPENCLAW_HOME OPENCLAW_CONFIG MEM0_URL MEM0_EXTENSION_PATH KIMI_API_KEY FEISHU_APP_ID FEISHU_APP_SECRET ENABLE_FEISHU OPENCLAW_GATEWAY_PORT
"$NODE_BIN" "$COMMON_DIR/patch_openclaw_config.mjs"

if command -v systemctl >/dev/null 2>&1; then
  SERVICE_USER="$(id -un)"
  TMP_OPENCLAW_SERVICE="$(mktemp)"
  TMP_MEM0_SERVICE="$(mktemp)"

  cat > "$TMP_OPENCLAW_SERVICE" <<SERVICE
[Unit]
Description=OpenClaw Gateway (Mem0 First)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=${SERVICE_USER}
WorkingDirectory=${OPENCLAW_PACKAGE_DIR}
Environment=OPENCLAW_NO_RESPAWN=1
ExecStart=${NODE_BIN} ./openclaw.mjs --no-color gateway run
Restart=always
RestartSec=3
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
SERVICE

  cat > "$TMP_MEM0_SERVICE" <<SERVICE
[Unit]
Description=Mem0 Local API
After=network-online.target openclaw-gateway.service
Wants=network-online.target openclaw-gateway.service

[Service]
Type=simple
User=${SERVICE_USER}
WorkingDirectory=${MEM0_DIR}
EnvironmentFile=${MEM0_DIR}/.env
Environment=PYTHONUNBUFFERED=1
ExecStart=${MEM0_DIR}/.venv/bin/uvicorn mem0_api:app --host 127.0.0.1 --port ${MEM0_PORT} --workers 1
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
SERVICE

  run_root install -m 644 "$TMP_OPENCLAW_SERVICE" /etc/systemd/system/openclaw-gateway.service
  run_root install -m 644 "$TMP_MEM0_SERVICE" /etc/systemd/system/mem0-local.service
  run_root systemctl daemon-reload

  if [ "${ENABLE_SWAP:-0}" = "1" ]; then
    run_root bash "$REPO_ROOT/deploy/ensure_swap_4g.sh"
  fi

  run_root systemctl enable --now openclaw-gateway.service
  run_root systemctl enable --now mem0-local.service

  rm -f "$TMP_OPENCLAW_SERVICE" "$TMP_MEM0_SERVICE"

  run_root systemctl is-active openclaw-gateway.service mem0-local.service
else
  echo "[WARN] systemctl not found; skip service installation."
  echo "[INFO] Start OpenClaw manually:"
  echo "  cd ${OPENCLAW_PACKAGE_DIR} && ${NODE_BIN} ./openclaw.mjs --no-color gateway run"
  echo "[INFO] Start Mem0 manually:"
  echo "  cd ${MEM0_DIR} && ./.venv/bin/uvicorn mem0_api:app --host 127.0.0.1 --port ${MEM0_PORT} --workers 1"
fi

echo "[INFO] health checks"
curl -fsS "http://127.0.0.1:${MEM0_PORT}/health" || true

cat <<DONE

[DONE] Linux one-click completed.
- OpenClaw config patched: ${OPENCLAW_CONFIG}
- Mem0 plugin installed: ${MEM0_EXTENSION_PATH}/index.ts
- Mem0 API installed: ${MEM0_DIR}/mem0_api.py

Optional env before running script:
  KIMI_API_KEY=***
  ENABLE_FEISHU=1 FEISHU_APP_ID=*** FEISHU_APP_SECRET=***
  OPENCLAW_PACKAGE_DIR=/abs/path/to/openclaw/package
DONE
