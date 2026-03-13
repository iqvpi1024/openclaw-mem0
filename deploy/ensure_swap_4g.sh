#!/usr/bin/env bash
set -euo pipefail

TARGET_MB=4096
SWAP_FILE="/swap.openclaw"

current_bytes=$(swapon --bytes --noheadings --show=SIZE 2>/dev/null | awk '{s+=$1} END{print s+0}')
target_bytes=$((TARGET_MB * 1024 * 1024))

if [ "$current_bytes" -ge "$target_bytes" ]; then
  echo "swap already >= ${TARGET_MB}MB (current bytes: ${current_bytes})"
  exit 0
fi

need_bytes=$((target_bytes - current_bytes))
need_mb=$(((need_bytes + 1024 * 1024 - 1) / (1024 * 1024)))

if swapon --show=NAME --noheadings 2>/dev/null | awk '{print $1}' | grep -qx "$SWAP_FILE"; then
  swapoff "$SWAP_FILE"
fi

if [ -f "$SWAP_FILE" ]; then
  rm -f "$SWAP_FILE"
fi

if command -v fallocate >/dev/null 2>&1; then
  fallocate -l "${need_mb}M" "$SWAP_FILE"
else
  dd if=/dev/zero of="$SWAP_FILE" bs=1M count="$need_mb" status=progress
fi

chmod 600 "$SWAP_FILE"
mkswap "$SWAP_FILE" >/dev/null
swapon "$SWAP_FILE"

if ! grep -qE "^${SWAP_FILE}[[:space:]]+none[[:space:]]+swap[[:space:]]+sw" /etc/fstab; then
  echo "${SWAP_FILE} none swap sw 0 0" >> /etc/fstab
fi

swapon --show
free -h
