#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

PYMC_EMBED_INSTALL="${PYMC_EMBED_INSTALL:-1}"
PYMC_EMBED_REPEATER_REPO="${PYMC_EMBED_REPEATER_REPO:-https://github.com/rightup/pyMC_Repeater.git}"
PYMC_EMBED_REPEATER_REF="${PYMC_EMBED_REPEATER_REF:-dev}"
PYMC_EMBED_CORE_REPO="${PYMC_EMBED_CORE_REPO:-https://github.com/rightup/pyMC_core.git}"
PYMC_EMBED_CORE_REF="${PYMC_EMBED_CORE_REF:-dev}"
IMAGE_ARCHIVE_PREFIX="${IMAGE_ARCHIVE_PREFIX:-luckfox-pico-pi-pymc-preinstalled-image}"

export PYMC_EMBED_INSTALL
export PYMC_EMBED_REPEATER_REPO
export PYMC_EMBED_REPEATER_REF
export PYMC_EMBED_CORE_REPO
export PYMC_EMBED_CORE_REF
export IMAGE_ARCHIVE_PREFIX

exec "${SCRIPT_DIR}/build-image-docker.sh" "$@"
