#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
API_HOST="${API_HOST:-127.0.0.1}"
API_PORT="${API_PORT:-8000}"

PYTHON_BIN="${PYTHON_BIN:-python3}"
PYMC_REPEATER_REPO="${PYMC_REPEATER_REPO:-https://github.com/rightup/pyMC_Repeater.git}"
PYMC_REPEATER_REF="${PYMC_REPEATER_REF:-dev}"
DEFAULT_REPEATER_HOME="${HOME:-/root}"
if [ "$(id -u 2>/dev/null || echo 1)" = "0" ]; then
  DEFAULT_REPEATER_HOME="/root"
fi
PYMC_REPEATER_HOME="${PYMC_REPEATER_HOME:-${DEFAULT_REPEATER_HOME}}"
PYMC_REPEATER_DIR="${PYMC_REPEATER_DIR:-${PYMC_REPEATER_HOME}/pyMC_Repeater}"

usage() {
  cat <<'EOF'
Usage: sh buildroot-manage.sh <command>

This script is only a Buildroot image bootstrap/proxy. It clones pyMC_Repeater
into `/root` when run as root, otherwise into the current user's home
directory, and then hands off to the repo's Buildroot-specific
`buildroot-manage.sh` when present. If the repo does not ship that file yet, it
falls back to the repo's stock `manage.sh`.

Commands:
  doctor      Check image prerequisites for upstream pyMC install
  install     Clone/update ~/pyMC_Repeater and run the repo install flow
  upgrade     Refresh ~/pyMC_Repeater and run the repo upgrade flow
  radio-profile
              Apply Luckfox radio pin mapping to /etc/pymc_repeater/config.yaml
  config      Run the repo config flow
  start       Run the repo service start flow
  stop        Run the repo service stop flow
  restart     Run the repo service restart flow
  status      Run the repo status flow
  logs        Run the repo logs flow
  uninstall   Run the repo uninstall flow
  debug       Run the repo debug flow
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

prompt_choice() {
  prompt_text=$1
  default_answer=${2:-}
  answer=""

  if [ ! -t 0 ]; then
    printf '%s' "${default_answer}"
    return 0
  fi

  if [ -n "${default_answer}" ]; then
    printf '%s [%s]: ' "${prompt_text}" "${default_answer}" >&2
  else
    printf '%s: ' "${prompt_text}" >&2
  fi
  IFS= read -r answer
  if [ -z "${answer}" ]; then
    answer="${default_answer}"
  fi
  printf '%s' "${answer}"
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
  if [ -f "${PYMC_REPEATER_DIR}/buildroot-manage.sh" ]; then
    env \
      TERM="${TERM:-xterm}" \
      PYMC_SILENT="${PYMC_SILENT:-1}" \
      bash "${PYMC_REPEATER_DIR}/buildroot-manage.sh" "${action}" "$@"
    return $?
  fi

  env \
    TERM="${TERM:-xterm}" \
    PYMC_SILENT="${PYMC_SILENT:-1}" \
    bash "${PYMC_REPEATER_DIR}/manage.sh" "${action}" "$@"
  return $?
}

normalize_radio_profile() {
  profile=$(printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]')
  case "${profile}" in
    1|v2|pimesh-v2|pimesh_1w_v2|pimesh-1w-v2)
      printf '%s\n' 'pimesh-v2'
      ;;
    2|v1|pimesh-v1|pimesh_1w_v1|pimesh-1w-v1|meshadv|mesh-adv)
      printf '%s\n' 'pimesh-v1'
      ;;
    3|skip|none|"")
      printf '%s\n' 'skip'
      ;;
    *)
      return 1
      ;;
  esac
}

apply_luckfox_radio_profile() {
  profile="${1:-}"
  cfg="${PYMC_CONFIG_PATH:-/etc/pymc_repeater/config.yaml}"

  [ -f "${cfg}" ] || fail "Missing pyMC config: ${cfg}"

  case "${profile}" in
    pimesh-v2)
      stage "Applying Luckfox radio profile: PiMesh V2"
      sx1262_block=$(cat <<'EOF'
sx1262:
  bus_id: 0
  busy_pin: 122
  cs_id: 0
  cs_pin: -1
  dio3_tcxo_voltage: 1.8
  en_pin: 0
  irq_pin: 121
  is_waveshare: false
  reset_pin: 54
  rxen_pin: -1
  rxled_pin: -1
  txen_pin: -1
  txled_pin: -1
  use_dio2_rf: true
  use_dio3_tcxo: true
EOF
)
      ;;
    pimesh-v1)
      stage "Applying Luckfox radio profile: PiMesh V1 / MeshAdv"
      sx1262_block=$(cat <<'EOF'
sx1262:
  bus_id: 0
  busy_pin: 123
  cs_id: 0
  cs_pin: 145
  dio3_tcxo_voltage: 1.8
  en_pin: -1
  irq_pin: 55
  is_waveshare: false
  reset_pin: 54
  rxen_pin: 53
  rxled_pin: -1
  txen_pin: 52
  txled_pin: -1
  use_dio2_rf: false
  use_dio3_tcxo: true
EOF
)
      ;;
    skip)
      info "skipping radio pin update"
      return 0
      ;;
    *)
      fail "Unknown radio profile: ${profile}"
      ;;
  esac

  cp "${cfg}" "${cfg}.bak-$(date +%Y%m%d-%H%M%S)"
  PYMC_CONFIG_PATH="${cfg}" SX1262_BLOCK="${sx1262_block}" "${PYTHON_BIN}" - <<'PY'
from pathlib import Path
import os

path = Path(os.environ["PYMC_CONFIG_PATH"])
block = os.environ["SX1262_BLOCK"].rstrip("\n") + "\n"
text = path.read_text()

if "sx1262:\n" in text:
    start = text.index("sx1262:\n")
    rest = text[start:]
    lines = rest.splitlines(True)
    end_offset = None
    for i, line in enumerate(lines[1:], start=1):
        if line and not line.startswith((" ", "\t")):
            end_offset = sum(len(x) for x in lines[:i])
            break
    if end_offset is None:
        end_offset = len(rest)
    text = text[:start] + block + rest[end_offset:]
else:
    text = text.rstrip() + "\n\n" + block

path.write_text(text)
PY

  info "updated ${cfg}"
  grep -A20 '^sx1262:' "${cfg}" || true
}

choose_and_apply_radio_profile() {
  if [ ! -f /etc/pymc_repeater/config.yaml ]; then
    warn "pyMC config not found yet; skipping radio profile selection"
    return 0
  fi

  selected="${LUCKFOX_RADIO_PROFILE:-}"
  if [ -z "${selected}" ]; then
    cat <<'EOF'

Select Luckfox radio profile:
  1) PiMesh V2
  2) PiMesh V1 / MeshAdv
  3) Skip for now
EOF
    selected=$(prompt_choice "Profile" "1")
  fi

  normalized=$(normalize_radio_profile "${selected}") || fail "Unknown radio profile choice: ${selected}"
  apply_luckfox_radio_profile "${normalized}"
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

  if "${PYTHON_BIN}" -m venv --help >/dev/null 2>&1; then
    info "python venv support available"
  else
    warn "python venv support missing"
  fi

  if "${PYTHON_BIN}" - <<'PY'
modules = [
    "sqlite3",
    "backports.tarfile",
    "yaml",
    "cherrypy",
    "cherrypy_cors",
    "autocommand",
    "jaraco.collections",
    "jaraco.text",
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

  if [ -f "${PYMC_REPEATER_DIR}/buildroot-manage.sh" ]; then
    info "repo Buildroot helper present at ${PYMC_REPEATER_DIR}/buildroot-manage.sh"
  elif [ -f "${PYMC_REPEATER_DIR}/manage.sh" ]; then
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
    choose_and_apply_radio_profile
    ;;
  upgrade)
    ensure_base_tools
    clone_or_refresh_repo
    shift
    run_repo_manage upgrade "$@"
    ;;
  radio-profile)
    shift
    if [ $# -gt 0 ]; then
      normalized=$(normalize_radio_profile "$1") || fail "Unknown radio profile choice: $1"
      apply_luckfox_radio_profile "${normalized}"
    else
      choose_and_apply_radio_profile
    fi
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
