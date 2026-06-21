from __future__ import annotations

import os
import uuid
from typing import Any, Dict, List, Optional

import chromadb

from ..embeddings import EmbeddingModel
from ..types import RetrievedChunk
from .base import VectorStore


class ChromaVectorStore(VectorStore):
    """ChromaDB persistent store.

    Notes:
    - We pass our own embeddings to keep behavior consistent with FAISS.
    - Requires a persistent directory and a collection name.
    """

    def __init__(
        self,
        *,
        persist_dir: str,
        collection_name: str = "solar_panel_knowledge",
        embedding_model: Optional[EmbeddingModel] = None,
    ):
        self.persist_dir = persist_dir
        self.collection_name = collection_name
        self.embedding_model = embedding_model or EmbeddingModel()

        os.makedirs(self.persist_dir, exist_ok=True)
        self._client = chromadb.PersistentClient(path=self.persist_dir)
        self._collection = self._client.get_or_create_collection(name=self.collection_name)

    def add_texts(self, texts: List[str], metadatas: Optional[List[Dict[str, Any]]] = None) -> None:
        if not texts:
            return
        if metadatas is None:
            metadatas = [{} for _ in texts]
        if len(metadatas) != len(texts):
            raise ValueError("metadatas length must match texts length")

        embeddings = self.embedding_model.embed_texts(texts).tolist()
        ids = [str(uuid.uuid4()) for _ in texts]

        self._collection.add(
            ids=ids,
            documents=texts,
            metadatas=metadatas,
            embeddings=embeddings,
        )

    def similarity_search(self, query: str, *, k: int) -> List[RetrievedChunk]:
        q_emb = self.embedding_model.embed_texts([query]).tolist()[0]
        res = self._collection.query(
            query_embeddings=[q_emb],
            n_results=k,
            include=["documents", "metadatas", "distances"],
        )

        # Chroma returns distances (smaller = closer). We convert to a score-like value.
        docs = res.get("documents", [[]])[0]
        metas = res.get("metadatas", [[]])[0]
        dists = res.get("distances", [[]])[0]

        out: List[RetrievedChunk] = []
        for doc, meta, dist in zip(docs, metas, dists):
            score = float(1.0 / (1.0 + float(dist)))
            out.append(RetrievedChunk(text=doc, score=score, metadata=meta or {}))
        return out
