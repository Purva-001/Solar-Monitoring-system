#!/usr/bin/env python3
"""
Generate printable QR codes that encode plain panel identifiers (PANEL_001 …).
Usage:
  pip install "qrcode[pil]"
  python scripts/generate_panel_qr_codes.py --out qr_codes
"""

from __future__ import annotations

import argparse
from pathlib import Path


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("--out", default="qr_codes", help="Output directory")
    args = p.parse_args()
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)

    try:
        import qrcode
        from PIL import Image  # noqa: F401 — ensures pillow is present
    except ImportError as e:
        raise SystemExit(
            "Missing dependency. Install with: pip install \"qrcode[pil]\""
        ) from e

    labels = ["PANEL_001", "PANEL_002", "PANEL_003", "PANEL_004"]
    for text in labels:
        qr = qrcode.QRCode(version=2, box_size=12, border=2)
        qr.add_data(text)
        qr.make(fit=True)
        img = qr.make_image(fill_color="#0f172a", back_color="#f8fafc")
        fp = out / f"{text}.png"
        img.save(fp)
        print(f"Wrote {fp}")


if __name__ == "__main__":
    main()
