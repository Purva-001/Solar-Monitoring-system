from __future__ import annotations

import re
from typing import List

import numpy as np


class EmbeddingModel:
    """Small wrapper around SentenceTransformers.

    Notes:
    - We compute embeddings inside the app so both FAISS and Chroma backends behave the same.
    - Embeddings are L2-normalized so inner product ~= cosine similarity.
    """

    def __init__(self, dim: int = 384):
        self.dim = int(dim)

    def embed_texts(self, texts: List[str]) -> np.ndarray:
        if not texts:
            return np.zeros((0, self.dim), dtype="float32")

        mat = np.zeros((len(texts), self.dim), dtype="float32")
        for i, t in enumerate(texts):
            if not t:
                continue
            for tok in re.findall(r"[a-z0-9_\-/]+", t.lower()):
                # Stable hashed bag-of-words embedding.
                # This is a lightweight fallback to keep the project PyTorch-free.
                h = 0
                for ch in tok:
                    h = (h * 131 + ord(ch)) & 0xFFFFFFFF
                mat[i, h % self.dim] += 1.0

        norms = np.linalg.norm(mat, axis=1, keepdims=True)
        norms[norms == 0.0] = 1.0
        mat = mat / norms
        return mat.astype("float32")
