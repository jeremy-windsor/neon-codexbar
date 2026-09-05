"""Private, atomic publication of files in the user's cache directory."""

from __future__ import annotations

import os
import stat
import tempfile
from pathlib import Path


def write_private_file(target: Path, contents: str) -> Path:
    """Publish a mode-0600 file without opening the existing destination.

    The parent directory must be trusted. Exclusive temporary creation and
    replacement avoid following destination links, even if the destination
    changes after the explicit symlink check.
    """

    target.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    try:
        existing_mode = target.lstat().st_mode
    except FileNotFoundError:
        pass
    else:
        if not stat.S_ISREG(existing_mode):
            raise OSError(f"Refusing non-regular file: {target}")

    fd, temporary_name = tempfile.mkstemp(
        prefix=f".{target.name}.", suffix=".tmp", dir=target.parent,
    )
    temporary = Path(temporary_name)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            handle.write(contents)
            handle.flush()
            os.fsync(handle.fileno())
        temporary.replace(target)
    finally:
        temporary.unlink(missing_ok=True)
    return target
