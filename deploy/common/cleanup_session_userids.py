#!/usr/bin/env python3
import argparse
import os
import re
import subprocess
import sys
from typing import Any, Dict, Iterable, Set

try:
  from dotenv import load_dotenv
except Exception:
  def load_dotenv(*_args: Any, **_kwargs: Any) -> bool:
    return False

SESSION_USER_RE = re.compile(r"user_id=(session:[^\s]+)")


def _as_int(name: str, default: int) -> int:
  value = os.getenv(name, str(default))
  try:
    return int(value)
  except ValueError as exc:
    raise RuntimeError(f"{name} must be an integer, got: {value}") from exc


def _build_config() -> Dict[str, Any]:
  llm_provider = os.getenv("MEM0_LLM_PROVIDER", "openai").strip().lower()
  embedder_provider = os.getenv("MEM0_EMBEDDER_PROVIDER", "openai").strip().lower()

  default_dims = 1536
  if embedder_provider == "huggingface":
    default_dims = 1024
  elif embedder_provider == "ollama":
    default_dims = _as_int("MEM0_EMBEDDING_DIMS", 1024)

  config: Dict[str, Any] = {
    "vector_store": {
      "provider": "qdrant",
      "config": {
        "collection_name": os.getenv("MEM0_COLLECTION_NAME", "mem0"),
        "path": os.getenv("MEM0_QDRANT_PATH", "./data/qdrant-openclaw-v2"),
        "embedding_model_dims": _as_int("MEM0_EMBEDDING_DIMS", default_dims),
      },
    },
    "history_db_path": os.getenv("MEM0_HISTORY_DB_PATH", "./data/history-openclaw-v2.db"),
    "llm": {"provider": llm_provider, "config": {}},
    "embedder": {"provider": embedder_provider, "config": {}},
  }

  llm_config = config["llm"]["config"]
  if llm_provider == "ollama":
    llm_config["model"] = os.getenv("MEM0_LLM_MODEL", "llama3.1")
    llm_config["host"] = os.getenv("MEM0_OLLAMA_HOST", "localhost")
    llm_config["port"] = _as_int("MEM0_OLLAMA_PORT", 11434)
  else:
    llm_config["model"] = os.getenv("MEM0_LLM_MODEL", "gpt-4.1-mini")

  embedder_config = config["embedder"]["config"]
  if embedder_provider == "ollama":
    embedder_config["model"] = os.getenv("MEM0_EMBEDDER_MODEL", "nomic-embed-text")
    embedder_config["host"] = os.getenv("MEM0_OLLAMA_HOST", "localhost")
    embedder_config["port"] = _as_int("MEM0_OLLAMA_PORT", 11434)
  elif embedder_provider == "huggingface":
    embedder_config["model"] = os.getenv("MEM0_EMBEDDER_MODEL", "BAAI/bge-large-zh-v1.5")
    hf_device = os.getenv("MEM0_HF_DEVICE", "").strip()
    if hf_device:
      embedder_config["model_kwargs"] = {"device": hf_device}
  else:
    embedder_config["model"] = os.getenv("MEM0_EMBEDDER_MODEL", "text-embedding-3-small")

  return config


def collect_session_user_ids(hours: int, units: Iterable[str]) -> Set[str]:
  user_ids: Set[str] = set()
  for unit in units:
    cmd = [
      "journalctl",
      "-u",
      unit,
      "--since",
      f"{hours} hours ago",
      "--no-pager",
      "-o",
      "cat",
    ]
    try:
      out = subprocess.check_output(cmd, stderr=subprocess.STDOUT, text=True)
    except subprocess.CalledProcessError as exc:
      out = exc.output or ""
    for match in SESSION_USER_RE.findall(out):
      user_ids.add(match.strip())
  return user_ids


def main() -> int:
  parser = argparse.ArgumentParser(
    description="Find session:* user_id values from journal logs and remove their memories from Mem0.",
  )
  parser.add_argument("--hours", type=int, default=168, help="Look back N hours in journal logs.")
  parser.add_argument(
    "--unit",
    action="append",
    default=[],
    help="Additional systemd unit to scan. Can be passed multiple times.",
  )
  parser.add_argument(
    "--apply",
    action="store_true",
    help="Actually execute delete_all. Without this flag it only prints candidates.",
  )
  parser.add_argument(
    "--user-id",
    action="append",
    default=[],
    help="Explicit session user_id to include (can be passed multiple times).",
  )
  args = parser.parse_args()

  load_dotenv("/root/mem0-local/.env")
  user_ids = set()
  user_ids.update(collect_session_user_ids(args.hours, ["mem0-local.service", "openclaw-gateway.service", *args.unit]))
  user_ids.update(uid.strip() for uid in args.user_id if uid and uid.strip().startswith("session:"))

  if not user_ids:
    print("No session:* user_id found.")
    return 0

  print("Candidate session user_ids:")
  for user_id in sorted(user_ids):
    print(f"- {user_id}")

  if not args.apply:
    print("\nDry-run mode. Re-run with --apply to delete these user_ids from Mem0.")
    return 0

  try:
    from mem0 import Memory
  except Exception as exc:
    print(f"Failed to import mem0 SDK: {exc}", file=sys.stderr)
    print("Use the mem0 virtualenv python, e.g. /root/mem0-local/.venv/bin/python cleanup_session_userids.py", file=sys.stderr)
    return 2

  memory = Memory.from_config(_build_config())
  deleted = 0
  for user_id in sorted(user_ids):
    try:
      memory.delete_all(user_id=user_id)
      deleted += 1
      print(f"deleted: {user_id}")
    except Exception as exc:
      print(f"failed: {user_id} -> {exc}", file=sys.stderr)

  print(f"\nDone. deleted={deleted}, total={len(user_ids)}")
  return 0


if __name__ == "__main__":
  raise SystemExit(main())
