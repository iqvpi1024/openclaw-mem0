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

detect_openclaw_dir() {
  local candidates=(
    "${OPENCLAW_PACKAGE_DIR:-}"
    "$HOME/openclaw-work/extracted/package"
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

RUN_HOME="${RUN_HOME:-$HOME/.openclaw-mem0}"
RUN_DIR="$RUN_HOME/run"
LOG_DIR="$RUN_HOME/logs"
BIN_DIR="$RUN_HOME/bin"
mkdir -p "$RUN_DIR" "$LOG_DIR" "$BIN_DIR"

cat > "$BIN_DIR/start_openclaw.sh" <<SCRIPT
#!/usr/bin/env bash
set -euo pipefail
cd "$OPENCLAW_PACKAGE_DIR"
nohup "$NODE_BIN" ./openclaw.mjs --no-color gateway run > "$LOG_DIR/openclaw.log" 2>&1 &
echo \$! > "$RUN_DIR/openclaw.pid"
echo "openclaw started pid=\$(cat \"$RUN_DIR/openclaw.pid\")"
SCRIPT

cat > "$BIN_DIR/start_mem0.sh" <<SCRIPT
#!/usr/bin/env bash
set -euo pipefail
cd "$MEM0_DIR"
nohup "$MEM0_DIR/.venv/bin/uvicorn" mem0_api:app --host 127.0.0.1 --port "$MEM0_PORT" --workers 1 > "$LOG_DIR/mem0.log" 2>&1 &
echo \$! > "$RUN_DIR/mem0.pid"
echo "mem0 started pid=\$(cat \"$RUN_DIR/mem0.pid\")"
SCRIPT

cat > "$BIN_DIR/start_stack.sh" <<SCRIPT
#!/usr/bin/env bash
set -euo pipefail
"$BIN_DIR/start_openclaw.sh"
sleep 2
"$BIN_DIR/start_mem0.sh"
SCRIPT

cat > "$BIN_DIR/stop_stack.sh" <<SCRIPT
#!/usr/bin/env bash
set -euo pipefail
for name in mem0 openclaw; do
  pid_file="$RUN_DIR/\${name}.pid"
  if [ -f "$pid_file" ]; then
    pid=\$(cat "$pid_file")
    if kill -0 "\$pid" 2>/dev/null; then
      kill "\$pid" || true
    fi
    rm -f "$pid_file"
  fi
done
SCRIPT

cat > "$BIN_DIR/status_stack.sh" <<SCRIPT
#!/usr/bin/env bash
set -euo pipefail
for name in openclaw mem0; do
  pid_file="$RUN_DIR/\${name}.pid"
  if [ -f "$pid_file" ] && kill -0 "\$(cat "$pid_file")" 2>/dev/null; then
    echo "\${name}: running pid=\$(cat "$pid_file")"
  else
    echo "\${name}: stopped"
  fi
done
curl -fsS "http://127.0.0.1:$MEM0_PORT/health" || true
SCRIPT

chmod +x "$BIN_DIR/"*.sh

"$BIN_DIR/start_stack.sh"
sleep 2
"$BIN_DIR/status_stack.sh"

cat <<DONE

[DONE] macOS one-click completed.
Run scripts:
  $BIN_DIR/start_stack.sh
  $BIN_DIR/stop_stack.sh
  $BIN_DIR/status_stack.sh

OpenClaw config patched: $OPENCLAW_CONFIG
Mem0 plugin installed: $MEM0_EXTENSION_PATH/index.ts
DONE
