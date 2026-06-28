from __future__ import annotations

import os
import shutil
import subprocess
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]


def test_usage_tooltip_qml_loads_with_sample_data() -> None:
    qml = shutil.which("qml6")
    if qml is None:
        pytest.skip("qml6 is not available")

    env = os.environ.copy()
    env.setdefault("QT_QPA_PLATFORM", "offscreen")

    result = subprocess.run(
        [
            qml,
            "--quiet",
            "-I",
            str(ROOT / "plasmoid" / "contents" / "ui"),
            "-f",
            str(ROOT / "tests" / "qml" / "usage_tooltip_smoke.qml"),
        ],
        cwd=ROOT,
        env=env,
        text=True,
        capture_output=True,
        timeout=10,
        check=False,
    )

    assert result.returncode == 0, result.stdout + result.stderr
