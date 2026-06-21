from __future__ import annotations

import os
import json
try:
    import google.generativeai as genai
    from google.generativeai.types import StopCandidateException
except ModuleNotFoundError:  # pragma: no cover
    genai = None  # type: ignore[assignment]
    StopCandidateException = Exception  # type: ignore[misc,assignment]
try:
    import boto3
except ModuleNotFoundError:  # pragma: no cover
    boto3 = None  # type: ignore[assignment]
import time
from pathlib import Path
from dataclasses import dataclass
from typing import Any, Dict, Optional
from urllib.parse import urlparse, urlunparse

from dotenv import load_dotenv
from fastapi import Body, FastAPI, File, HTTPException, Query, Request, UploadFile
from fastapi.responses import FileResponse
from fastapi.staticfiles import StaticFiles
from fastapi.middleware.cors import CORSMiddleware

from .onnx_infer import predict_image_bytes
from .rag import ensure_ingested, get_store, retrieve_context_from_model_output
from .dummy_data.panel_readings import get_dummy_panel_readings

import requests
from fastapi.responses import Response
from datetime import datetime, timezone
import threading
import hashlib
import re

PROJECT_ROOT = Path(__file__).resolve().parents[1]
FRONTEND_DIR = PROJECT_ROOT / "frontend"
MODELS_DIR = PROJECT_ROOT / "models"
DEFAULT_ONNX_MODEL = os.getenv("ONNX_MODEL", "last.onnx")
MODEL_PATH = str(MODELS_DIR / DEFAULT_ONNX_MODEL)
FALLBACK_IMAGE_PATH_JPG = PROJECT_ROOT / "backend" / "image.jpg"
FALLBACK_IMAGE_PATH_PNG = PROJECT_ROOT / "backend" / "image.png"
V_UPLOADS_DIR = PROJECT_ROOT / "v" / "uploads"

ESP32_CONTROL_URL = (os.getenv("ESP32_CONTROL_URL") or "").strip() or "http://10.14.20.80"
ESP32_SERVO_ON_PATH = (os.getenv("ESP32_SERVO_ON_PATH") or "").strip() or "/servo?pos=180"
ESP32_SERVO_OFF_PATH = (os.getenv("ESP32_SERVO_OFF_PATH") or "").strip() or "/servo?pos=0"
ESP32_SERVO_AUTO_OFF_SECONDS = int(os.getenv("ESP32_SERVO_AUTO_OFF_SECONDS") or "5")

TASKS_PATH = PROJECT_ROOT / "backend" / "tasks.json"
_TASKS_LOCK = threading.Lock()
_TASKS: dict[str, dict[str, Any]] = {}


def _use_dynamodb_tasks() -> bool:
    return str(os.getenv("MAINTENANCE_STORE") or "").strip().lower() == "dynamodb"


def _ddb_table_name() -> str:
    return str(os.getenv("DDB_TABLE_NAME") or "").strip() or "maintenance_tasks"


def _ddb_task_id(panel_id: str) -> str:
    return f"TASK#{panel_id}"


_DDB_TABLE = None


def _now_iso_utc() -> str:
    return datetime.now(timezone.utc).isoformat()


def _get_ddb_table():
    global _DDB_TABLE
    if _DDB_TABLE is not None:
        return _DDB_TABLE
    if boto3 is None:
        raise RuntimeError("boto3 is not installed. Please install boto3 to use DynamoDB task storage")
    resource = boto3.resource("dynamodb")
    _DDB_TABLE = resource.Table(_ddb_table_name())
    return _DDB_TABLE


def _ddb_upsert_task(
    *,
    panel_id: str,
    technician: str,
    status: str,
    notes: str,
    suggested_work: str,
    updated_at: str,
) -> dict[str, Any]:
    table = _get_ddb_table()
    pid = (panel_id or "").strip()
    if not pid:
        raise ValueError("panel_id is required")
    tid = _ddb_task_id(pid)

    resp = table.update_item(
        Key={"panel_id": pid, "task_id": tid},
        UpdateExpression=(
            "SET #tech=:tech, #st=:st, #notes=:notes, #sw=:sw, #ua=:ua, "
            "#ca=if_not_exists(#ca, :ua)"
        ),
        ExpressionAttributeNames={
            "#tech": "technician",
            "#st": "status",
            "#notes": "notes",
            "#sw": "suggested_work",
            "#ca": "created_at",
            "#ua": "updated_at",
        },
        ExpressionAttributeValues={
            ":tech": str(technician or "Kunal"),
            ":st": str(status or "PENDING"),
            ":notes": str(notes or ""),
            ":sw": str(suggested_work or ""),
            ":ua": str(updated_at),
        },
        ReturnValues="ALL_NEW",
    )
    attrs = (resp or {}).get("Attributes") or {}
    return {
        "panel_id": pid,
        "technician": str(attrs.get("technician") or "Kunal"),
        "status": str(attrs.get("status") or "PENDING"),
        "notes": str(attrs.get("notes") or ""),
        "suggested_work": str(attrs.get("suggested_work") or ""),
        "created_at": attrs.get("created_at"),
        "updated_at": attrs.get("updated_at"),
    }


def _ddb_get_task(*, panel_id: str) -> dict[str, Any] | None:
    table = _get_ddb_table()
    pid = (panel_id or "").strip()
    if not pid:
        raise ValueError("panel_id is required")
    tid = _ddb_task_id(pid)
    resp = table.get_item(Key={"panel_id": pid, "task_id": tid})
    item = (resp or {}).get("Item")
    if not item:
        return None
    return {
        "panel_id": pid,
        "technician": str(item.get("technician") or "Kunal"),
        "status": str(item.get("status") or "PENDING"),
        "notes": str(item.get("notes") or ""),
        "suggested_work": str(item.get("suggested_work") or ""),
        "created_at": item.get("created_at"),
        "updated_at": item.get("updated_at"),
    }


def _ddb_list_tasks() -> list[dict[str, Any]]:
    table = _get_ddb_table()
    items: list[dict[str, Any]] = []
    start_key = None
    while True:
        if start_key:
            resp = table.scan(ExclusiveStartKey=start_key)
        else:
            resp = table.scan()
        batch = (resp or {}).get("Items") or []
        for it in batch:
            if not isinstance(it, dict):
                continue
            # Only include our canonical single-task-per-panel items
            pid = str(it.get("panel_id") or "").strip()
            tid = str(it.get("task_id") or "").strip()
            if not pid or tid != _ddb_task_id(pid):
                continue
            items.append(
                {
                    "panel_id": pid,
                    "technician": str(it.get("technician") or "Kunal"),
                    "status": str(it.get("status") or "PENDING"),
                    "notes": str(it.get("notes") or ""),
                    "suggested_work": str(it.get("suggested_work") or ""),
                    "created_at": it.get("created_at"),
                    "updated_at": it.get("updated_at"),
                }
            )
        start_key = (resp or {}).get("LastEvaluatedKey")
        if not start_key:
            break
    items.sort(key=lambda r: str(r.get("updated_at") or ""), reverse=True)
    return items


def _load_tasks() -> None:
    global _TASKS
    if not TASKS_PATH.exists():
        _TASKS = {}
        return
    try:
        raw = json.loads(TASKS_PATH.read_text(encoding="utf-8") or "{}")
        _TASKS = raw if isinstance(raw, dict) else {}
    except Exception:
        _TASKS = {}


def _save_tasks() -> None:
    tmp = TASKS_PATH.with_suffix(".tmp")
    tmp.write_text(json.dumps(_TASKS, indent=2), encoding="utf-8")
    tmp.replace(TASKS_PATH)


def _normalize_defect_label(v: Any) -> str:
    s = str(v or "").strip()
    if not s:
        return ""

    # Normalize common separators so labels like "Physical-Damage" match checks for "physical damage".
    s = re.sub(r"[\-_]+", " ", s)
    return re.sub(r"\s+", " ", s)


def _is_assignable_defect(defect_label: str, suggestion_md: str | None = None) -> bool:
    d = _normalize_defect_label(defect_label).lower()
    if not d:
        d = ""

    # Never auto-assign work orders for cleaning/soiling.
    # Cleaning is handled separately (e.g. ESP32 servo motor trigger) and should not create technician tasks.
    if any(k in d for k in ("dust", "dusty", "dirty", "soiling", "soil", "bird", "dropping", "clean", "cleaning", "wipe")):
        return False

    # Check ONNX/primary defect first
    for key in (
        "electrical",
        "electrical damage",
        "physical",
        "physical damage",
        "crack",
        "broken",
        "burn",
        "hotspot",
    ):
        if key in d:
            return True

    # Fallback: infer from Gemini markdown if defect label is generic/unknown
    s = _normalize_defect_label(str(suggestion_md or "")).lower()

    # If Gemini recommends cleaning/soiling removal, don't create a task.
    if _should_trigger_cleaning_servo(s):
        return False

    return any(
        k in s
        for k in (
            "electrical damage",
            "physical damage",
            "physical crack",
            "crack",
            "broken",
            "burn",
            "hotspot",
        )
    )


def _build_suggested_work(defect_label: str) -> str:
    d = _normalize_defect_label(defect_label).lower()
    if "electrical" in d:
        return "Inspect connectors, junction box, wiring; perform IV test; replace faulty components if needed."
    if "crack" in d or "physical" in d or "broken" in d:
        return "Inspect panel surface for cracks/physical damage; isolate if unsafe; schedule replacement if required."
    if "hotspot" in d or "burn" in d:
        return "Perform thermal scan; check bypass diodes and connectors; schedule repair/replacement."
    return "Inspect panel and perform standard fault troubleshooting."


def _is_cleaning_or_soiling_text(s: Any) -> bool:
    t = _normalize_defect_label(str(s or "")).lower()
    return any(k in t for k in ("dust", "dusty", "dirty", "soiling", "bird", "dropping", "clean", "cleaning", "wipe"))


def _upsert_task_for_panel(*, panel_id: str, defect_label: str, suggestion_md: str | None = None) -> dict[str, Any]:
    pid = (panel_id or "").strip()
    if not pid:
        raise ValueError("panel_id is required")

    updated_at = _now_iso_utc()
    notes = f"Auto-assigned from AI health report. Defect: {_normalize_defect_label(defect_label) or 'Unknown'}"
    suggested_work = _build_suggested_work(defect_label)

    if _use_dynamodb_tasks():
        existing = None
        try:
            existing = _ddb_get_task(panel_id=pid)
        except Exception:
            existing = None

        existing_status = str((existing or {}).get("status") or "").upper()
        if existing and existing_status in {"DONE", "RESOLVED"}:
            return existing

        technician_raw = str((existing or {}).get("technician") or "").strip()
        if not technician_raw or technician_raw.lower() in {"maintenance officer", "officer", "unassigned"}:
            technician = "Kunal"
        else:
            technician = technician_raw
        status = str((existing or {}).get("status") or "PENDING")
        return _ddb_upsert_task(
            panel_id=pid,
            technician=technician,
            status=status,
            notes=notes,
            suggested_work=suggested_work,
            updated_at=updated_at,
        )

    with _TASKS_LOCK:
        existing = _TASKS.get(pid) if isinstance(_TASKS, dict) else None
        created_at = str((existing or {}).get("created_at") or "").strip() or updated_at

        # Don't overwrite a task that is already DONE/RESOLVED unless you explicitly want to.
        existing_status = str((existing or {}).get("status") or "").upper()
        if existing and existing_status in {"DONE", "RESOLVED"}:
            return {
                "panel_id": pid,
                "technician": str(existing.get("technician") or "Kunal"),
                "status": str(existing.get("status") or "PENDING"),
                "notes": str(existing.get("notes") or ""),
                "suggested_work": str(existing.get("suggested_work") or ""),
                "created_at": created_at,
                "updated_at": existing.get("updated_at"),
            }

        technician_raw = str((existing or {}).get("technician") or "").strip()
        if not technician_raw or technician_raw.lower() in {"maintenance officer", "officer", "unassigned"}:
            technician = "Kunal"
        else:
            technician = technician_raw
        status = str((existing or {}).get("status") or "PENDING")

        _TASKS[pid] = {
            "technician": technician,
            "status": status,
            "notes": notes,
            "suggested_work": suggested_work,
            "created_at": created_at,
            "updated_at": updated_at,
        }
        _save_tasks()

        return {
            "panel_id": pid,
            "technician": technician,
            "status": status,
            "notes": notes,
            "suggested_work": suggested_work,
            "created_at": created_at,
            "updated_at": updated_at,
        }


def _maybe_auto_assign_task(*, panel_id: str, defect_label: str, suggestion_md: str | None = None) -> dict[str, Any] | None:
    if not _is_assignable_defect(defect_label, suggestion_md=suggestion_md):
        return None
    try:
        return _upsert_task_for_panel(panel_id=panel_id, defect_label=defect_label, suggestion_md=suggestion_md)
    except Exception as e:
        _log(f"⚠️  Failed to auto-assign maintenance task for panel_id={panel_id}: {e}")
        return {"panel_id": (panel_id or "").strip(), "error": str(e)}


def _get_fallback_image_path() -> Path | None:
    latest_upload = _get_latest_v_upload_image_path()
    if latest_upload:
        return latest_upload

    # Prefer latest captured panel image from workspace capture folders.
    for capture_dir_name in ("captures", "capture"):
        captures_dir = PROJECT_ROOT / capture_dir_name
        if captures_dir.exists():
            candidates = []
            for ext in ("*.jpg", "*.jpeg", "*.png", "*.webp"):
                candidates.extend(captures_dir.glob(ext))
            if candidates:
                candidates.sort(key=lambda p: p.stat().st_mtime, reverse=True)
                return candidates[0]

    solar_dashboard_backend = PROJECT_ROOT / "solar-dashboard" / "backend"
    for name in ("image.jpg", "image.jpeg", "image.png", "image1.jpg", "image2.jpg"):
        fp = solar_dashboard_backend / name
        if fp.exists():
            return fp

    solar_dashboard_frontend = PROJECT_ROOT / "solar-dashboard" / "frontend"
    for name in ("image.jpg", "image.jpeg", "image.png"):
        fp = solar_dashboard_frontend / name
        if fp.exists():
            return fp

    # Final fallback: static bundled image in backend folder.
    if FALLBACK_IMAGE_PATH_JPG.exists():
        return FALLBACK_IMAGE_PATH_JPG
    if FALLBACK_IMAGE_PATH_PNG.exists():
        return FALLBACK_IMAGE_PATH_PNG
    return None


def _get_latest_v_upload_image_path() -> Path | None:
    try:
        if not V_UPLOADS_DIR.exists() or not V_UPLOADS_DIR.is_dir():
            return None
        candidates: list[Path] = []
        for ext in ("*.jpg", "*.jpeg", "*.png", "*.webp"):
            candidates.extend(V_UPLOADS_DIR.glob(ext))
        if not candidates:
            return None
        candidates.sort(key=lambda p: p.stat().st_mtime, reverse=True)
        return candidates[0]
    except Exception:
        return None


def _get_latest_upload_or_esp32_image_bytes() -> bytes:
    fp = _get_latest_v_upload_image_path()
    if fp and fp.exists() and fp.is_file():
        return fp.read_bytes()
    return _get_esp32_image()


def _iv_current_to_amps(raw_i: Any) -> float:
    """Convert per-string current to amps. Matches frontend: |x| > 50 → milliamps, else amps."""
    try:
        x = float(raw_i)
    except (TypeError, ValueError):
        return 0.0
    ax = abs(x)
    return x / 1000.0 if ax > 50.0 else x


def _extract_panel_powers_w(readings: Any) -> tuple[float, float, float, float]:
    """Extract (p1, p2, p3, p4) power values in watts from a get_panel_readings() response.

    Supports both shapes:
    - New shape: {panel1power, panel2power, panel3power, panel4power}
    - Old shape: {power: {P1, P2, P3, P4}} or {P1, P2, P3, P4}
    """

    def _num(v: Any) -> float:
        try:
            if v is None:
                return 0.0
            if isinstance(v, dict):
                v = v.get("value")
            return float(v)
        except Exception:
            return 0.0

    if not isinstance(readings, dict):
        return (0.0, 0.0, 0.0, 0.0)

    if any(k in readings for k in ("panel1power", "panel2power", "panel3power", "panel4power")):
        return (
            abs(_num(readings.get("panel1power"))),
            abs(_num(readings.get("panel2power"))),
            abs(_num(readings.get("panel3power"))),
            abs(_num(readings.get("panel4power"))),
        )

    power = readings.get("power")
    if isinstance(power, dict):
        return (
            abs(_num(power.get("P1"))),
            abs(_num(power.get("P2"))),
            abs(_num(power.get("P3"))),
            abs(_num(power.get("P4"))),
        )

    return (
        abs(_num(readings.get("P1"))),
        abs(_num(readings.get("P2"))),
        abs(_num(readings.get("P3"))),
        abs(_num(readings.get("P4"))),
    )


def _pick_markdown_section(md: str, titles: list[str]) -> str | None:
    if not md:
        return None
    wanted = {str(t or "").strip().lower() for t in (titles or []) if str(t or "").strip()}
    lines = str(md).replace("\r\n", "\n").split("\n")

    def is_heading(line: str) -> bool:
        return bool(re.match(r"^#{1,6}\s+", line))

    def heading_level(line: str) -> int:
        m = re.match(r"^(#{1,6})\s+", line)
        return len(m.group(1)) if m else 0

    def heading_title(line: str) -> str:
        return re.sub(r"^#{1,6}\s+", "", line).strip().lower()

    for i, line in enumerate(lines):
        if not is_heading(line):
            continue
        if heading_title(line) not in wanted:
            continue
        level = heading_level(line)
        end = len(lines)
        for j in range(i + 1, len(lines)):
            if is_heading(lines[j]) and heading_level(lines[j]) <= level:
                end = j
                break
        chunk = "\n".join(lines[i:end]).strip()
        return chunk or None
    return None


def _should_trigger_cleaning_servo(health_report_md: str) -> bool:
    if not health_report_md:
        return False
    rec_section = _pick_markdown_section(
        health_report_md,
        ["recommendations", "recommended actions", "recommended action"],
    )
    text = (rec_section or health_report_md).lower()
    # Trigger servo when recommendations include cleaning actions.
    # Keep this intentionally permissive so common outputs like
    # "Clean the panel surface gently" also trigger.
    return bool(
        re.search(r"\bclean(ing)?\b", text)
        or re.search(r"\bwipe\b.{0,40}\bsurface\b", text)
        or re.search(r"\bremove\b.{0,40}\bdust\b", text)
    )


def _esp32_set_servo(on: bool) -> None:
    """Move ESP32 servo: on=True → pos=180 (cleaning position), on=False → pos=0 (rest)."""
    base = (ESP32_CONTROL_URL or "").strip().rstrip("/")
    if not base:
        return
    path = ESP32_SERVO_ON_PATH if on else ESP32_SERVO_OFF_PATH
    url = f"{base}{path if path.startswith('/') else '/' + path}"
    try:
        requests.get(url, timeout=2)
    except Exception:
        # Don't fail the API response if ESP32 is unreachable.
        return


def _trigger_cleaning_servo_async() -> None:
    """Activate servo motor for cleaning, then return to rest after delay."""
    def _worker() -> None:
        _esp32_set_servo(True)
        try:
            delay = max(0, int(ESP32_SERVO_AUTO_OFF_SECONDS))
        except Exception:
            delay = 5
        if delay > 0:
            time.sleep(delay)
            _esp32_set_servo(False)

    threading.Thread(target=_worker, daemon=True).start()

# ==================== GEMINI INTEGRATION ====================

TRANSIENT_STATUS_CODES = {429, 500, 502, 503, 504}

def _get_gemini_cooldown_seconds() -> int:
    value = (os.getenv("GEMINI_COOLDOWN_SECONDS") or "60").strip()
    try:
        seconds = int(value)
    except ValueError:
        seconds = 60
    return max(0, seconds)

_GEMINI_CACHE: dict[str, dict[str, Any]] = {}

# Simple in-memory cache for weather responses
_WEATHER_CACHE: dict[str, dict[str, Any]] = {}


def _normalize_openweather_api_key(raw: str) -> str:
    """Use first plausible token when OPENWEATHER_API_KEY lists multiple pasted keys."""
    if not raw or not isinstance(raw, str):
        return ""
    text = raw.strip().strip('"').strip("'")
    for sep in ("\n", ",", ";", "|"):
        if sep in text:
            for seg in text.split(sep):
                s = seg.strip().strip('"').strip("'")
                if len(s) >= 16:
                    return s
    return text if len(text) >= 16 else ""

@dataclass(frozen=True)
class GeminiRateLimit(Exception):
    retry_after_seconds: float

def _parse_retry_delay_seconds(error_body: str) -> Optional[float]:
    """Parse retry-after from error response"""
    try:
        data = json.loads(error_body)
        if "error" in data and isinstance(data["error"], dict):
            error_dict = data["error"]
            if "details" in error_dict:
                for detail in error_dict["details"]:
                    if detail.get("@type") == "type.googleapis.com/google.rpc.RetryInfo":
                        retry_delay = detail.get("retryDelay")
                        if retry_delay:
                            seconds = float(retry_delay.get("seconds", 0))
                            nanos = float(retry_delay.get("nanos", 0))
                            return seconds + (nanos / 1e9)
    except Exception:
        pass
    return None

def _get_api_keys() -> list[str]:
    """Extract multiple API keys from environment"""
    explicit = (os.getenv("GEMINI_API_KEYS") or "").strip()
    if explicit:
        return [k.strip() for k in explicit.split(",") if k.strip()]

    # Allow comma-separated keys in GEMINI_API_KEY as well (common user mistake)
    single = (os.getenv("GEMINI_API_KEY") or "").strip()
    if not single:
        return []
    return [k.strip() for k in single.split(",") if k.strip()]

def _pick_model() -> str:
    """Pick Gemini model from environment"""
    explicit = (os.getenv("GEMINI_MODEL") or "").strip()
    if explicit:
        return explicit
    
    csv = (os.getenv("GEMINI_MODELS") or "").strip()
    if csv:
        models = [m.strip() for m in csv.split(",") if m.strip()]
        if models:
            return models[0]
    
    return "models/gemini-2.0-flash"

def build_prompt(*, model_output: Dict[str, Any], rag_context: str) -> str:
    """Build comprehensive prompt for Gemini"""
    fault = model_output.get("primary_defect")
    fault_s = str(fault or "Unknown")
    confidence = float(model_output.get("confidence") or 0.0)
    panel_id = str(model_output.get("panel_id") or "Unknown")
    rag_context_s = "" if rag_context is None else str(rag_context)
    
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
    
    defect_info = defect_contexts.get(fault_s, {})
    urgency_level = _determine_urgency(fault_s, confidence, defect_info)

    fault_l = fault_s.strip().lower()
    if fault_l == "clean" and float(confidence or 0) >= 0.9:
        action_required = "Monitor"
    elif "critical" in urgency_level.lower() or "electrical" in fault_l or "physical" in fault_l:
        action_required = "Immediate maintenance"
    else:
        action_required = "Inspect & maintain"
    
    return (
        "You are an expert solar PV operations assistant specialized in defect identification and technician guidance.\n"
        "Write for a NON-TECHNICAL user. Use very simple words and short sentences.\n"
        "Avoid jargon (e.g., encapsulation, mismatch, thermal cycling). If you must use a technical term, add a 3-6 word explanation in parentheses.\n"
        "DEFECT TYPE: " + fault_s + "\n"
        "PANEL ID: " + panel_id + "\n"
        "MODEL CONFIDENCE: {:.1%}\n".format(confidence) +
        "\n"
        "YOUR TASK:\n"
        "1. Analyze the detected defect using the retrieved solar panel knowledge base\n"
        "2. Determine severity, impact, and required actions\n"
        "3. Prefer facts from retrieved knowledge when available.\n"
        "4. If the knowledge base does not contain enough specifics, provide SAFE, generic best-practice guidance instead of writing 'Not found in retrieved knowledge'.\n"
        "5. If defect is 'Clean' and confidence is high, keep it very short and focus on monitoring and routine maintenance.\n"
        "\n"
        "DEFECT-SPECIFIC CONTEXT:\n"
        "- Defect: " + fault_s + "\n"
        "- Expected Urgency Threshold: " + str(defect_info.get("urgency_threshold", "N/A")) + "\n"
        "- Safety Risk Level: " + defect_info.get("safety_risk", "Unknown") + "\n"
        "- Typical Maintenance Actions: " + defect_info.get("typical_actions", "Unknown") + "\n"
        "- Critical Inspection Points: " + defect_info.get("inspection_focus", "Unknown") + "\n"
        "\n"
        "OUTPUT FORMAT (STRICTLY FOLLOW):\n"
        "Use GitHub-flavored Markdown. No preamble, no greeting, no emojis.\n"
        "Section headings must be exactly as shown. Keep it SHORT and actionable.\n"
        "Use SIMPLE language. Do not copy long quotes from the knowledge base.\n"
        "\n"
        "## Summary\n"
        "| Field | Value |\n"
        "|-------|-------|\n"
        "| **Panel ID** | " + panel_id + " |\n"
        "| **Defect Detected** | " + fault_s + " |\n"
        "| **Model Confidence** | {:.1%} |\n".format(confidence) +
        "| **Urgency Level** | " + urgency_level + " |\n"
        "| **Action Required** | " + action_required + " |\n"
        "\n"
        "## Root Cause Analysis\n"
        "Write 1-3 VERY short bullet points explaining the most likely cause in simple words.\n"
        "Do not repeat the words 'Possible causes:' in every bullet.\n"
        "If unsure, say 'Most likely cause:' then give the best safe guess.\n"
        "\n"
        "## Recommendations\n"
        "Write 3-5 action items as a checklist using '- [ ]'.\n"
        "Each item must be one short line and start with a verb (Inspect, Isolate, Clean, Record, Notify).\n"
        "No long explanations. No SOP IDs. No extra sections.\n"
        "Do not output the phrase 'Not found in retrieved knowledge'.\n"
        "\n"
        "---\n\n"
        "RETRIEVED KNOWLEDGE BASE (Use these facts only):\n"
        f"{rag_context_s}\n"
    )

def _determine_urgency(defect: str, confidence: float, defect_info: Dict[str, Any]) -> str:
    """Determine urgency level based on defect type and confidence"""
    threshold = defect_info.get("urgency_threshold", 0.6)
    
    if defect in ("Electrical-damage", "Physical-Damage"):
        return "🔴 CRITICAL - Immediate action required"
    elif defect == "Snow-Covered":
        return "🟡 MEDIUM - Monitor and plan removal"
    elif defect == "Bird-drop":
        return "🟠 HIGH - Schedule maintenance within 24-48 hours"
    elif defect == "Dusty":
        return "🟡 MEDIUM - Schedule cleaning within 1-2 weeks"
    else:
        return "🟢 LOW - Continue normal operation"

def generate_recommendation(
    *,
    model_output: Dict[str, Any],
    rag_context: str,
    max_output_tokens: int = 2500,
    model_override: str | None = None,
) -> str:
    """Generate recommendation using Gemini API"""
    if genai is None:
        raise RuntimeError("Gemini integration is disabled because 'google-generativeai' is not installed")
    api_keys = _get_api_keys()
    if not api_keys:
        raise RuntimeError("No GEMINI_API_KEY found in environment")
    
    model = (model_override or "").strip() or _pick_model()
    prompt = build_prompt(model_output=model_output, rag_context=rag_context)
    
    last_error: Exception | None = None
    
    for api_key in api_keys:
        try:
            genai.configure(api_key=api_key)
            client = genai.GenerativeModel(model)
            response = client.generate_content(prompt, stream=False)
            return response.text
            
        except StopCandidateException as e:
            last_error = e
            print(f"⚠️  Gemini safety filter blocked response: {e}")
            continue
            
        except Exception as e:
            error_str = str(e)
            status_code = None
            
            if hasattr(e, "status_code"):
                status_code = e.status_code
            
            if status_code in TRANSIENT_STATUS_CODES or "429" in error_str or "503" in error_str:
                retry_delay = _parse_retry_delay_seconds(error_str) if status_code == 429 else 60
                last_error = GeminiRateLimit(retry_after_seconds=retry_delay or 60)
                print(f"⚠️  Rate limited, retrying with next key...")
                continue
            
            last_error = e
            print(f"❌ Gemini error with key: {e}")
            continue
    
    if isinstance(last_error, GeminiRateLimit):
        raise last_error
    
    raise RuntimeError(f"All Gemini API keys failed. Last error: {last_error}")


def build_maintenance_prompt(*, model_output: Dict[str, Any], rag_context: str) -> str:
    defect = str(model_output.get("primary_defect") or "").strip() or "Unknown"
    confidence = float(model_output.get("confidence") or 0)
    panel_id = str(model_output.get("panel_id") or "Unknown")
    urgency = _determine_urgency(defect, confidence, {})

    return (
        "You are an expert solar PV maintenance planner.\n"
        "Generate a SHORT, actionable maintenance plan based strictly on the retrieved knowledge.\n"
        "If the knowledge is not specific enough, provide safe generic best-practice steps.\n"
        "No greeting, no emojis. Output GitHub-flavored Markdown only.\n"
        "\n"
        f"PANEL ID: {panel_id}\n"
        f"DEFECT: {defect}\n"
        f"MODEL CONFIDENCE: {confidence:.1%}\n"
        f"URGENCY: {urgency}\n"
        "\n"
        "OUTPUT FORMAT (STRICT):\n"
        "## Summary\n"
        "| Field | Value |\n"
        "|-------|-------|\n"
        f"| **Panel ID** | {panel_id} |\n"
        f"| **Defect** | {defect} |\n"
        f"| **Confidence** | {confidence:.1%} |\n"
        f"| **Urgency** | {urgency} |\n"
        "\n"
        "## Maintenance Actions\n"
        "Write 4-8 bullet points of actions (short).\n"
        "\n"
        "## Safety\n"
        "Write 2-4 bullet points.\n"
        "\n"
        "## Materials / Tools\n"
        "Write 3-6 bullet points.\n"
        "\n"
        "## Verification\n"
        "Write 3-6 bullet points to confirm the fix (visual + basic electrical checks).\n"
        "\n"
        "---\n\n"
        "RETRIEVED KNOWLEDGE BASE (Use these facts only):\n"
        f"{rag_context}\n"
    )


def generate_maintenance_plan(*, model_output: Dict[str, Any], rag_context: str, model_override: str | None = None) -> str:
    if genai is None:
        raise RuntimeError("Gemini integration is disabled because 'google-generativeai' is not installed")
    api_keys = _get_api_keys()
    if not api_keys:
        raise RuntimeError("No GEMINI_API_KEY found in environment")

    model = (model_override or "").strip() or _pick_model()
    prompt = build_maintenance_prompt(model_output=model_output, rag_context=rag_context)

    last_error: Exception | None = None
    for api_key in api_keys:
        try:
            genai.configure(api_key=api_key)
            client = genai.GenerativeModel(model)
            response = client.generate_content(prompt, stream=False)
            return response.text
        except StopCandidateException as e:
            last_error = e
            print(f"⚠️  Gemini safety filter blocked response: {e}")
            continue
        except Exception as e:
            error_str = str(e)
            status_code = getattr(e, "status_code", None)
            if status_code in TRANSIENT_STATUS_CODES or "429" in error_str or "503" in error_str:
                retry_delay = _parse_retry_delay_seconds(error_str) if status_code == 429 else 60
                last_error = GeminiRateLimit(retry_after_seconds=retry_delay or 60)
                continue
            last_error = e
            continue

    if isinstance(last_error, GeminiRateLimit):
        raise last_error

    raise RuntimeError(f"All Gemini API keys failed. Last error: {last_error}")

# ==================== FASTAPI SETUP ====================

def _load_env() -> None:
    # Precedence (last wins): backend/.env -> solar-dashboard/.env -> project-root/.env
    load_dotenv(Path(__file__).resolve().parent / ".env", override=True)
    load_dotenv(PROJECT_ROOT / "solar-dashboard" / ".env", override=True)
    load_dotenv(PROJECT_ROOT / ".env", override=True)

_load_env()

app = FastAPI()

# Enable CORS for frontend development
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_origin_regex=r"^https?://(localhost|127\.0\.0\.1|192\.168\.\d+\.\d+)(:\d+)?$",
    allow_credentials=False,
    allow_methods=["*"],
    allow_headers=["*"],
)

store = get_store()

CAPTURE_DIR = PROJECT_ROOT / "captures"
CAPTURE_DIR.mkdir(exist_ok=True)

# Comparison persistence (ported from Flask gateway)
COMPARISON_PATH = PROJECT_ROOT / "backend" / "panel_comparisons.json"
_COMPARISON_LOCK = threading.Lock()
_COMPARISON_RUNNING: dict[str, bool] = {}


def _load_comparisons() -> dict:
    try:
        if COMPARISON_PATH.exists():
            with open(COMPARISON_PATH, "r", encoding="utf-8") as f:
                data = json.load(f)
                return data if isinstance(data, dict) else {}
    except Exception as e:
        _log(f"❌ Failed to load comparisons: {e}")
    return {}


def _save_comparisons(comparisons: dict) -> None:
    tmp = str(COMPARISON_PATH) + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(comparisons, f, ensure_ascii=False, indent=2)
    os.replace(tmp, COMPARISON_PATH)


def _quiet_mode_enabled() -> bool:
    val = str(os.getenv("QUIET_MODE", "") or os.getenv("PPT_MODE", "")).strip().lower()
    return val in {"1", "true", "yes", "on"}


def _log(msg: str) -> None:
    if _quiet_mode_enabled():
        return
    print(msg)


def _resolve_model_path(model_name: str | None) -> str:
    name = (model_name or "").strip() or DEFAULT_ONNX_MODEL
    safe = Path(name).name
    if not safe.lower().endswith(".onnx"):
        safe = safe + ".onnx"
    model_path = MODELS_DIR / safe
    if not model_path.exists():
        raise HTTPException(status_code=400, detail=f"ONNX model not found: {safe}")
    return str(model_path)

# ESP32-CAM configuration
def _get_esp32_cam_url() -> str:
    raw = (os.getenv("ESP32_CAM_URL") or "http://10.177.206.2:3001/images/latest.jpg")
    # Guard against accidental newline/comment pollution in .env
    first_line = raw.splitlines()[0].strip()
    if "#" in first_line:
        first_line = first_line.split("#", 1)[0].strip()
    # Also drop any trailing whitespace-separated tokens
    first_token = first_line.split()[0] if first_line else ""
    return first_token

AWS_API_ENDPOINT = (os.getenv("AWS_API_ENDPOINT") or "").strip()
AWS_SOLAR_HISTORY_ENDPOINT = (os.getenv("AWS_SOLAR_HISTORY_ENDPOINT") or "").strip()

# QR / Flutter: alias → canonical inverter string id used across the stack
_CANONICAL_PANEL_BY_ALIAS: dict[str, str] = {
    "PANEL_001": "PL01-B02-INV03-STR05-P01",
    "PANEL_002": "PL01-B02-INV03-STR05-P02",
    "PANEL_003": "PL01-B02-INV03-STR05-P03",
    "PANEL_004": "PL01-B02-INV03-STR05-P04",
    "PANEL001": "PL01-B02-INV03-STR05-P01",
    "PANEL002": "PL01-B02-INV03-STR05-P02",
    "PANEL003": "PL01-B02-INV03-STR05-P03",
    "PANEL004": "PL01-B02-INV03-STR05-P04",
}

_READINGS_CHANNEL_BY_CANONICAL: dict[str, int] = {
    "PL01-B02-INV03-STR05-P01": 1,
    "PL01-B02-INV03-STR05-P02": 2,
    "PL01-B02-INV03-STR05-P03": 3,
    "PL01-B02-INV03-STR05-P04": 4,
}

_CHANNEL_TO_CANONICAL: dict[int, str] = {v: k for k, v in _READINGS_CHANNEL_BY_CANONICAL.items()}
_PANEL_ALIAS_RE = re.compile(r"^PANEL[_\-]?\s*0*(\d+)$", re.IGNORECASE)


def normalize_panel_identity(raw: str) -> tuple[str, int]:
    """Return (canonical_panel_id, 1-based AWS channel index for V#/I#/P#/panel#*)."""
    s = str(raw or "").strip()
    if not s:
        return "PL01-B02-INV03-STR05-P01", 1
    key = s.upper().replace(" ", "")
    if key in _CANONICAL_PANEL_BY_ALIAS:
        canon = _CANONICAL_PANEL_BY_ALIAS[key]
        return canon, int(_READINGS_CHANNEL_BY_CANONICAL.get(canon, 1))
    m = _PANEL_ALIAS_RE.match(s.strip())
    if m:
        n = int(m.group(1))
        ch = max(1, min(4, n))
        return _CHANNEL_TO_CANONICAL.get(ch, "PL01-B02-INV03-STR05-P01"), ch
    # Already canonical or unknown → default channel lookup / 1
    return s, int(_READINGS_CHANNEL_BY_CANONICAL.get(s, 1))


def _public_http_base(request: Request) -> str:
    configured = (os.getenv("PUBLIC_API_BASE_URL") or "").strip().rstrip("/")
    if configured:
        return configured
    try:
        return str(request.base_url).rstrip("/")
    except Exception:
        return "http://127.0.0.1:8000"


def _extract_short_suggestion(suggestion_md: str) -> str:
    md = suggestion_md.strip()
    if not md:
        return "No AI suggestion available yet. Pull to refresh or enable Gemini."
    lines = md.replace("\r\n", "\n").split("\n")
    for i, line in enumerate(lines):
        if line.strip().lower().startswith("## recommendations"):
            for j in range(i + 1, min(len(lines), i + 25)):
                t = lines[j].strip()
                if not t:
                    continue
                if re.match(r"^[-*]\s*(\[\s*\])?", t):
                    return re.sub(r"^[-*]\s*(\[\s*\]\s*)?", "", t).strip()[:400]
            break
    return md[:280] + ("…" if len(md) > 280 else "")


def _derive_health_score_0_100(defect_label: str, confidence01: float) -> int:
    d = _normalize_defect_label(defect_label).lower()
    try:
        c = float(confidence01)
    except (TypeError, ValueError):
        c = 0.0
    if not d or d == "none" or "clean" in d:
        return 95
    raw = int(round(100 - (max(0.0, min(1.0, c)) * 70)))
    return max(10, min(90, raw))


def _mobile_status_label(score: int) -> str:
    if score >= 90:
        return "Healthy"
    if score >= 75:
        return "Warning"
    return "Critical"


_FLUTTER_PANEL_AI_CACHE: dict[str, dict[str, Any]] = {}
_FLUTTER_PANEL_AI_CACHE_LOCK = threading.Lock()


def _cached_or_run_mobile_ai_snapshot(
    *,
    canonical_id: str,
    force_ai: bool,
    onnx_model: str,
    gemini_model: str,
) -> dict[str, Any]:
    """ONNX + optional Gemini recommendation; cached briefly for fast polling."""

    ttl = float(os.getenv("FLUTTER_AI_CACHE_SECONDS", "90") or "90")
    now = time.time()
    canon = canonical_id.strip()
    with _FLUTTER_PANEL_AI_CACHE_LOCK:
        ent = _FLUTTER_PANEL_AI_CACHE.get(canon)
        if ent and not force_ai and (now - float(ent.get("ts", 0))) < ttl:
            snap = dict(ent["snapshot"] or {})
            snap.setdefault("top_predictions", [])
            snap.setdefault("onnx_model", "")
            return snap

    try:
        image_bytes = _get_esp32_image()
        image_bytes, _ = _crop_solar_panel_bytes(image_bytes)
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        filename = f"panel_{canon}_{timestamp}.jpg"
        file_path = CAPTURE_DIR / filename
        with open(file_path, "wb") as f:
            f.write(image_bytes)

        model_path = _resolve_model_path(onnx_model)
        fault_display, confidence, top = predict_image_bytes(model_path=model_path, image_bytes=image_bytes)

        store = get_store()
        ensure_ingested(store)
        _, rag_context = retrieve_context_from_model_output(store=store, model_output={"fault": fault_display}, k=3)

        cache_key = f"flutter::{canon}::{Path(model_path).name}::{filename}"
        cached = None if force_ai else _GEMINI_CACHE.get(cache_key)
        cooldown_seconds = _get_gemini_cooldown_seconds()
        suggestion = ""
        gemini_error = None

        pd = fault_display if fault_display is not None else "Clean"
        if cached and (now - float(cached.get("ts", 0))) < cooldown_seconds:
            suggestion = str(cached.get("suggestion") or "")
            gemini_error = cached.get("gemini_error")
        else:
            try:
                suggestion = generate_recommendation(
                    model_output={
                        "primary_defect": pd,
                        "confidence": float(confidence),
                        "top_predictions": top,
                        "panel_id": canon,
                    },
                    rag_context=rag_context,
                    max_output_tokens=2500,
                    model_override=gemini_model.strip() or None,
                )
                gemini_error = None
            except GeminiRateLimit as e:
                suggestion = ""
                gemini_error = f"Gemini rate-limited. Retry after ~{int(e.retry_after_seconds)}s."
            except Exception as e:
                suggestion = ""
                gemini_error = f"Gemini unavailable: {e}"

            _GEMINI_CACHE[cache_key] = {"ts": now, "suggestion": suggestion, "gemini_error": gemini_error}

        if suggestion and _should_trigger_cleaning_servo(suggestion):
            _trigger_cleaning_servo_async()
        maintenance_task = _maybe_auto_assign_task(panel_id=canon, defect_label=str(pd or ""), suggestion_md=suggestion)

        dl = _normalize_defect_label(str(pd or "")).strip() or ("None" if str(pd).lower() == "clean" else str(pd))

        defect_out = dl if dl.lower() != "clean" else "Clean"
        if fault_display is None and str(pd).strip().lower() == "clean":
            defect_out = "Clean"

        hs = _derive_health_score_0_100(defect_out, float(confidence))
        top_list: list[dict[str, Any]] = []
        if isinstance(top, list):
            for item in top:
                if not isinstance(item, dict):
                    continue
                top_list.append(
                    {
                        "label": str(item.get("label") or item.get("name") or ""),
                        "score": float(item.get("score") or item.get("confidence") or 0.0),
                    }
                )

        snapshot = {
            "defect": defect_out,
            "confidence": float(confidence),
            "health_score": int(hs),
            "status": _mobile_status_label(int(hs)),
            "suggestion_short": _extract_short_suggestion(suggestion),
            "health_report_markdown": suggestion,
            "gemini_error": gemini_error,
            "image_filename": filename,
            "image_rel_url": f"/captures/{filename}",
            "maintenance_task": maintenance_task,
            "snapshot_time_iso": datetime.now(timezone.utc).isoformat(),
            "top_predictions": top_list,
            "onnx_model": Path(model_path).name,
        }
    except HTTPException:
        snapshot = {
            "defect": "Unknown",
            "confidence": 0.0,
            "health_score": 72,
            "status": _mobile_status_label(72),
            "suggestion_short": "Vision pipeline unavailable — check ESP32 fallback image.",
            "health_report_markdown": "",
            "gemini_error": "Vision pipeline failed",
            "image_filename": None,
            "image_rel_url": None,
            "maintenance_task": None,
            "snapshot_time_iso": datetime.now(timezone.utc).isoformat(),
            "top_predictions": [],
            "onnx_model": "",
        }
    except Exception as e:
        snapshot = {
            "defect": "Unknown",
            "confidence": 0.0,
            "health_score": 72,
            "status": _mobile_status_label(72),
            "suggestion_short": f"Analysis error: {e}",
            "health_report_markdown": "",
            "gemini_error": str(e),
            "image_filename": None,
            "image_rel_url": None,
            "maintenance_task": None,
            "snapshot_time_iso": datetime.now(timezone.utc).isoformat(),
            "top_predictions": [],
            "onnx_model": "",
        }

    with _FLUTTER_PANEL_AI_CACHE_LOCK:
        _FLUTTER_PANEL_AI_CACHE[canon] = {"ts": time.time(), "snapshot": snapshot}
    return snapshot


def _fetch_live_readings_from_aws() -> dict[str, Any]:
    if not AWS_API_ENDPOINT:
        raise ValueError("AWS_API_ENDPOINT not configured")

    _log(f"📡 Fetching sensor data from AWS API: {AWS_API_ENDPOINT}")

    response = requests.get(AWS_API_ENDPOINT, timeout=10)
    response.raise_for_status()
    data = response.json()

    if isinstance(data, dict):
        body = data.get("body")
        if isinstance(body, str) and body.strip():
            try:
                data = json.loads(body)
            except Exception:
                pass
        if isinstance(data, dict) and isinstance(data.get("data"), (dict, list)):
            data = data.get("data")

    if isinstance(data, list) and data:
        last = data[-1]
        if isinstance(last, dict):
            data = last

    def _num(v: Any, default: float = 0.0) -> float:
        try:
            if v is None:
                return float(default)
            if isinstance(v, dict):
                v = v.get("value", default)
            return float(v)
        except Exception:
            return float(default)

    if not isinstance(data, dict):
        raise ValueError("AWS readings payload missing object row")

    is_new_shape = any(k in data for k in ("panel1voltage", "panel1power", "panel1current"))
    is_iv_shape = any(k in data for k in ("I1", "V1", "I2", "V2", "I3", "V3", "I4", "V4"))

    if is_new_shape:
        panel1voltage = _num(data.get("panel1voltage"))
        panel2voltage = _num(data.get("panel2voltage"))
        panel3voltage = _num(data.get("panel3voltage"))
        panel4voltage = _num(data.get("panel4voltage"))
        panel1power = _num(data.get("panel1power"))
        panel2power = _num(data.get("panel2power"))
        panel3power = _num(data.get("panel3power"))
        panel4power = _num(data.get("panel4power"))
        panel1current = _num(data.get("panel1current"))
        panel2current = _num(data.get("panel2current"))
        panel3current = _num(data.get("panel3current"))
        panel4current = _num(data.get("panel4current"))
        device_id = data.get("deviceId") or data.get("device_id") or "solar-system"
    elif is_iv_shape:
        panel1voltage = _num(data.get("V1"))
        panel2voltage = _num(data.get("V2"))
        panel3voltage = _num(data.get("V3"))
        panel4voltage = _num(data.get("V4"))
        panel1current = _iv_current_to_amps(data.get("I1"))
        panel2current = _iv_current_to_amps(data.get("I2"))
        panel3current = _iv_current_to_amps(data.get("I3"))
        panel4current = _iv_current_to_amps(data.get("I4"))
        panel1power = float(panel1current) * float(panel1voltage)
        panel2power = float(panel2current) * float(panel2voltage)
        panel3power = float(panel3current) * float(panel3voltage)
        panel4power = float(panel4current) * float(panel4voltage)
        device_id = data.get("deviceId") or data.get("device_id") or "solar-system"
    else:
        panel1voltage = _num(data.get("V1"))
        panel2voltage = _num(data.get("V2"))
        panel3voltage = _num(data.get("V3"))
        panel4voltage = _num(data.get("V4"))
        panel1power = _num(data.get("P1"))
        panel2power = _num(data.get("P2"))
        panel3power = _num(data.get("P3"))
        panel4power = _num(data.get("P4"))
        panel1current = 0.0
        panel2current = 0.0
        panel3current = 0.0
        panel4current = 0.0
        device_id = "solar-system"

    p1_num = float(panel1power)
    p2_num = float(panel2power)
    p3_num = float(panel3power)
    p4_num = float(panel4power)
    power_below_threshold = any(float(val or 0.0) < 5.0 for val in (p1_num, p2_num, p3_num, p4_num))

    return {
        "deviceId": device_id,
        "panel1voltage": float(panel1voltage),
        "panel2voltage": float(panel2voltage),
        "panel3voltage": float(panel3voltage),
        "panel4voltage": float(panel4voltage),
        "panel1power": float(panel1power),
        "panel2power": float(panel2power),
        "panel3power": float(panel3power),
        "panel4power": float(panel4power),
        "panel1current": float(panel1current),
        "panel2current": float(panel2current),
        "panel3current": float(panel3current),
        "panel4current": float(panel4current),
        "timestamp": datetime.now().isoformat(),
        "alert": power_below_threshold,
        "source": "aws",
    }


def _esp32_candidate_urls(url: str) -> list[str]:
    raw = (url or "").strip()
    if not raw:
        return []

    p = urlparse(raw)
    if not p.scheme:
        p = urlparse("http://" + raw)

    # Normalize path for common firmwares:
    # - http://ip/
    # - http://ip/capture
    path = p.path or "/"
    if path != "/" and path.endswith("/"):
        path = path[:-1]
    base_path = "/" if path in ("", "/") else path

    base = urlunparse((p.scheme, p.netloc, base_path, "", "", ""))
    base_slash = base if base.endswith("/") else base + "/"
    capture = base if base_path.endswith("/capture") else base_slash + "capture"

    candidates: list[str] = []
    # Prefer /capture (often the only endpoint that returns an image)
    if capture not in candidates:
        candidates.append(capture)
    # Only try the raw URL if it is different from /capture
    if raw and raw != capture and raw not in candidates:
        candidates.append(raw)
    # Only try base '/' when the provided URL was not already a specific path
    if base_path in ("", "/") and base_slash not in candidates:
        candidates.append(base_slash)
    return candidates


def _get_esp32_image() -> bytes:
    """Try to get image from ESP32, fallback to local image if unavailable"""
    last_error: Exception | None = None

    timeout_s = float(os.getenv("ESP32_TIMEOUT_SECONDS", "5") or "5")

    for candidate in _esp32_candidate_urls(_get_esp32_cam_url()):
        try:
            _log(f"📸 Attempting to fetch from ESP32: {candidate}")
            r = requests.get(candidate, timeout=timeout_s)
            r.raise_for_status()
            content_type = (r.headers.get("content-type") or "").lower()
            body = r.content or b""
            is_jpeg = body.startswith(b"\xff\xd8\xff")
            is_png = body.startswith(b"\x89PNG\r\n\x1a\n")
            if not ("image/" in content_type or is_jpeg or is_png):
                raise requests.exceptions.RequestException(
                    f"ESP32 response is not an image (content-type={content_type or 'unknown'}, size={len(body)})"
                )
            _log("✅ Image fetched from ESP32-CAM")
            return body
        except requests.exceptions.RequestException as e:
            last_error = e
            _log(f"⚠️  ESP32 candidate failed: {candidate} -> {e}")
            continue

    _log(f"⚠️  ESP32-CAM unavailable: {last_error}")
    _log("📁 Falling back to local image")

    fallback_path = _get_fallback_image_path()
    if fallback_path:
        with open(fallback_path, "rb") as f:
            _log("✅ Image loaded from fallback image")
            return f.read()

    raise HTTPException(
        status_code=502,
        detail="ESP32-CAM unavailable and fallback image missing",
    )


def _env_flag(name: str, default: bool) -> bool:
    v = os.getenv(name)
    if v is None:
        return default
    return str(v).strip().lower() not in ("0", "false", "no")


def _crop_solar_panel_bytes(image_bytes: bytes) -> tuple[bytes, dict[str, int] | None]:
    if not _env_flag("CROP_PANEL", True):
        return image_bytes, None

    try:
        import cv2  # type: ignore
        import numpy as np  # type: ignore

        def order_points(pts: np.ndarray) -> np.ndarray:
            # pts: (4, 2)
            rect = np.zeros((4, 2), dtype="float32")
            s = pts.sum(axis=1)
            rect[0] = pts[np.argmin(s)]
            rect[2] = pts[np.argmax(s)]
            d = np.diff(pts, axis=1)
            rect[1] = pts[np.argmin(d)]
            rect[3] = pts[np.argmax(d)]
            return rect

        def expand_box(box: np.ndarray, pad_px: int, w_img: int, h_img: int) -> np.ndarray:
            c = np.mean(box, axis=0)
            v = box - c
            norm = np.linalg.norm(v, axis=1).reshape(-1, 1)
            norm = np.maximum(norm, 1e-6)
            box2 = box + (v / norm) * float(pad_px)
            box2[:, 0] = np.clip(box2[:, 0], 0, w_img - 1)
            box2[:, 1] = np.clip(box2[:, 1], 0, h_img - 1)
            return box2

        arr = np.frombuffer(image_bytes, dtype=np.uint8)
        img = cv2.imdecode(arr, cv2.IMREAD_COLOR)
        if img is None:
            return image_bytes, None

        h, w = img.shape[:2]
        if h <= 0 or w <= 0:
            return image_bytes, None

        gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)
        gray = cv2.GaussianBlur(gray, (5, 5), 0)
        edges = cv2.Canny(gray, 50, 150)
        edges = cv2.dilate(edges, None, iterations=2)
        edges = cv2.erode(edges, None, iterations=1)

        # Fill gaps to make the panel a single blob when possible
        kernel = cv2.getStructuringElement(cv2.MORPH_RECT, (7, 7))
        edges = cv2.morphologyEx(edges, cv2.MORPH_CLOSE, kernel, iterations=1)

        cnts, _ = cv2.findContours(edges, cv2.RETR_EXTERNAL, cv2.CHAIN_APPROX_SIMPLE)
        if not cnts:
            return image_bytes, None

        best = None
        best_score = 0.0
        img_area = float(h * w)

        best_cnt = None

        for c in cnts:
            area_cnt = float(cv2.contourArea(c))
            if area_cnt <= 0:
                continue

            rect = cv2.minAreaRect(c)
            (cx, cy), (rw, rh), _ = rect
            rw = float(rw)
            rh = float(rh)
            if rw <= 1 or rh <= 1:
                continue

            rect_area = rw * rh
            if rect_area < img_area * 0.06 or rect_area > img_area * 0.98:
                continue

            ar = (max(rw, rh) / max(1.0, min(rw, rh)))
            if ar < 1.1 or ar > 4.5:
                continue

            # Prefer large rectangles that are reasonably "filled" by the contour
            fill = area_cnt / max(1.0, rect_area)
            if fill < 0.20:
                continue

            score = rect_area * (0.5 + min(1.0, fill))
            if score > best_score:
                best_score = score
                best = rect
                best_cnt = c

        if best is None:
            return image_bytes, None

        pad = int(round(min(w, h) * 0.03))

        # Perspective warp (better for tilted panels)
        try:
            box = cv2.boxPoints(best)
            box = np.array(box, dtype="float32")
            box = expand_box(box, pad, w, h)
            rect_pts = order_points(box)

            (tl, tr, br, bl) = rect_pts
            widthA = np.linalg.norm(br - bl)
            widthB = np.linalg.norm(tr - tl)
            maxW = int(max(widthA, widthB))

            heightA = np.linalg.norm(tr - br)
            heightB = np.linalg.norm(tl - bl)
            maxH = int(max(heightA, heightB))

            if maxW < 40 or maxH < 40:
                raise ValueError("Crop too small")

            dst = np.array(
                [[0, 0], [maxW - 1, 0], [maxW - 1, maxH - 1], [0, maxH - 1]],
                dtype="float32",
            )

            M = cv2.getPerspectiveTransform(rect_pts, dst)
            warped = cv2.warpPerspective(img, M, (maxW, maxH))

            ok, buf = cv2.imencode(".jpg", warped, [int(cv2.IMWRITE_JPEG_QUALITY), 92])
            if not ok:
                raise ValueError("Encode failed")

            return buf.tobytes(), {"x": 0, "y": 0, "w": int(maxW), "h": int(maxH)}
        except Exception:
            # Fallback: axis-aligned bounding rect around the best contour
            if best_cnt is None:
                return image_bytes, None
            x, y, cw, ch = cv2.boundingRect(best_cnt)
            x1 = max(0, x - pad)
            y1 = max(0, y - pad)
            x2 = min(w, x + cw + pad)
            y2 = min(h, y + ch + pad)
            if x2 <= x1 or y2 <= y1:
                return image_bytes, None

            crop = img[y1:y2, x1:x2]
            ok, buf = cv2.imencode(".jpg", crop, [int(cv2.IMWRITE_JPEG_QUALITY), 92])
            if not ok:
                return image_bytes, None

            return buf.tobytes(), {"x": int(x1), "y": int(y1), "w": int(x2 - x1), "h": int(y2 - y1)}
    except Exception:
        return image_bytes, None


@app.get("/api/camera/latest-upload")
def get_latest_upload_image() -> Response:
    fp = _get_latest_v_upload_image_path()
    if not fp:
        raise HTTPException(status_code=404, detail="No image found in v/uploads")
    mt = "image/jpeg"
    suffix = fp.suffix.lower()
    if suffix in (".png",):
        mt = "image/png"
    elif suffix in (".webp",):
        mt = "image/webp"
    with open(fp, "rb") as f:
        return Response(f.read(), media_type=mt)


@app.get("/api/camera/esp32-feed")
def get_esp32_camera_feed() -> Response:
    """Latest frame from ESP32 (or fallback image) as image bytes — for mobile / external viewers."""
    try:
        body = _get_esp32_image()
    except HTTPException as e:
        raise e
    mt = "image/png" if body.startswith(b"\x89PNG\r\n\x1a\n") else "image/jpeg"
    return Response(content=body, media_type=mt)


@app.on_event("startup")
def _startup() -> None:
    ensure_ingested(store)
    if not _use_dynamodb_tasks():
        with _TASKS_LOCK:
            _load_tasks()


@app.get("/api/panel/task")
def get_panel_task(panel_id: str = Query("")) -> dict[str, Any]:
    pid = (panel_id or "").strip()
    if not pid:
        raise HTTPException(status_code=400, detail="panel_id is required")

    if _use_dynamodb_tasks():
        try:
            task = _ddb_get_task(panel_id=pid)
        except Exception as e:
            raise HTTPException(status_code=500, detail=f"Failed to load task from DynamoDB: {e}")
        if not task:
            return {
                "panel_id": pid,
                "technician": "Kunal",
                "status": "PENDING",
                "notes": "",
                "suggested_work": "",
            }
        return task

    with _TASKS_LOCK:
        task = _TASKS.get(pid)
    if not task:
        return {
            "panel_id": pid,
            "technician": "Kunal",
            "status": "PENDING",
            "notes": "",
            "suggested_work": "",
        }
    return {
        "panel_id": pid,
        "technician": str(task.get("technician") or "Kunal"),
        "status": str(task.get("status") or "PENDING"),
        "notes": str(task.get("notes") or ""),
        "suggested_work": str(task.get("suggested_work") or ""),
        "created_at": task.get("created_at"),
        "updated_at": task.get("updated_at"),
    }


@app.post("/api/panel/task")
def put_panel_task(
    panel_id: str = Query(""),
    panelId: str = Query(""),
    payload: dict[str, Any] = Body(default_factory=dict),
) -> dict[str, Any]:
    pid = (panel_id or "").strip()
    if not pid:
        raise HTTPException(status_code=400, detail="panel_id is required")

    technician = str(payload.get("technician") or "Kunal")
    status = str(payload.get("status") or "PENDING")
    notes_in = payload.get("notes")
    suggested_work_in = payload.get("suggested_work")

    # Do not allow creating/overwriting a technician task for cleaning/soiling.
    # Cleaning is handled via ESP32 LED trigger and should not create a work order.
    if _is_cleaning_or_soiling_text(notes_in) or _is_cleaning_or_soiling_text(suggested_work_in):
        return {
            "panel_id": pid,
            "skipped": True,
            "reason": "cleaning_or_soiling",
        }
    updated_at = _now_iso_utc()

    if _use_dynamodb_tasks():
        try:
            existing = _ddb_get_task(panel_id=pid) or {}
            notes = str(notes_in) if notes_in is not None else str(existing.get("notes") or "")
            suggested_work = (
                str(suggested_work_in)
                if suggested_work_in is not None
                else str(existing.get("suggested_work") or "")
            )
            return _ddb_upsert_task(
                panel_id=pid,
                technician=technician,
                status=status,
                notes=notes,
                suggested_work=suggested_work,
                updated_at=updated_at,
            )
        except Exception as e:
            raise HTTPException(status_code=500, detail=f"Failed to persist task to DynamoDB: {e}")

    notes = str(notes_in or "")
    suggested_work = str(suggested_work_in or "")

    with _TASKS_LOCK:
        existing = _TASKS.get(pid) if isinstance(_TASKS, dict) else None
        created_at = str((existing or {}).get("created_at") or "").strip() or updated_at
        _TASKS[pid] = {
            "technician": technician,
            "status": status,
            "notes": notes,
            "suggested_work": suggested_work,
            "created_at": created_at,
            "updated_at": updated_at,
        }
        try:
            _save_tasks()
        except Exception as e:
            raise HTTPException(status_code=500, detail=f"Failed to persist task: {e}")

    return {
        "panel_id": pid,
        "technician": technician,
        "status": status,
        "notes": notes,
        "suggested_work": suggested_work,
        "created_at": created_at,
        "updated_at": updated_at,
    }


@app.get("/api/tasks")
def list_tasks() -> list[dict[str, Any]]:
    if _use_dynamodb_tasks():
        try:
            items = _ddb_list_tasks()
            return [t for t in items if not _is_cleaning_or_soiling_text(t.get("notes"))]
        except Exception as e:
            raise HTTPException(status_code=500, detail=f"Failed to list tasks from DynamoDB: {e}")
    with _TASKS_LOCK:
        items = list((_TASKS or {}).items())
    out: list[dict[str, Any]] = []
    for pid, task in items:
        if not isinstance(task, dict):
            continue
        out.append(
            {
                "panel_id": pid,
                "technician": str(task.get("technician") or "Kunal"),
                "status": str(task.get("status") or "PENDING"),
                "notes": str(task.get("notes") or ""),
                "suggested_work": str(task.get("suggested_work") or ""),
                "created_at": task.get("created_at"),
                "updated_at": task.get("updated_at"),
            }
        )
    out = [t for t in out if not _is_cleaning_or_soiling_text(t.get("notes"))]
    out.sort(key=lambda r: str(r.get("updated_at") or ""), reverse=True)
    return out


@app.get("/api/debug/maintenance-store")
def debug_maintenance_store() -> dict[str, Any]:
    return {
        "maintenance_store": str(os.getenv("MAINTENANCE_STORE") or ""),
        "use_dynamodb": _use_dynamodb_tasks(),
        "ddb_table_name": _ddb_table_name(),
        "aws_default_region": str(os.getenv("AWS_DEFAULT_REGION") or ""),
        "aws_region": str(os.getenv("AWS_REGION") or ""),
        "env_has_maintenance_store": "MAINTENANCE_STORE" in os.environ,
        "env_has_ddb_table_name": "DDB_TABLE_NAME" in os.environ,
        "env_has_aws_access_key_id": "AWS_ACCESS_KEY_ID" in os.environ,
        "env_has_aws_secret_access_key": "AWS_SECRET_ACCESS_KEY" in os.environ,
    }


@app.post("/api/debug/ddb-task-write")
def debug_ddb_task_write(panel_id: str = Query("")) -> dict[str, Any]:
    pid = (panel_id or "").strip() or "PL01-B02-INV03-STR05-P01"
    if not _use_dynamodb_tasks():
        raise HTTPException(status_code=400, detail="MAINTENANCE_STORE is not set to dynamodb")
    updated_at = _now_iso_utc()
    try:
        return _ddb_upsert_task(
            panel_id=pid,
            technician="Kunal",
            status="PENDING",
            notes="Debug write test",
            suggested_work="Inspect panel",
            updated_at=updated_at,
        )
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"DynamoDB write failed: {e}")


@app.get("/api/debug/esp32-servo")
def debug_esp32_servo(on: int = Query(1)) -> dict[str, Any]:
    base = (ESP32_CONTROL_URL or "").strip().rstrip("/")
    if not base:
        raise HTTPException(status_code=400, detail="ESP32_CONTROL_URL is not set")
    path = ESP32_SERVO_ON_PATH if int(on or 0) == 1 else ESP32_SERVO_OFF_PATH
    url = f"{base}{path if path.startswith('/') else '/' + path}"
    try:
        r = requests.get(url, timeout=3)
        return {"ok": True, "requested_url": url, "status_code": r.status_code, "text": (r.text or "")[:200]}
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to reach ESP32 at {url}: {e}")

if FRONTEND_DIR.exists():
    app.mount("/static", StaticFiles(directory=str(FRONTEND_DIR)), name="static")
    app.mount("/captures", StaticFiles(directory=str(CAPTURE_DIR)), name="captures")

@app.get("/api/assets/{filename}")
def get_asset_file(filename: str) -> FileResponse:
    """Compatibility route for legacy frontend image URLs."""
    safe_name = Path(filename).name
    asset_path = CAPTURE_DIR / safe_name
    if not asset_path.exists() or not asset_path.is_file():
        raise HTTPException(status_code=404, detail=f"Asset not found: {safe_name}")
    return FileResponse(str(asset_path))

@app.get("/")
def index() -> FileResponse:
    index_path = FRONTEND_DIR / "index.html"
    if not index_path.exists():
        raise HTTPException(status_code=500, detail="frontend/index.html not found")
    return FileResponse(str(index_path))

# ==================== PANEL READINGS ENDPOINT ====================

@app.get("/api/panel/readings/dummy")
def get_panel_readings_dummy() -> dict[str, Any]:
    return get_dummy_panel_readings()


@app.get("/api/panel/readings")
def get_panel_readings(panel_id: str = Query("PL01-B02-INV03-STR05-P01")):
    """Live panel snapshot from AWS_API_ENDPOINT (same row used for V1–V4 / panels 1–4)."""
    _ = panel_id
    try:
        if not AWS_API_ENDPOINT:
            _log("⚠️  AWS_API_ENDPOINT not set — returning dummy readings")
            return get_dummy_panel_readings()
        out = _fetch_live_readings_from_aws()
        _log("✅ Real sensor data transformed from AWS API")
        return out
    except requests.exceptions.RequestException as e:
        _log(f"⚠️ AWS API unavailable ({e}), using dummy readings")
        return get_dummy_panel_readings()
    except Exception as e:
        _log(f"⚠️ Readings error ({e}), using dummy readings")
        return get_dummy_panel_readings()


@app.get("/panel/{panel_id}")
async def flutter_panel_health_bundle(
    panel_id: str,
    request: Request,
    refresh_ai: int = Query(0, description="Set to 1 to bypass mobile AI/analysis cache."),
    onnx_model: str = Query(""),
    gemini_model: str = Query(""),
) -> dict[str, Any]:
    """Unified payload for Flutter after QR scan: live AWS-derived electricals + cached ONNX/Gemini + image URL."""

    canon, channel = normalize_panel_identity(panel_id)
    readings = get_panel_readings(canon)

    v = abs(float(readings.get(f"panel{channel}voltage") or 0.0))
    i_a = abs(float(readings.get(f"panel{channel}current") or 0.0))
    p_w = abs(float(readings.get(f"panel{channel}power") or 0.0))

    wx: dict[str, Any]
    try:
        wx_raw = get_wardha_weather()
        wx = wx_raw if isinstance(wx_raw, dict) else {}
    except Exception:
        wx = {}

    try:
        t_raw = wx.get("temperature_c")
        temperature_c = float(t_raw) if t_raw is not None else None
    except (TypeError, ValueError):
        temperature_c = None

    ai = _cached_or_run_mobile_ai_snapshot(
        canonical_id=canon,
        force_ai=bool(int(refresh_ai or 0)),
        onnx_model=onnx_model,
        gemini_model=gemini_model,
    )

    base = _public_http_base(request)
    rel_img = ai.get("image_rel_url") or ""
    snapshot_url = f"{base}{rel_img}" if rel_img else ""

    readings_ts_iso = str(readings.get("timestamp") or datetime.now().isoformat())
    try:
        readings_dt = datetime.fromisoformat(readings_ts_iso.replace("Z", "+00:00"))
        readings_disp = readings_dt.strftime("%Y-%m-%d %I:%M %p")
    except Exception:
        readings_disp = readings_ts_iso

    try:
        snap_iso = str(ai.get("snapshot_time_iso") or "")
        snap_dt = datetime.fromisoformat(snap_iso.replace("Z", "+00:00"))
        ai_disp = snap_dt.strftime("%Y-%m-%d %I:%M %p")
    except Exception:
        ai_disp = str(ai.get("snapshot_time_iso") or readings_disp)

    # Primary image: latest analysed capture; fallbacks stream live ESP32/upload endpoints.
    image_alternatives = [
        snapshot_url,
        f"{base}/api/camera/esp32-feed?t={int(time.time() * 1000)}",
        f"{base}/api/camera/latest-upload?t={int(time.time() * 1000)}",
    ]

    top_preds = ai.get("top_predictions") if isinstance(ai.get("top_predictions"), list) else []
    defect_analysis = {
        "defect": ai.get("defect"),
        "confidence": float(ai.get("confidence") or 0.0),
        "top_predictions": top_preds,
    }
    parts = [p for p in str(canon).split("-") if p]
    string_id = f"{parts[-2]}-{parts[-1]}" if len(parts) >= 2 else str(canon)

    return {
        "panel_id": canon,
        "panel_alias_scanned": panel_id.strip(),
        "string_id": string_id,
        "channel_index": channel,
        "voltage": round(v, 4),
        "current": round(i_a, 6),
        "power": round(p_w, 4),
        "temperature_c": temperature_c,
        "defect": ai.get("defect"),
        "confidence": ai.get("confidence"),
        "health_score": ai.get("health_score"),
        "suggestion": ai.get("suggestion_short"),
        "health_report_markdown": ai.get("health_report_markdown"),
        "defect_analysis": defect_analysis,
        "onnx_model": ai.get("onnx_model") or "",
        "status": ai.get("status"),
        "last_updated_sensor": readings_disp,
        "last_updated": readings_disp,
        "last_updated_ai_snapshot": ai_disp,
        "image_url": snapshot_url or image_alternatives[1],
        "image_candidates": image_alternatives,
        "readings": readings,
        "weather": wx,
        "gemini_error": ai.get("gemini_error"),
        "aws_endpoint_configured": bool(AWS_API_ENDPOINT),
        "readings_source": readings.get("source"),
    }


@app.get("/api/panels/all")
def get_all_panels():
    """Dashboard panels list.

    Flutter expects an array of panels with id/name/location/capacity/current_output/health_score.
    We derive values from live readings where possible.
    """
    try:
        readings = get_panel_readings("PL01-B02-INV03-STR05-P01")
        p1 = abs(float(readings.get("panel1power", 0) or 0))
        p2 = abs(float(readings.get("panel2power", 0) or 0))
        p3 = abs(float(readings.get("panel3power", 0) or 0))
        p4 = abs(float(readings.get("panel4power", 0) or 0))
        total_w = p1 + p2 + p3 + p4

        def health_from_power(w: float) -> float:
            if w >= 5:
                return 95.0
            if w >= 1:
                return 85.0
            return 60.0

        panels = [
            {
                "id": "PL01-B02-INV03-STR05-P01",
                "name": "Solar Panel 1",
                "location": "Panel 1",
                "capacity": 5000,
                "current_output": total_w,
                "health_score": health_from_power(total_w),
            },
            {
                "id": "PL01-B02-INV03-STR05-P02",
                "name": "Solar Panel 2",
                "location": "Panel 2",
                "capacity": 5000,
                "current_output": total_w,
                "health_score": health_from_power(total_w),
            },
            {
                "id": "PL01-B02-INV03-STR05-P03",
                "name": "Solar Panel 3",
                "location": "Panel 3",
                "capacity": 5000,
                "current_output": total_w,
                "health_score": health_from_power(total_w),
            },
            {
                "id": "PL01-B02-INV03-STR05-P04",
                "name": "Solar Panel 4",
                "location": "Panel 4",
                "capacity": 5000,
                "current_output": total_w,
                "health_score": health_from_power(total_w),
            },
        ]
        return panels
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to fetch panels: {e}")


@app.get("/api/solar-history")
def get_solar_history(assetId: str = Query("SolarPanel_01")):
    """Proxy historical solar panel data from AWS API Gateway to avoid browser CORS."""
    try:
        if not AWS_SOLAR_HISTORY_ENDPOINT:
            raise HTTPException(
                status_code=500,
                detail="AWS_SOLAR_HISTORY_ENDPOINT is not set. Define it in your .env and restart the backend.",
            )
        resp = requests.get(
            AWS_SOLAR_HISTORY_ENDPOINT,
            params={"assetId": assetId},
            timeout=10,
        )
        resp.raise_for_status()
        data = resp.json()
        if isinstance(data, list):
            return data
        # Some deployments wrap in {data: [...]}
        if isinstance(data, dict) and isinstance(data.get("data"), list):
            return data["data"]
        return []
    except requests.exceptions.RequestException as e:
        raise HTTPException(status_code=502, detail=f"Failed to fetch solar-history: {e}")
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Unexpected solar-history error: {e}")


@app.get("/api/solar-iv-pv")
def get_solar_iv_pv_snapshot():
    """Latest JSON snapshot for I-V / P-V charts from AWS_API_ENDPOINT."""
    try:
        if not AWS_API_ENDPOINT:
            raise HTTPException(
                status_code=500,
                detail="AWS_API_ENDPOINT is not set. Define it in your .env and restart the backend.",
            )

        resp = requests.get(AWS_API_ENDPOINT, timeout=10)
        resp.raise_for_status()

        data = resp.json()

        # Support common API Gateway wrappers.
        if isinstance(data, dict):
            body = data.get("body")
            if isinstance(body, str) and body.strip():
                try:
                    data = json.loads(body)
                except Exception:
                    pass
            if isinstance(data, dict) and isinstance(data.get("data"), (dict, list)):
                data = data.get("data")

        if isinstance(data, (dict, list)):
            return data

        raise HTTPException(
            status_code=502,
            detail=f"Unexpected snapshot response type: {type(data).__name__}",
        )
    except requests.exceptions.RequestException as e:
        raise HTTPException(status_code=502, detail=f"Failed to fetch solar snapshot: {e}")
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Unexpected solar snapshot error: {e}")

@app.get("/api/panel/info")
def get_panel_info(panel_id: str = Query("PL01-B02-INV03-STR05-P01")):
    """Get panel information and check if analysis is needed"""
    try:
        # Get sensor readings
        readings = get_panel_readings(panel_id)

        p1_num = float(readings.get("panel1power") or 0.0)
        p2_num = float(readings.get("panel2power") or 0.0)
        p3_num = float(readings.get("panel3power") or 0.0)
        p4_num = float(readings.get("panel4power") or 0.0)
        power_below_threshold = any(
            (val is not None) and float(val) < 5.0
            for val in (p1_num, p2_num, p3_num, p4_num)
        )

        if power_below_threshold:
            print(
                f"🚨 ALERT: Power below threshold (P1={p1_num}W, P2={p2_num}W, P3={p3_num}W, P4={p4_num}W) < 5.0W!"
            )
            return {
                "panel_id": panel_id,
                "status": "alert",
                "message": "Power (P1/P2/P3/P4) is below 5.0W - TRIGGERING ANALYSIS",
                "voltage": readings.get("voltage"),
                "current": readings.get("current"),
                "power": readings.get("power"),
                "requires_analysis": True,
                "timestamp": readings.get("timestamp")
            }
        else:
            return {
                "panel_id": panel_id,
                "status": "normal",
                "message": "Power (P1/P2/P3/P4) is not below 5.0W",
                "voltage": readings.get("voltage"),
                "current": readings.get("current"),
                "power": readings.get("power"),
                "requires_analysis": False,
                "timestamp": readings.get("timestamp")
            }
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to get panel info: {e}")


@app.get("/api/panel/comparison/before")
def panel_comparison_before(panel_id: str = Query("PL01-B02-INV03-STR05-P01")):
    comps = _load_comparisons()
    rec = comps.get(panel_id) or {}
    return rec.get("before") or {}


@app.post("/api/panel/comparison/before")
def panel_comparison_before_capture(panel_id: str = Query("PL01-B02-INV03-STR05-P01")):
    try:
        readings = get_panel_readings(panel_id)
        p1, p2, p3, p4 = _extract_panel_powers_w(readings)
        total_w = float(p1 + p2 + p3 + p4)

        image_bytes = _get_latest_upload_or_esp32_image_bytes()
        image_sha256 = hashlib.sha256(image_bytes).hexdigest()
        ts = datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%S")
        filename = f"comparison_before_{panel_id}_{ts}.jpg"
        fp = CAPTURE_DIR / filename
        with open(fp, "wb") as f:
            f.write(image_bytes)

        before = {
            "panel_id": panel_id,
            "power_before": total_w,
            "panel1power_before": float(p1),
            "panel2power_before": float(p2),
            "panel3power_before": float(p3),
            "panel4power_before": float(p4),
            "resolution_status": "Faulty" if total_w < 5 else "Healthy",
            "deviation_percent": float(max(0, (5 - total_w) * 10)),
            "timestamp": _now_iso_utc(),
            "image": {"filename": filename, "url": f"/api/assets/{filename}", "sha256": image_sha256},
        }

        with _COMPARISON_LOCK:
            comps = _load_comparisons()
            rec = comps.get(panel_id) or {}
            rec["before"] = before
            rec["latest_before_at"] = before["timestamp"]
            comps[panel_id] = rec
            _save_comparisons(comps)

        return before
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to capture before snapshot: {e}")


@app.get("/api/panel/comparison/latest")
def panel_comparison_latest(panel_id: str = Query("PL01-B02-INV03-STR05-P01")):
    comps = _load_comparisons()
    rec = comps.get(panel_id) or {}
    latest = rec.get("latest") or {}
    return latest


@app.post("/api/panel/comparison/run")
def panel_comparison_run(panel_id: str = Query("PL01-B02-INV03-STR05-P01")):
    with _COMPARISON_LOCK:
        if _COMPARISON_RUNNING.get(panel_id):
            raise HTTPException(status_code=409, detail="Comparison already running")
        _COMPARISON_RUNNING[panel_id] = True

    try:
        comps = _load_comparisons()
        rec = comps.get(panel_id) or {}
        before = rec.get("before") or {}
        power_before = float(before.get("power_before") or 0.0)

        readings = get_panel_readings(panel_id)
        p1, p2, p3, p4 = _extract_panel_powers_w(readings)
        power_after = float(p1 + p2 + p3 + p4)

        image_bytes = _get_latest_upload_or_esp32_image_bytes()
        image_sha256 = hashlib.sha256(image_bytes).hexdigest()
        ts = datetime.now(timezone.utc).strftime("%Y%m%d_%H%M%S")
        filename = f"comparison_after_{panel_id}_{ts}.jpg"
        fp = CAPTURE_DIR / filename
        with open(fp, "wb") as f:
            f.write(image_bytes)

        after = {
            "panel_id": panel_id,
            "power_after": power_after,
            "panel1power_after": float(p1),
            "panel2power_after": float(p2),
            "panel3power_after": float(p3),
            "panel4power_after": float(p4),
            "resolution_status": "Healthy" if power_after >= 5 else "Faulty",
            "deviation_percent": float(max(0, (5 - power_after) * 10)),
            "timestamp": _now_iso_utc(),
            "image": {"filename": filename, "url": f"/api/assets/{filename}", "sha256": image_sha256},
        }

        resolution = "RESOLVED" if power_after >= power_before else "NOT_RESOLVED"
        latest = {
            "panel_id": panel_id,
            "power_before": power_before,
            "power_after": power_after,
            "panel1power_before": float(before.get("panel1power_before") or 0.0),
            "panel2power_before": float(before.get("panel2power_before") or 0.0),
            "panel3power_before": float(before.get("panel3power_before") or 0.0),
            "panel4power_before": float(before.get("panel4power_before") or 0.0),
            "panel1power_after": float(p1),
            "panel2power_after": float(p2),
            "panel3power_after": float(p3),
            "panel4power_after": float(p4),
            "resolution_status": resolution,
            "before": before,
            "after": after,
            "timestamp": _now_iso_utc(),
        }

        with _COMPARISON_LOCK:
            comps = _load_comparisons()
            rec = comps.get(panel_id) or {}
            rec["latest"] = latest
            rec["after"] = after
            rec["updated_at"] = _now_iso_utc()
            comps[panel_id] = rec
            _save_comparisons(comps)

        return latest
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to run comparison: {e}")
    finally:
        with _COMPARISON_LOCK:
            _COMPARISON_RUNNING[panel_id] = False


@app.get("/api/panel/predictive-maintenance")
def get_predictive_maintenance(panel_id: str = Query("PL01-B02-INV03-STR05-P01")):
    try:
        readings = get_panel_readings(panel_id)
        p1 = abs(float(readings.get("panel1power", 0) or 0))
        p2 = abs(float(readings.get("panel2power", 0) or 0))
        p3 = abs(float(readings.get("panel3power", 0) or 0))
        p4 = abs(float(readings.get("panel4power", 0) or 0))
        total_w = p1 + p2 + p3 + p4

        if total_w < 1:
            priority = "High"
            trend = "decreasing"
            next_days = 7
        elif total_w < 5:
            priority = "Medium"
            trend = "stable"
            next_days = 21
        else:
            priority = "Low"
            trend = "improving"
            next_days = 45

        predicted_30 = max(0.0, min(100.0, 95.0 - (5.0 - min(5.0, total_w)) * 3.0))
        predicted_90 = max(0.0, min(100.0, predicted_30 - 5.0))

        return {
            "panel_id": panel_id,
            "maintenance_priority": priority,
            "trend": trend,
            "predicted_efficiency_30days": predicted_30,
            "predicted_efficiency_90days": predicted_90,
            "next_maintenance_recommended_days": next_days,
            "timestamp": datetime.now().isoformat(),
        }
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to compute predictive maintenance: {e}")


@app.get("/api/panel/health-report")
async def get_health_report(
    panel_id: str = Query("PL01-B02-INV03-STR05-P01"),
    onnx_model: str = Query(""),
    gemini_model: str = Query(""),
    force: int = Query(0),
):
    try:
        readings = get_panel_readings(panel_id)

        image_bytes = _get_esp32_image()
        image_bytes, _ = _crop_solar_panel_bytes(image_bytes)
        image_sha256 = hashlib.sha256(image_bytes).hexdigest()

        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        filename = f"panel_{panel_id}_{timestamp}.jpg"
        file_path = CAPTURE_DIR / filename
        with open(file_path, "wb") as f:
            f.write(image_bytes)

        model_path = _resolve_model_path(onnx_model)
        fault_display, confidence, top = predict_image_bytes(model_path=model_path, image_bytes=image_bytes)

        store = get_store()
        ensure_ingested(store)
        _, rag_context = retrieve_context_from_model_output(store=store, model_output={"fault": fault_display}, k=3)

        now = time.time()
        cache_key = f"health::{panel_id}::{Path(model_path).name}::{(gemini_model.strip() or _pick_model())}::{filename}"
        cached = None if force else _GEMINI_CACHE.get(cache_key)
        cooldown_seconds = _get_gemini_cooldown_seconds()
        if cached and (now - float(cached.get("ts", 0))) < cooldown_seconds:
            suggestion = str(cached.get("suggestion") or "")
            gemini_error = cached.get("gemini_error")
        else:
            try:
                suggestion = generate_recommendation(
                    model_output={"primary_defect": fault_display or fault_display is None and "Clean" or fault_display, "confidence": float(confidence), "top_predictions": top, "panel_id": panel_id},
                    rag_context=rag_context,
                    max_output_tokens=2500,
                    model_override=gemini_model.strip() or None,
                )
                gemini_error = None
            except GeminiRateLimit as e:
                suggestion = ""
                gemini_error = f"Gemini is rate-limited. Please retry after {int(e.retry_after_seconds)} seconds."
            except Exception as e:
                suggestion = ""
                gemini_error = f"Gemini call failed: {e}"

            _GEMINI_CACHE[cache_key] = {"ts": now, "suggestion": suggestion, "gemini_error": gemini_error}

        if suggestion and _should_trigger_cleaning_servo(suggestion):
            _trigger_cleaning_servo_async()

        maintenance_task = _maybe_auto_assign_task(
            panel_id=panel_id,
            defect_label=fault_display,
            suggestion_md=suggestion,
        )

        return {
            "status": "analyzed",
            "analysis_triggered": True,
            "panel_id": panel_id,
            "timestamp": datetime.now().isoformat(),
            "image": {"filename": filename, "url": f"/captures/{filename}", "timestamp": timestamp, "sha256": image_sha256},
            "ml": {"onnx_model": Path(model_path).name, "onnx_model_path": model_path},
            "defect_analysis": {"defect": fault_display, "confidence": float(confidence), "top_predictions": top},
            "knowledge_context": rag_context,
            "health_report": suggestion,
            "gemini_error": gemini_error,
            "sensor_data": readings,
            "maintenance_task": maintenance_task,
        }
    except HTTPException as e:
        raise e
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to generate health report: {e}")


@app.post("/api/panel/auto-analyze")
async def auto_analyze(
    panel_id: str = Query("PL01-B02-INV03-STR05-P01"),
    onnx_model: str = Query(""),
    gemini_model: str = Query(""),
    force: int = Query(0),
):
    """
    Automatic workflow:
    1. Get sensor readings
    2. Check if power (P1/P2/P3) is below 5.0W
    3. If yes, capture image and analyze
    4. Return full health report
    """
    try:
        _log(f"\n{'='*60}")
        _log(f"🔄 STARTING AUTOMATIC ANALYSIS FOR PANEL: {panel_id}")
        _log(f"{'='*60}\n")
        
        # Step 1: Get sensor readings
        _log("📊 Step 1: Fetching sensor readings from AWS...")
        readings = get_panel_readings(panel_id)
        power = readings.get("power", {}) if isinstance(readings.get("power"), dict) else {}
        p1_value = power.get("P1", 0)
        p2_value = power.get("P2", 0)
        p3_value = power.get("P3", 0)
        p1_num = float(p1_value) if p1_value is not None else 0.0
        p2_num = float(p2_value) if p2_value is not None else 0.0
        p3_num = float(p3_value) if p3_value is not None else 0.0

        _log(f"✅ Power readings: P1={p1_num}W, P2={p2_num}W, P3={p3_num}W")

        power_below_threshold = any(
            (val is not None) and float(val) < 5.0
            for val in (p1_num, p2_num, p3_num)
        )

        if not power_below_threshold:
            _log("✅ Power is not below 5.0W threshold. No analysis needed.")
            return {
                "status": "normal",
                "panel_id": panel_id,
                "message": "Power (P1/P2/P3) is not below 5.0W",
                "voltage_data": readings,
                "analysis_triggered": False,
                "timestamp": datetime.now().isoformat()
            }

        _log(f"🚨 ALERT: Power below 5.0W (P1={p1_num}W, P2={p2_num}W, P3={p3_num}W) - ANALYSIS TRIGGERED!")
        
        # Step 2: Capture image
        _log("\n📸 Step 2: Capturing image...")
        image_bytes = _get_esp32_image()
        image_bytes, _ = _crop_solar_panel_bytes(image_bytes)
        image_sha256 = hashlib.sha256(image_bytes).hexdigest()
        
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        filename = f"panel_{panel_id}_{timestamp}.jpg"
        file_path = CAPTURE_DIR / filename
        
        with open(file_path, "wb") as f:
            f.write(image_bytes)
        
        _log(f"✅ Image saved: {filename}")
        
        # Step 3: ONNX inference
        _log("\n🤖 Step 3: Running ONNX model inference...")
        model_path = _resolve_model_path(onnx_model)
        
        try:
            fault, confidence, top = predict_image_bytes(model_path=model_path, image_bytes=image_bytes)
            _log(f"✅ Inference complete: {fault} (confidence: {confidence:.1%})")
        except Exception as e:
            raise HTTPException(status_code=500, detail=f"ONNX inference failed: {e}")

        fault_display: str | None
        if str(fault or "").strip().lower() == "clean":
            fault_display = None
        else:
            fault_display = str(fault)
        
        model_output = {
            "primary_defect": fault,
            "confidence": confidence,
            "top_predictions": top,
            "panel_id": panel_id
        }
        
        # Step 4: RAG retrieval
        _log("\n📚 Step 4: Retrieving context from knowledge base...")
        ensure_ingested(store)
        rag_query, rag_context = retrieve_context_from_model_output(store=store, model_output=model_output, k=3)
        
        if not rag_context:
            raise HTTPException(status_code=500, detail="RAG retrieval returned empty context")
        
        _log(f"✅ Retrieved {len(rag_context)} characters of context")
        
        # Step 5: Gemini AI recommendation
        _log("\n🤖 Step 5: Generating AI health report via Gemini...")
        now = time.time()
        cache_key = f"health::{panel_id}::{Path(model_path).name}::{(gemini_model.strip() or _pick_model())}::{filename}"
        cached = None if force else _GEMINI_CACHE.get(cache_key)
        cooldown_seconds = _get_gemini_cooldown_seconds()
        if cached and (now - float(cached.get("ts", 0))) < cooldown_seconds:
            suggestion = str(cached.get("suggestion") or "")
            gemini_error = cached.get("gemini_error")
            remaining = int(max(0, cooldown_seconds - (now - float(cached.get("ts", 0)))))
            _log(f"⏳ Gemini cooldown active ({remaining}s remaining). Reusing cached result.")
        else:
            try:
                suggestion = generate_recommendation(
                    model_output=model_output,
                    rag_context=rag_context,
                    model_override=(gemini_model.strip() or None),
                )
                _log("✅ Health report generated successfully")
                gemini_error: str | None = None
            except GeminiRateLimit as e:
                suggestion = ""
                gemini_error = f"Gemini is rate-limited. Please retry after {int(e.retry_after_seconds)} seconds."
                _log(f"⚠️  {gemini_error}")
            except Exception as e:
                suggestion = ""
                gemini_error = f"Gemini call failed: {e}"
                _log(f"⚠️  {gemini_error}")

            _GEMINI_CACHE[cache_key] = {
                "ts": now,
                "suggestion": suggestion,
                "gemini_error": gemini_error,
            }

        if suggestion and _should_trigger_cleaning_servo(suggestion):
            _trigger_cleaning_servo_async()

        maintenance_task = _maybe_auto_assign_task(
            panel_id=panel_id,
            defect_label=fault_display,
            suggestion_md=suggestion,
        )
        
        _log(f"\n{'='*60}")
        _log(f"✅ ANALYSIS COMPLETE FOR PANEL: {panel_id}")
        _log(f"{'='*60}\n")
        
        health_report = {
            "status": "analyzed",
            "analysis_triggered": True,
            "panel_id": panel_id,
            "timestamp": datetime.now().isoformat(),
            
            # Power data that triggered analysis
            "power_trigger": {
                "p1_value": p1_value,
                "p2_value": p2_value,
                "p3_value": p3_value,
                "threshold": 5.0,
                "status": "TRIGGERED",
                "message": "Power (P1/P2/P3) is below 5.0W"
            },
            
            # Image information
            "image": {
                "filename": filename,
                "url": f"/captures/{filename}",
                "timestamp": timestamp,
                "sha256": image_sha256,
            },
            "ml": {
                "onnx_model": Path(model_path).name,
                "onnx_model_path": model_path,
            },
            
            # AI defect analysis
            "defect_analysis": {
                "defect": fault_display,
                "confidence": float(confidence),
                "top_predictions": top
            },
            
            # Knowledge base context
            "knowledge_context": rag_context,
            
            # AI health report
            "health_report": suggestion,
            "gemini_error": gemini_error,
            
            # All sensor data
            "sensor_data": readings,
            "maintenance_task": maintenance_task,
        }
        
        return health_report
        
    except HTTPException as e:
        raise e
    except Exception as e:
        print(f"\n❌ ANALYSIS FAILED: {e}")
        raise HTTPException(status_code=500, detail=f"Analysis failed: {e}")


@app.post("/api/panel/maintenance-plan")
async def maintenance_plan(
    panel_id: str = Query(""),
    panelId: str = Query(""),
    onnx_model: str = Query(""),
    gemini_model: str = Query(""),
    force: int = Query(0),
):
    pid = (panel_id or "").strip() or (panelId or "").strip() or "PL01-B02-INV03-STR05-P01"
    try:
        image_bytes = _get_esp32_image()
        image_bytes, _ = _crop_solar_panel_bytes(image_bytes)
        timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
        filename = f"panel_{pid}_{timestamp}.jpg"
        file_path = CAPTURE_DIR / filename
        with open(file_path, "wb") as f:
            f.write(image_bytes)

        model_path = _resolve_model_path(onnx_model)

        fault, confidence, top = predict_image_bytes(model_path=model_path, image_bytes=image_bytes)
        defect = str(fault or "").strip()
        conf = float(confidence or 0)

        if defect.lower() == "clean" and conf >= 0.9:
            return {
                "status": "no_maintenance",
                "panel_id": pid,
                "timestamp": datetime.now().isoformat(),
                "image": {"filename": filename, "url": f"/captures/{filename}", "timestamp": timestamp},
                "defect_analysis": {"defect": None, "confidence": conf, "top_predictions": top},
                "maintenance_plan": "## Summary\n\nNo maintenance required. Continue monitoring and follow routine cleaning schedule.\n",
            }

        model_output = {
            "primary_defect": defect,
            "confidence": conf,
            "top_predictions": top,
            "panel_id": pid,
        }

        ensure_ingested(store)
        rag_query, rag_context = retrieve_context_from_model_output(store=store, model_output=model_output, k=3)
        if not rag_context:
            raise HTTPException(status_code=500, detail="RAG retrieval returned empty context")

        now = time.time()
        cache_key = f"maintenance::{pid}::{Path(model_path).name}::{(gemini_model.strip() or _pick_model())}::{filename}"
        cached = _GEMINI_CACHE.get(cache_key)
        cooldown_seconds = _get_gemini_cooldown_seconds()
        if cached and (now - float(cached.get("ts", 0))) < cooldown_seconds:
            plan_md = str(cached.get("suggestion") or "")
            gemini_error = cached.get("gemini_error")
        else:
            try:
                plan_md = generate_maintenance_plan(
                    model_output=model_output,
                    rag_context=rag_context,
                    model_override=(gemini_model.strip() or None),
                )
                gemini_error = None
            except GeminiRateLimit as e:
                plan_md = ""
                gemini_error = f"Gemini is rate-limited. Please retry after {int(e.retry_after_seconds)} seconds."
            except Exception as e:
                plan_md = ""
                gemini_error = f"Gemini call failed: {e}"

            _GEMINI_CACHE[cache_key] = {"ts": now, "suggestion": plan_md, "gemini_error": gemini_error}

        if plan_md and _should_trigger_cleaning_servo(plan_md):
            _trigger_cleaning_servo_async()

        return {
            "status": "maintenance_generated",
            "panel_id": pid,
            "timestamp": datetime.now().isoformat(),
            "image": {"filename": filename, "url": f"/captures/{filename}", "timestamp": timestamp, "sha256": image_sha256},
            "ml": {"onnx_model": Path(model_path).name, "onnx_model_path": model_path},
            "defect_analysis": {"defect": defect, "confidence": conf, "top_predictions": top},
            "knowledge_context": rag_context,
            "maintenance_plan": plan_md,
            "gemini_error": gemini_error,
        }
    except HTTPException as e:
        raise e
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"Failed to generate maintenance plan: {e}")

@app.get("/api/workflow/status")
def get_workflow_status():
    """Get current workflow status"""
    return {
        "backend": "online",
        "ml_model": Path(MODEL_PATH).exists(),
        "rag_store": store is not None,
        "capture_dir": CAPTURE_DIR.exists(),
        "esp32_url": _get_esp32_cam_url(),
        "aws_api": AWS_API_ENDPOINT,
        "captures_count": len(list(CAPTURE_DIR.glob("*.jpg")))
    }

@app.get("/api/diagnostic")
def diagnostic():
    """Diagnostic endpoint to check all components"""
    fallback_path = _get_fallback_image_path()
    diagnostics = {
        "model_path": MODEL_PATH,
        "model_exists": Path(MODEL_PATH).exists(),
        "capture_dir_exists": CAPTURE_DIR.exists(),
        "rag_store_initialized": store is not None,
        "gemini_api_key_set": bool(os.getenv("GEMINI_API_KEY")),
        "esp32_url": _get_esp32_cam_url(),
        "aws_api": AWS_API_ENDPOINT,
        "fallback_image_exists": bool(fallback_path),
        "fallback_image_path": str(fallback_path) if fallback_path else None
    }
    
    return diagnostics


@app.get("/api/weather/wardha")
def get_wardha_weather():
    cache_key = "wardha"
    now = time.time()
    cached = _WEATHER_CACHE.get(cache_key)
    if cached and (now - float(cached.get("ts", 0))) < 60:
        return cached.get("data")

    lat = float(os.getenv("WARDHA_LAT", "20.7453") or "20.7453")
    lon = float(os.getenv("WARDHA_LON", "78.6022") or "78.6022")

    api_key = _normalize_openweather_api_key(os.getenv("OPENWEATHER_API_KEY") or "")

    def store_and_return(payload: dict[str, Any]) -> dict[str, Any]:
        _WEATHER_CACHE[cache_key] = {"ts": now, "data": payload}
        return payload

    def fallback(note: Optional[str] = None) -> dict[str, Any]:
        data: dict[str, Any] = {
            "city": "Wardha",
            "condition": "Partly cloudy",
            "temperature_c": 31.0,
            "humidity_percent": 52,
            "timestamp": datetime.now().isoformat(),
            "source": "fallback",
        }
        if note:
            data["note"] = note
        return store_and_return(data)

    url = "https://api.openweathermap.org/data/2.5/weather"
    if not api_key:
        return fallback("Set OPENWEATHER_API_KEY in .env for live weather (https://openweathermap.org/api)")

    try:
        r = requests.get(
            url,
            params={
                "lat": lat,
                "lon": lon,
                "appid": api_key,
                "units": "metric",
            },
            timeout=10,
        )
        r.raise_for_status()
        payload = r.json() or {}

        main = payload.get("main") or {}
        if isinstance(payload, dict) and payload.get("message") and main.get("temp") is None:
            return fallback(str(payload.get("message")))

        weather_list = payload.get("weather") or []
        w0 = weather_list[0] if isinstance(weather_list, list) and weather_list else {}

        data = {
            "city": (payload.get("name") or "Wardha"),
            "condition": (w0.get("description") or w0.get("main") or "—"),
            "temperature_c": main.get("temp"),
            "humidity_percent": main.get("humidity"),
            "timestamp": datetime.now().isoformat(),
            "source": "openweather",
        }

        return store_and_return(data)
    except requests.exceptions.RequestException:
        if cached and cached.get("data"):
            return cached["data"]
        return fallback("OpenWeather request failed — check API key and network")
    except Exception as e:
        return fallback(str(e))
