from __future__ import annotations

from pathlib import Path
import json
import hashlib
from typing import Any, Dict, List, Tuple

from rag_module.ingest import ingest_knowledge
from rag_module.query import build_query_from_ml_output, format_retrieved_context
from rag_module.types import RetrievedChunk
from rag_module.vectorstores import ChromaVectorStore

# Try to import PDF extraction tools
try:
    import PyPDF2
    HAS_PYPDF = True
except ImportError:
    HAS_PYPDF = False

try:
    import pdfplumber
    HAS_PDFPLUMBER = True
except ImportError:
    HAS_PDFPLUMBER = False


def _extract_text_from_pdf(pdf_path: Path) -> str:
    """Extract text from PDF file using available libraries."""
    if HAS_PDFPLUMBER:
        try:
            with pdfplumber.open(str(pdf_path)) as pdf:
                text = ""
                for page in pdf.pages:
                    page_text = page.extract_text()
                    if page_text:
                        text += page_text + "\n"
                return text
        except Exception as e:
            print(f"Warning: pdfplumber failed on {pdf_path.name}: {e}")
    
    if HAS_PYPDF:
        try:
            text = ""
            with open(pdf_path, "rb") as f:
                reader = PyPDF2.PdfReader(f)
                for page in reader.pages:
                    text += page.extract_text() + "\n"
            return text
        except Exception as e:
            print(f"Warning: PyPDF2 failed on {pdf_path.name}: {e}")
    
    print(f"Warning: No PDF extraction library available for {pdf_path.name}")
    return f"[PDF file: {pdf_path.name} - content extraction not available]\n"


def _extract_text_from_knowledge_file(file_path: Path) -> str:
    """Extract text from knowledge file (txt or pdf)."""
    if file_path.suffix.lower() == ".pdf":
        return _extract_text_from_pdf(file_path)
    elif file_path.suffix.lower() == ".txt":
        return file_path.read_text(encoding="utf-8")
    else:
        print(f"Warning: Unsupported file type: {file_path.suffix}")
        return ""


PROJECT_ROOT = Path(__file__).resolve().parents[1]
PERSIST_DIR = PROJECT_ROOT / "vector_db" / "chroma"
KNOWLEDGE_DIR = Path(__file__).resolve().parent / "knowledge_base"
COLLECTION_NAME = "solar_panel_knowledge"

_FINGERPRINT_PATH = PERSIST_DIR / "knowledge_fingerprint.json"


def _knowledge_fingerprint() -> str:
    if not KNOWLEDGE_DIR.exists():
        return ""
    files = sorted(list(KNOWLEDGE_DIR.glob("*.txt")) + list(KNOWLEDGE_DIR.glob("*.pdf")))
    h = hashlib.sha256()
    for fp in files:
        try:
            st = fp.stat()
            h.update(fp.name.encode("utf-8"))
            h.update(str(int(st.st_mtime_ns)).encode("utf-8"))
            h.update(str(int(st.st_size)).encode("utf-8"))
        except Exception:
            continue
    return h.hexdigest()


def _read_last_fingerprint() -> str:
    try:
        if _FINGERPRINT_PATH.exists():
            data = json.loads(_FINGERPRINT_PATH.read_text(encoding="utf-8") or "{}")
            if isinstance(data, dict):
                return str(data.get("fingerprint") or "")
    except Exception:
        pass
    return ""


def _write_last_fingerprint(fp: str) -> None:
    try:
        PERSIST_DIR.mkdir(parents=True, exist_ok=True)
        _FINGERPRINT_PATH.write_text(json.dumps({"fingerprint": fp}, indent=2), encoding="utf-8")
    except Exception:
        pass


def get_store() -> ChromaVectorStore:
    return ChromaVectorStore(persist_dir=str(PERSIST_DIR), collection_name=COLLECTION_NAME)


def _format_retrieved_context(chunks: List[RetrievedChunk]) -> str:
    if not chunks:
        return "No relevant knowledge retrieved."

    blocks: List[str] = []
    for i, ch in enumerate(chunks, start=1):
        src = ch.metadata.get("source", "unknown")
        relevance = "Highly Relevant" if ch.score > 0.7 else "Relevant" if ch.score > 0.5 else "Low Relevance"
        header = f"\n{'='*80}\nCONTEXT {i} | Source: {src} | Relevance: {relevance} (Score: {ch.score:.4f})\n{'='*80}\n"
        blocks.append(header + ch.text)
    
    footer = f"\n\n{'='*80}\nEND OF RETRIEVED KNOWLEDGE BASE\n{'='*80}"
    return "".join(blocks) + footer


def retrieve_context_from_model_output(
    *,
    store: ChromaVectorStore,
    model_output: Dict[str, Any],
    k: int = 10,
) -> Tuple[str, str]:
    query = build_query_from_ml_output(model_output)
    chunks = store.similarity_search(query, k=k)

    # Prefer the canonical formatter from rag_module to keep consistent output.
    try:
        context = format_retrieved_context(chunks)
    except Exception:
        context = _format_retrieved_context(chunks)
    return query, context


def ensure_ingested(store: ChromaVectorStore) -> None:
    current_fp = _knowledge_fingerprint()
    last_fp = _read_last_fingerprint()

    # Determine whether we should refresh ingestion.
    refresh = bool(current_fp) and (current_fp != last_fp)

    # Skip ingestion if the persistent collection already has documents and no refresh needed.
    try:
        count = int(store._collection.count())  # type: ignore[attr-defined]
    except Exception:
        count = 0

    if count > 0 and not refresh:
        return

    # If knowledge changed, reset the collection to avoid duplicates.
    if refresh:
        try:
            store._client.delete_collection(name=COLLECTION_NAME)  # type: ignore[attr-defined]
            store._collection = store._client.get_or_create_collection(name=COLLECTION_NAME)  # type: ignore[attr-defined]
        except Exception as e:
            print(f"Warning: failed to reset Chroma collection: {e}")

    if not KNOWLEDGE_DIR.exists():
        raise RuntimeError(f"Knowledge directory not found: {KNOWLEDGE_DIR}")

    # Get all knowledge files (txt and pdf)
    knowledge_files = sorted(list(KNOWLEDGE_DIR.glob("*.txt")) + list(KNOWLEDGE_DIR.glob("*.pdf")))
    if not knowledge_files:
        raise RuntimeError(f"No knowledge files found in: {KNOWLEDGE_DIR}")

    texts: List[str] = []
    sources: List[str] = []
    for file_path in knowledge_files:
        print(f"Processing knowledge file: {file_path.name}")
        content = _extract_text_from_knowledge_file(file_path)
        if content.strip():
            texts.append(content)
            sources.append(file_path.name)
        else:
            print(f"Warning: {file_path.name} extracted no content")

    if texts:
        ingest_knowledge(store, knowledge_texts=texts, sources=sources)
    else:
        raise RuntimeError(f"No content extracted from knowledge files in: {KNOWLEDGE_DIR}")

    if current_fp:
        _write_last_fingerprint(current_fp)

    # Must never be empty after startup.
    try:
        new_count = int(store._collection.count())  # type: ignore[attr-defined]
    except Exception:
        new_count = 0
    if new_count <= 0:
        raise RuntimeError("RAG retrieval is empty after ingestion; check knowledge base ingestion.")


def retrieve_context(*, store: ChromaVectorStore, fault: str, confidence: float, k: int = 3) -> str:
    model_output = {
        "primary_defect": fault,
        "confidence": confidence,
        "top_predictions": [{"label": fault, "score": confidence}],
    }
    _query, context = retrieve_context_from_model_output(store=store, model_output=model_output, k=k)
    return context
