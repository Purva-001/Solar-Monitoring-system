from __future__ import annotations

from abc import ABC, abstractmethod
from typing import Any, Dict, List, Optional

from ..types import RetrievedChunk


class VectorStore(ABC):
    """Vector store contract.

    RAG responsibilities here:
    - store factual/company knowledge text
    - retrieve relevant text chunks

    Not allowed here:
    - making operational decisions (clean/isolate/replace)
    - calling Gemini / any LLM
    """

    @abstractmethod
    def add_texts(self, texts: List[str], metadatas: Optional[List[Dict[str, Any]]] = None) -> None:
        raise NotImplementedError

    @abstractmethod
    def similarity_search(self, query: str, *, k: int) -> List[RetrievedChunk]:
        raise NotImplementedError
