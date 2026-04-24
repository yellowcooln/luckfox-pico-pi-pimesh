#!/bin/sh
set -eu

TARGET_DIR="$1"
EXTERNAL_DIR="${BR2_EXTERNAL_YELLOWCOOLN_PATH:?missing BR2_EXTERNAL_YELLOWCOOLN_PATH}"
APP_DIR="${TARGET_DIR}/opt/pymc-repeater-buildroot"
ROOT_PASSWORD_HASH='$1$dXmV8ZLO$eNAQzSYOgRkYMJRdsHwLS1'
SDK_DIR=$(CDPATH= cd -- "${TARGET_DIR}/../../../../../.." && pwd)
SDK_BOARD_CONFIG_LINK="${SDK_DIR}/.BoardConfig.mk"
SDK_OVERLAY_DIR="${SDK_DIR}/project/cfg/BoardConfig_IPC/overlay"

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

install -m 0755 "${EXTERNAL_DIR}/buildroot-manage.sh" "${APP_DIR}/buildroot-manage.sh"
install -m 0755 "${EXTERNAL_DIR}/tailscale-manage.sh" "${APP_DIR}/tailscale-manage.sh"
install -m 0755 "${EXTERNAL_DIR}/board/luckfox/pico-pi-pimesh/rootfs-overlay/usr/local/bin/network-setup.sh" "${APP_DIR}/network-setup.sh"
install -m 0755 "${EXTERNAL_DIR}/board/luckfox/pico-pi-pimesh/rootfs-overlay/usr/local/bin/wifi-setup.sh" "${APP_DIR}/wifi-setup.sh"
install -m 0755 "${EXTERNAL_DIR}/board/luckfox/pico-pi-pimesh/rootfs-overlay/usr/local/sbin/network-priority.sh" "${APP_DIR}/network-priority.sh"
install -m 0644 "${EXTERNAL_DIR}/README.md" "${APP_DIR}/README.md"
install -m 0644 "${EXTERNAL_DIR}/BUILDROOT.md" "${APP_DIR}/BUILDROOT.md"

mkdir -p "${TARGET_DIR}/usr/local/bin" "${TARGET_DIR}/usr/local/sbin"
ln -snf /opt/pymc-repeater-buildroot/network-setup.sh "${TARGET_DIR}/usr/local/bin/network-setup.sh"
ln -snf /opt/pymc-repeater-buildroot/wifi-setup.sh "${TARGET_DIR}/usr/local/bin/wifi-setup.sh"
ln -snf /opt/pymc-repeater-buildroot/network-priority.sh "${TARGET_DIR}/usr/local/sbin/network-priority.sh"

mkdir -p "${TARGET_DIR}/root"
ln -snf /opt/pymc-repeater-buildroot "${TARGET_DIR}/root/pymc-repeater-buildroot"

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
login_user=root
login_password=luckfox
EOF
