# neon-codexbar — Claude Phase 0-1 Fixes

Date: 2026-04-26
Author: Claude review
Repo: `jeremy-windsor/neon-codexbar`
Scope: corrective work after the Phase 0-1 build. No new features. No QML/daemon/installer.

## Read first

1. `plans/phase-0-1-dispatch.md` — original Phase 0-1 brief
2. `docs/PHASE_0_1_RESULTS.md` — what actually happened
3. `plans/gpt-neon-codexbar-plan.md` — governing architecture

Core rule still applies:

> CodexBar owns providers. neon-codexbar owns KDE UX.

## Why this exists

Phase 1 acceptance criteria were met against fixtures. Phase 0 was not — `codexbar` was not installed on the build host, so every command surface assumption is unverified. This document fixes the latent bugs that assumption introduced and finishes the Phase 0 work that was deferred.

Fixes are ordered by blast radius. P0 will misfire on the first live run. P3 is debt.

---

## P0 fixes — will break on first live run

### Fix 1: `config_dump` command-form fallback is broken

**Problem.** `CodexBarRunner.config_dump()` tries three command forms in order:

1. `config dump --pretty`
2. `config dump --format json`
3. `config dump`

It returns the first one whose exit code is 0 and whose stdout is non-empty. If `--pretty` emits human-readable text (not JSON), it will "succeed," the loop returns immediately, and `parse_config_dump` then fails with `JSONDecodeError`. The `--format json` fallback never runs.

This is the most likely place Phase 0 validation bites us, because the GPT plan explicitly flagged that we don't know what `--pretty` actually emits.

**Proposed change.** Reorder candidates so JSON-explicit forms come first, and validate that stdout actually parses as JSON before accepting a result:

1. `config dump --format json` (most explicit)
2. `config dump --pretty`
3. `config dump`

In the loop, attempt `json.loads(result.stdout)` on each ok+non-empty result. Only return on parse success. On parse failure, keep the result as `last_result` and continue.

**Pros.** Resilient to either flag combination working. No false positives.
**Cons.** Adds a parse attempt per candidate (cheap). Slightly more complex control flow.

**Acceptance.**
- Unit test: feed runner three mocked candidates where `--pretty` returns text and `--format json` returns valid JSON. Verify the JSON form is used.
- Unit test: all three return non-JSON. Verify `last_result` is returned and discovery surfaces a parse-error diagnostic.

---

### Fix 2: `--format json --pretty` combination is unverified

**Problem.** `fetch_provider` passes both flags to every provider call:

```
codexbar --provider <id> --source <src> --format json --pretty
```

Some CLIs treat these as mutually exclusive. We have no evidence CodexBar accepts both. If it rejects the combination, every provider fetch fails until Phase 0 validation catches it — and the failure mode (non-zero exit, empty/garbage stdout) will look like a provider auth problem in diagnostics.

**Proposed change.** Drop `--pretty` from `fetch_provider`. JSON output does not need pretty-printing for machine consumption — the runner already redacts and the CLI's `_dump_json` re-formats with `json.dumps(..., indent=2)`. Keep `--pretty` only on `config_dump` candidates where it's a known working form.

**Pros.** Removes a flag we have no evidence is supported in combination. Smaller surface to validate in Phase 0.
**Cons.** If the user runs `codexbar` directly for debugging, output isn't pretty-printed. Acceptable — that's not our path.

**Acceptance.**
- `runner.fetch_provider("codex", "cli")` produces a command list with `--format json` and no `--pretty`.
- Existing fixture-based tests still pass.

---

## P1 fixes — finish Phase 0

### Fix 3: Run Phase 0 validation against a live `codexbar`

**Problem.** Every command-surface assumption in the adapter is inferred from upstream schema, not captured from a real CLI run. We don't actually know:

- whether `config dump` emits JSON with either flag
- whether `--format json` and `--pretty` compose
- the exact JSON shape for each provider on Linux
- which fields are present vs. null vs. absent in real payloads
- the exact error envelope shape

**Proposed change.** Install `codexbar` on the KDE Neon target machine (Jeremy's laptop, where Codex/Claude/zai/OpenRouter auth already exists per the GPT plan's "what we know already" section). Run the Phase 0 command matrix from `plans/phase-0-1-dispatch.md`. Capture sanitized fixtures from real output and either replace or augment the inferred ones under `tests/fixtures/codexbar/`.

If a real fixture differs structurally from the inferred one, file the diff in `docs/PHASE_0_1_RESULTS.md` and update the normalizer + tests in a focused diff.

**Pros.** Removes the largest unknown in the codebase. Unblocks Phase 2.
**Cons.** Has to be run by Jeremy on his machine — sandbox can't do it. Risk of discovering normalizer rework is needed.

**Acceptance.**
- `docs/PHASE_0_1_RESULTS.md` updated with real command outputs and exit codes.
- Fixtures replaced or annotated with `# captured live` vs. `# inferred from schema`.
- All Phase 1 tests still pass against whichever fixtures are kept.
- Any normalizer/discovery changes needed to match real output are merged with passing tests.

**Stop condition.** If real CodexBar JSON differs structurally enough that the normalizer needs a rewrite (not a tweak), stop and write a short follow-up plan rather than freelancing.

---

## P2 fixes — correctness and clarity

### Fix 4: Version string is duplicated across two `__init__.py` files

**Problem.** Both `neon_codexbar/__init__.py` (the source-checkout shim) and `src/neon_codexbar/__init__.py` (the real package) hardcode `__version__ = "0.1.0"`. Bump one, forget the other, ship a mismatch. `pyproject.toml` has its own `version = "0.1.0"` as a third copy.

**Proposed change.** Make the shim read `__version__` from the real package after the `__path__` redirect, instead of hardcoding it. Leave `pyproject.toml` as the canonical version source for now (single-sourcing into pyproject is a separate, larger refactor).

**Pros.** Eliminates one of three copies. Two is still bad but better than three, and the remaining two (pyproject vs. package) are at least in different file types so divergence is easier to spot.
**Cons.** Doesn't fully solve the problem. A `hatch-vcs` or `importlib.metadata.version("neon-codexbar")` approach would be cleaner but adds a build dependency.

**Acceptance.** Bumping `src/neon_codexbar/__init__.py` to `0.2.0` makes `python3 -m neon_codexbar --version` print `0.2.0` from a clean checkout without editing the shim.

---

### Fix 5: Python version requirement is inconsistent across docs

**Problem.** `pyproject.toml` requires `>=3.11`. Dispatch and plan docs say 3.10+. Code uses `datetime.UTC` (3.11+) so pyproject is correct.

**Proposed change.** Update the version mention in `plans/gpt-neon-codexbar-plan.md`, `plans/claude-neon-codexbar-plan.md`, and any installer/README references to `>=3.11`. Don't downgrade the code.

**Pros.** Trivial. Stops future contributors from filing 3.10 compatibility issues.
**Cons.** None.

**Acceptance.** `grep -r "3.10" plans/ docs/ README.md` returns no Python-version mentions.

---

### Fix 6: `plan` heuristic is a magic string check

**Problem.** In `normalizer.py`:

```python
plan = (
    login_method
    if login_method and not login_method.lower().startswith("balance:")
    else None
)
```

This filters OpenRouter's `loginMethod: "Balance: $74.50"` out of the plan field. The intent is reasonable — a balance string is not a plan name — but the rule is undocumented and provider-specific behavior is hidden in a generic helper.

**Proposed change.** Two options:

| Option | Pros | Cons |
|---|---|---|
| **A: Comment + named constant.** Extract `_NON_PLAN_LOGIN_PREFIXES = ("balance:",)` with a comment explaining the OpenRouter case. | Smallest diff. Honest about the heuristic. | Still provider-specific logic in a generic file. |
| **B: Move to per-provider override.** Set `plan = None` for `openrouter` explicitly via a small dict, treat `login_method` as plan everywhere else. | More explicit. Easier to extend. | Edges toward "neon-codexbar knows about providers," which the architecture rule says to avoid. |

**Recommendation:** A. It's a display heuristic, not provider logic, and CodexBar is the source of truth for `loginMethod`.

**Acceptance.** Constant exists with comment. Behavior unchanged. Existing tests pass.

---

### Fix 7: OpenRouter `keyDataFetched: true` with null key fields drops a signal

**Problem.** `_openrouter_credit_meters` only emits a "Key Quota" meter when `keyLimit` or `keyUsage` is non-null. If `keyDataFetched: true` but both are null, we silently drop the fact that CodexBar tried and got nothing.

**Proposed change.** When `keyDataFetched: true` and both key fields are null, append a setup hint or diagnostic note rather than silently skipping. Don't fabricate a meter — just don't pretend the field doesn't exist.

**Pros.** Surfaces real CodexBar signal. No fake data.
**Cons.** Adds a code path that's only exercised by a fixture we don't have yet. Worth pairing with Fix 3 so we capture a real OpenRouter payload first.

**Acceptance.** Pair with Fix 3. If a real OpenRouter payload shows this case, write a fixture and a test. If not, defer.

---

## P3 fixes — debt for later, document and move on

### Fix 8: `extraRateWindows` fallback path is untested

**Problem.** Normalizer handles an `extraRateWindows` list but no fixture exercises it. The shape is a guess.

**Proposed change.** Don't fix yet. Add a comment in `normalizer.py` marking it as `# TODO: no fixture, shape inferred — verify against live provider that emits this`. Re-evaluate after Fix 3 reveals whether any provider uses it.

---

### Fix 9: All CLI subcommands require `--json`

**Problem.** `discover`, `fetch`, and `diagnose` all have `--json` marked `required=True`. No human-readable mode.

**Proposed change.** Don't fix in Phase 0-1. Track for Phase 2 dispatch — by then we'll know whether anyone actually wants prose output, since the daemon and widget consume JSON anyway.

---

### Fix 10: No CLI-level test for `discover --json`

**Problem.** `parse_config_dump` is unit-tested. `fetch --fixture` has a CLI subprocess test. `discover` has neither end-to-end coverage.

**Proposed change.** Add a CLI subprocess test that invokes `discover --json` against a runner pointed at a fake `codexbar` binary (small shell script in tmp_path that emits the config_dump fixture). Defer if Fix 3 supplies a real binary path test instead.

---

## Execution order

Do these in order. Each is a focused diff. No bundling.

1. **Fix 1** (config_dump ordering) — pure logic fix, no live CLI needed
2. **Fix 2** (drop `--pretty` from fetch) — pure logic fix, no live CLI needed
3. **Fix 4** (shim version drift) — trivial
4. **Fix 5** (Python version doc consistency) — trivial
5. **Fix 6** (plan heuristic comment) — trivial
6. **Fix 3** (live Phase 0 validation) — must be run on Jeremy's KDE machine
7. **Fix 7** (OpenRouter key-data signal) — pair with Fix 3 outcomes
8. **Fixes 8/9/10** — document as deferred in `docs/PHASE_0_1_RESULTS.md`, do not implement

Stop after step 5 and confirm before starting step 6. Fix 3 is the one with real risk; everything before it is mechanical.

## Acceptance for this fix pass

- All Phase 1 tests still green.
- Two new tests added (Fix 1 ordering, optional Fix 10).
- `docs/PHASE_0_1_RESULTS.md` updated with live Phase 0 results or annotated explicitly that they're still deferred.
- No new dependencies.
- No QML/daemon/installer scope creep. Same rule as before: if tempted, stop.

## Stop conditions

Stop and report if:

- Fix 1 reveals that none of the three `config dump` forms emits JSON. Means we need to write a text parser, which is a different scope.
- Fix 3 reveals real CodexBar JSON differs structurally from the inferred fixtures.
- Live `codexbar` rejects `--source <name> --format json` for any tested provider.
- Any fix requires touching provider auth/parsing in `neon_codexbar`. That's the scope wall.
