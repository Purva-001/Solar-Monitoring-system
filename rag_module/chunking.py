from __future__ import annotations

from typing import List


def chunk_text(text: str, *, chunk_size: int = 600, chunk_overlap: int = 80) -> List[str]:
    

    cleaned = "\n".join(line.rstrip() for line in text.splitlines()).strip()
    if not cleaned:
        return []

    chunks: List[str] = []
    start = 0
    while start < len(cleaned):
        end = min(len(cleaned), start + chunk_size)
        chunk = cleaned[start:end].strip()
        if chunk:
            chunks.append(chunk)
        if end == len(cleaned):
            break
        start = max(0, end - chunk_overlap)

    return chunks
