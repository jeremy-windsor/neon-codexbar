#!/usr/bin/env bash
# neon-codexbar Phase 3 uninstaller.
# Targets KDE Neon (Debian-derived) with Plasma 6.
#
# Steps:
#   1. systemctl --user disable --now neon-codexbar.service (ignore not-found).
#   2. Remove ~/.config/systemd/user/neon-codexbar.service (ignore not-found).
#   3. systemctl --user daemon-reload.
#   4. kpackagetool6 -t Plasma/Applet -r org.jeremywindsor.neon-codexbar (ignore not-found).
#   5. pip uninstall -y neon-codexbar (ignore not-found).
#   6. With --purge: delete ~/.config/neon-codexbar/ and ~/.cache/neon-codexbar/.
#      Without --purge: print where the user data lives and leave it.
#
# This script NEVER touches ~/.codexbar/ — that is owned by CodexBar, not us.

set -euo pipefail

USER_UNIT="${HOME}/.config/systemd/user/neon-codexbar.service"
PLASMOID_ID="org.jeremywindsor.neon-codexbar"
USER_CONFIG_DIR="${HOME}/.config/neon-codexbar"
USER_CACHE_DIR="${HOME}/.cache/neon-codexbar"
CODEXBAR_DIR="${HOME}/.codexbar"   # NEVER delete; reference for the safety check.

PURGE=0
for arg in "$@"; do
  case "${arg}" in
    --purge)
      PURGE=1
      ;;
    -h|--help)
      cat <<'USAGE'
Usage: uninstall.sh [--purge]

Removes the neon-codexbar systemd unit, plasmoid, and Python package.

Options:
  --purge   Also delete user data:
              ~/.config/neon-codexbar/
              ~/.cache/neon-codexbar/
            Without --purge, user data is preserved.

Never deletes ~/.codexbar/ (that belongs to CodexBar, not neon-codexbar).
USAGE
      exit 0
      ;;
    *)
      printf 'uninstall.sh: unknown argument: %s\n' "${arg}" >&2
      printf 'Try --help.\n' >&2
      exit 2
      ;;
  esac
done

info() {
  printf '==> %s\n' "$*"
}

warn() {
  printf 'WARNING: %s\n' "$*" >&2
}

die() {
  printf 'uninstall.sh: error: %s\n' "$*" >&2
  exit 1
}

# --- step 1: disable + stop systemd unit --------------------------------------
info "Stopping and disabling neon-codexbar.service (user)"
if command -v systemctl >/dev/null 2>&1; then
  # `disable --now` errors if the unit doesn't exist; that's fine here.
  systemctl --user disable --now neon-codexbar.service >/dev/null 2>&1 || true
else
  warn "systemctl not found; skipping unit disable step"
fi

# --- step 2: remove unit file --------------------------------------------------
info "Removing user unit file ${USER_UNIT}"
rm -f -- "${USER_UNIT}"

# --- step 3: daemon-reload ----------------------------------------------------
if command -v systemctl >/dev/null 2>&1; then
  info "Reloading systemd user manager"
  systemctl --user daemon-reload >/dev/null 2>&1 || true
fi

# --- step 4: remove plasmoid ---------------------------------------------------
info "Removing plasmoid ${PLASMOID_ID}"
if command -v kpackagetool6 >/dev/null 2>&1; then
  # Tolerate "not installed" errors silently.
  kpackagetool6 -t Plasma/Applet -r "${PLASMOID_ID}" >/dev/null 2>&1 || true
else
  warn "kpackagetool6 not found; skipping plasmoid removal"
fi

# --- step 5: uninstall Python package ------------------------------------------
info "Uninstalling Python package neon-codexbar"
PIP_BIN=""
if command -v pip3 >/dev/null 2>&1; then
  PIP_BIN="$(command -v pip3)"
elif command -v pip >/dev/null 2>&1; then
  PIP_BIN="$(command -v pip)"
fi
if [[ -n "${PIP_BIN}" ]]; then
  "${PIP_BIN}" uninstall -y neon-codexbar >/dev/null 2>&1 || true
else
  warn "pip not found; skipping Python package uninstall"
fi

# --- step 6: user data ---------------------------------------------------------
# Belt-and-suspenders: bail if anyone ever points USER_CONFIG_DIR or
# USER_CACHE_DIR at ~/.codexbar/ by accident.
if [[ "${USER_CONFIG_DIR}" == "${CODEXBAR_DIR}" ]] || [[ "${USER_CACHE_DIR}" == "${CODEXBAR_DIR}" ]]; then
  die "refusing to operate on ~/.codexbar/ (that belongs to CodexBar, not us)"
fi

if [[ "${PURGE}" -eq 1 ]]; then
  warn "--purge: deleting neon-codexbar user data."
  warn "  ${USER_CONFIG_DIR}"
  warn "  ${USER_CACHE_DIR}"
  warn "  (~/.codexbar/ is NOT touched; it belongs to CodexBar.)"
  rm -rf -- "${USER_CONFIG_DIR}" "${USER_CACHE_DIR}"
  info "User data removed"
else
  echo
  echo "User data was preserved. To remove it, re-run with --purge:"
  echo "  ${USER_CONFIG_DIR}"
  echo "  ${USER_CACHE_DIR}"
  echo
  echo "Note: ~/.codexbar/ belongs to CodexBar and is never touched by this script."
fi

info "neon-codexbar uninstalled"
