import sys
import os
from flask import Flask, jsonify, request, Response, send_from_directory, abort
from flask_cors import CORS
import requests
import json
from dotenv import load_dotenv
from datetime import datetime, timedelta
from defect_detector import DefectDetector
from pathlib import Path
from urllib.parse import urlparse, urlunparse
import threading
import re

# Load environment variables from .env files (prefer repo root)
_HERE = Path(__file__).resolve()
load_dotenv(_HERE.parent / ".env")
load_dotenv(_HERE.parents[1] / ".env")
load_dotenv(_HERE.parents[2] / ".env")
load_dotenv(_HERE.parents[3] / ".env")
load_dotenv()

# Add parent directory to path to import rag_module
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..'))

# Initialize Flask app
app = Flask(__name__)
CORS(app)

TASKS_PATH = Path(__file__).resolve().parent / "panel_tasks.json"
COMPARISON_PATH = Path(__file__).resolve().parent / "panel_comparisons.json"
_COMPARISON_LOCK = threading.Lock()
_COMPARISON_RUNNING: dict = {}

# AWS API endpoint for live sensor data (I–V / P–V snapshot charts use this via /api/solar-iv-pv).
_DEFAULT_PANEL_READINGS = "https://ay8w848sv5.execute-api.us-east-1.amazonaws.com/default/solar-data"
# Time-series history for Voltage / Power / Current trend charts.
_DEFAULT_SOLAR_HISTORY = "https://tm6scx17o3.execute-api.us-east-1.amazonaws.com/solar-history"

AWS_API_ENDPOINT = os.getenv("AWS_API_ENDPOINT", _DEFAULT_PANEL_READINGS)
ASSET_ID = "cd29fe97-2d5e-47b4-a951-04c9e29544ac"

AWS_SOLAR_HISTORY_ENDPOINT = os.getenv("AWS_SOLAR_HISTORY_ENDPOINT", _DEFAULT_SOLAR_HISTORY)

# FastAPI (YOLOv8 + RAG + Gemini) backend base URL
FASTAPI_BACKEND_URL = os.getenv("FASTAPI_BACKEND_URL", "http://localhost:8000")


@app.route("/api/assets/<path:filename>", methods=["GET"])
def serve_asset(filename):
    base_dir = Path(__file__).resolve().parent
    shared_dir = (Path(__file__).resolve().parents[2] / "backend")

    candidate_dirs = [base_dir]
    if shared_dir.exists():
        candidate_dirs.append(shared_dir)

    safe_name = os.path.basename(filename)
    if not safe_name:
        abort(404)

    for d in candidate_dirs:
        fp = d / safe_name
        if fp.exists() and fp.is_file():
            return send_from_directory(str(d), safe_name)

    abort(404)

WARDHA_LAT = 20.7453
WARDHA_LON = 78.6022


def _normalize_openweather_api_key(raw: str) -> str:
    """Use first plausible token when OPENWEATHER_API_KEY contains commas or multiple pasted keys."""
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


def _wardha_weather_fallback(note=None):
    """Stable demo/fallback payload when OpenWeather is unavailable or misconfigured."""
    payload = {
        "city": "Wardha",
        "temperature_c": 31.0,
        "humidity_percent": 52,
        "pressure_hpa": 1012,
        "condition": "Partly cloudy",
        "wind_mps": 3.1,
        "timestamp": datetime.now().isoformat(),
        "source": "fallback",
    }
    if note:
        payload["note"] = note
    return jsonify(payload), 200

# Dummy panel data
DUMMY_PANELS = [
    {
        "id": "PL01-B02-INV03-STR05-P01",
        "name": "Solar Panel 1",
        "location": "Roof A",
        "capacity": 400,
        "current_output": 320,
        "health_score": 96,
        "last_update": datetime.now().isoformat()
    },
    {
        "id": "PL01-B02-INV03-STR05-P02",
        "name": "Solar Panel 2",
        "location": "Roof B",
        "capacity": 400,
        "current_output": 380,
        "health_score": 98,
        "last_update": datetime.now().isoformat()
    },
    {
        "id": "PL01-B02-INV03-STR05-P03",
        "name": "Solar Panel 3",
        "location": "Roof C",
        "capacity": 400,
        "current_output": 290,
        "health_score": 95,
        "last_update": datetime.now().isoformat()
    }
]

# ==================== API ENDPOINTS ====================

def _load_tasks() -> dict:
    try:
        if TASKS_PATH.exists():
            with open(TASKS_PATH, "r", encoding="utf-8") as f:
                data = json.load(f)
                return data if isinstance(data, dict) else {}
    except Exception as e:
        print(f"❌ Failed to load tasks: {e}")
    return {}


def _save_tasks(tasks: dict) -> None:
    try:
        tmp = str(TASKS_PATH) + ".tmp"
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump(tasks, f, ensure_ascii=False, indent=2)
        os.replace(tmp, TASKS_PATH)
    except Exception as e:
        print(f"❌ Failed to save tasks: {e}")
        raise


def _load_comparisons() -> dict:
    try:
        if COMPARISON_PATH.exists():
            with open(COMPARISON_PATH, "r", encoding="utf-8") as f:
                data = json.load(f)
                return data if isinstance(data, dict) else {}
    except Exception as e:
        print(f"❌ Failed to load comparisons: {e}")
    return {}


def _save_comparisons(comparisons: dict) -> None:
    try:
        tmp = str(COMPARISON_PATH) + ".tmp"
        with open(tmp, "w", encoding="utf-8") as f:
            json.dump(comparisons, f, ensure_ascii=False, indent=2)
        os.replace(tmp, COMPARISON_PATH)
    except Exception as e:
        print(f"❌ Failed to save comparisons: {e}")
        raise


def _calc_improvement(power_before, power_after):
    try:
        pb = float(power_before)
        pa = float(power_after)
        if pb == 0:
            return None
        return ((pa - pb) / pb) * 100.0
    except Exception:
        return None


def _resolution_from_improvement(improvement_percent):
    try:
        imp = float(improvement_percent)
        if imp > 10.0:
            return "Resolved"
        if imp >= 3.0:
            return "Monitor"
        return "Escalate"
    except Exception:
        return "Escalate"


def _extract_power_from_sensor_data(sensor_data):
    if not isinstance(sensor_data, dict):
        return None

    # Common alternate keys
    for alt in ("P", "POWER", "power", "power_w", "powerW", "Power"):
        if alt in sensor_data:
            v = sensor_data.get(alt)
            if isinstance(v, (int, float)):
                try:
                    return float(v)
                except Exception:
                    pass
            if isinstance(v, dict) and "value" in v:
                try:
                    vv = v.get("value")
                    if isinstance(vv, dict) and "value" in vv:
                        vv = vv.get("value")
                    return float(vv)
                except Exception:
                    pass

    # Direct numeric values
    for key in ("P1", "P2", "P3"):
        if key in sensor_data and isinstance(sensor_data.get(key), (int, float)):
            try:
                return float(sensor_data.get(key))
            except Exception:
                pass

    # If multiple P channels exist, return sum when possible
    try:
        p_vals = []
        for key in ("P1", "P2", "P3"):
            v = sensor_data.get(key)
            if isinstance(v, dict) and "value" in v:
                v = v.get("value")
                if isinstance(v, dict) and "value" in v:
                    v = v.get("value")
            if isinstance(v, (int, float)):
                p_vals.append(float(v))
        if p_vals:
            return float(sum(p_vals))
    except Exception:
        pass

    p1 = sensor_data.get("P1")
    if isinstance(p1, dict) and "value" in p1:
        try:
            v = p1.get("value")
            if isinstance(v, dict) and "value" in v:
                v = v.get("value")
            return float(v)
        except Exception:
            pass
    for k, v in sensor_data.items():
        if not str(k).upper().startswith("P"):
            continue

        if isinstance(v, (int, float)):
            try:
                return float(v)
            except Exception:
                continue

        if isinstance(v, dict) and "value" in v:
            try:
                vv = v.get("value")
                if isinstance(vv, dict) and "value" in vv:
                    vv = vv.get("value")
                return float(vv)
            except Exception:
                continue
    return None


def _safe_abs(v):
    try:
        fv = float(v)
        return abs(fv)
    except Exception:
        return v


def _flatten_sensor_payload(sensor_payload: dict) -> dict:
    """Accept both AWS shape (V1/P1 at top level) and FastAPI shape (voltage/power nested)."""
    if not isinstance(sensor_payload, dict):
        return {}

    flattened = dict(sensor_payload)

    # FastAPI sensor_data often contains: { voltage: {V1,V2,V3}, power: {P1,P2,P3}, current: ... }
    voltage = sensor_payload.get("voltage")
    if isinstance(voltage, dict):
        for k, v in voltage.items():
            # v may be numeric or {value: ...}
            if isinstance(v, dict) and "value" in v:
                flattened[k] = v
            else:
                flattened[k] = {"value": v}

    power = sensor_payload.get("power")
    if isinstance(power, dict):
        for k, v in power.items():
            if isinstance(v, dict) and "value" in v:
                flattened[k] = v
            else:
                flattened[k] = {"value": v}

    return flattened


def _compute_deviation_percent(sensor_data):
    """Simple deviation proxy for UI; uses V1 vs average(V2,V3) when available."""
    if not isinstance(sensor_data, dict):
        return None
    sensor_data = _flatten_sensor_payload(sensor_data)
    try:
        v1 = _safe_abs(sensor_data.get("V1", {}).get("value"))
        v2 = _safe_abs(sensor_data.get("V2", {}).get("value"))
        v3 = _safe_abs(sensor_data.get("V3", {}).get("value"))
        v1 = float(v1) if v1 is not None else None
        v2 = float(v2) if v2 is not None else None
        v3 = float(v3) if v3 is not None else None
        vals = [x for x in (v2, v3) if isinstance(x, float)]
        if not isinstance(v1, float) or not vals:
            return None
        baseline = sum(vals) / len(vals)
        if baseline == 0:
            return None
        return (abs(v1 - baseline) / baseline) * 100.0
    except Exception:
        return None


def _fetch_fastapi_auto_analyze(panel_id: str) -> dict:
    url = f"{FASTAPI_BACKEND_URL.rstrip('/')}/api/panel/auto-analyze"
    resp = requests.post(url, params={"panel_id": panel_id}, timeout=180)
    if resp.status_code >= 400:
        raise RuntimeError(f"FastAPI auto-analyze error {resp.status_code}: {resp.text[:300]}")
    return resp.json() or {}


def _fetch_aws_sensor_values() -> dict:
    """Fallback sensor fetch. Returns AWS values payload (same shape as /api/panel/readings)."""
    resp = requests.get(AWS_API_ENDPOINT, timeout=8)
    if resp.status_code >= 400:
        raise RuntimeError(f"AWS values error {resp.status_code}: {resp.text[:200]}")
    payload = resp.json() or {}
    return payload if isinstance(payload, dict) else {}


def _power_and_deviation_from_any_sensor_payload(sensor_payload: dict):
    flattened = _flatten_sensor_payload(sensor_payload)
    power = _extract_power_from_sensor_data(flattened)
    deviation = _compute_deviation_percent(flattened)
    return power, deviation


def _normalize_image_url(image_obj_or_url):
    """FastAPI returns /captures/<file>. Convert to absolute URL using FASTAPI_BACKEND_URL."""
    if isinstance(image_obj_or_url, dict):
        image_obj_or_url = image_obj_or_url.get("url")
    u = (image_obj_or_url or "").strip()
    if not u:
        return None
    if u.startswith("http://") or u.startswith("https://"):
        return u
    base = (FASTAPI_BACKEND_URL or "").rstrip("/")
    return f"{base}{u}" if base and u.startswith("/") else u


@app.route("/api/panel/comparison/before", methods=["GET", "POST"])
def panel_comparison_before():
    panel_id = request.args.get("panel_id") or request.args.get("panelId") or ""
    panel_id = panel_id.strip() or "PL01-B02-INV03-STR05-P01"

    if request.method == "GET":
        comps = _load_comparisons()
        rec = comps.get(panel_id) or {}
        return jsonify(rec.get("before") or {}), 200

    # POST: store BEFORE snapshot from latest FastAPI analysis.
    try:
        report = _fetch_fastapi_auto_analyze(panel_id)
        sensor_data = report.get("sensor_data") or {}
        power, deviation = _power_and_deviation_from_any_sensor_payload(sensor_data)

        if power is None or deviation is None:
            try:
                aws_payload = _fetch_aws_sensor_values()
                power2, deviation2 = _power_and_deviation_from_any_sensor_payload(aws_payload)
                power = power if power is not None else power2
                deviation = deviation if deviation is not None else deviation2
            except Exception:
                pass
        before = {
            "panel_id": panel_id,
            "power_before": power,
            "fault_severity": (report.get("defect_analysis") or {}).get("defect"),
            "deviation_percent": deviation,
            "before_image_url": _normalize_image_url((report.get("image") or {}).get("url")),
            "health_status": "" ,
            "health_report": report,
            "timestamp": datetime.now().isoformat(),
        }

        with _COMPARISON_LOCK:
            comps = _load_comparisons()
            rec = comps.get(panel_id) or {}
            rec["before"] = before
            rec["latest_before_at"] = before["timestamp"]
            comps[panel_id] = rec
            _save_comparisons(comps)

        return jsonify(before), 200
    except Exception as e:
        return jsonify({"error": "Failed to capture before snapshot", "message": str(e)}), 500


@app.route("/api/panel/comparison/latest", methods=["GET"])
def panel_comparison_latest():
    panel_id = request.args.get("panel_id") or request.args.get("panelId") or ""
    panel_id = panel_id.strip() or "PL01-B02-INV03-STR05-P01"
    comps = _load_comparisons()
    rec = comps.get(panel_id) or {}
    latest = rec.get("latest") or {}
    return jsonify(latest), 200


@app.route("/api/panel/comparison/run", methods=["POST"])
def panel_comparison_run():
    panel_id = request.args.get("panel_id") or request.args.get("panelId") or ""
    panel_id = panel_id.strip() or "PL01-B02-INV03-STR05-P01"

    with _COMPARISON_LOCK:
        if _COMPARISON_RUNNING.get(panel_id):
            return jsonify({"error": "Comparison already running", "panel_id": panel_id}), 409
        _COMPARISON_RUNNING[panel_id] = True

    try:
        comps = _load_comparisons()
        rec = comps.get(panel_id) or {}
        before = rec.get("before") or {}
        power_before = before.get("power_before")

        # capture AFTER
        report_after = _fetch_fastapi_auto_analyze(panel_id)
        sensor_after = report_after.get("sensor_data") or {}
        power_after, deviation_after = _power_and_deviation_from_any_sensor_payload(sensor_after)

        if power_after is None or deviation_after is None:
            try:
                aws_payload = _fetch_aws_sensor_values()
                power2, deviation2 = _power_and_deviation_from_any_sensor_payload(aws_payload)
                power_after = power_after if power_after is not None else power2
                deviation_after = deviation_after if deviation_after is not None else deviation2
            except Exception:
                pass

        improvement = _calc_improvement(power_before, power_after)
        resolution = _resolution_from_improvement(improvement)

        after = {
            "panel_id": panel_id,
            "power_after": power_after,
            "deviation_percent": deviation_after,
            "after_image_url": _normalize_image_url((report_after.get("image") or {}).get("url")),
            "health_status": "",
            "health_report": report_after,
            "timestamp": datetime.now().isoformat(),
        }

        latest = {
            "panel_id": panel_id,
            "power_before": power_before,
            "power_after": power_after,
            "improvement_percent": improvement,
            "resolution_status": resolution,
            "before_image_url": before.get("before_image_url"),
            "after_image_url": after.get("after_image_url"),
            "timestamp": after["timestamp"],
            "before": before,
            "after": after,
        }

        with _COMPARISON_LOCK:
            comps = _load_comparisons()
            rec = comps.get(panel_id) or {}
            rec["latest"] = latest
            rec["after"] = after
            rec["updated_at"] = datetime.now().isoformat()
            comps[panel_id] = rec
            _save_comparisons(comps)

        return jsonify(latest), 200
    except Exception as e:
        return jsonify({"error": "Failed to run comparison", "message": str(e)}), 500
    finally:
        with _COMPARISON_LOCK:
            _COMPARISON_RUNNING[panel_id] = False

@app.route("/", methods=["GET"])
def index():
    """Root endpoint"""
    return jsonify({"message": "Solar Dashboard Backend API", "version": "1.0"}), 200

@app.route("/api/health", methods=["GET"])
def health():
    """Health check endpoint"""
    return jsonify({"status": "ok", "service": "solar-dashboard-backend"}), 200


@app.route("/api/weather/wardha", methods=["GET"])
def get_weather_wardha():
    """Fetch live weather for Wardha using OpenWeather; fallback when key/API fails."""
    env_key = _normalize_openweather_api_key(os.getenv("OPENWEATHER_API_KEY", "") or "")
    api_key = env_key or request.args.get("appid") or ""

    url = "https://api.openweathermap.org/data/2.5/weather"
    if not api_key:
        return _wardha_weather_fallback("missing OPENWEATHER_API_KEY — add a key from https://openweathermap.org/api")

    try:
        resp = requests.get(
            url,
            params={"lat": WARDHA_LAT, "lon": WARDHA_LON, "appid": api_key, "units": "metric"},
            timeout=10,
        )
        if resp.status_code >= 400:
            body_preview = (resp.text or "")[:200]
            print(f"⚠️ OpenWeather HTTP {resp.status_code}: {body_preview}")
            return _wardha_weather_fallback(f"OpenWeather returned {resp.status_code}")

        data = resp.json()
        main = data.get("main") or {}
        if isinstance(data, dict) and data.get("message") and main.get("temp") is None:
            return _wardha_weather_fallback(str(data.get("message")))

        weather0 = (data.get("weather") or [{}])[0] or {}
        wind = data.get("wind") or {}

        return (
            jsonify(
                {
                    "city": "Wardha",
                    "temperature_c": main.get("temp"),
                    "humidity_percent": main.get("humidity"),
                    "pressure_hpa": main.get("pressure"),
                    "condition": weather0.get("main") or weather0.get("description"),
                    "wind_mps": wind.get("speed"),
                    "timestamp": datetime.now().isoformat(),
                    "source": "openweather",
                }
            ),
            200,
        )
    except requests.exceptions.Timeout:
        print("⚠️ OpenWeather timeout")
        return _wardha_weather_fallback("OpenWeather timeout")
    except Exception as e:
        print(f"⚠️ OpenWeather error: {e}")
        return _wardha_weather_fallback(str(e))

@app.route("/api/panels/all", methods=["GET"])
def get_all_panels():
    """Get all solar panels"""
    try:
        return jsonify(DUMMY_PANELS), 200
    except Exception as e:
        print(f"❌ Error fetching panels: {e}")
        return jsonify({"error": "Failed to fetch panels", "message": str(e)}), 500

@app.route("/api/panel/info", methods=["GET"])
def get_panel_info():
    """Get panel information"""
    try:
        panel_id = request.args.get("panelId", "PL01-B02-INV03-STR05-P01")
        
        # Find panel by ID
        panel = next((p for p in DUMMY_PANELS if p["id"] == panel_id), None)
        
        if panel:
            return jsonify(panel), 200
        else:
            return jsonify({"error": "Panel not found"}), 404
            
    except Exception as e:
        print(f"❌ Error fetching panel info: {e}")
        return jsonify({"error": "Failed to fetch panel info", "message": str(e)}), 500

def _unwrap_live_readings_payload(data):
    """Flatten [{snapshot}], {\"data\": [...]}, or API Gateway {body: \"json\"} to one dict."""
    if isinstance(data, dict):
        body = data.get("body")
        if isinstance(body, str) and body.strip():
            try:
                data = json.loads(body)
            except Exception:
                pass
        if isinstance(data, dict) and isinstance(data.get("data"), (dict, list)):
            data = data.get("data")
    if isinstance(data, list):
        for row in reversed(data):
            if isinstance(row, dict) and not row.get("error"):
                return dict(row)
        return {}
    return dict(data) if isinstance(data, dict) else {}


def _sensor_current_to_amps(n):
    try:
        v = float(n)
    except (TypeError, ValueError):
        return 0.0
    v = abs(v)
    return v / 1000.0 if v > 50.0 else v


def _enrich_flat_readings_row(row):
    """Add aggregate I and P1–P4 when AWS sends only I1–I4 / V1–V4 (plain numbers)."""
    if not isinstance(row, dict):
        return row
    if any(isinstance(val, dict) for val in row.values()):
        return row
    out = dict(row)
    if out.get("I") is None:
        total_a = 0.0
        any_i = False
        for k in ("I1", "I2", "I3", "I4"):
            if k not in out or out[k] is None:
                continue
            any_i = True
            total_a += _sensor_current_to_amps(out[k])
        if any_i:
            out["I"] = total_a
    for i in range(1, 5):
        pk = f"P{i}"
        if out.get(pk) is not None:
            continue
        vk, ik = f"V{i}", f"I{i}"
        if vk not in out and ik not in out:
            continue
        try:
            vv = float(out.get(vk) or 0)
            ia = _sensor_current_to_amps(out.get(ik) or 0)
            out[pk] = abs(vv * ia)
        except (TypeError, ValueError):
            pass
    return out


@app.route("/api/panel/readings", methods=["GET"])
def get_panel_readings():
    """Get real-time sensor readings from AWS API"""
    try:
        asset_id = request.args.get("assetId", ASSET_ID)
        
        print(f"📡 Fetching sensor data from AWS API: {AWS_API_ENDPOINT}")
        
        # Fetch from AWS API (no asset_id parameter needed for new endpoint)
        response = requests.get(
            AWS_API_ENDPOINT,
            timeout=5
        )
        response.raise_for_status()
        
        raw = response.json()
        row = _unwrap_live_readings_payload(raw)
        row = _enrich_flat_readings_row(row)
        print(f"✅ Real sensor data received from AWS API")
        print(f"Data: {row}")
        
        return jsonify(row), 200
        
    except requests.exceptions.Timeout:
        print(f"⏱️ AWS API timeout, using dummy data")
        dummy_sensor_data = _get_dummy_sensor_data(asset_id)
        return jsonify(dummy_sensor_data), 200
        
    except requests.exceptions.RequestException as e:
        print(f"❌ Error fetching from AWS API: {e}")
        dummy_sensor_data = _get_dummy_sensor_data(asset_id)
        return jsonify(dummy_sensor_data), 200


@app.route("/api/panel/predictive-maintenance", methods=["GET"])
def get_predictive_maintenance():
    """Return a lightweight predictive maintenance summary.

    React UI expects this endpoint. We derive predictions from current panel info
    and return stable fields for dashboard rendering.
    """
    panel_id = request.args.get("panel_id") or request.args.get("panelId") or "PL01-B02-INV03-STR05-P01"

    try:
        # Prefer pulling a health score from panel info if available.
        panel = next((p for p in DUMMY_PANELS if p.get("id") == panel_id), None)
        health = None
        if panel:
            try:
                health = float(panel.get("health_score"))
            except Exception:
                health = None

        if health is None:
            # Default to mid-range if unknown.
            health = 90.0

        # Simple heuristic projections.
        predicted_30 = max(0.0, min(100.0, health - 2.5))
        predicted_90 = max(0.0, min(100.0, health - 6.0))

        if health < 75:
            priority = "High"
            trend = "decreasing"
            next_days = 7
        elif health < 90:
            priority = "Medium"
            trend = "stable"
            next_days = 21
        else:
            priority = "Low"
            trend = "improving"
            next_days = 45

        return (
            jsonify(
                {
                    "panel_id": panel_id,
                    "maintenance_priority": priority,
                    "trend": trend,
                    "predicted_efficiency_30days": predicted_30,
                    "predicted_efficiency_90days": predicted_90,
                    "next_maintenance_recommended_days": next_days,
                    "timestamp": datetime.now().isoformat(),
                }
            ),
            200,
        )
    except Exception as e:
        return jsonify({"error": "Failed to compute predictive maintenance", "message": str(e)}), 500


@app.route("/api/solar-history", methods=["GET"])
def get_solar_history():
    """Proxy historical solar panel data from AWS API Gateway to avoid browser CORS."""
    asset_id = request.args.get("assetId", "SolarPanel_01")
    try:
        resp = requests.get(
            AWS_SOLAR_HISTORY_ENDPOINT,
            params={"assetId": asset_id},
            timeout=10,
        )

        if resp.status_code >= 400:
            return (
                jsonify(
                    {
                        "error": "AWS solar-history returned error",
                        "status": resp.status_code,
                        "body": resp.text,
                    }
                ),
                resp.status_code,
            )

        try:
            data = resp.json()
        except Exception:
            return (
                jsonify(
                    {
                        "error": "AWS solar-history response was not valid JSON",
                        "status": resp.status_code,
                        "body": resp.text,
                    }
                ),
                502,
            )

        if not isinstance(data, list):
            return (
                jsonify(
                    {
                        "error": "Unexpected solar-history response",
                        "message": "Expected a JSON array",
                        "received_type": str(type(data)),
                    }
                ),
                502,
            )

        return jsonify(data), 200
    except requests.exceptions.Timeout:
        return jsonify({"error": "AWS solar-history timeout"}), 504
    except requests.exceptions.RequestException as e:
        return jsonify({"error": "Failed to fetch solar-history", "message": str(e)}), 502


@app.route("/api/solar-iv-pv", methods=["GET"])
def get_solar_iv_pv():
    """Latest JSON from AWS_API_ENDPOINT for I–V / P–V (same source as live panel readings)."""
    try:
        resp = requests.get(AWS_API_ENDPOINT, timeout=8)

        if resp.status_code >= 400:
            return (
                jsonify(
                    {
                        "error": "AWS solar snapshot returned error",
                        "status": resp.status_code,
                        "body": resp.text,
                    }
                ),
                resp.status_code,
            )

        try:
            data = resp.json()
        except Exception:
            return (
                jsonify(
                    {
                        "error": "AWS solar snapshot was not valid JSON",
                        "status": resp.status_code,
                        "body": resp.text,
                    }
                ),
                502,
            )

        if isinstance(data, list):
            return jsonify(data), 200
        if isinstance(data, dict):
            return jsonify(data), 200

        return (
            jsonify(
                {
                    "error": "Unexpected solar snapshot response",
                    "message": "Expected a JSON object or array",
                    "received_type": str(type(data)),
                }
            ),
            502,
        )
    except requests.exceptions.Timeout:
        return jsonify({"error": "AWS solar snapshot timeout"}), 504
    except requests.exceptions.RequestException as e:
        return jsonify({"error": "Failed to fetch solar snapshot", "message": str(e)}), 502


@app.route("/api/panel/health-report", methods=["GET"])
def get_panel_health_report():
    """Generate/Fetch health report from FastAPI (YOLOv8 + RAG + Gemini) backend."""
    panel_id = request.args.get("panel_id") or request.args.get("panelId") or "PL01-B02-INV03-STR05-P01"

    try:
        url = f"{FASTAPI_BACKEND_URL.rstrip('/')}/api/panel/auto-analyze"
        print(f"🤖 Proxying health report request to FastAPI: {url} (panel_id={panel_id})")

        resp = requests.post(url, params={"panel_id": panel_id}, timeout=120)
        if resp.status_code >= 400:
            print(f"❌ FastAPI responded with {resp.status_code}: {resp.text[:500]}")
            return (
                jsonify(
                    {
                        "error": "FastAPI returned error",
                        "fastapi_status": resp.status_code,
                        "fastapi_body": resp.text,
                    }
                ),
                resp.status_code,
            )

        try:
            return jsonify(resp.json()), 200
        except Exception:
            return (
                jsonify(
                    {
                        "error": "FastAPI response was not valid JSON",
                        "fastapi_status": resp.status_code,
                        "fastapi_body": resp.text,
                    }
                ),
                502,
            )
    except requests.exceptions.Timeout:
        return jsonify({"error": "FastAPI health report timeout"}), 504
    except requests.exceptions.ConnectionError as e:
        print(f"❌ Cannot connect to FastAPI at {FASTAPI_BACKEND_URL}: {e}")
        return (
            jsonify(
                {
                    "error": "Cannot connect to FastAPI backend",
                    "fastapi_base_url": FASTAPI_BACKEND_URL,
                    "message": str(e),
                }
            ),
            502,
        )
    except requests.exceptions.RequestException as e:
        print(f"❌ Error fetching health report from FastAPI: {e}")
        status = getattr(getattr(e, "response", None), "status_code", None)
        body = getattr(getattr(e, "response", None), "text", None)
        return (
            jsonify(
                {
                    "error": "Failed to fetch health report from FastAPI",
                    "fastapi_base_url": FASTAPI_BACKEND_URL,
                    "fastapi_status": status,
                    "fastapi_body": body,
                    "message": str(e),
                }
            ),
            502,
        )


@app.route("/api/panel/task", methods=["GET", "PUT"])
def panel_task():
    panel_id = request.args.get("panel_id") or request.args.get("panelId")
    if request.method == "GET":
        if not panel_id:
            return jsonify({"error": "panel_id is required"}), 400
        tasks = _load_tasks()
        return jsonify(tasks.get(panel_id) or {}), 200

    # PUT
    payload = request.get_json(silent=True) or {}
    panel_id = panel_id or payload.get("panel_id") or payload.get("panelId")
    if not panel_id:
        return jsonify({"error": "panel_id is required"}), 400

    allowed_status = {"PENDING", "IN_PROGRESS", "DONE"}
    status = (payload.get("status") or "PENDING").strip().upper()
    if status not in allowed_status:
        return jsonify({"error": "Invalid status", "allowed": sorted(list(allowed_status))}), 400

    record = {
        "panel_id": panel_id,
        "technician": (payload.get("technician") or "").strip(),
        "status": status,
        "notes": (payload.get("notes") or "").strip(),
        "suggested_work": (payload.get("suggested_work") or "").strip(),
        "updated_at": datetime.now().isoformat(),
    }

    tasks = _load_tasks()
    tasks[panel_id] = record
    try:
        _save_tasks(tasks)
    except Exception as e:
        return jsonify({"error": "Failed to save task", "message": str(e)}), 500

    return jsonify(record), 200


@app.route("/api/panel/maintenance-plan", methods=["POST"])
def get_panel_maintenance_plan():
    """Generate maintenance plan from FastAPI (YOLOv8 + RAG + Gemini) backend."""
    panel_id = request.args.get("panel_id") or request.args.get("panelId") or "PL01-B02-INV03-STR05-P01"

    try:
        url = f"{FASTAPI_BACKEND_URL.rstrip('/')}/api/panel/maintenance-plan"
        print(f"🛠️ Proxying maintenance plan request to FastAPI: {url} (panel_id={panel_id})")

        resp = requests.post(url, params={"panel_id": panel_id}, timeout=180)
        if resp.status_code >= 400:
            print(f"❌ FastAPI responded with {resp.status_code}: {resp.text[:500]}")
            return (
                jsonify(
                    {
                        "error": "FastAPI returned error",
                        "fastapi_status": resp.status_code,
                        "fastapi_body": resp.text,
                    }
                ),
                resp.status_code,
            )

        try:
            return jsonify(resp.json()), 200
        except Exception:
            return (
                jsonify(
                    {
                        "error": "FastAPI response was not valid JSON",
                        "fastapi_status": resp.status_code,
                        "fastapi_body": resp.text,
                    }
                ),
                502,
            )
    except requests.exceptions.Timeout:
        return jsonify({"error": "FastAPI maintenance plan timeout"}), 504
    except requests.exceptions.ConnectionError as e:
        print(f"❌ Cannot connect to FastAPI at {FASTAPI_BACKEND_URL}: {e}")
        return (
            jsonify(
                {
                    "error": "Cannot connect to FastAPI backend",
                    "fastapi_base_url": FASTAPI_BACKEND_URL,
                    "message": str(e),
                }
            ),
            502,
        )
    except requests.exceptions.RequestException as e:
        print(f"❌ Error fetching maintenance plan from FastAPI: {e}")
        status = getattr(getattr(e, "response", None), "status_code", None)
        body = getattr(getattr(e, "response", None), "text", None)
        return (
            jsonify(
                {
                    "error": "Failed to fetch maintenance plan from FastAPI",
                    "fastapi_base_url": FASTAPI_BACKEND_URL,
                    "fastapi_status": status,
                    "fastapi_body": body,
                    "message": str(e),
                }
            ),
            502,
        )

def _get_dummy_sensor_data(asset_id):
    """Return dummy sensor data as fallback"""
    return {
        "I1": {"value": 272, "timestamp": 1768827220},
        "I2": {"value": 386, "timestamp": 1768827220},
        "P1": {"value": 1.84, "timestamp": 1768827220},
        "P2": {"value": 1.84, "timestamp": 1768827220},
        "P3": {"value": 2.72, "timestamp": 1768827220},
        "P4": {"value": 2.72, "timestamp": 1768827220},
        "V1": {"value": 6.46, "timestamp": 1768827220},
        "V2": {"value": 7.07, "timestamp": 1768827220},
        "V3": {"value": 7.35, "timestamp": 1768827220},
        "V4": {"value": 6.75, "timestamp": 1768827220}
    }

@app.route("/api/camera/feed", methods=["GET"])
def get_camera_feed():
    """Proxy endpoint to fetch camera feed from ESP32 camera"""
    fallback_jpg = os.path.join(os.path.dirname(__file__), "image.jpg")
    fallback_png = os.path.join(os.path.dirname(__file__), "image.png")
    shared_fallback_jpg = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", "..", "backend", "image.jpg"))
    shared_fallback_png = os.path.normpath(os.path.join(os.path.dirname(__file__), "..", "..", "backend", "image.png"))

    def _get_fallback_path():
        if os.path.exists(fallback_jpg):
            return fallback_jpg
        if os.path.exists(shared_fallback_jpg):
            return shared_fallback_jpg
        if os.path.exists(fallback_png):
            return fallback_png
        if os.path.exists(shared_fallback_png):
            return shared_fallback_png
        return None

    def _candidate_camera_urls(raw: str):
        raw = (raw or "").strip()
        if not raw:
            return []

        p = urlparse(raw)
        if not p.scheme:
            p = urlparse("http://" + raw)

        path = p.path or "/"
        if path != "/" and path.endswith("/"):
            path = path[:-1]
        base_path = "/" if path in ("", "/") else path

        base = urlunparse((p.scheme, p.netloc, base_path, "", "", ""))
        base_slash = base if base.endswith("/") else base + "/"

        capture = base if base_path.endswith("/capture") else base_slash + "capture"
        stream = base if base_path.endswith("/stream") else base_slash + "stream"
        jpg = base if base_path.endswith("/jpg") else base_slash + "jpg"

        urls = []
        # Prefer single-image endpoints first
        for u in (capture, jpg, raw, base_slash, stream):
            if u and u not in urls:
                urls.append(u)
        return urls

    def _fallback_image_response():
        try:
            fp = _get_fallback_path()
            if fp:
                mt = "image/jpeg" if fp.lower().endswith(".jpg") else "image/png"
                with open(fp, "rb") as f:
                    return Response(f.read(), mimetype=mt)
        except Exception as e:
            print(f"❌ Error reading fallback image: {e}")
        return jsonify({"error": "Camera feed unavailable and fallback image missing"}), 503

    try:
        camera_url = request.args.get("url")
        
        if not camera_url:
            return jsonify({"error": "Camera URL parameter is required"}), 400
        
        last_error = None
        for url in _candidate_camera_urls(camera_url):
            try:
                print(f"📷 Fetching camera feed from: {url}")
                response = requests.get(url, timeout=10)
                response.raise_for_status()

                content_type = (response.headers.get("content-type") or "").lower()
                body = response.content or b""
                is_jpeg = body.startswith(b"\xff\xd8\xff")
                is_png = body.startswith(b"\x89PNG\r\n\x1a\n")
                if not ("image/" in content_type or is_jpeg or is_png):
                    raise requests.exceptions.RequestException(
                        f"Camera response is not an image (content-type={content_type or 'unknown'}, size={len(body)})"
                    )

                return Response(body, mimetype=(content_type if "image/" in content_type else "image/jpeg"))
            except requests.exceptions.RequestException as e:
                last_error = e
                continue

        print(f"❌ Cannot fetch image from camera: {last_error}")
        return _fallback_image_response()
        
    except requests.exceptions.Timeout:
        print(f"⏱️ Camera request timeout")
        return _fallback_image_response()
        
    except requests.exceptions.ConnectionError:
        print(f"❌ Cannot connect to camera at {camera_url}")
        return _fallback_image_response()
        
    except Exception as e:
        print(f"❌ Error fetching camera feed: {e}")
        return _fallback_image_response()

if __name__ == "__main__":
    print("🚀 Starting Solar Dashboard Backend...")
    print(f"📡 AWS API Endpoint: {AWS_API_ENDPOINT}")
    print(f"🔑 Asset ID: {ASSET_ID}")
    print("🌐 Server running on http://localhost:5000")
    app.run(host="0.0.0.0", port=5000, debug=True)

