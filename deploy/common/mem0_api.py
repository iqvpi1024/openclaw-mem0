import os
import logging
from functools import lru_cache
from typing import Any, Dict, Optional

from dotenv import load_dotenv
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel, Field

from mem0 import Memory

load_dotenv()

app = FastAPI(title="mem0 Local API", version="1.0")
logger = logging.getLogger("mem0-local")


class AddRequest(BaseModel):
    user_id: str = Field(..., min_length=1)
    text: str = Field(..., min_length=1)
    metadata: Optional[Dict[str, Any]] = None
    infer: bool = True
    prompt: Optional[str] = None


class SearchRequest(BaseModel):
    user_id: str = Field(..., min_length=1)
    query: str = Field(..., min_length=1)
    limit: int = Field(5, ge=1, le=100)


def _as_int(name: str, default: int) -> int:
    value = os.getenv(name, str(default))
    try:
        return int(value)
    except ValueError as exc:
        raise RuntimeError(f"{name} must be an integer, got: {value}") from exc


def _build_config() -> Dict[str, Any]:
    llm_provider = os.getenv("MEM0_LLM_PROVIDER", "openai").strip().lower()
    embedder_provider = os.getenv("MEM0_EMBEDDER_PROVIDER", "openai").strip().lower()

    if ("openai" in {llm_provider, embedder_provider}) and not os.getenv("OPENAI_API_KEY"):
        raise RuntimeError("OPENAI_API_KEY is required when using OpenAI llm/embedder providers.")

    qdrant_path = os.getenv("MEM0_QDRANT_PATH", "./data/qdrant")
    history_db_path = os.getenv("MEM0_HISTORY_DB_PATH", "./data/history.db")
    os.makedirs(os.path.dirname(qdrant_path) or ".", exist_ok=True)
    os.makedirs(os.path.dirname(history_db_path) or ".", exist_ok=True)

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
                "path": qdrant_path,
                "embedding_model_dims": _as_int("MEM0_EMBEDDING_DIMS", default_dims),
            },
        },
        "history_db_path": history_db_path,
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
        model_kwargs: Dict[str, Any] = {}
        hf_device = os.getenv("MEM0_HF_DEVICE", "").strip()
        if hf_device:
            model_kwargs["device"] = hf_device
        if model_kwargs:
            embedder_config["model_kwargs"] = model_kwargs
    else:
        embedder_config["model"] = os.getenv("MEM0_EMBEDDER_MODEL", "text-embedding-3-small")

    return config


@lru_cache(maxsize=1)
def get_memory() -> Memory:
    return Memory.from_config(_build_config())


def _health_payload() -> Dict[str, Any]:
    try:
        get_memory()
        return {
            "status": "ok",
            "vector_store": "qdrant(local)",
            "llm_provider": os.getenv("MEM0_LLM_PROVIDER", "openai"),
            "embedder_provider": os.getenv("MEM0_EMBEDDER_PROVIDER", "openai"),
        }
    except Exception as exc:
        return {"status": "error", "error": str(exc)}


def _extract_results_length(payload: Any) -> int:
    if isinstance(payload, list):
        return len(payload)
    if isinstance(payload, dict):
        items = payload.get("results")
        if isinstance(items, list):
            return len(items)
    return 0


@app.get("/health")
def health() -> Dict[str, Any]:
    return _health_payload()


@app.post("/memory/add")
def add_memory(request: AddRequest) -> Dict[str, Any]:
    memory = get_memory()
    metadata = request.metadata or {}
    logger.warning(
        "memory.add user_id=%s infer=%s stage=%s text_len=%s",
        request.user_id,
        request.infer,
        str(metadata.get("stage", "")),
        len(request.text),
    )

    try:
        result = memory.add(
            request.text,
            user_id=request.user_id,
            metadata=metadata,
            infer=request.infer,
            prompt=request.prompt,
        )
        used_raw_fallback = False
        # Ensure "full instruction persistence": if semantic extraction returns empty, persist raw text.
        if request.infer and _extract_results_length(result) == 0:
            raw_metadata = dict(metadata)
            raw_metadata["mem0_fallback"] = "infer_empty"
            raw_metadata["mem0_infer_prompt"] = request.prompt or ""
            raw_result = memory.add(
                request.text,
                user_id=request.user_id,
                metadata=raw_metadata,
                infer=False,
                prompt=None,
            )
            used_raw_fallback = True
            result = {
                "semantic": result,
                "raw_fallback": raw_result,
            }
            logger.warning("memory.add fallback infer_empty user_id=%s", request.user_id)

        return {"status": "ok", "result": result, "raw_fallback": used_raw_fallback}
    except Exception as exc:
        error_text = str(exc)
        # mem0 may persist vector data successfully but fail history sqlite write.
        # Treat it as success when the just-written text is already searchable.
        if "readonly database" in error_text.lower():
            try:
                verify = memory.search(request.text, user_id=request.user_id, limit=5)
                candidates = verify.get("results") if isinstance(verify, dict) else verify
                if isinstance(candidates, list):
                    for item in candidates:
                        text = ""
                        if isinstance(item, dict):
                            text = str(item.get("memory") or item.get("text") or "")
                        elif isinstance(item, str):
                            text = item
                        if text.strip() == request.text.strip():
                            logger.warning(
                                "memory.add readonly-but-present user_id=%s stage=%s",
                                request.user_id,
                                str(metadata.get("stage", "")),
                            )
                            return {
                                "status": "ok",
                                "result": {
                                    "warning": error_text,
                                    "recovered": "vector_store_persisted",
                                },
                                "raw_fallback": False,
                            }
            except Exception:
                pass

        if request.infer:
            try:
                raw_metadata = dict(metadata)
                raw_metadata["mem0_fallback"] = "infer_error"
                raw_metadata["mem0_infer_prompt"] = request.prompt or ""
                raw_result = memory.add(
                    request.text,
                    user_id=request.user_id,
                    metadata=raw_metadata,
                    infer=False,
                    prompt=None,
                )
                logger.warning(
                    "memory.add infer_error fallback user_id=%s error=%s",
                    request.user_id,
                    str(exc),
                )
                return {
                    "status": "ok",
                    "result": {
                        "semantic_error": error_text,
                        "raw_fallback": raw_result,
                    },
                    "raw_fallback": True,
                }
            except Exception:
                pass
        raise HTTPException(status_code=503, detail=error_text) from exc


@app.post("/memory/search")
def search_memory(request: SearchRequest) -> Dict[str, Any]:
    logger.warning(
        "memory.search user_id=%s query_len=%s limit=%s",
        request.user_id,
        len(request.query),
        request.limit,
    )
    try:
        result = get_memory().search(
            request.query,
            user_id=request.user_id,
            limit=request.limit,
        )
        return {"status": "ok", "result": result}
    except Exception as exc:
        raise HTTPException(status_code=503, detail=str(exc)) from exc


@app.get("/memory/all/{user_id}")
def list_memories(user_id: str) -> Dict[str, Any]:
    try:
        result = get_memory().get_all(user_id=user_id)
        return {"status": "ok", "result": result}
    except Exception as exc:
        raise HTTPException(status_code=503, detail=str(exc)) from exc
