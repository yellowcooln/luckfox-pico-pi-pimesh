#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

BOARD_CONFIG_REL="${BOARD_CONFIG_REL:-project/cfg/BoardConfig_IPC/BoardConfig-EMMC-Buildroot-RV1106_Luckfox_Pico_Zero-IPC.mk}"
PYMC_GENERATE_CUSTOM_DTS="${PYMC_GENERATE_CUSTOM_DTS:-0}"
IMAGE_ARCHIVE_PREFIX="${IMAGE_ARCHIVE_PREFIX:-luckfox-pico-zero-pymc-image}"

export BOARD_CONFIG_REL
export PYMC_GENERATE_CUSTOM_DTS
export IMAGE_ARCHIVE_PREFIX

exec "${SCRIPT_DIR}/build-image.sh" "$@"
