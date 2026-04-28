# CodexBar Config Bootstrap Plan

## Problem

`neon-codexbar` discovers enabled providers from CodexBar config:

```bash
codexbar config dump --format json
```

On Jeremy's KDE Neon laptop, direct Claude worked:

```bash
codexbar --provider claude --source cli --format json
```

but `neon-codexbar fetch --json` only returned Codex because
`~/.codexbar/config.json` did not exist yet. CodexBar used its default provider
state, where only Codex was enabled and Claude was disabled.

Creating `~/.codexbar/config.json` from the full config dump and enabling
Claude made `neon-codexbar` discover and fetch both providers.

## Install Strategy

The installer should bootstrap CodexBar config when missing, but it must not
take ownership of provider choices or secrets.

### Rules

1. If `~/.codexbar/config.json` is missing:
   - create `~/.codexbar/`
   - write the full output of `codexbar config dump --format json`
   - set mode `0600`
   - preserve CodexBar's default enabled/disabled state

2. If `~/.codexbar/config.json` already exists:
   - do not overwrite it
   - run validation if available
   - warn clearly if invalid

3. Never enable extra providers automatically during install.

4. Never write API keys or auth material.

5. Keep provider auth in CodexBar-supported locations:
   - CLI providers: `~/.codex`, `~/.claude`, etc.
   - API providers: CodexBar-supported config/env/systemd drop-ins

## Proposed Installer Step

Add a `bootstrap_codexbar_config` function to `packaging/install.sh` after the
Python package install confirms the `codexbar` binary can be found.

Candidate shell shape:

```bash
bootstrap_codexbar_config() {
  local codexbar_config_dir="${HOME}/.codexbar"
  local codexbar_config="${codexbar_config_dir}/config.json"

  if [[ -f "${codexbar_config}" ]]; then
    info "CodexBar config already exists at ${codexbar_config}; leaving it unchanged"
    if codexbar config validate --format json >/dev/null 2>&1; then
      info "CodexBar config validates"
    else
      warn "CodexBar config did not validate. Run: codexbar config validate --format json --pretty"
    fi
    return
  fi

  info "Creating initial CodexBar config at ${codexbar_config}"
  mkdir -p "${codexbar_config_dir}"
  local tmp
  tmp="$(mktemp)"
  codexbar config dump --format json > "${tmp}" \
    || { rm -f "${tmp}"; warn "Could not dump CodexBar config; skipping bootstrap"; return; }
  install -m 0600 "${tmp}" "${codexbar_config}"
  rm -f "${tmp}"
}
```

Use the same CodexBar binary resolution that `neon-codexbar` uses if possible.
If the CLI binary is named `CodexBarCLI` in `~/.local/bin`, call the resolved
path instead of assuming `codexbar` is on `PATH`.

## Provider Enablement UX

After bootstrap, installer should print a short next step:

```text
CodexBar config created at ~/.codexbar/config.json.
To enable more providers, edit that file and flip enabled=true for one provider
at a time, then run:
  codexbar config validate --format json --pretty
  neon-codexbar fetch --json
  systemctl --user restart neon-codexbar.service
```

Example Claude enablement:

```bash
jq '(.providers[] | select(.id == "claude") | .enabled) = true' \
  ~/.codexbar/config.json > /tmp/codexbar-config.json
install -m 600 /tmp/codexbar-config.json ~/.codexbar/config.json
rm -f /tmp/codexbar-config.json
```

## Diagnostics Policy Follow-Up

Bootstrapping the full config exposes every CodexBar provider. Current
diagnostics warn for every disabled provider missing from neon-codexbar's Linux
source policy. This is noisy.

Recommended policy:

- disabled + unsupported: quiet
- disabled + supported: quiet
- enabled + supported: fetch
- enabled + unsupported: diagnostic warning
- enabled + fetch failure: provider error card

This keeps normal popup diagnostics focused on user-actionable issues.

## Test Plan

### Missing Config

```bash
mv ~/.codexbar/config.json ~/.codexbar/config.json.backup
./packaging/install.sh
test -f ~/.codexbar/config.json
stat -c '%a %n' ~/.codexbar/config.json
codexbar config validate --format json --pretty
```

Expected:

- config file exists
- mode is `600`
- validation succeeds
- installer does not enable Claude/z.ai/OpenRouter automatically

### Existing Config

```bash
cp ~/.codexbar/config.json /tmp/codexbar-config-before.json
./packaging/install.sh
cmp ~/.codexbar/config.json /tmp/codexbar-config-before.json
```

Expected:

- installer does not overwrite existing config

### Claude Enablement

```bash
jq '(.providers[] | select(.id == "claude") | .enabled) = true' \
  ~/.codexbar/config.json > /tmp/codexbar-config.json
install -m 600 /tmp/codexbar-config.json ~/.codexbar/config.json
rm -f /tmp/codexbar-config.json

neon-codexbar fetch --json
systemctl --user restart neon-codexbar.service
```

Expected:

- fetch returns Codex and Claude cards
- daemon snapshot has two cards
- popup renders both cards

## Acceptance Criteria

- Clean install creates a valid full CodexBar config if missing.
- Existing CodexBar config is preserved.
- Installer does not auto-enable providers.
- No secrets are written by neon-codexbar.
- Multi-provider testing has a stable starting config file.
- Disabled unsupported providers no longer flood normal diagnostics once the
  diagnostics policy follow-up is implemented.
