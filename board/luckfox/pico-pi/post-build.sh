#!/bin/sh
set -eu

TARGET_DIR="$1"
EXTERNAL_DIR="${BR2_EXTERNAL_LUCKFOX_PICO_PI_PATH:?missing BR2_EXTERNAL_LUCKFOX_PICO_PI_PATH}"
APP_DIR="${TARGET_DIR}/opt/scripts"
ROOT_PASSWORD_HASH='$1$dXmV8ZLO$eNAQzSYOgRkYMJRdsHwLS1'
SDK_DIR=$(CDPATH= cd -- "${TARGET_DIR}/../../../../../.." && pwd)
SDK_BOARD_CONFIG_LINK="${SDK_DIR}/.BoardConfig.mk"
SDK_OVERLAY_DIR="${SDK_DIR}/project/cfg/BoardConfig_IPC/overlay"

sync_python_sqlite_stdlib() {
  python_dir=$(find "${TARGET_DIR}/usr/lib" -maxdepth 1 -mindepth 1 -type d -name 'python3.*' | head -n 1 || true)
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
  python_dir=$(find "${TARGET_DIR}/usr/lib" -maxdepth 1 -mindepth 1 -type d -name 'python3.*' | head -n 1 || true)
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
rm -f "${TARGET_DIR}/root/scripts"
rm -f "${TARGET_DIR}/usr/local/bin/network-setup.sh"
rm -f "${TARGET_DIR}/usr/local/bin/wifi-setup.sh"
rm -f "${TARGET_DIR}/etc/init.d/S41dhcpcd"
rm -f "${TARGET_DIR}/etc/init.d/S50telnet"

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
image_version=0.6.9
EOF
