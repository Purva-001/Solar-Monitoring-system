from __future__ import annotations

import json
import os
from dataclasses import asdict
from typing import Any, Dict, List, Optional

import faiss
import numpy as np

from ..embeddings import EmbeddingModel
from ..types import RetrievedChunk
from .base import VectorStore


class FaissVectorStore(VectorStore):
    """FAISS store using cosine similarity (via inner product on normalized vectors).

    Persistence layout:
    - <persist_dir>/index.faiss
    - <persist_dir>/docs.jsonl   (one JSON per chunk: {"text": ..., "metadata": ...})
    """

    def __init__(self, *, persist_dir: str, embedding_model: Optional[EmbeddingModel] = None):
        self.persist_dir = persist_dir
        self.embedding_model = embedding_model or EmbeddingModel()

        os.makedirs(self.persist_dir, exist_ok=True)

        self._index_path = os.path.join(self.persist_dir, "index.faiss")
        self._docs_path = os.path.join(self.persist_dir, "docs.jsonl")

        self._docs: List[Dict[str, Any]] = []
        self._index: Optional[faiss.Index] = None

        self._load_if_exists()

    def _load_if_exists(self) -> None:
        if os.path.exists(self._index_path) and os.path.exists(self._docs_path):
            self._index = faiss.read_index(self._index_path)
            self._docs = []
            with open(self._docs_path, "r", encoding="utf-8") as f:
                for line in f:
                    line = line.strip()
                    if line:
                        self._docs.append(json.loads(line))

    def _ensure_index(self, dim: int) -> None:
        if self._index is None:
            # IndexFlatIP uses inner product; with normalized embeddings, this equals cosine similarity.
            self._index = faiss.IndexFlatIP(dim)

    def _persist(self) -> None:
        if self._index is None:
            return
        faiss.write_index(self._index, self._index_path)
        with open(self._docs_path, "w", encoding="utf-8") as f:
            for doc in self._docs:
                f.write(json.dumps(doc, ensure_ascii=False) + "\n")

    def add_texts(self, texts: List[str], metadatas: Optional[List[Dict[str, Any]]] = None) -> None:
        if not texts:
            return
        if metadatas is None:
            metadatas = [{} for _ in texts]
        if len(metadatas) != len(texts):
            raise ValueError("metadatas length must match texts length")

        vectors = self.embedding_model.embed_texts(texts)
        self._ensure_index(vectors.shape[1])

        self._index.add(vectors)
        for t, m in zip(texts, metadatas):
            self._docs.append({"text": t, "metadata": m})

        self._persist()

    def similarity_search(self, query: str, *, k: int) -> List[RetrievedChunk]:
        if self._index is None or not self._docs:
            return []

        q = self.embedding_model.embed_texts([query])
        scores, indices = self._index.search(q, k)

        out: List[RetrievedChunk] = []
        for score, idx in zip(scores[0].tolist(), indices[0].tolist()):
            if idx == -1:
                continue
            doc = self._docs[idx]
            out.append(RetrievedChunk(text=doc["text"], score=float(score), metadata=doc.get("metadata", {})))
        return out
