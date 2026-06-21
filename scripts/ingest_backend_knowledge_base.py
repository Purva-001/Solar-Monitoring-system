import argparse
import sys
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parents[1]
if str(PROJECT_ROOT) not in sys.path:
    sys.path.insert(0, str(PROJECT_ROOT))

from backend.rag import _extract_text_from_knowledge_file  # noqa: E402
from rag_module.ingest import ingest_knowledge  # noqa: E402
from rag_module.vectorstores import ChromaVectorStore  # noqa: E402


def main() -> None:
    parser = argparse.ArgumentParser(description="Ingest backend/knowledge_base PDFs/TXTs into Chroma vector DB")
    parser.add_argument(
        "--knowledge-dir",
        default=str(PROJECT_ROOT / "backend" / "knowledge_base"),
        help="Directory containing .pdf/.txt knowledge files",
    )
    parser.add_argument(
        "--persist-dir",
        default=str(PROJECT_ROOT / "vector_db" / "chroma"),
        help="Chroma persistent directory",
    )
    parser.add_argument(
        "--collection",
        default="solar_panel_knowledge",
        help="Chroma collection name",
    )
    parser.add_argument("--k", type=int, default=10, help="Unused (kept for compatibility)")
    parser.add_argument("--chunk-size", type=int, default=1200)
    parser.add_argument("--chunk-overlap", type=int, default=200)

    args = parser.parse_args()

    knowledge_dir = Path(args.knowledge_dir)
    if not knowledge_dir.exists():
        raise SystemExit(f"Knowledge directory not found: {knowledge_dir}")

    files = sorted(list(knowledge_dir.glob("*.txt")) + list(knowledge_dir.glob("*.pdf")))
    if not files:
        raise SystemExit(f"No .txt/.pdf files found in: {knowledge_dir}")

    texts = []
    sources = []
    for fp in files:
        print(f"[ingest] extracting: {fp.name}")
        content = _extract_text_from_knowledge_file(fp)
        if content and content.strip():
            texts.append(content)
            sources.append(fp.name)
        else:
            print(f"[ingest] warning: no extracted content for: {fp.name}")

    store = ChromaVectorStore(persist_dir=args.persist_dir, collection_name=args.collection)

    n_chunks = ingest_knowledge(
        store,
        knowledge_texts=texts,
        sources=sources,
        chunk_size=args.chunk_size,
        chunk_overlap=args.chunk_overlap,
    )

    print(f"[ingest] done: stored {n_chunks} chunks")
    print(f"[ingest] persist_dir: {args.persist_dir}")
    print(f"[ingest] collection: {args.collection}")


if __name__ == "__main__":
    main()
