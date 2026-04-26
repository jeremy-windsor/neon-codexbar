from __future__ import annotations

from collections.abc import Sequence

from neon_codexbar.adapter.discovery import discover
from neon_codexbar.adapter.runner import CodexBarRunner
from neon_codexbar.models import CommandResult


def _result(args: Sequence[str], stdout: str, exit_code: int = 0) -> CommandResult:
    return CommandResult(
        command=["codexbar", *args],
        stdout=stdout,
        stderr="",
        exit_code=exit_code,
        timed_out=False,
        duration_seconds=0.01,
    )


class FakeRunner(CodexBarRunner):
    def __init__(self, responses: dict[tuple[str, ...], CommandResult]) -> None:
        super().__init__()
        self.responses = responses
        self.calls: list[list[str]] = []

    def run(
        self,
        args: Sequence[str],
        *,
        timeout_seconds: float | None = None,
    ) -> CommandResult:
        del timeout_seconds
        self.calls.append(list(args))
        return self.responses[tuple(args)]


class PrettyFirstRunner(FakeRunner):
    def config_dump_candidates(self) -> list[list[str]]:
        return [
            ["config", "dump", "--pretty"],
            ["config", "dump", "--format", "json"],
            ["config", "dump"],
        ]


def test_config_dump_prefers_json_explicit_candidate() -> None:
    json_args = ("config", "dump", "--format", "json")
    runner = FakeRunner(
        {
            json_args: _result(json_args, '{"providers": []}'),
            ("config", "dump", "--pretty"): _result(
                ("config", "dump", "--pretty"),
                "providers: none",
            ),
            ("config", "dump"): _result(("config", "dump"), "providers: none"),
        }
    )

    result = runner.config_dump()

    assert result.ok is True
    assert result.command == ["codexbar", *json_args]
    assert runner.calls == [list(json_args)]


def test_config_dump_continues_when_pretty_candidate_is_not_json() -> None:
    pretty_args = ("config", "dump", "--pretty")
    json_args = ("config", "dump", "--format", "json")
    runner = PrettyFirstRunner(
        {
            pretty_args: _result(pretty_args, "providers: none"),
            json_args: _result(json_args, '{"providers": []}'),
            ("config", "dump"): _result(("config", "dump"), "providers: none"),
        }
    )

    result = runner.config_dump()

    assert result.ok is True
    assert result.command == ["codexbar", *json_args]
    assert runner.calls == [list(pretty_args), list(json_args)]


def test_config_dump_all_non_json_surfaces_parse_diagnostic() -> None:
    responses = {
        tuple(args): _result(args, "providers: none")
        for args in CodexBarRunner().config_dump_candidates()
    }
    runner = FakeRunner(responses)

    result = runner.config_dump()

    assert result.ok is False
    assert result.command == ["codexbar", "config", "dump"]
    assert result.error is not None
    assert "not valid JSON" in result.error

    discovery = discover(FakeRunner(responses))
    assert discovery.providers == []
    assert discovery.diagnostics
    assert "not valid JSON" in discovery.diagnostics[0]


def test_fetch_provider_requests_json_without_pretty() -> None:
    runner = FakeRunner(
        {
            (
                "--provider",
                "codex",
                "--source",
                "cli",
                "--format",
                "json",
            ): _result(
                ["--provider", "codex", "--source", "cli", "--format", "json"],
                "[]",
            )
        }
    )

    result = runner.fetch_provider("codex", "cli")

    assert result.ok is True
    command = runner.calls[0]
    assert "--format" in command
    assert command[command.index("--format") + 1] == "json"
    assert "--pretty" not in command
