#!/bin/sh
set -eu

TARGET_DIR="$1"
EXTERNAL_DIR="${BR2_EXTERNAL_LUCKFOX_PICO_PI_PATH:?missing BR2_EXTERNAL_LUCKFOX_PICO_PI_PATH}"
APP_DIR="${TARGET_DIR}/opt/scripts"
ROOT_PASSWORD_HASH='$1$dXmV8ZLO$eNAQzSYOgRkYMJRdsHwLS1'
SDK_DIR=$(CDPATH= cd -- "${TARGET_DIR}/../../../../../.." && pwd)
SDK_BOARD_CONFIG_LINK="${SDK_DIR}/.BoardConfig.mk"
SDK_OVERLAY_DIR="${SDK_DIR}/project/cfg/BoardConfig_IPC/overlay"
PYMC_EMBED_STAGE_DIR="${PYMC_EMBED_STAGE_DIR:-}"
PYMC_EMBED_INSTALL="${PYMC_EMBED_INSTALL:-0}"
PYMC_EMBED_RUNTIME_SITE_DIR="${PYMC_EMBED_STAGE_DIR}/venv-site-packages"

target_python_dir() {
  find "${TARGET_DIR}/usr/lib" -maxdepth 1 -mindepth 1 -type d -name 'python3.*' | head -n 1 || true
}

install_baked_runtime_payload() {
  [ "${PYMC_EMBED_INSTALL}" = "1" ] || return 0
  [ -n "${PYMC_EMBED_STAGE_DIR}" ] || {
    printf '%s\n' "Embedded runtime requested but PYMC_EMBED_STAGE_DIR is empty" >&2
    exit 1
  }

  repeater_src="${PYMC_EMBED_STAGE_DIR}/pyMC_Repeater"
  runtime_site_dir="${PYMC_EMBED_RUNTIME_SITE_DIR}"
  python_dir=$(target_python_dir)
  [ -n "${python_dir}" ] || {
    printf '%s\n' "Missing target Python directory under ${TARGET_DIR}/usr/lib" >&2
    exit 1
  }
  python_version=$(basename "${python_dir}")
  venv_dir="${TARGET_DIR}/opt/pymc_repeater/venv"
  venv_site_dir="${venv_dir}/lib/${python_version}/site-packages"
  data_dir="${TARGET_DIR}/var/lib/pymc_repeater"
  config_dir="${TARGET_DIR}/etc/pymc_repeater"

  [ -f "${repeater_src}/buildroot-manage.sh" ] || {
    printf '%s\n' "Missing embedded pyMC_Repeater checkout: ${repeater_src}" >&2
    exit 1
  }
  [ -d "${runtime_site_dir}" ] || {
    printf '%s\n' "Missing baked runtime site-packages: ${runtime_site_dir}" >&2
    exit 1
  }

  rm -rf "${TARGET_DIR}/opt/pymc_repeater"
  mkdir -p "${TARGET_DIR}/opt/pymc_repeater" "${venv_site_dir}" "${data_dir}" "${config_dir}" "${TARGET_DIR}/var/log/pymc_repeater"

  cp -a "${repeater_src}" "${TARGET_DIR}/opt/pymc_repeater/pyMC_Repeater"
  chmod 0755 "${TARGET_DIR}/opt/pymc_repeater/pyMC_Repeater/buildroot-manage.sh"

  cp -a "${runtime_site_dir}/." "${venv_site_dir}/"
  printf '%s\n' "/usr/lib/${python_version}/site-packages" > "${venv_site_dir}/buildroot-system-site-packages.pth"

  mkdir -p "${venv_dir}/bin"
  ln -snf /usr/bin/python3 "${venv_dir}/bin/python"
  ln -snf /usr/bin/python3 "${venv_dir}/bin/python3"
  cat > "${venv_dir}/bin/pip" <<'EOF'
#!/bin/sh
exec "$(dirname "$0")/python" -m pip "$@"
EOF
  cat > "${venv_dir}/bin/pip3" <<'EOF'
#!/bin/sh
exec "$(dirname "$0")/python" -m pip "$@"
EOF
  chmod 0755 "${venv_dir}/bin/pip" "${venv_dir}/bin/pip3"
  cat > "${venv_dir}/pyvenv.cfg" <<EOF
home = /usr/bin
include-system-site-packages = false
version = ${python_version#python}
EOF

  cp "${repeater_src}/config.yaml.example" "${config_dir}/config.yaml.example"
  cp "${repeater_src}/config.yaml.example" "${config_dir}/config.yaml"
  cp "${repeater_src}/radio-settings.json" "${data_dir}/"
  cp "${repeater_src}/radio-settings-buildroot.json" "${data_dir}/"
  cp "${repeater_src}/radio-presets.json" "${data_dir}/"

  python3 - "${config_dir}/config.yaml" "${data_dir}/radio-settings.json" "${data_dir}/radio-settings-buildroot.json" "${data_dir}/radio-presets.json" "${PYMC_EMBED_BUILDROOT_BOARD:-}" "${PYMC_EMBED_RADIO_PRESET:-}" <<'PY'
import json
import sys
import yaml

config_path, radio_settings_path, buildroot_settings_path, presets_path, board_choice, preset_choice = sys.argv[1:7]

with open(config_path, "r", encoding="utf-8") as fh:
    data = yaml.safe_load(fh) or {}
with open(radio_settings_path, "r", encoding="utf-8") as fh:
    radio_settings = json.load(fh)
with open(buildroot_settings_path, "r", encoding="utf-8") as fh:
    buildroot_settings = json.load(fh)
with open(presets_path, "r", encoding="utf-8") as fh:
    presets_data = json.load(fh)

buildroot_hardware = buildroot_settings.get("buildroot_hardware") or {}
default_board = buildroot_settings.get("default_board")
board_key = board_choice or default_board
if board_key not in buildroot_hardware:
    raise SystemExit(f"Unknown Buildroot board: {board_key}")

board = buildroot_hardware[board_key]
hardware = ((radio_settings.get("hardware") or {}).get(board.get("hardware_id")) or {}).copy()
if not hardware:
    raise SystemExit(f"Missing hardware config: {board.get('hardware_id')}")
sx1262 = hardware.copy()
sx1262.update(board.get("sx1262_overrides") or {})

entries = ((presets_data.get("config") or {}).get("suggested_radio_settings") or {}).get("entries", [])
default_preset = buildroot_settings.get("default_radio_preset")
preset_title = preset_choice or default_preset
preset = next((entry for entry in entries if entry.get("title") == preset_title), None)
if not preset:
    raise SystemExit(f"Unknown radio preset: {preset_title}")

radio = data.setdefault("radio", {})
radio["frequency"] = int(round(float(preset.get("frequency", 0)) * 1_000_000))
radio["spreading_factor"] = int(preset.get("spreading_factor", 7))
radio["bandwidth"] = int(round(float(preset.get("bandwidth", 0)) * 1000))
radio["coding_rate"] = int(preset.get("coding_rate", 5))
radio["tx_power"] = int(board.get("tx_power", radio.get("tx_power", 22)))

data["radio_type"] = hardware.get("radio_type", "sx1262")

sx = data.setdefault("sx1262", {})
sx.setdefault("bus_id", 0)
sx.setdefault("cs_id", 0)
sx.setdefault("txled_pin", -1)
sx.setdefault("rxled_pin", -1)
sx.setdefault("is_waveshare", False)
for key, value in sx1262.items():
    sx[key] = value

if data["radio_type"] == "sx1262_ch341":
    ch341 = data.setdefault("ch341", {})
    for key in ("vid", "pid"):
        if key in hardware:
            ch341[key] = hardware[key]

with open(config_path, "w", encoding="utf-8") as fh:
    yaml.safe_dump(data, fh, sort_keys=False)
PY

  cat > "${TARGET_DIR}/etc/init.d/S80pymc-repeater" <<'EOF'
#!/bin/sh
DAEMON="/opt/pymc_repeater/venv/bin/python"
PIDFILE="/var/run/pymc-repeater.pid"
LOGFILE="/var/log/pymc_repeater/repeater.log"
WORKDIR="/var/lib/pymc_repeater"
CONFIG_FILE="/etc/pymc_repeater/config.yaml"
RUN_AS="root"

start() {
    mkdir -p "$(dirname "$PIDFILE")" "$(dirname "$LOGFILE")" "$WORKDIR"
    if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
        echo "pymc-repeater is already running."
        return 0
    fi
    start-stop-daemon --start --quiet --background --make-pidfile --pidfile "$PIDFILE" \
        --chuid "$RUN_AS" --exec /bin/sh -- -c "cd \"$WORKDIR\" && exec \"$DAEMON\" -m repeater.main --config \"$CONFIG_FILE\" >>\"$LOGFILE\" 2>&1"
}

stop() {
    if [ ! -f "$PIDFILE" ]; then
        echo "pymc-repeater is not running."
        return 0
    fi
    start-stop-daemon --stop --quiet --retry 5 --pidfile "$PIDFILE" >/dev/null 2>&1 || true
    rm -f "$PIDFILE"
}

status() {
    if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
        echo "pymc-repeater is running."
        return 0
    fi
    echo "pymc-repeater is stopped."
    return 1
}

case "${1:-}" in
    start) start ;;
    stop) stop ;;
    restart) stop; start ;;
    status) status ;;
    *)
        echo "Usage: $0 {start|stop|restart|status}"
        exit 1
        ;;
esac
EOF
  chmod 0755 "${TARGET_DIR}/etc/init.d/S80pymc-repeater"
}

sync_python_sqlite_stdlib() {
  python_dir=$(target_python_dir)
  [ -n "${python_dir}" ] || return 0

  sqlite_init="${python_dir}/sqlite3/__init__.py"
  [ -f "${sqlite_init}" ] && return 0

  buildroot_output_dir=$(CDPATH= cd -- "${TARGET_DIR}/.." && pwd)
  python_build_dir=$(find "${buildroot_output_dir}/build" -maxdepth 1 -mindepth 1 -type d -name 'python3-*' | head -n 1 || true)
  [ -n "${python_build_dir}" ] || {
    printf '%s\n' "Missing Buildroot Python build directory under ${buildroot_output_dir}/build" >&2
    exit 1
  }

  source_sqlite_dir="${python_build_dir}/Lib/sqlite3"
  [ -f "${source_sqlite_dir}/__init__.py" ] || {
    printf '%s\n' "Missing Python sqlite3 stdlib source: ${source_sqlite_dir}" >&2
    exit 1
  }

  cp -a "${source_sqlite_dir}" "${python_dir}/sqlite3"
}

sync_python_sqlite_extension() {
  python_dir=$(target_python_dir)
  [ -n "${python_dir}" ] || return 0

  sqlite_ext=$(find "${python_dir}/lib-dynload" -maxdepth 1 -type f -name '_sqlite3*.so' | head -n 1 || true)
  [ -n "${sqlite_ext}" ] && return 0

  buildroot_output_dir=$(CDPATH= cd -- "${TARGET_DIR}/.." && pwd)
  python_build_dir=$(find "${buildroot_output_dir}/build" -maxdepth 1 -mindepth 1 -type d -name 'python3-*' | head -n 1 || true)
  [ -n "${python_build_dir}" ] || {
    printf '%s\n' "Missing Buildroot Python build directory under ${buildroot_output_dir}/build" >&2
    exit 1
  }

  source_sqlite_ext=$(find "${python_build_dir}" -type f -name '_sqlite3*.so' | head -n 1 || true)
  [ -n "${source_sqlite_ext}" ] || {
    printf '%s\n' "Missing built Python _sqlite3 extension under ${python_build_dir}" >&2
    exit 1
  }

  mkdir -p "${python_dir}/lib-dynload"
  cp -a "${source_sqlite_ext}" "${python_dir}/lib-dynload/"
}

restore_vendor_overlays() {
  [ -f "${SDK_BOARD_CONFIG_LINK}" ] || {
    printf '%s\n' "Missing SDK board config link: ${SDK_BOARD_CONFIG_LINK}" >&2
    exit 1
  }
  [ -d "${SDK_OVERLAY_DIR}" ] || {
    printf '%s\n' "Missing SDK overlay directory: ${SDK_OVERLAY_DIR}" >&2
    exit 1
  }

  # shellcheck disable=SC1090
  . "${SDK_BOARD_CONFIG_LINK}"

  for overlay_name in ${RK_POST_OVERLAY:-}; do
    overlay_path="${SDK_OVERLAY_DIR}/${overlay_name}"
    [ -d "${overlay_path}" ] || {
      printf '%s\n' "Missing vendor overlay: ${overlay_path}" >&2
      exit 1
    }
    cp -a "${overlay_path}/." "${TARGET_DIR}/"
  done
}

restore_vendor_overlays

mkdir -p "${APP_DIR}"
rm -rf "${APP_DIR}/shims"
rm -rf "${TARGET_DIR}/opt/pymc-repeater-buildroot"
rm -rf "${TARGET_DIR}/root/pymc-repeater-buildroot"
rm -rf "${TARGET_DIR}/root/pyMC_Repeater" "${TARGET_DIR}/root/pyMC_core"
rm -f "${TARGET_DIR}/root/scripts"
rm -f "${TARGET_DIR}/usr/local/bin/network-setup.sh"
rm -f "${TARGET_DIR}/usr/local/bin/wifi-setup.sh"
rm -f "${TARGET_DIR}/etc/init.d/S41dhcpcd"
rm -f "${TARGET_DIR}/etc/init.d/S50telnet"
rm -f "${TARGET_DIR}/etc/init.d/S79pymc-embedded-install"
rm -f "${TARGET_DIR}/etc/default/pymc-embedded-install"

install -m 0755 "${EXTERNAL_DIR}/buildroot-manage.sh" "${APP_DIR}/buildroot-manage.sh"
install -m 0755 "${EXTERNAL_DIR}/tailscale-manage.sh" "${APP_DIR}/tailscale-manage.sh"
install -m 0755 "${EXTERNAL_DIR}/pymc-console-webui.sh" "${APP_DIR}/pymc-console-webui.sh"
install -m 0755 "${EXTERNAL_DIR}/board/luckfox/pico-pi/rootfs-overlay/usr/local/bin/network-setup.sh" "${APP_DIR}/network-setup.sh"
install -m 0755 "${EXTERNAL_DIR}/board/luckfox/pico-pi/rootfs-overlay/usr/local/bin/wifi-setup.sh" "${APP_DIR}/wifi-setup.sh"
install -m 0644 "${EXTERNAL_DIR}/README.md" "${APP_DIR}/README.md"
install -m 0644 "${EXTERNAL_DIR}/BUILDROOT.md" "${APP_DIR}/BUILDROOT.md"

mkdir -p "${TARGET_DIR}/usr/local/bin" "${TARGET_DIR}/usr/local/sbin"
install -m 0755 "${EXTERNAL_DIR}/board/luckfox/pico-pi/rootfs-overlay/usr/local/sbin/network-priority.sh" "${TARGET_DIR}/usr/local/sbin/network-priority.sh"
ln -snf /opt/scripts/network-setup.sh "${TARGET_DIR}/usr/local/bin/network-setup.sh"
ln -snf /opt/scripts/wifi-setup.sh "${TARGET_DIR}/usr/local/bin/wifi-setup.sh"

sync_python_sqlite_stdlib
sync_python_sqlite_extension
install_baked_runtime_payload

mkdir -p "${TARGET_DIR}/root"
ln -snf /opt/scripts "${TARGET_DIR}/root/scripts"

mkdir -p "${TARGET_DIR}/var/empty"
chmod 0755 "${TARGET_DIR}/var/empty"

if [ ! -x "${TARGET_DIR}/usr/bin/luckfox-config" ]; then
  printf '%s\n' "Vendor overlay chain did not restore /usr/bin/luckfox-config" >&2
  exit 1
fi

# Force the final image to ship with a known SSH login even if vendor overlays
# replace Buildroot's generated shadow file earlier in the SDK pipeline.
if [ -f "${TARGET_DIR}/etc/shadow" ]; then
  sed -i "s|^root:[^:]*:|root:${ROOT_PASSWORD_HASH}:|" "${TARGET_DIR}/etc/shadow"
fi

if [ -f "${TARGET_DIR}/etc/passwd" ]; then
  sed -i 's|^root:[^:]*:[^:]*:[^:]*:[^:]*:[^:]*:[^:]*$|root:x:0:0:root:/root:/bin/sh|' "${TARGET_DIR}/etc/passwd"
fi

mkdir -p "${TARGET_DIR}/etc"
cat > "${TARGET_DIR}/etc/pymc-image-build-id" <<EOF
image_name=Luckfox pyMC Repeater Buildroot
image_version=0.6.9
EOF
