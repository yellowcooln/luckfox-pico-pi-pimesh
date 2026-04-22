#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
SRC_DIR="${SCRIPT_DIR}/.buildroot-src"
RUNTIME_DIR="${SCRIPT_DIR}/.buildroot-runtime"
CONFIG_DIR="${RUNTIME_DIR}/config"
DATA_DIR="${RUNTIME_DIR}/data"
LOG_DIR="${RUNTIME_DIR}/logs"
SITE_PACKAGES_DIR="${RUNTIME_DIR}/site-packages"
VENV_DIR="${RUNTIME_DIR}/venv"
LAUNCHER_PATH="${RUNTIME_DIR}/run-pymc-repeater.sh"
PID_FILE="${RUNTIME_DIR}/pymc-repeater.pid"
LOG_FILE="${LOG_DIR}/pymc-repeater.log"
INIT_SCRIPT_PATH="/etc/init.d/S95pymc-repeater"

PYTHON_BIN="${PYTHON_BIN:-python3}"
PYMC_CORE_REPO="${PYMC_CORE_REPO:-https://github.com/rightup/pyMC_core.git}"
PYMC_CORE_REF="${PYMC_CORE_REF:-dev}"
PYMC_REPEATER_REPO="${PYMC_REPEATER_REPO:-https://github.com/rightup/pyMC_Repeater.git}"
PYMC_REPEATER_REF="${PYMC_REPEATER_REF:-dev}"

PYMC_CORE_SRC="${SRC_DIR}/pyMC_core"
PYMC_REPEATER_SRC="${SRC_DIR}/pyMC_Repeater"
CONFIG_PATH="${CONFIG_DIR}/config.yaml"
IDENTITY_PATH="${CONFIG_DIR}/identity.key"

usage() {
  cat <<'EOF'
Usage: sh buildroot-manage.sh <command>

Commands:
  install                Install Python deps, sync upstream sources, and write config
  configure              Rebuild config.yaml without forcing radio hardware
  doctor                 Check Buildroot prerequisites and common radio device nodes
  run                    Run pyMC_Repeater in the foreground
  start                  Start pyMC_Repeater in the background; use "start logs" to tail logs
  stop                   Stop the background process
  restart                Restart the background process
  status                 Show runtime status
  logs                   Tail the runtime log
  install-init-script    Install BusyBox init script
  uninstall-init-script  Remove BusyBox init script
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
  ensure_python_version
}

python_runtime_ready() {
  "${PYTHON_BIN}" - <<'PY'
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
    "serial",
    "usb",
    "Crypto",
]

for module in modules:
    __import__(module)
PY
}

ensure_native_build_prereqs() {
  if ! command -v gcc >/dev/null 2>&1; then
    fail "Missing gcc. spidev needs a compiler on this image."
  fi
  if ! command -v make >/dev/null 2>&1; then
    fail "Missing make. spidev needs build tools on this image."
  fi
  if ! "${PYTHON_BIN}" - <<'PY'
import sysconfig
from pathlib import Path

include_dir = Path(sysconfig.get_config_var("INCLUDEPY") or "")
header = include_dir / "Python.h"
raise SystemExit(0 if header.exists() else 1)
PY
  then
    fail "Missing Python development headers. spidev build needs Python.h on this image."
  fi
}

ensure_directories() {
  mkdir -p "${SRC_DIR}" "${RUNTIME_DIR}" "${CONFIG_DIR}" "${DATA_DIR}" "${LOG_DIR}"
}

as_root() {
  if [ "$(id -u)" -eq 0 ]; then
    "$@"
    return
  fi
  if command -v sudo >/dev/null 2>&1; then
    sudo "$@"
    return
  fi
  fail "This command requires root. Re-run as root or install sudo."
}

clone_or_refresh_repo() {
  repo_url="$1"
  repo_ref="$2"
  dest_dir="$3"

  if [ -d "${dest_dir}/.git" ]; then
    stage "Refreshing $(basename "${dest_dir}")"
    git -C "${dest_dir}" fetch --tags --force origin
    git -C "${dest_dir}" reset --hard
    git -C "${dest_dir}" clean -fd
  else
    stage "Cloning $(basename "${dest_dir}")"
    git clone "${repo_url}" "${dest_dir}"
  fi

  git -C "${dest_dir}" checkout -f "${repo_ref}"
}

sync_sources() {
  ensure_directories
  clone_or_refresh_repo "${PYMC_CORE_REPO}" "${PYMC_CORE_REF}" "${PYMC_CORE_SRC}"
  clone_or_refresh_repo "${PYMC_REPEATER_REPO}" "${PYMC_REPEATER_REF}" "${PYMC_REPEATER_SRC}"
}

python_bootstrap() {
  if [ -x "${VENV_DIR}/bin/python" ]; then
    printf '%s' "${VENV_DIR}/bin/python"
    return
  fi
  printf '%s' "${PYTHON_BIN}"
}

pip_bootstrap() {
  if [ -x "${VENV_DIR}/bin/pip" ]; then
    printf '%s' "${VENV_DIR}/bin/pip"
    return
  fi
  printf '%s -m pip' "${PYTHON_BIN}"
}

prepare_python_runtime() {
  stage "Preparing Python runtime"
  ensure_directories

  if python_runtime_ready; then
    info "Using system Python packages already present in the image"
    return
  fi

  ensure_native_build_prereqs

  if "${PYTHON_BIN}" -m venv --help >/dev/null 2>&1; then
    if [ ! -x "${VENV_DIR}/bin/python" ]; then
      "${PYTHON_BIN}" -m venv "${VENV_DIR}"
    fi
    "${VENV_DIR}/bin/pip" install --upgrade pip setuptools wheel
    "${VENV_DIR}/bin/pip" install \
      "pycryptodome>=3.23.0" \
      "PyNaCl>=1.5.0" \
      "PyYAML>=6.0.0" \
      "python-periphery>=2.4.1" \
      "spidev>=3.5" \
      "pyserial>=3.5" \
      "pyusb>=1.2.1" \
      "CherryPy>=18.0.0" \
      "paho-mqtt>=1.6.0" \
      "cherrypy-cors==1.7.0" \
      "psutil>=5.9.0" \
      "PyJWT>=2.8.0" \
      "ws4py>=0.6.0"
    return
  fi

  mkdir -p "${SITE_PACKAGES_DIR}"
  "${PYTHON_BIN}" -m pip install --upgrade pip setuptools wheel
  "${PYTHON_BIN}" -m pip install --target "${SITE_PACKAGES_DIR}" \
    "pycryptodome>=3.23.0" \
    "PyNaCl>=1.5.0" \
    "PyYAML>=6.0.0" \
    "python-periphery>=2.4.1" \
    "spidev>=3.5" \
    "pyserial>=3.5" \
    "pyusb>=1.2.1" \
    "CherryPy>=18.0.0" \
    "paho-mqtt>=1.6.0" \
    "cherrypy-cors==1.7.0" \
    "psutil>=5.9.0" \
    "PyJWT>=2.8.0" \
    "ws4py>=0.6.0"
}

prompt_with_default() {
  prompt_text="$1"
  default_value="$2"
  result=""
  if [ -t 0 ]; then
    printf '%s [%s]: ' "$prompt_text" "$default_value"
    IFS= read -r result
  fi
  if [ -z "${result}" ]; then
    result="${default_value}"
  fi
  printf '%s' "${result}"
}

build_pythonpath() {
  py_path="${PYMC_REPEATER_SRC}:${PYMC_CORE_SRC}/src"
  if [ -d "${SITE_PACKAGES_DIR}" ]; then
    py_path="${SITE_PACKAGES_DIR}:${py_path}"
  fi
  printf '%s' "${py_path}"
}

ensure_launcher() {
  stage "Writing launcher"
  cat > "${LAUNCHER_PATH}" <<EOF
#!/bin/sh
set -eu
SCRIPT_DIR=\$(CDPATH= cd -- "\$(dirname -- "\$0")" && pwd)
CONFIG_PATH="${CONFIG_PATH}"
LOG_FILE="${LOG_FILE}"
PYTHON_BIN="${PYTHON_BIN}"
VENV_PYTHON="${VENV_DIR}/bin/python"
VENV_BIN="${VENV_DIR}/bin"
PYTHONPATH_VALUE="$(build_pythonpath)"
export PYMC_REPEATER_CONFIG="\${CONFIG_PATH}"
export PYTHONUNBUFFERED=1
export PYTHONPATH="\${PYTHONPATH_VALUE}\${PYTHONPATH:+:\${PYTHONPATH}}"
mkdir -p "\$(dirname -- "\${LOG_FILE}")"
cd "${PYMC_REPEATER_SRC}"
if [ -x "\${VENV_PYTHON}" ]; then
  export PATH="\${VENV_BIN}:\${PATH}"
  exec "\${VENV_PYTHON}" -m repeater.main --config "\${CONFIG_PATH}" "\$@"
fi
exec "\${PYTHON_BIN}" -m repeater.main --config "\${CONFIG_PATH}" "\$@"
EOF
  chmod +x "${LAUNCHER_PATH}"
}

write_config() {
  stage "Writing config.yaml"

  node_name="${NODE_NAME:-}"
  admin_password="${ADMIN_PASSWORD:-}"
  guest_password="${GUEST_PASSWORD:-}"

  if [ -z "${node_name}" ]; then
    node_name=$(prompt_with_default "Node name" "pymc-repeater")
  fi
  if [ -z "${admin_password}" ]; then
    admin_password=$(prompt_with_default "Admin password" "admin123")
  fi
  if [ -z "${guest_password}" ]; then
    guest_password=$(prompt_with_default "Guest password" "guest123")
  fi
  CONFIG_PATH="${CONFIG_PATH}" \
  IDENTITY_PATH="${IDENTITY_PATH}" \
  DATA_DIR="${DATA_DIR}" \
  PYMC_REPEATER_SRC="${PYMC_REPEATER_SRC}" \
  NODE_NAME="${node_name}" \
  ADMIN_PASSWORD="${admin_password}" \
  GUEST_PASSWORD="${guest_password}" \
  "$(python_bootstrap)" - <<'PY'
import os
import secrets
from pathlib import Path

import yaml

config_path = Path(os.environ["CONFIG_PATH"])
identity_path = Path(os.environ["IDENTITY_PATH"])
data_dir = Path(os.environ["DATA_DIR"])
example_path = Path(os.environ["PYMC_REPEATER_SRC"]) / "config.yaml.example"

with example_path.open("r", encoding="utf-8") as handle:
    config = yaml.safe_load(handle)

config.setdefault("repeater", {})
config["repeater"]["node_name"] = os.environ["NODE_NAME"]
config["repeater"]["identity_file"] = str(identity_path)
config["repeater"].setdefault("security", {})
config["repeater"]["security"]["admin_password"] = os.environ["ADMIN_PASSWORD"]
config["repeater"]["security"]["guest_password"] = os.environ["GUEST_PASSWORD"]
config["repeater"]["security"]["jwt_secret"] = secrets.token_hex(32)

config.setdefault("storage", {})
config["storage"]["storage_dir"] = str(data_dir)

config_path.parent.mkdir(parents=True, exist_ok=True)
with config_path.open("w", encoding="utf-8") as handle:
    yaml.safe_dump(config, handle, default_flow_style=False, sort_keys=False)
PY
}

doctor() {
  stage "Checking prerequisites"
  ensure_base_tools
  info "Python: $("${PYTHON_BIN}" -V 2>&1)"
  info "Git: $(git --version)"
  if "${PYTHON_BIN}" -m venv --help >/dev/null 2>&1; then
    info "venv: available"
  else
    warn "venv: unavailable, will fall back to --target installs"
  fi
  if command -v gcc >/dev/null 2>&1; then
    info "gcc: available"
  else
    warn "gcc: missing"
  fi
  if command -v make >/dev/null 2>&1; then
    info "make: available"
  else
    warn "make: missing"
  fi
  if "${PYTHON_BIN}" - <<'PY'
import sysconfig
from pathlib import Path
include_dir = Path(sysconfig.get_config_var("INCLUDEPY") or "")
header = include_dir / "Python.h"
raise SystemExit(0 if header.exists() else 1)
PY
  then
    info "Python.h: available"
  else
    warn "Python.h: missing"
  fi

  stage "Checking common radio device nodes"
  found_any=0
  for path in /dev/spidev* /dev/gpiochip*; do
    if [ -e "${path}" ]; then
      info "present: ${path}"
      found_any=1
    fi
  done
  if [ "${found_any}" -eq 0 ]; then
    warn "No /dev/spidev* or /dev/gpiochip* nodes detected"
  fi

  stage "Checking network"
  if command -v ip >/dev/null 2>&1; then
    ip -o -4 addr show | sed 's/^/  - /'
  else
    warn "ip command not available"
  fi
}

is_running() {
  if [ ! -f "${PID_FILE}" ]; then
    return 1
  fi
  pid=$(cat "${PID_FILE}" 2>/dev/null || true)
  if [ -z "${pid}" ]; then
    return 1
  fi
  kill -0 "${pid}" >/dev/null 2>&1
}

run_foreground() {
  [ -x "${LAUNCHER_PATH}" ] || fail "Launcher missing. Run: sh buildroot-manage.sh install"
  exec "${LAUNCHER_PATH}"
}

start_background() {
  [ -x "${LAUNCHER_PATH}" ] || fail "Launcher missing. Run: sh buildroot-manage.sh install"
  mkdir -p "${LOG_DIR}"
  if is_running; then
    info "pyMC_Repeater is already running"
    return
  fi
  nohup "${LAUNCHER_PATH}" >> "${LOG_FILE}" 2>&1 &
  echo "$!" > "${PID_FILE}"
  sleep 1
  if is_running; then
    info "Started pyMC_Repeater (pid $(cat "${PID_FILE}"))"
  else
    fail "pyMC_Repeater did not stay running. Check: sh buildroot-manage.sh logs"
  fi
}

stop_background() {
  if ! is_running; then
    info "pyMC_Repeater is not running"
    rm -f "${PID_FILE}"
    return
  fi
  pid=$(cat "${PID_FILE}")
  kill "${pid}" >/dev/null 2>&1 || true
  sleep 1
  if kill -0 "${pid}" >/dev/null 2>&1; then
    kill -9 "${pid}" >/dev/null 2>&1 || true
  fi
  rm -f "${PID_FILE}"
  info "Stopped pyMC_Repeater"
}

show_status() {
  if is_running; then
    info "running (pid $(cat "${PID_FILE}"))"
  else
    info "not running"
  fi
  info "config: ${CONFIG_PATH}"
  info "log: ${LOG_FILE}"
}

tail_logs() {
  mkdir -p "${LOG_DIR}"
  touch "${LOG_FILE}"
  tail -f "${LOG_FILE}"
}

install_init_script() {
  stage "Installing BusyBox init script"
  tmp_file="${RUNTIME_DIR}/S95pymc-repeater"
  cat > "${tmp_file}" <<EOF
#!/bin/sh
case "\$1" in
  start)
    cd "${SCRIPT_DIR}" && sh buildroot-manage.sh start
    ;;
  stop)
    cd "${SCRIPT_DIR}" && sh buildroot-manage.sh stop
    ;;
  restart)
    cd "${SCRIPT_DIR}" && sh buildroot-manage.sh restart
    ;;
  status)
    cd "${SCRIPT_DIR}" && sh buildroot-manage.sh status
    ;;
  *)
    echo "Usage: \$0 {start|stop|restart|status}"
    exit 1
    ;;
esac
EOF
  chmod +x "${tmp_file}"
  as_root cp "${tmp_file}" "${INIT_SCRIPT_PATH}"
  info "Installed ${INIT_SCRIPT_PATH}"
}

uninstall_init_script() {
  stage "Removing BusyBox init script"
  if [ -f "${INIT_SCRIPT_PATH}" ]; then
    as_root rm -f "${INIT_SCRIPT_PATH}"
    info "Removed ${INIT_SCRIPT_PATH}"
  else
    info "Init script not installed"
  fi
}

install_all() {
  ensure_base_tools
  sync_sources
  prepare_python_runtime
  ensure_launcher
  write_config
  doctor
}

cmd="${1:-}"
case "${cmd}" in
  install)
    install_all
    ;;
  configure)
    ensure_base_tools
    ensure_directories
    write_config
    ;;
  doctor)
    doctor
    ;;
  run)
    shift
    run_foreground "$@"
    ;;
  start)
    start_background
    if [ "${2:-}" = "logs" ]; then
      tail_logs
    fi
    ;;
  stop)
    stop_background
    ;;
  restart)
    stop_background
    start_background
    ;;
  status)
    show_status
    ;;
  logs)
    tail_logs
    ;;
  install-init-script)
    install_init_script
    ;;
  uninstall-init-script)
    uninstall_init_script
    ;;
  ""|help|-h|--help)
    usage
    ;;
  *)
    fail "Unknown command: ${cmd}"
    ;;
esac
