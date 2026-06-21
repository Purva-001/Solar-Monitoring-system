from __future__ import annotations

from typing import Any, Dict, Iterable, List, Optional

from .chunking import chunk_text
from .types import DocumentChunk
from .vectorstores.base import VectorStore


def ingest_knowledge(
    store: VectorStore,
    *,
    knowledge_texts: List[str],
    sources: Optional[List[str]] = None,
    chunk_size: int = 1200,
    chunk_overlap: int = 200,
) -> int:
   

    if sources is None:
        sources = ["knowledge" for _ in knowledge_texts]
    if len(sources) != len(knowledge_texts):
        raise ValueError("sources length must match knowledge_texts length")

    chunks: List[DocumentChunk] = []
    for text, source in zip(knowledge_texts, sources):
        for i, c in enumerate(chunk_text(text, chunk_size=chunk_size, chunk_overlap=chunk_overlap)):
            chunks.append(DocumentChunk(text=c, metadata={"source": source, "chunk_index": i}))

    store.add_texts(
        [c.text for c in chunks],
        metadatas=[c.metadata for c in chunks],
    )

    return len(chunks)


def ingest_knowledge_lines(
    store: VectorStore,
    *,
    lines: Iterable[str],
    source: str,
    chunk_size: int = 600,
    chunk_overlap: int = 80,
) -> int:
    """Convenience ingestion for a single text file's lines."""

    text = "".join(lines)
    return ingest_knowledge(
        store,
        knowledge_texts=[text],
        sources=[source],
        chunk_size=chunk_size,
        chunk_overlap=chunk_overlap,
    )
