from __future__ import annotations

from typing import Any, Dict, List, Optional

from .types import RetrievedChunk
from .vectorstores.base import VectorStore


def build_query_from_ml_output(model_output: Dict[str, Any]) -> str:
    """Convert your classifier output JSON into a text query.

    Important:
    - We do *not* make decisions here.
    - We only form a retrieval query to fetch relevant SOP/threshold/impact facts.

    Expected model_output example keys:
    - panel_id
    - primary_defect
    - confidence
    - top_predictions: [{label, score}, ...]
    """

    panel_id = model_output.get("panel_id")
    primary_defect = model_output.get("primary_defect")
    confidence = model_output.get("confidence")
    top_predictions = model_output.get("top_predictions") or []

    top_str = ", ".join(
        f"{p.get('label')} ({p.get('score')})" for p in top_predictions if isinstance(p, dict)
    )

    # The query is intentionally phrased to match domain knowledge sections.
    parts: List[str] = [
        "solar panel defect knowledge",
        f"primary_defect: {primary_defect}",
        f"confidence: {confidence}",
        f"top_predictions: {top_str}",
    ]
    if panel_id is not None:
        parts.append(f"panel_id: {panel_id}")

    parts.extend(
        [
            "impact and risk",
            "maintenance SOP",
            "decision thresholds",
            "cleaning isolation replacement criteria",
        ]
    )

    return "\n".join(str(p) for p in parts if p is not None)


def format_retrieved_context(chunks: List[RetrievedChunk]) -> str:
    """Return retrieved context as plain text (no JSON), ready to pass to Gemini.

    This is deliberately LLM-friendly:
    - includes source metadata
    - separates chunks clearly
    - keeps content unchanged (no decisions, no summarization)
    """

    if not chunks:
        return ""

    blocks: List[str] = []
    for i, ch in enumerate(chunks, start=1):
        src = ch.metadata.get("source", "unknown")
        blocks.append(f"[CONTEXT {i} | source={src} | score={ch.score:.4f}]\n{ch.text}")

    return "\n\n---\n\n".join(blocks)


def query_rag(
    store: VectorStore,
    *,
    model_output: Dict[str, Any],
    k: int = 10,
) -> str:
    """Main entry point: ML output -> retrieval -> plain text context.

    Flow (end-to-end):
    1) ResNet output JSON
    2) build_query_from_ml_output(...) => a text query
    3) store.similarity_search(query, k)
    4) format_retrieved_context(...) => plain text for Gemini prompt assembly

    We intentionally return only context. Another layer (outside RAG) can:
    - combine this context with the raw ML output
    - call Gemini to reason and decide actions
    """

    query = build_query_from_ml_output(model_output)
    retrieved = store.similarity_search(query, k=k)
    return format_retrieved_context(retrieved)
