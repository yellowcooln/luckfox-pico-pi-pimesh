#!/bin/sh
# pyMC Console Web UI helper for LuckFox Pico Pi / Buildroot.

set -eu

INSTALL_DIR="/opt/pymc_repeater"
CONFIG_DIR="/etc/pymc_repeater"
CONFIG_FILE="${CONFIG_DIR}/config.yaml"
CONSOLE_DIR="/opt/pymc_console"
UI_DIR="${CONSOLE_DIR}/web/html"
UI_REPO="${PYMC_CONSOLE_REPO:-dmduran12/pymc_console-dist}"
UI_RELEASE_URL="https://github.com/${UI_REPO}/releases"
UI_TARBALL="${PYMC_CONSOLE_TARBALL:-pymc-ui-latest.tar.gz}"
INIT_SCRIPT="/etc/init.d/S80pymc-repeater"

info() {
  printf '%s\n' "  - $*"
}

stage() {
  printf '\n==> %s\n' "$*"
}

fail() {
  printf '%s\n' "Error: $*" >&2
  exit 1
}

need_root() {
  [ "$(id -u)" -eq 0 ] || fail "Run as root."
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || fail "Missing required command: $1"
}

repeater_installed() {
  [ -d "$INSTALL_DIR" ] || [ -x "$INIT_SCRIPT" ] || [ -f "$CONFIG_FILE" ]
}

console_installed() {
  [ -d "$UI_DIR" ]
}

get_console_version() {
  if [ -f "${UI_DIR}/VERSION" ]; then
    tr -d '[:space:]' < "${UI_DIR}/VERSION"
  else
    printf '%s\n' "unknown"
  fi
}

get_primary_ip() {
  hostname -I 2>/dev/null | awk '{print $1}'
}

set_web_path() {
  [ -f "$CONFIG_FILE" ] || fail "Missing repeater config: $CONFIG_FILE"

  python3 - "$CONFIG_FILE" "$UI_DIR" <<'PY'
import sys
import yaml

config_path, ui_dir = sys.argv[1:3]
with open(config_path, "r", encoding="utf-8") as fh:
    data = yaml.safe_load(fh) or {}

web = data.setdefault("web", {})
web["web_path"] = ui_dir

with open(config_path, "w", encoding="utf-8") as fh:
    yaml.safe_dump(data, fh, default_flow_style=False, sort_keys=False)
PY
}

download_dashboard() {
  temp_file="/tmp/pymc-ui-$$.tar.gz"
  info "Downloading dashboard from ${UI_RELEASE_URL}/latest/download/${UI_TARBALL}"

  if command -v curl >/dev/null 2>&1; then
    curl -fsSL -o "$temp_file" "${UI_RELEASE_URL}/latest/download/${UI_TARBALL}" \
      || fail "Download failed"
  elif command -v wget >/dev/null 2>&1; then
    wget -O "$temp_file" "${UI_RELEASE_URL}/latest/download/${UI_TARBALL}" \
      || fail "Download failed"
  else
    fail "Need curl or wget"
  fi

  rm -rf "$UI_DIR"
  mkdir -p "$UI_DIR"
  tar -xzf "$temp_file" -C "$UI_DIR"
  rm -f "$temp_file"
}

restart_repeater() {
  if [ -x "$INIT_SCRIPT" ]; then
    info "Restarting pymc-repeater"
    "$INIT_SCRIPT" restart || true
  else
    info "pymc-repeater init script not found; restart skipped"
  fi
}

do_install_like() {
  is_fresh="$1"

  repeater_installed || fail "pyMC_Repeater is not installed yet. Run /root/scripts/buildroot-manage.sh install first."

  download_dashboard

  if [ "$is_fresh" = "1" ]; then
    set_web_path
    info "Dashboard installed and web.web_path set to ${UI_DIR}"
  else
    info "Dashboard updated"
  fi

  restart_repeater

  ip="$(get_primary_ip)"
  version="$(get_console_version)"
  printf '\nConsole version: %s\n' "$version"
  printf 'Dashboard: http://%s:8000/\n' "${ip:-localhost}"
}

do_install() {
  if console_installed; then
    fail "Console already installed at ${UI_DIR}. Run: sh $0 upgrade"
  fi
  do_install_like 1
}

do_upgrade() {
  if ! console_installed; then
    fail "Console is not installed. Run: sh $0 install"
  fi
  do_install_like 0
}

do_uninstall() {
  console_installed || fail "Console is not installed."
  rm -rf "$CONSOLE_DIR"
  info "Removed ${CONSOLE_DIR}"
  restart_repeater
}

show_help() {
  cat <<EOF
pyMC Console helper for LuckFox Pico Pi / Buildroot

Usage: sh $0 <command>

Commands:
  install     Download and install the console dashboard into ${CONSOLE_DIR}
  upgrade     Refresh dashboard assets in ${UI_DIR}
  uninstall   Remove ${CONSOLE_DIR}
  status      Show current dashboard status
  help        Show this help
EOF
}

do_status() {
  if console_installed; then
    printf 'Console: installed\n'
    printf 'Path: %s\n' "$UI_DIR"
    printf 'Version: %s\n' "$(get_console_version)"
  else
    printf 'Console: not installed\n'
  fi
  if [ -f "$CONFIG_FILE" ]; then
    python3 - "$CONFIG_FILE" <<'PY'
import sys, yaml
with open(sys.argv[1], "r", encoding="utf-8") as fh:
    data = yaml.safe_load(fh) or {}
print("Configured web_path:", ((data.get("web") or {}).get("web_path") or "unset"))
PY
  fi
}

case "${1:-help}" in
  install)
    need_root
    stage "Installing pyMC Console"
    do_install
    ;;
  upgrade)
    need_root
    stage "Upgrading pyMC Console"
    do_upgrade
    ;;
  uninstall)
    need_root
    stage "Uninstalling pyMC Console"
    do_uninstall
    ;;
  status)
    do_status
    ;;
  help|-h|--help|"")
    show_help
    ;;
  *)
    fail "Unknown command: $1"
    ;;
esac
