#!/bin/sh
set -eu

TARGET_DIR="$1"

mkdir -p "${TARGET_DIR}/var/empty"
chown 0:0 "${TARGET_DIR}/var/empty"
chmod 0755 "${TARGET_DIR}/var/empty"
