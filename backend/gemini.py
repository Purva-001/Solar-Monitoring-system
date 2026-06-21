from __future__ import annotations

import json
import os
import re
from dataclasses import dataclass
from typing import Any, Dict, Optional

import requests


TRANSIENT_STATUS_CODES = {429, 500, 502, 503, 504}


@dataclass(frozen=True)
class GeminiRateLimit(Exception):
    retry_after_seconds: float


def _parse_retry_delay_seconds(error_body: str) -> Optional[float]:
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


def _get_api_keys() -> list[str]:
    """Extract multiple API keys from environment. Support comma or pipe-separated list."""
    explicit = (os.getenv("GEMINI_API_KEYS") or "").strip()
    if explicit:
        # Support both comma and pipe as separators
        separator = "," if "," in explicit else "|"
        keys = [k.strip() for k in explicit.split(separator) if k.strip()]
        if keys:
            return keys
    
    # Fallback to single key
    single_key = (os.getenv("GEMINI_API_KEY") or "").strip()
    if single_key:
        return [single_key]
    
    return []


def _pick_model() -> str:
    explicit = (os.getenv("GEMINI_MODEL") or "").strip()
    if explicit:
        return explicit

    csv = (os.getenv("GEMINI_MODELS") or "").strip()
    if csv:
        models = [m.strip() for m in csv.split(",") if m.strip()]
        if models:
            return models[0]

    return "models/gemini-2.5-flash"


def build_prompt(*, model_output: Dict[str, Any], rag_context: str) -> str:
    fault = model_output.get("primary_defect")
    confidence = model_output.get("confidence")
    panel_id = model_output.get("panel_id", "Unknown")
    
    # Define defect-specific contexts for more precise LLM guidance
    defect_contexts = {
        "Dusty": {
            "urgency_threshold": 0.7,
            "safety_risk": "Low - accumulation can mask other issues",
            "typical_actions": "Cleaning with deionized water, early morning/evening timing to reduce thermal stress",
            "inspection_focus": "Surface cleanliness, residue verification, cracks under dust",
        },
        "Bird-drop": {
            "urgency_threshold": 0.6,
            "safety_risk": "Medium - can create localized hotspots and mismatch losses",
            "typical_actions": "Careful removal, subsequent cleaning, hotspot monitoring",
            "inspection_focus": "Hotspot development, thermal imaging confirmation, cell integrity",
        },
        "Physical-Damage": {
            "urgency_threshold": 0.5,
            "safety_risk": "High - may cause moisture ingress and rapid performance decline",
            "typical_actions": "Immediate visual assessment, potential electrical isolation",
            "inspection_focus": "Crack severity, encapsulation integrity, frame gaps, conductor exposure",
        },
        "Electrical-damage": {
            "urgency_threshold": 0.4,
            "safety_risk": "Critical - fire hazard, electrical shock risk",
            "typical_actions": "Immediate isolation, professional assessment required, safety protocols",
            "inspection_focus": "Burn marks, discoloration, connector integrity, conductor damage",
        },
        "Snow-Covered": {
            "urgency_threshold": 0.8,
            "safety_risk": "Medium - no immediate electrical hazard, but complete power loss",
            "typical_actions": "Monitor for natural melting, avoid thermal shock from hot water",
            "inspection_focus": "Ice/snow accumulation depth, underlying panel condition after removal",
        },
        "Clean": {
            "urgency_threshold": 1.0,
            "safety_risk": "None - normal operation",
            "typical_actions": "Standard maintenance schedule, no immediate intervention",
            "inspection_focus": "Routine performance monitoring, schedule next maintenance",
        },
    }
    
    defect_info = defect_contexts.get(fault, {})
    urgency_level = _determine_urgency(fault, confidence, defect_info)
    
    return (
        "You are an expert solar PV operations assistant specialized in defect identification and technician guidance.\n"
        "DEFECT TYPE: " + fault + "\n"
        "PANEL ID: " + panel_id + "\n"
        "MODEL CONFIDENCE: {:.1%}\n".format(confidence) +
        "\n"
        "YOUR TASK:\n"
        "1. Analyze the detected defect using the retrieved solar panel knowledge base\n"
        "2. Determine severity, impact, and required actions\n"
        "3. Use ONLY facts from the retrieved knowledge - do NOT invent procedures\n"
        "4. If critical information is missing, explicitly state 'Not found in retrieved knowledge'\n"
        "\n"
        "DEFECT-SPECIFIC CONTEXT:\n"
        "- Defect: " + fault + "\n"
        "- Expected Urgency Threshold: " + str(defect_info.get("urgency_threshold", "N/A")) + "\n"
        "- Safety Risk Level: " + defect_info.get("safety_risk", "Unknown") + "\n"
        "- Typical Maintenance Actions: " + defect_info.get("typical_actions", "Unknown") + "\n"
        "- Critical Inspection Points: " + defect_info.get("inspection_focus", "Unknown") + "\n"
        "\n"
        "OUTPUT FORMAT (STRICTLY FOLLOW):\n"
        "Use GitHub-flavored Markdown. No preamble, no greeting, no emojis.\n"
        "Section headings must be exactly as shown. Use bullet points for details.\n"
        "\n"
        "## Summary\n"
        "| Field | Value |\n"
        "|-------|-------|\n"
        "| **Panel ID** | " + panel_id + " |\n"
        "| **Defect Detected** | " + fault + " |\n"
        "| **Model Confidence** | {:.1%} |\n".format(confidence) +
        "| **Urgency Level** | " + urgency_level + " |\n"
        "| **Action Required** | See immediate actions below |\n"
        "\n"
        "## 1) Defect Analysis\n"
        "### What this defect means:\n"
        "Explain in simple technical language:\n"
        "- Physical description of the defect\n"
        "- Why it occurs on solar panels\n"
        "- Immediate impacts on power generation\n"
        "- Secondary risks (if any)\n"
        "\n"
        "### Expected Power Impact:\n"
        "- Primary impact (e.g., power loss %, performance ratio drop)\n"
        "- Timeline of degradation\n"
        "- Risk of escalation without intervention\n"
        "\n"
        "## 2) Safety Assessment\n"
        "### Immediate Safety Concerns:\n"
        "- Electrical hazard risk (High/Medium/Low/None)\n"
        "- Environmental hazard risk (e.g., thermal shock, avalanche)\n"
        "- Technician safety requirements and PPE\n"
        "- Isolation requirements (if applicable)\n"
        "\n"
        "## 3) Immediate Actions (First 15-30 Minutes)\n"
        "### Do FIRST:\n"
        "1. [First safety/assessment step]\n"
        "2. [Safety isolation/notification if required]\n"
        "3. [Initial visual confirmation]\n"
        "4. [Who to notify and escalation path]\n"
        "5. [Critical next steps]\n"
        "\n"
        "### DO NOT:\n"
        "- [List any warnings about incorrect procedures]\n"
        "- [Safety violations to avoid]\n"
        "\n"
        "## 4) Maintenance Procedure (SOP-Based)\n"
        "### Required Equipment & Materials:\n"
        "- [Tools needed]\n"
        "- [Safety equipment]\n"
        "- [Consumables/consumables]\n"
        "\n"
        "### Step-by-Step Procedure:\n"
        "1. [Preparation step]\n"
        "2. [Main procedure step]\n"
        "3. [Verification step]\n"
        "[Continue with actual SOP steps from knowledge base]\n"
        "\n"
        "### Post-Action Verification:\n"
        "- Visual inspection checklist\n"
        "- Performance testing requirements\n"
        "- Success criteria\n"
        "\n"
        "## 5) Documentation & Follow-up\n"
        "### Required Documentation:\n"
        "- Panel ID, defect type, severity\n"
        "- Date/time of detection and action\n"
        "- Technician name and credentials\n"
        "- Before/after photos (if applicable)\n"
        "- Performance metrics post-repair\n"
        "\n"
        "### Follow-up Schedule:\n"
        "- Next inspection date\n"
        "- Monitoring frequency\n"
        "- Performance baseline to track\n"
        "- Escalation triggers for re-inspection\n"
        "\n"
        "## 6) Information Needed for Final Decision\n"
        "### On-site confirmation required:\n"
        "- [Specific measurements or observations needed]\n"
        "- [Environmental factors to verify]\n"
        "- [Performance data to collect]\n"
        "- [Risk factors to assess]\n"
        "\n"
        "---\n\n"
        "RETRIEVED KNOWLEDGE BASE (Use these facts only):\n"
        f"{rag_context}\n"
    )


def _determine_urgency(defect: str, confidence: float, defect_info: Dict[str, Any]) -> str:
    """Determine urgency level based on defect type and confidence."""
    threshold = defect_info.get("urgency_threshold", 0.6)
    
    if defect in ("Electrical-damage", "Physical-Damage"):
        if confidence > 0.8:
            return "CRITICAL - Immediate action required (within 1 hour)"
        elif confidence > threshold:
            return "HIGH - Action required same day"
        else:
            return "MEDIUM - Action required within 48 hours"
    
    elif defect == "Snow-Covered":
        if confidence > 0.9:
            return "MEDIUM - Monitor, action if not clearing naturally"
        else:
            return "LOW - Monitor for natural clearance"
    
    elif defect == "Bird-drop":
        if confidence > 0.7:
            return "MEDIUM - Schedule cleaning and monitoring"
        else:
            return "LOW-MEDIUM - Verify and schedule cleaning"
    
    elif defect == "Dusty":
        if confidence > 0.8:
            return "LOW-MEDIUM - Schedule cleaning soon"
        else:
            return "LOW - Routine cleaning schedule"
    
    else:  # Clean
        return "LOW - Continue standard monitoring"


def generate_recommendation(*, model_output: Dict[str, Any], rag_context: str, max_output_tokens: int = 2500) -> str:
    """Generate recommendation using Gemini API with fallback to multiple API keys."""
    api_keys = _get_api_keys()
    if not api_keys:
        raise RuntimeError(
            "No Gemini API keys configured. "
            "Set GEMINI_API_KEYS (comma or pipe-separated) or GEMINI_API_KEY environment variable."
        )

    model = _pick_model()
    prompt = build_prompt(model_output=model_output, rag_context=rag_context)
    
    last_error: Exception | None = None
    
    for key_idx, api_key in enumerate(api_keys):
        try:
            print(f"[Attempt {key_idx + 1}/{len(api_keys)}] Using API key #{key_idx + 1}")
            url = f"https://generativelanguage.googleapis.com/v1beta/{model}:generateContent?key={api_key}"
            
            payload = {
                "contents": [{"role": "user", "parts": [{"text": prompt}]}],
                "generationConfig": {"temperature": 0.3, "maxOutputTokens": int(max_output_tokens)},
            }

            resp = requests.post(url, json=payload, timeout=120)

            if resp.status_code == 429:
                # Rate limited on this key, try next one
                retry = None
                if resp.headers.get("Retry-After"):
                    try:
                        retry = float(resp.headers["Retry-After"])
                    except Exception:
                        retry = None
                if retry is None:
                    retry = _parse_retry_delay_seconds(resp.text)
                if retry is None:
                    retry = 10.0
                
                error_msg = f"API key #{key_idx + 1} hit rate limit (429). Retry after {retry}s. Trying next key..."
                print(error_msg)
                last_error = GeminiRateLimit(retry_after_seconds=retry)
                continue  # Try next key

            if resp.status_code != 200:
                error_msg = f"Gemini API error {resp.status_code} with key #{key_idx + 1}: {resp.text}"
                print(error_msg)
                last_error = RuntimeError(error_msg)
                continue  # Try next key

            data = resp.json()
            candidates = data.get("candidates") or []
            if not candidates:
                return ""

            content = candidates[0].get("content") or {}
            parts = content.get("parts") or []
            texts = [p.get("text", "") for p in parts if isinstance(p, dict)]
            raw_text = "".join(texts).strip()
            
            # Post-process the response to ensure proper markdown formatting
            formatted = raw_text
            formatted = formatted.replace("\r\n", "\n")
            formatted = formatted.replace("\n\n\n", "\n\n")
            formatted = formatted.replace("---", "\n\n---\n\n")
            
            print(f"[Success] Generated recommendation using API key #{key_idx + 1}")
            return formatted
            
        except (requests.Timeout, requests.ConnectionError) as e:
            error_msg = f"Connection error with API key #{key_idx + 1}: {e}. Trying next key..."
            print(error_msg)
            last_error = e
            continue
        except Exception as e:
            error_msg = f"Unexpected error with API key #{key_idx + 1}: {e}. Trying next key..."
            print(error_msg)
            last_error = e
            continue
    
    # All keys exhausted
    raise RuntimeError(
        f"All {len(api_keys)} API key(s) exhausted. Last error: {last_error}"
    )
