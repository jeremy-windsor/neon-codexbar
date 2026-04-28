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
PLASMA_APPLETS_RC="${HOME}/.config/plasma-org.kde.plasma.desktop-appletsrc"

PURGE=0
FORCE=0
RESTART_PLASMA=0
for arg in "$@"; do
  case "${arg}" in
    --purge)
      PURGE=1
      ;;
    --force)
      FORCE=1
      ;;
    --restart-plasma)
      RESTART_PLASMA=1
      ;;
    -h|--help)
      cat <<'USAGE'
Usage: uninstall.sh [--purge] [--force] [--restart-plasma]

Removes the neon-codexbar systemd unit, plasmoid, and Python package.

Options:
  --purge            Also delete user data:
                       ~/.config/neon-codexbar/
                       ~/.cache/neon-codexbar/
                     Without --purge, user data is preserved.

  --force            Skip the interactive confirmation when a live
                     neon-codexbar widget is detected on a Plasma panel.
                     The package is removed anyway. The widget will appear
                     broken in the panel until you remove it manually.

  --restart-plasma   Restart plasmashell at the end so removed plasmoid
                     instances visually disappear. Closes/reopens panels —
                     interactive sessions only. Without this flag, the
                     script prints the restart command for you to run.

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

# --- step 0: detect live panel instances --------------------------------------
# kpackagetool6 -r removes the installed package but leaves any applet
# instance already placed on a panel. Those instances live in
# plasma-org.kde.plasma.desktop-appletsrc and have to be removed manually
# from Plasma's panel-edit mode (or by restarting plasmashell, which then
# shows them as broken icons until removed). Detect this case and warn
# loudly before destroying the package.
PANEL_INSTANCE_FOUND=0
if [[ -f "${PLASMA_APPLETS_RC}" ]]; then
  if grep -qF "${PLASMOID_ID}" "${PLASMA_APPLETS_RC}" 2>/dev/null; then
    PANEL_INSTANCE_FOUND=1
  fi
fi

if [[ "${PANEL_INSTANCE_FOUND}" -eq 1 ]]; then
  cat >&2 <<EOF

neon-codexbar still appears in your Plasma panel layout
(${PLASMA_APPLETS_RC}).

Recommended order:
  1. Right-click panel -> Enter Edit Mode
  2. Hover/right-click the neon-codexbar widget -> Remove
  3. Re-run this uninstall script

If you continue, the package will be removed but Plasma may leave a broken
panel item until plasmashell is restarted and the item is deleted manually.
EOF
  if [[ "${FORCE}" -eq 1 ]]; then
    warn "--force given; continuing despite live panel instance"
  elif [[ -t 0 ]] && [[ -t 1 ]]; then
    # Interactive shell: ask. Default to NO so a stray Enter doesn't proceed.
    printf '\nContinue uninstall anyway? [y/N] '
    read -r reply
    case "${reply}" in
      y|Y|yes|YES)
        info "Continuing"
        ;;
      *)
        info "Aborted by user. Remove the panel widget first, then re-run."
        exit 0
        ;;
    esac
  else
    # Non-interactive (script, CI, pipe). Plan says: continue, but warn.
    warn "non-interactive shell; continuing without prompt (use --force to silence this warning)"
  fi
fi

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

# --- step 7: optional plasmashell restart -------------------------------------
# Restarting the shell makes orphaned panel instances disappear cleanly. We
# never restart unless --restart-plasma is given because closing/reopening
# panels is destructive to the user's session state.
if [[ "${RESTART_PLASMA}" -eq 1 ]]; then
  if [[ "${PANEL_INSTANCE_FOUND}" -eq 1 ]]; then
    info "Restarting plasmashell to clear orphaned panel instance (panels will reload)"
  else
    info "Restarting plasmashell as requested (panels will reload)"
  fi
  if command -v kquitapp6 >/dev/null 2>&1; then
    kquitapp6 plasmashell >/dev/null 2>&1 || true
  fi
  if command -v kstart >/dev/null 2>&1; then
    kstart plasmashell >/dev/null 2>&1 &
    disown
    info "plasmashell restart issued"
  else
    warn "kstart not found; plasmashell will respawn on next session start"
  fi
elif [[ "${PANEL_INSTANCE_FOUND}" -eq 1 ]]; then
  echo
  echo "IMPORTANT: a neon-codexbar widget instance was on your panel before"
  echo "this uninstall ran. To clear it, either:"
  echo "  - remove it from the panel via right-click -> Edit Mode, OR"
  echo "  - restart plasmashell now to surface it as a removable broken icon:"
  echo "      kquitapp6 plasmashell && kstart plasmashell"
  echo "  - or re-run this script with --restart-plasma to do it for you."
fi
