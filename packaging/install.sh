#!/usr/bin/env bash
# neon-codexbar Phase 3 installer.
# Targets KDE Neon (Debian-derived) with Plasma 6.
# Idempotent: safe to re-run.
#
# What this does:
#   1. Verifies prerequisites (kpackagetool6, python3 >=3.11, systemd --user).
#   2. Installs the Python package with `pip install --user .` from repo root.
#   3. Installs or upgrades the plasmoid via kpackagetool6.
#   4. Installs the user systemd unit, daemon-reloads, enable --now.
#
# What this DOES NOT do:
#   - Touch any provider API keys (Z_AI_API_KEY, OPENROUTER_API_KEY, etc.).
#     Provider auth lives outside this installer. See docs/PROVIDER_SETUP.md.

set -euo pipefail

# --- locate repo root from the script's own directory --------------------------
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
REPO_ROOT="$(cd -- "${SCRIPT_DIR}/.." &>/dev/null && pwd)"

PLASMOID_DIR="${REPO_ROOT}/plasmoid"
UNIT_SRC="${SCRIPT_DIR}/neon-codexbar.service"
USER_UNIT_DIR="${HOME}/.config/systemd/user"
UNIT_DEST="${USER_UNIT_DIR}/neon-codexbar.service"
PLASMOID_ID="org.jeremywindsor.neon-codexbar"

# --- helpers -------------------------------------------------------------------
die() {
  printf 'install.sh: error: %s\n' "$*" >&2
  exit 1
}

info() {
  printf '==> %s\n' "$*"
}

# --- step 1: prerequisites -----------------------------------------------------
info "Checking prerequisites"

command -v kpackagetool6 >/dev/null 2>&1 \
  || die "kpackagetool6 not found. Install KDE Plasma 6 development tools (e.g. 'sudo apt install plasma-framework' or your distro equivalent)."

command -v python3 >/dev/null 2>&1 \
  || die "python3 not found. Install Python 3.11 or later."

# python3 >= 3.11 check
if ! python3 - <<'PY' >/dev/null 2>&1
import sys
sys.exit(0 if sys.version_info >= (3, 11) else 1)
PY
then
  ACTUAL_PY="$(python3 -c 'import sys; print("%d.%d.%d" % sys.version_info[:3])' 2>/dev/null || echo 'unknown')"
  die "python3 must be >= 3.11 (found ${ACTUAL_PY})."
fi

command -v pip >/dev/null 2>&1 || command -v pip3 >/dev/null 2>&1 \
  || die "pip not found. Install python3-pip (e.g. 'sudo apt install python3-pip')."

PIP_BIN="$(command -v pip3 || command -v pip)"

command -v systemctl >/dev/null 2>&1 \
  || die "systemctl not found. systemd is required."

# Verify systemd --user is functional. `systemctl --user status` exits non-zero
# under some conditions even when working; we accept either success or the
# benign "no units" exit. What we cannot tolerate is "Failed to connect to bus".
if ! systemctl --user status >/dev/null 2>&1; then
  if ! systemctl --user list-units --no-pager >/dev/null 2>&1; then
    die "systemd --user is not available in this session. Make sure you are running as a regular user with a logged-in user systemd instance (loginctl enable-linger \$USER may help on headless systems)."
  fi
fi

info "Prerequisites OK"

# --- step 2: pip install --user . ---------------------------------------------
info "Installing Python package from ${REPO_ROOT}"

# Newer Debian-based distros (Neon included) ship PEP-668 / EXTERNALLY-MANAGED,
# which makes `pip install --user .` fail against the system Python. We try the
# clean form first, then fall back to --break-system-packages for the user-site
# install. Power users on a venv won't hit this branch.
PIP_FLAGS=("install" "--user")
if ! "${PIP_BIN}" "${PIP_FLAGS[@]}" "${REPO_ROOT}" 2>/tmp/neon-codexbar-pip.log; then
  if grep -q "externally-managed-environment" /tmp/neon-codexbar-pip.log 2>/dev/null; then
    info "Detected PEP-668 environment; retrying with --break-system-packages (user-site only)"
    PIP_FLAGS+=("--break-system-packages")
    "${PIP_BIN}" "${PIP_FLAGS[@]}" "${REPO_ROOT}" \
      || { cat /tmp/neon-codexbar-pip.log >&2; die "pip install failed even with --break-system-packages."; }
  else
    cat /tmp/neon-codexbar-pip.log >&2
    die "pip install --user failed. Check pip output above."
  fi
fi
rm -f /tmp/neon-codexbar-pip.log

info "Python package installed"

# --- step 3: plasmoid install or upgrade --------------------------------------
[[ -d "${PLASMOID_DIR}" ]] \
  || die "Plasmoid directory not found at ${PLASMOID_DIR}"

[[ -f "${PLASMOID_DIR}/metadata.json" ]] \
  || die "Plasmoid metadata.json not found at ${PLASMOID_DIR}/metadata.json"

info "Checking for existing plasmoid ${PLASMOID_ID}"

PLASMOID_INSTALLED=0
# `kpackagetool6 -l` prints one package id per line. grep -F -x for an exact
# match. set +e around the pipeline so pipefail doesn't bite when grep finds
# nothing.
set +e
kpackagetool6 -t Plasma/Applet -l 2>/dev/null | grep -F -x "${PLASMOID_ID}" >/dev/null
if [[ $? -eq 0 ]]; then
  PLASMOID_INSTALLED=1
fi
set -e

if [[ "${PLASMOID_INSTALLED}" -eq 1 ]]; then
  info "Plasmoid already installed; upgrading"
  kpackagetool6 -t Plasma/Applet -u "${PLASMOID_DIR}" \
    || die "kpackagetool6 upgrade failed for ${PLASMOID_DIR}"
else
  info "Installing plasmoid from ${PLASMOID_DIR}"
  kpackagetool6 -t Plasma/Applet -i "${PLASMOID_DIR}" \
    || die "kpackagetool6 install failed for ${PLASMOID_DIR}"
fi

info "Plasmoid ready"

# --- step 4: systemd user unit -------------------------------------------------
[[ -f "${UNIT_SRC}" ]] \
  || die "Systemd unit not found at ${UNIT_SRC}"

info "Installing systemd user unit to ${UNIT_DEST}"

mkdir -p "${USER_UNIT_DIR}" \
  || die "Could not create ${USER_UNIT_DIR}"

# Copy is idempotent; install -m 0644 ensures sane perms each time.
install -m 0644 "${UNIT_SRC}" "${UNIT_DEST}" \
  || die "Could not install unit file to ${UNIT_DEST}"

systemctl --user daemon-reload \
  || die "systemctl --user daemon-reload failed"

# enable --now is idempotent: enabling an already-enabled unit is a no-op,
# starting an already-running unit is a no-op.
systemctl --user enable --now neon-codexbar.service \
  || die "systemctl --user enable --now neon-codexbar.service failed. Run 'systemctl --user status neon-codexbar.service' and 'journalctl --user -u neon-codexbar.service' for details."

info "Daemon enabled and started"

# --- final message -------------------------------------------------------------
echo
printf 'Done. Add the widget: right-click panel \xe2\x86\x92 Add Widgets \xe2\x86\x92 search '\''neon-codexbar'\''. Provider auth setup: see docs/PROVIDER_SETUP.md.\n'
