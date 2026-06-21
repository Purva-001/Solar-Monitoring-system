
from __future__ import annotations

from datetime import datetime
from typing import Any, Dict


def get_dummy_panel_readings() -> Dict[str, Any]:
    return {
        "deviceId": "solar-system",
        # 40W solar panel values around 5 PM in summer
        "panel1power": 21.4,
        "panel2power": 22.1,
        "panel3power": 20.8,
        "panel4power": 21.7,

        # Typical evening voltage
        "panel1voltage": 17.8,
        "panel2voltage": 18.1,
        "panel3voltage": 17.5,
        "panel4voltage": 18.0,

        # Current = Power / Voltage
        "panel1current": 1.20,
        "panel2current": 1.22,
        "panel3current": 1.19,
        "panel4current": 1.21,


        "timestamp": datetime.now().isoformat(),
        "alert": False,
        "source": "dummy",
    }
