#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
SHIM_DIR="${SCRIPT_DIR}/shims"
API_HOST="${API_HOST:-127.0.0.1}"
API_PORT="${API_PORT:-8000}"

PYTHON_BIN="${PYTHON_BIN:-python3}"
PYMC_REPEATER_REPO="${PYMC_REPEATER_REPO:-https://github.com/rightup/pyMC_Repeater.git}"
PYMC_REPEATER_REF="${PYMC_REPEATER_REF:-dev}"
PYMC_REPEATER_HOME="${PYMC_REPEATER_HOME:-${HOME:-/root}}"
PYMC_REPEATER_DIR="${PYMC_REPEATER_DIR:-${PYMC_REPEATER_HOME}/pyMC_Repeater}"

usage() {
  cat <<'EOF'
Usage: sh buildroot-manage.sh <command>

This script is only a Buildroot image bootstrap/proxy. It clones stock upstream
pyMC_Repeater into the current user's home directory and then hands off to the
repo's own manage.sh.

Commands:
  doctor      Check image prerequisites for upstream pyMC install
  install     Clone/update ~/pyMC_Repeater and run upstream "manage.sh install"
  upgrade     Refresh ~/pyMC_Repeater and run upstream "manage.sh upgrade"
  config      Run upstream "manage.sh config"
  start       Run upstream "manage.sh start"
  stop        Run upstream "manage.sh stop"
  restart     Run upstream "manage.sh restart"
  status      Run upstream "manage.sh status"
  logs        Run upstream "manage.sh logs"
  uninstall   Run upstream "manage.sh uninstall"
  debug       Run upstream "manage.sh debug"
  wait-ready  Wait for the local pyMC API port to open
  advert      Wait for the API, then run "pymc-cli advert"
  repo-path   Print the upstream pyMC_Repeater checkout path
  repo-sync   Clone or refresh the upstream pyMC_Repeater checkout only
EOF
}

stage() {
  printf '\n==> %s\n' "$1"
}

info() {
  printf '  - %s\n' "$1"
}

warn() {
  printf '  - %s\n' "$1" >&2
}

fail() {
  printf '%s\n' "$1" >&2
  exit 1
}

need_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    fail "Missing required command: $1"
  fi
}

ensure_python_version() {
  need_cmd "${PYTHON_BIN}"
  "${PYTHON_BIN}" - <<'PY'
import sys
raise SystemExit(0 if sys.version_info >= (3, 10) else 1)
PY
}

ensure_base_tools() {
  need_cmd git
  need_cmd bash
  ensure_python_version
}

clone_or_refresh_repo() {
  if [ -d "${PYMC_REPEATER_DIR}/.git" ]; then
    stage "Refreshing pyMC_Repeater"
    git -C "${PYMC_REPEATER_DIR}" fetch --tags --force origin
    git -C "${PYMC_REPEATER_DIR}" reset --hard
    git -C "${PYMC_REPEATER_DIR}" clean -fd
  else
    stage "Cloning pyMC_Repeater"
    mkdir -p "$(dirname "${PYMC_REPEATER_DIR}")"
    git clone --branch "${PYMC_REPEATER_REF}" "${PYMC_REPEATER_REPO}" "${PYMC_REPEATER_DIR}"
    return
  fi

  git -C "${PYMC_REPEATER_DIR}" checkout -f "${PYMC_REPEATER_REF}"
  git -C "${PYMC_REPEATER_DIR}" reset --hard "origin/${PYMC_REPEATER_REF}"
}

ensure_repo_present() {
  [ -f "${PYMC_REPEATER_DIR}/manage.sh" ] || fail "Missing ${PYMC_REPEATER_DIR}/manage.sh. Run: sh buildroot-manage.sh install"
}

run_repo_manage() {
  action="$1"
  shift || true
  ensure_repo_present
  exec env \
    PATH="${SHIM_DIR}:${PATH}" \
    TERM="${TERM:-xterm}" \
    PYMC_SILENT="${PYMC_SILENT:-1}" \
    bash "${PYMC_REPEATER_DIR}/manage.sh" "${action}" "$@"
}

doctor() {
  stage "Checking image baseline"
  ensure_base_tools

  for cmd in dialog jq wget sudo; do
    if command -v "${cmd}" >/dev/null 2>&1; then
      info "found ${cmd}"
    else
      warn "missing ${cmd}"
    fi
  done

  for shim in apt-get getent journalctl pkaction pip systemctl useradd usermod; do
    if [ -x "${SHIM_DIR}/${shim}" ]; then
      info "shim ready: ${shim}"
    else
      warn "missing shim: ${shim}"
    fi
  done

  if "${PYTHON_BIN}" -m venv --help >/dev/null 2>&1; then
    info "python venv support available"
  else
    warn "python venv support missing"
  fi

  if "${PYTHON_BIN}" - <<'PY'
modules = [
    "yaml",
    "cherrypy",
    "cherrypy_cors",
    "paho.mqtt.client",
    "psutil",
    "jwt",
    "ws4py",
    "nacl",
    "periphery",
    "spidev",
    "serial",
    "usb",
    "Crypto",
]
for module in modules:
    __import__(module)
PY
  then
    info "core python runtime packages are present"
  else
    warn "python runtime packages missing; image is not ready for stock upstream install"
  fi

  for path in /dev/spidev* /dev/gpiochip*; do
    if [ -e "${path}" ]; then
      info "detected ${path}"
    fi
  done

  if [ -f "${PYMC_REPEATER_DIR}/manage.sh" ]; then
    info "repo checkout present at ${PYMC_REPEATER_DIR}"
  else
    info "repo checkout not present yet; install will clone it to ${PYMC_REPEATER_DIR}"
  fi
}

wait_ready() {
  timeout_seconds="${1:-60}"
  stage "Waiting for pyMC API"
  end_time=$(( $(date +%s) + timeout_seconds ))
  while [ "$(date +%s)" -le "${end_time}" ]; do
    if API_HOST="${API_HOST}" API_PORT="${API_PORT}" "${PYTHON_BIN}" - <<'PY'
import os
import socket

host = os.environ["API_HOST"]
port = int(os.environ["API_PORT"])

with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
    sock.settimeout(1)
    raise SystemExit(0 if sock.connect_ex((host, port)) == 0 else 1)
PY
    then
      info "API ready on ${API_HOST}:${API_PORT}"
      return 0
    fi
    sleep 1
  done
  fail "Timed out waiting for pyMC API on ${API_HOST}:${API_PORT}"
}

run_advert() {
  wait_ready "${1:-60}"
  need_cmd pymc-cli
  printf 'advert\nexit\n' | pymc-cli --host "${API_HOST}" --port "${API_PORT}"
}

cmd="${1:-}"
case "${cmd}" in
  install)
    ensure_base_tools
    clone_or_refresh_repo
    shift
    run_repo_manage install "$@"
    ;;
  upgrade)
    ensure_base_tools
    clone_or_refresh_repo
    shift
    run_repo_manage upgrade "$@"
    ;;
  config|start|stop|restart|status|logs|uninstall|debug)
    ensure_base_tools
    shift
    run_repo_manage "${cmd}" "$@"
    ;;
  doctor)
    doctor
    ;;
  wait-ready)
    shift
    wait_ready "${1:-60}"
    ;;
  advert)
    shift
    run_advert "${1:-60}"
    ;;
  repo-path)
    printf '%s\n' "${PYMC_REPEATER_DIR}"
    ;;
  repo-sync)
    ensure_base_tools
    clone_or_refresh_repo
    ;;
  ""|help|-h|--help)
    usage
    ;;
  *)
    fail "Unknown command: ${cmd}"
    ;;
esac
