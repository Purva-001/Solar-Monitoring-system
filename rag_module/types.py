from __future__ import annotations

from dataclasses import dataclass
from typing import Any, Dict, Optional


@dataclass(frozen=True)
class DocumentChunk:
    text: str
    metadata: Dict[str, Any]


@dataclass(frozen=True)
class RetrievedChunk:
    text: str
    score: float
    metadata: Dict[str, Any]

    @property
    def source(self) -> Optional[str]:
        src = self.metadata.get("source")
        return str(src) if src is not None else None
