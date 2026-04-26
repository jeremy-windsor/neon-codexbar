from __future__ import annotations

from neon_codexbar.adapter.source_policy import decision_for, source_for


def test_linux_source_policy_known_providers() -> None:
    assert source_for("codex") == "cli"
    assert source_for("claude") == "cli"
    assert source_for("zai") == "api"
    assert source_for("openrouter") == "api"


def test_unknown_provider_is_skipped_not_auto() -> None:
    decision = decision_for("mystery")

    assert decision.skipped is True
    assert decision.source is None
    assert decision.diagnostic is not None
    assert "auto" in decision.diagnostic
