from __future__ import annotations

import os
from pathlib import Path
from typing import Dict, List, Tuple

import numpy as np
import onnxruntime as ort
from PIL import Image


CLASSES: List[str] = [
    "Bird-drop",
    "Clean",
    "Dusty",
    "Electrical-damage",
    "Physical-Damage",
    "Snow-Covered",
]


def _softmax(x: np.ndarray) -> np.ndarray:
    x = x.astype("float32")
    x = x - np.max(x)
    e = np.exp(x)
    return e / np.sum(e)


def _parse_float_csv(value: str, expected_len: int) -> np.ndarray:
    parts = [p.strip() for p in value.split(",") if p.strip()]
    if len(parts) != expected_len:
        raise ValueError(f"Expected {expected_len} comma-separated floats, got: {value}")
    return np.array([float(p) for p in parts], dtype="float32")


def _env_flag(name: str, default: bool) -> bool:
    v = os.getenv(name)
    if v is None:
        return default
    return v.strip() not in ("0", "false", "FALSE", "no", "NO")


def _env_int(name: str, default: int) -> int:
    v = os.getenv(name)
    if v is None:
        return default
    try:
        n = int(str(v).strip())
        return n if n > 0 else default
    except Exception:
        return default


def _letterbox_pil(img: Image.Image, size: int, fill: tuple[int, int, int]) -> Image.Image:
    img = img.convert("RGB")
    w, h = img.size
    if w <= 0 or h <= 0:
        return img.resize((size, size))

    r = min(size / w, size / h)
    new_w = max(1, int(round(w * r)))
    new_h = max(1, int(round(h * r)))
    resized = img.resize((new_w, new_h), resample=Image.BILINEAR)

    canvas = Image.new("RGB", (size, size), fill)
    left = (size - new_w) // 2
    top = (size - new_h) // 2
    canvas.paste(resized, (left, top))
    return canvas


def _clahe_rgb(arr01: np.ndarray) -> np.ndarray:
    try:
        import cv2  # type: ignore
    except Exception:
        return arr01

    rgb_u8 = np.clip(arr01 * 255.0, 0, 255).astype(np.uint8)
    lab = cv2.cvtColor(rgb_u8, cv2.COLOR_RGB2LAB)
    l, a, b = cv2.split(lab)
    clip_limit = float(os.getenv("ONNX_CLAHE_CLIP", "2.0"))
    grid = _env_int("ONNX_CLAHE_GRID", 8)
    clahe = cv2.createCLAHE(clipLimit=max(0.1, clip_limit), tileGridSize=(grid, grid))
    l2 = clahe.apply(l)
    lab2 = cv2.merge((l2, a, b))
    rgb2 = cv2.cvtColor(lab2, cv2.COLOR_LAB2RGB)
    return (rgb2.astype("float32") / 255.0).astype("float32")


def preprocess_image(img: Image.Image) -> np.ndarray:
    input_size = _env_int("ONNX_INPUT_SIZE", 224)
    letterbox = _env_flag("ONNX_LETTERBOX", False)
    fill_value = _env_int("ONNX_LETTERBOX_FILL", 114)
    fill = (fill_value, fill_value, fill_value)

    img = _letterbox_pil(img, input_size, fill) if letterbox else img.convert("RGB").resize((input_size, input_size))

    arr = np.asarray(img).astype("float32") / 255.0

    if _env_flag("ONNX_CLAHE", False):
        arr = _clahe_rgb(arr)

    normalize = _env_flag("ONNX_NORMALIZE", False)
    if normalize:
        mean_env = os.getenv("ONNX_MEAN")
        std_env = os.getenv("ONNX_STD")
        mean = (
            _parse_float_csv(mean_env, 3)
            if mean_env
            else np.array([0.485, 0.456, 0.406], dtype="float32")
        )
        std = (
            _parse_float_csv(std_env, 3)
            if std_env
            else np.array([0.229, 0.224, 0.225], dtype="float32")
        )
        arr = (arr - mean) / std

    # HWC -> CHW
    arr = np.transpose(arr, (2, 0, 1))

    # Add batch dimension
    arr = np.expand_dims(arr, axis=0)

    return arr.astype("float32")


_SESSION_CACHE: dict[tuple[str, int], ort.InferenceSession] = {}


def get_session(model_path: str) -> ort.InferenceSession:
    p = Path(model_path)
    try:
        mtime_ns = int(p.stat().st_mtime_ns)
    except Exception as e:
        raise FileNotFoundError(f"ONNX model not found or unreadable: {model_path} ({e})")

    key = (str(p), mtime_ns)
    cached = _SESSION_CACHE.get(key)
    if cached is not None:
        return cached

    providers = ["CPUExecutionProvider"]
    sess = ort.InferenceSession(str(p), providers=providers)
    _SESSION_CACHE[key] = sess

    # Best-effort: drop older mtimes for this model path to avoid unbounded growth.
    for old_key in [k for k in _SESSION_CACHE.keys() if k[0] == str(p) and k != key]:
        _SESSION_CACHE.pop(old_key, None)

    return sess


def predict_image_bytes(*, model_path: str, image_bytes: bytes, top_k: int = 3) -> Tuple[str, float, List[Dict[str, float]]]:
    sess = get_session(model_path)

    input_name = sess.get_inputs()[0].name
    output_name = sess.get_outputs()[0].name

    try:
        from io import BytesIO

        img = Image.open(BytesIO(image_bytes))
    except Exception as e:
        raise ValueError(f"Invalid image: {e}")

    x = preprocess_image(img)

    outputs = sess.run([output_name], {input_name: x})
    y = np.array(outputs[0])

    # Common shapes: [1, C], [C], [1, 1, C], etc.
    y = np.squeeze(y)
    if y.ndim != 1:
        raise RuntimeError(f"Unexpected model output shape: {y.shape}")

    # Some exports already output probabilities.
    # Heuristic: values within [0,1] and sum ~ 1 => treat as probs; else softmax logits.
    y_min = float(np.min(y))
    y_max = float(np.max(y))
    y_sum = float(np.sum(y))
    looks_like_probs = (y_min >= -1e-6) and (y_max <= 1.0 + 1e-6) and (abs(y_sum - 1.0) < 1e-2)
    probs = y.astype("float32") if looks_like_probs else _softmax(y)

    idxs = np.argsort(-probs)[: max(1, min(top_k, len(CLASSES)))]
    top = [{"label": CLASSES[int(i)], "score": float(probs[int(i)])} for i in idxs]

    best_idx = int(idxs[0])
    fault = CLASSES[best_idx]
    confidence = float(probs[best_idx])

    return fault, confidence, top
