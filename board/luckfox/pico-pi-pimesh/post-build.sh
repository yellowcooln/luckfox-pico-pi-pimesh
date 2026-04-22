#!/bin/sh
set -eu

TARGET_DIR="$1"
EXTERNAL_DIR="${BR2_EXTERNAL_YELLOWCOOLN_PATH:?missing BR2_EXTERNAL_YELLOWCOOLN_PATH}"
APP_DIR="${TARGET_DIR}/opt/pymc-repeater-buildroot"

mkdir -p "${APP_DIR}/patches"

install -m 0755 "${EXTERNAL_DIR}/buildroot-manage.sh" "${APP_DIR}/buildroot-manage.sh"
install -m 0644 "${EXTERNAL_DIR}/README.md" "${APP_DIR}/README.md"
install -m 0644 "${EXTERNAL_DIR}/BUILDROOT.md" "${APP_DIR}/BUILDROOT.md"

for patch in "${EXTERNAL_DIR}"/patches/*.patch; do
    install -m 0644 "${patch}" "${APP_DIR}/patches/$(basename "${patch}")"
done

mkdir -p "${TARGET_DIR}/root"
ln -snf /opt/pymc-repeater-buildroot "${TARGET_DIR}/root/pymc-repeater-buildroot"
