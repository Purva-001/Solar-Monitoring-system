
import sys
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parents[1]
if str(PROJECT_ROOT) not in sys.path:
    sys.path.insert(0, str(PROJECT_ROOT))

from rag_module.ingest import ingest_knowledge
from rag_module.vectorstores import ChromaVectorStore, FaissVectorStore


def main() -> None:
    backend = "chroma"  # change to "faiss" if you have FAISS installed

    knowledge_path = Path(__file__).resolve().parents[1] / "knowledge" / "example_knowledge.txt"
    knowledge_text = knowledge_path.read_text(encoding="utf-8")

    if backend == "faiss":
        store = FaissVectorStore(persist_dir=str(Path(__file__).resolve().parents[1] / "vector_db" / "faiss"))
    else:
        store = ChromaVectorStore(persist_dir=str(Path(__file__).resolve().parents[1] / "vector_db" / "chroma"))

    n_chunks = ingest_knowledge(
        store,
        knowledge_texts=[knowledge_text],
        sources=["example_knowledge.txt"],
    )

    print(f"Ingested {n_chunks} chunks into {backend}.")


if __name__ == "__main__":
    main()
