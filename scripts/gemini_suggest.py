import json
import os
import re
import sys
import time
from pathlib import Path

import requests
from dotenv import load_dotenv

PROJECT_ROOT = Path(__file__).resolve().parents[1]
if str(PROJECT_ROOT) not in sys.path:
    sys.path.insert(0, str(PROJECT_ROOT))

from rag_module.query import query_rag
from rag_module.vectorstores import ChromaVectorStore


TRANSIENT_STATUS_CODES = {429, 500, 502, 503, 504}


def _parse_retry_delay_seconds(error_body: str) -> float | None:
    """Best-effort parse of RetryInfo.retryDelay like '48s' from Gemini error JSON."""

    try:
        data = json.loads(error_body)
        details = (data.get("error") or {}).get("details") or []
        for d in details:
            if isinstance(d, dict) and d.get("@type", "").endswith("RetryInfo"):
                delay = d.get("retryDelay")
                if isinstance(delay, str):
                    m = re.match(r"^(\d+(?:\.\d+)?)s$", delay.strip())
                    if m:
                        return float(m.group(1))
    except Exception:
        return None
    return None


def build_gemini_prompt(*, model_output: dict, retrieved_context: str, min_words: int, bullets_per_section: int) -> str:
    return (
        "You are an assistant for solar PV operations.\n"
        "Use ONLY the retrieved company/SOP/threshold context below.\n"
        "If the context is insufficient, say what is missing and recommend an inspection step to gather facts.\n"
        "Do NOT invent policies, thresholds, or procedures.\n"
        "Where relevant, cite the context block like [CONTEXT 2].\n"
        "Safety: do not give dangerous or urgent commands; phrase guidance as 'follow SOP' / 'have a qualified technician verify'.\n\n"
        "Output requirements (must follow):\n"
        f"- Write at least {min_words} words.\n"
        "- Include all 5 numbered sections below, even if some sections must say 'Not found in retrieved context'.\n"
        f"- In sections 2, 3, and 4 include at least {bullets_per_section} bullet points each.\n"
        "- Every bullet that mentions a fact/procedure/threshold must cite [CONTEXT n].\n\n"
        "Formatting requirements (must follow):\n"
        "- Do NOT include any preamble, greeting, or title.\n"
        "- Start your output with exactly: '1) Interpretation of ML output'.\n\n"
        "INPUT: ML MODEL OUTPUT (JSON)\n"
        f"{json.dumps(model_output, indent=2)}\n\n"
        "RETRIEVED CONTEXT (verbatim)\n"
        f"{retrieved_context}\n\n"
        "TASK\n"
        "Provide a detailed, practical suggestion for a technician/supervisor (company-SOP aligned).\n"
        "Structure your answer exactly like this:\n"
        "1) Interpretation of ML output (uncertainty-aware; mention top-2 closeness if applicable)\n"
        "2) Applicable impact/risk facts (cite [CONTEXT n])\n"
        "3) Applicable SOP steps to reference (cite [CONTEXT n])\n"
        "4) Recommended next checks for a human to perform (no automation; do not claim confirmation)\n"
        "5) What would change the recommendation (what additional info/inspection results are needed)\n"
    )


def build_gemini_continue_prompt(
    *,
    partial_answer: str,
    retrieved_context: str,
    min_words: int,
    bullets_per_section: int,
) -> str:
    """Ask Gemini to continue without repeating the already generated text."""

    return (
        "Continue the answer below WITHOUT repeating any existing text.\n"
        "Use ONLY the retrieved context provided. Do NOT invent policies, thresholds, or procedures.\n"
        "Cite sources like [CONTEXT 2] when stating facts/procedures/thresholds.\n\n"
        "Output requirements (must follow):\n"
        f"- Total answer must be at least {min_words} words.\n"
        "- Must contain all 5 numbered sections (1..5).\n"
        f"- Sections 2, 3, and 4 must each contain at least {bullets_per_section} bullet points.\n\n"
        "ALREADY GENERATED (do not repeat):\n"
        f"{partial_answer}\n\n"
        "RETRIEVED CONTEXT (verbatim):\n"
        f"{retrieved_context}\n\n"
        "Now continue from exactly where it cuts off and complete the missing sections." 
    )


def call_gemini(*, api_key: str, model: str, prompt: str, max_output_tokens: int) -> tuple[str, str | None]:
    url = f"https://generativelanguage.googleapis.com/v1beta/{model}:generateContent?key={api_key}"

    payload = {
        "contents": [
            {
                "role": "user",
                "parts": [{"text": prompt}],
            }
        ],
        "generationConfig": {
            "temperature": 0.3,
            "maxOutputTokens": max_output_tokens,
        },
    }

    last_exc: Exception | None = None
    last_status_code: int | None = None
    last_body: str | None = None
    for attempt in range(1, 4):
        try:
            resp = requests.post(url, json=payload, timeout=120)
            last_status_code = resp.status_code
            last_body = resp.text
            if resp.status_code == 200:
                try:
                    data = resp.json()
                except Exception as e:  # JSON decode error or unexpected content
                    last_exc = e
                    time.sleep(1.5 * attempt)
                    continue
                break

            # Retry on transient errors.
            if resp.status_code in TRANSIENT_STATUS_CODES:
                if resp.status_code == 429 and last_body:
                    retry_after = _parse_retry_delay_seconds(last_body)
                    if retry_after is not None:
                        time.sleep(min(retry_after, 90.0))
                    else:
                        time.sleep(2.0 * attempt)
                else:
                    time.sleep(1.5 * attempt)
                continue

            raise RuntimeError(f"Gemini API error {resp.status_code}: {resp.text}")
        except (requests.Timeout, requests.ConnectionError) as e:
            last_exc = e
            time.sleep(1.5 * attempt)
    else:
        raise RuntimeError(
            "Gemini request failed after retries. "
            f"last_status_code={last_status_code} last_exception={last_exc} last_response_body={last_body}"
        )

    candidates = data.get("candidates") or []
    if not candidates:
        return "", None

    finish_reason = candidates[0].get("finishReason")
    content = candidates[0].get("content") or {}
    parts = content.get("parts") or []
    if not parts:
        return "", finish_reason

    texts = [p.get("text", "") for p in parts if isinstance(p, dict)]
    return "".join(texts).strip(), finish_reason


def main() -> None:
    # Load variables from .env in the project root (and also from current working directory if present).
    load_dotenv(PROJECT_ROOT / ".env")
    load_dotenv()

    api_key = os.getenv("GEMINI_API_KEY")
    if not api_key:
        raise RuntimeError("GEMINI_API_KEY is not set. Set it in your environment before running.")

    model = os.getenv("GEMINI_MODEL")
    models_to_try: list[str]
    if model:
        models_to_try = [model]
    else:
        models_csv = os.getenv("GEMINI_MODELS", "").strip()
        if models_csv:
            models = [m.strip() for m in models_csv.split(",") if m.strip()]
            prefer_pro = os.getenv("GEMINI_PREFER_PRO", "0").strip() in ("1", "true", "TRUE", "yes", "YES")
            pro = [m for m in models if "pro" in m]
            flash = [m for m in models if "flash" in m and m not in pro]
            other = [m for m in models if m not in pro and m not in flash]

            # Default: prefer flash (more available on free tier / higher RPM), then others, then pro.
            # Opt-in: set GEMINI_PREFER_PRO=1 to try pro first.
            models_to_try = (pro + flash + other) if prefer_pro else (flash + other + pro)
        else:
            models_to_try = ["models/gemini-2.5-flash"]

    # Trying multiple models can burn quota quickly. Keep it off by default.
    try_all_models = os.getenv("GEMINI_TRY_ALL_MODELS", "0").strip() in ("1", "true", "TRUE", "yes", "YES")
    if not try_all_models:
        models_to_try = models_to_try[:1]

    store = ChromaVectorStore(persist_dir=str(PROJECT_ROOT / "vector_db" / "chroma"))

    # Output sizing knobs (increase carefully if you hit 429 quota/rate limits).
    min_words = int(os.getenv("GEMINI_MIN_WORDS", "300"))
    bullets_per_section = int(os.getenv("GEMINI_BULLETS_PER_SECTION", "4"))
    max_output_tokens = int(os.getenv("GEMINI_MAX_OUTPUT_TOKENS", "1800"))
    max_passes = int(os.getenv("GEMINI_MAX_PASSES", "2"))

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

    rag_k = int(os.getenv("GEMINI_RAG_K", "3"))
    retrieved_context = query_rag(store, model_output=model_output, k=rag_k)

    max_context_chars = int(os.getenv("GEMINI_MAX_CONTEXT_CHARS", "6000"))
    if len(retrieved_context) > max_context_chars:
        retrieved_context = retrieved_context[:max_context_chars].rstrip() + "\n\n[TRUNCATED CONTEXT]"
    prompt = build_gemini_prompt(
        model_output=model_output,
        retrieved_context=retrieved_context,
        min_words=min_words,
        bullets_per_section=bullets_per_section,
    )

    print("\n=== GEMINI SUGGESTION ===\n")
    suggestion: str | None = None
    model_used: str | None = None
    last_error: Exception | None = None
    for m in models_to_try:
        try:
            suggestion, _finish = call_gemini(api_key=api_key, model=m, prompt=prompt, max_output_tokens=max_output_tokens)
            model_used = m
            break
        except Exception as e:
            last_error = e
            continue
    if suggestion is None:
        raise RuntimeError(f"All Gemini models failed: {models_to_try}. Last error: {last_error}")

    # If the model returns a very short/truncated answer, try to continue for a limited number of passes.
    passes_done = 1
    while passes_done < max_passes:
        has_all_sections = all(f"{i})" in suggestion for i in (1, 2, 3, 4, 5))
        word_count = len(suggestion.split())
        if has_all_sections and word_count >= min_words:
            break

        continue_prompt = build_gemini_continue_prompt(
            partial_answer=suggestion,
            retrieved_context=retrieved_context,
            min_words=min_words,
            bullets_per_section=bullets_per_section,
        )
        more_text, _finish = call_gemini(
            api_key=api_key,
            model=model_used or models_to_try[0],
            prompt=continue_prompt,
            max_output_tokens=max_output_tokens,
        )
        if not more_text:
            break
        suggestion = (suggestion.rstrip() + "\n\n" + more_text.lstrip()).strip()
        passes_done += 1

    out_dir = PROJECT_ROOT / "outputs"
    out_dir.mkdir(parents=True, exist_ok=True)
    out_path = out_dir / "gemini_suggestion.txt"
    out_path.write_text(suggestion + "\n", encoding="utf-8")

    print(suggestion)
    if model_used:
        print(f"\n[Model used: {model_used}]")
    print(f"\n[Saved full output to: {out_path}]")


if __name__ == "__main__":
    main()
