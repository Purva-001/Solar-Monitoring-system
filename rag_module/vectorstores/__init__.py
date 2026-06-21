from .base import VectorStore
from .chroma_store import ChromaVectorStore

try:
    from .faiss_store import FaissVectorStore
except Exception:  # pragma: no cover
    class FaissVectorStore:  # type: ignore
        def __init__(self, *args, **kwargs):
            raise ImportError(
                "FaissVectorStore requires the 'faiss' module, which is not installed. "
                "On Windows, FAISS is commonly installed via conda; otherwise switch backend to 'chroma'."
            )

__all__ = ["VectorStore", "FaissVectorStore", "ChromaVectorStore"]
