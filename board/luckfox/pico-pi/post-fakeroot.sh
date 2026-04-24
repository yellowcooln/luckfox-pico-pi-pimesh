#!/bin/sh
set -eu

TARGET_DIR="$1"

mkdir -p "${TARGET_DIR}/var/empty"
chown 0:0 "${TARGET_DIR}/var/empty"
chmod 0755 "${TARGET_DIR}/var/empty"

mkdir -p "${TARGET_DIR}/dev"
if [ ! -e "${TARGET_DIR}/dev/tty" ]; then
  mknod -m 0666 "${TARGET_DIR}/dev/tty" c 5 0
fi
chown 0:5 "${TARGET_DIR}/dev/tty"
chmod 0666 "${TARGET_DIR}/dev/tty"
