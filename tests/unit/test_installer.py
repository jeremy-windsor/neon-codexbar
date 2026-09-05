from __future__ import annotations

import os
import subprocess
from pathlib import Path

import pytest

ROOT = Path(__file__).resolve().parents[2]


@pytest.mark.parametrize("scenario", ["success", "failure", "pep668", "retry_failure"])
def test_installer_uses_private_log_and_cleans_up(tmp_path: Path, scenario: str) -> None:
    """Exercise the real pip-install block without installing or restarting anything."""
    installer = (ROOT / "packaging" / "install.sh").read_text()
    block = installer.split('PIP_FLAGS=("install" "--user")', 1)[1].split(
        'info "Python package installed"', 1,
    )[0]
    script = r'''
set -euo pipefail
info() { :; }
die() { echo "$*" >&2; exit 1; }
fake_pip() {
    test "$(stat -c %a "$PIP_LOG")" = 600 || exit 90
    [[ -f "$PIP_LOG" && ! -L "$PIP_LOG" ]] || exit 91
    echo private-log-verified
    if [[ "$*" == *--break-system-packages* ]]; then
        [[ "$SCENARIO" != retry_failure ]]
        return
    fi
    case "$SCENARIO" in
        success) return 0 ;;
        failure) echo ordinary-pip-failure >&2; return 1 ;;
        *) echo externally-managed-environment >&2; return 1 ;;
    esac
}
PIP_BIN=fake_pip
REPO_ROOT=unused
PIP_FLAGS=("install" "--user")
'''
    result = subprocess.run(
        ["bash", "-c", script + block],
        env={**os.environ, "TMPDIR": str(tmp_path), "SCENARIO": scenario},
        capture_output=True, text=True, check=False,
    )

    assert "private-log-verified" in result.stdout
    assert result.returncode == (0 if scenario in ("success", "pep668") else 1)
    assert not list(tmp_path.iterdir())
