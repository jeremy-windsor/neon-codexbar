"""CodexBar subprocess runner."""

from __future__ import annotations

import json
import shutil
import subprocess
import time
from collections.abc import Sequence
from dataclasses import replace
from pathlib import Path

from neon_codexbar.config import AppConfig
from neon_codexbar.diagnostics import redact_string
from neon_codexbar.models import CommandResult

DEFAULT_TIMEOUT_SECONDS = 30.0


class CodexBarUnavailableError(RuntimeError):
    """Raised when the CodexBar CLI cannot be located."""


def _is_executable(path: Path) -> bool:
    return path.is_file() and path.stat().st_mode & 0o111 != 0


class CodexBarRunner:
    """Small, testable wrapper around the upstream ``codexbar`` CLI."""

    def __init__(
        self,
        *,
        config: AppConfig | None = None,
        codexbar_path: str | None = None,
        timeout_seconds: float = DEFAULT_TIMEOUT_SECONDS,
    ) -> None:
        self.config = config or AppConfig()
        self.codexbar_path = codexbar_path or self.config.codexbar_path
        self.timeout_seconds = timeout_seconds

    def locate(self) -> str | None:
        """Locate CodexBar from explicit config/env, PATH, or common local paths."""

        candidates: list[Path] = []
        if self.codexbar_path:
            candidates.append(Path(self.codexbar_path).expanduser())

        on_path = shutil.which("codexbar")
        if on_path:
            candidates.append(Path(on_path))

        candidates.extend(
            [
                Path.home() / ".local" / "bin" / "codexbar",
                Path.home() / "bin" / "codexbar",
                Path("/opt/neon-codexbar/bin/codexbar"),
            ]
        )

        for candidate in candidates:
            try:
                resolved = candidate.resolve()
            except OSError:
                resolved = candidate
            if _is_executable(resolved):
                return str(resolved)
        return None

    def run(self, args: Sequence[str], *, timeout_seconds: float | None = None) -> CommandResult:
        """Run CodexBar with arguments and return a structured, redacted result."""

        binary = self.locate()
        timeout = timeout_seconds if timeout_seconds is not None else self.timeout_seconds
        if binary is None:
            return CommandResult(
                command=["codexbar", *args],
                stdout="",
                stderr="CodexBar CLI not found on PATH or configured locations.",
                exit_code=127,
                timed_out=False,
                duration_seconds=0.0,
                error="CodexBar CLI not found on PATH or configured locations.",
            )

        command = [binary, *args]
        start = time.monotonic()
        try:
            completed = subprocess.run(
                command,
                capture_output=True,
                text=True,
                timeout=timeout,
                check=False,
            )
            duration = time.monotonic() - start
            return CommandResult(
                command=command,
                stdout=redact_string(completed.stdout, redact_identity=False),
                stderr=redact_string(completed.stderr),
                exit_code=completed.returncode,
                timed_out=False,
                duration_seconds=duration,
            )
        except subprocess.TimeoutExpired as exc:
            duration = time.monotonic() - start
            stdout = exc.stdout.decode() if isinstance(exc.stdout, bytes) else (exc.stdout or "")
            stderr = exc.stderr.decode() if isinstance(exc.stderr, bytes) else (exc.stderr or "")
            return CommandResult(
                command=command,
                stdout=redact_string(stdout, redact_identity=False),
                stderr=redact_string(stderr),
                exit_code=124,
                timed_out=True,
                duration_seconds=duration,
                error=f"CodexBar command timed out after {timeout:g}s.",
            )
        except OSError as exc:
            duration = time.monotonic() - start
            return CommandResult(
                command=command,
                stdout="",
                stderr=redact_string(str(exc)),
                exit_code=126,
                timed_out=False,
                duration_seconds=duration,
                error=redact_string(str(exc)),
            )

    def version(self) -> CommandResult:
        """Run ``codexbar --version``."""

        return self.run(["--version"])

    def config_dump_candidates(self) -> list[list[str]]:
        """Return known config dump command forms in preferred order."""

        return [
            ["config", "dump", "--format", "json"],
            ["config", "dump", "--pretty"],
            ["config", "dump"],
        ]

    @staticmethod
    def _with_json_parse_error(result: CommandResult, exc: json.JSONDecodeError) -> CommandResult:
        """Return a result annotated with a config-dump JSON parse diagnostic."""

        message = (
            "CodexBar config dump was not valid JSON "
            f"for {' '.join(result.command)}: {exc.msg} "
            f"(line {exc.lineno}, column {exc.colno})."
        )
        stderr = "\n".join(part for part in (result.stderr.strip(), message) if part)
        return replace(result, stderr=stderr, error=message)

    def config_dump(self) -> CommandResult:
        """Run the first known config dump command form that emits valid JSON."""

        last_result: CommandResult | None = None
        for args in self.config_dump_candidates():
            result = self.run(args)
            if result.ok and result.stdout.strip():
                try:
                    json.loads(result.stdout)
                except json.JSONDecodeError as exc:
                    last_result = self._with_json_parse_error(result, exc)
                    continue
                return result
            last_result = result
            if result.exit_code == 127:
                break
        if last_result is None:
            return CommandResult(
                command=["codexbar", "config", "dump"],
                stdout="",
                stderr="No config dump command attempted.",
                exit_code=1,
                timed_out=False,
                duration_seconds=0.0,
                error="No config dump command attempted.",
            )
        return last_result

    def fetch_provider(self, provider_id: str, source: str) -> CommandResult:
        """Fetch one provider through CodexBar with explicit source and JSON output."""

        if source == "auto":
            return CommandResult(
                command=["codexbar", "--provider", provider_id, "--source", source],
                stdout="",
                stderr="neon-codexbar refuses to use --source auto on Linux.",
                exit_code=2,
                timed_out=False,
                duration_seconds=0.0,
                error="neon-codexbar refuses to use --source auto on Linux.",
            )
        return self.run(
            [
                "--provider",
                provider_id,
                "--source",
                source,
                "--format",
                "json",
            ]
        )
