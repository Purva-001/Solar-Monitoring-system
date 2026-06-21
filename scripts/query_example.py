import json
import sys
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parents[1]
if str(PROJECT_ROOT) not in sys.path:
    sys.path.insert(0, str(PROJECT_ROOT))

from rag_module.query import query_rag
from rag_module.vectorstores import ChromaVectorStore, FaissVectorStore


def main() -> None:
    backend = "chroma"  # change to "faiss" if you have FAISS installed

    if backend == "faiss":
        store = FaissVectorStore(persist_dir=str(Path(__file__).resolve().parents[1] / "vector_db" / "faiss"))
    else:
        store = ChromaVectorStore(persist_dir=str(Path(__file__).resolve().parents[1] / "vector_db" / "chroma"))

    model_output = {
        "panel_id": "Panel-01",
        "primary_defect": "Dusty",
        "confidence": 0.41,
        "top_predictions": [
            {"label": "Dusty", "score": 0.41},
            {"label": "Bird-drop", "score": 0.36},
            {"label": "Physical-Damage", "score": 0.13},
        ],
    }

    context_text = query_rag(store, model_output=model_output, k=5)

    # Plain text output intended to be appended to a Gemini prompt in a later stage.
    print("\n=== RETRIEVED CONTEXT (PLAIN TEXT) ===\n")
    print(context_text)


if __name__ == "__main__":
    main()
