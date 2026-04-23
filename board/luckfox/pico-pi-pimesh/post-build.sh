#!/bin/sh
set -eu

TARGET_DIR="$1"
EXTERNAL_DIR="${BR2_EXTERNAL_YELLOWCOOLN_PATH:?missing BR2_EXTERNAL_YELLOWCOOLN_PATH}"
APP_DIR="${TARGET_DIR}/opt/pymc-repeater-buildroot"
ROOT_PASSWORD_HASH='$1$dXmV8ZLO$eNAQzSYOgRkYMJRdsHwLS1'

mkdir -p "${APP_DIR}"

install -m 0755 "${EXTERNAL_DIR}/buildroot-manage.sh" "${APP_DIR}/buildroot-manage.sh"
install -m 0755 "${EXTERNAL_DIR}/tailscale-manage.sh" "${APP_DIR}/tailscale-manage.sh"
install -m 0644 "${EXTERNAL_DIR}/README.md" "${APP_DIR}/README.md"
install -m 0644 "${EXTERNAL_DIR}/BUILDROOT.md" "${APP_DIR}/BUILDROOT.md"

mkdir -p "${TARGET_DIR}/root"
ln -snf /opt/pymc-repeater-buildroot "${TARGET_DIR}/root/pymc-repeater-buildroot"

mkdir -p "${TARGET_DIR}/var/empty"
chmod 0755 "${TARGET_DIR}/var/empty"

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
