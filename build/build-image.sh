#!/bin/sh
set -eu

usage() {
  cat <<'EOF'
Usage: ./build/build-image.sh <luckfox-sdk-dir>

Example:
  ./build/build-image.sh ~/src/luckfox-pico

Environment:
  BOARD_CONFIG_REL   SDK-relative board config path.
                     Default: project/cfg/BoardConfig_IPC/BoardConfig-EMMC-Buildroot-RV1106_Luckfox_Pico_Pi-IPC.mk
  SKIP_BUILD         Set to 1 to stop after check/info validation.
EOF
}

stage() {
  printf '\n==> %s\n' "$1"
}

fail() {
  printf '%s\n' "$1" >&2
  exit 1
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  usage
  exit 0
fi

[ $# -eq 1 ] || {
  usage >&2
  exit 1
}

SDK_DIR=$1
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd -- "${SCRIPT_DIR}/.." && pwd)
FRAGMENT="${REPO_ROOT}/build/luckfox_pico_pi_pymc.fragment"
BOARD_CONFIG_REL="${BOARD_CONFIG_REL:-project/cfg/BoardConfig_IPC/BoardConfig-EMMC-Buildroot-RV1106_Luckfox_Pico_Pi-IPC.mk}"
BOARD_CONFIG_PATH="${SDK_DIR}/${BOARD_CONFIG_REL}"
SDK_BOARD_CONFIG_LINK="${SDK_DIR}/.BoardConfig.mk"
SDK_BUILDROOT_DEFCONFIG="${SDK_DIR}/config/buildroot_defconfig"
SDK_BUILDSH="${SDK_DIR}/build.sh"
TOOLCHAIN_ENV="${SDK_DIR}/tools/linux/toolchain/arm-rockchip830-linux-uclibcgnueabihf/env_install_toolchain.sh"
TOOLCHAIN_BIN="${SDK_DIR}/tools/linux/toolchain/arm-rockchip830-linux-uclibcgnueabihf/bin"

[ -d "${SDK_DIR}" ] || fail "Luckfox SDK directory not found: ${SDK_DIR}"
[ -f "${SDK_BUILDSH}" ] || fail "Missing Luckfox SDK build script: ${SDK_BUILDSH}"
[ -f "${BOARD_CONFIG_PATH}" ] || fail "Missing board config: ${BOARD_CONFIG_PATH}"
[ -f "${FRAGMENT}" ] || fail "Missing config fragment: ${FRAGMENT}"
[ -f "${TOOLCHAIN_ENV}" ] || fail "Missing Luckfox toolchain env script: ${TOOLCHAIN_ENV}"
[ -d "${TOOLCHAIN_BIN}" ] || fail "Missing Luckfox toolchain bin directory: ${TOOLCHAIN_BIN}"

BASE_DEFCONFIG=$(
  sed -n 's/^export RK_BUILDROOT_DEFCONFIG=\(.*\)$/\1/p' "${BOARD_CONFIG_PATH}" |
    tail -n 1
)
[ -n "${BASE_DEFCONFIG}" ] || fail "Could not read RK_BUILDROOT_DEFCONFIG from ${BOARD_CONFIG_PATH}"

BASE_DEFCONFIG_PATH="${SDK_DIR}/sysdrv/tools/board/buildroot/${BASE_DEFCONFIG}"
[ -f "${BASE_DEFCONFIG_PATH}" ] || fail "Missing base Buildroot defconfig: ${BASE_DEFCONFIG_PATH}"

stage "Selecting Luckfox board config"
ln -snf "${BOARD_CONFIG_REL}" "${SDK_BOARD_CONFIG_LINK}"
printf 'Board config: %s\n' "${BOARD_CONFIG_REL}"

stage "Writing merged Buildroot defconfig"
mkdir -p "${SDK_DIR}/config"
{
  cat "${BASE_DEFCONFIG_PATH}"
  printf '\n'
  cat "${FRAGMENT}"
} > "${SDK_BUILDROOT_DEFCONFIG}"
printf 'Base defconfig: %s\n' "${BASE_DEFCONFIG_PATH}"
printf 'Merged defconfig: %s\n' "${SDK_BUILDROOT_DEFCONFIG}"

stage "Validating SDK environment"
(
  cd "${SDK_DIR}"
  export BR2_EXTERNAL="${REPO_ROOT}"
  export PATH="${TOOLCHAIN_BIN}:${PATH}"
  ./build.sh check
  ./build.sh info
)

if [ "${SKIP_BUILD:-0}" = "1" ]; then
  stage "Validation complete"
  printf 'Merged defconfig ready at: %s\n' "${SDK_BUILDROOT_DEFCONFIG}"
  exit 0
fi

stage "Building Luckfox image"
(
  cd "${SDK_DIR}"
  export BR2_EXTERNAL="${REPO_ROOT}"
  export PATH="${TOOLCHAIN_BIN}:${PATH}"
  ./build.sh
  ./build.sh firmware
)

stage "Build complete"
printf 'Artifacts: %s/output/image\n' "${SDK_DIR}"
printf 'Expected flash image: %s/output/image/update.img\n' "${SDK_DIR}"
