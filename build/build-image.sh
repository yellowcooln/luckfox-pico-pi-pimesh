#!/bin/sh
set -eu

usage() {
  cat <<'EOF'
Usage: ./build-image.sh [luckfox-sdk-dir]

Example:
  ./build-image.sh
  ./build-image.sh /path/to/luckfox-pico

Environment:
  SDK_REPO           Luckfox SDK git URL.
                     Default: https://github.com/LuckfoxTECH/luckfox-pico.git
  SDK_REF            Luckfox SDK branch, tag, or commit.
                     Default: main
  SDK_WORK_DIR       Repo-local SDK checkout directory when no positional path is given.
                     Default: <repo>/build/.work/luckfox-pico
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

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || fail "Missing required command: $1"
}

sync_sdk_repo() {
  repo_url=$1
  repo_ref=$2
  dest_dir=$3

  need_cmd git

  if [ -d "${dest_dir}/.git" ]; then
    stage "Refreshing Luckfox SDK"
    git -C "${dest_dir}" fetch --tags --force origin
    git -C "${dest_dir}" reset --hard
    git -C "${dest_dir}" clean -fd
  else
    stage "Cloning Luckfox SDK"
    mkdir -p "$(dirname "${dest_dir}")"
    git clone "${repo_url}" "${dest_dir}"
  fi

  git -C "${dest_dir}" checkout -f "${repo_ref}"
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  usage
  exit 0
fi

[ $# -le 1 ] || {
  usage >&2
  exit 1
}

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd -- "${SCRIPT_DIR}/.." && pwd)
FRAGMENT="${REPO_ROOT}/build/luckfox_pico_pi_pymc.fragment"
SDK_REPO="${SDK_REPO:-https://github.com/LuckfoxTECH/luckfox-pico.git}"
SDK_REF="${SDK_REF:-main}"
SDK_WORK_DIR="${SDK_WORK_DIR:-${REPO_ROOT}/build/.work/luckfox-pico}"
BOARD_CONFIG_REL="${BOARD_CONFIG_REL:-project/cfg/BoardConfig_IPC/BoardConfig-EMMC-Buildroot-RV1106_Luckfox_Pico_Pi-IPC.mk}"
SDK_DIR="${1:-${SDK_WORK_DIR}}"
BOARD_CONFIG_PATH="${SDK_DIR}/${BOARD_CONFIG_REL}"
SDK_BOARD_CONFIG_LINK="${SDK_DIR}/.BoardConfig.mk"
SDK_BUILDROOT_DEFCONFIG="${SDK_DIR}/config/buildroot_defconfig"
SDK_BUILDSH="${SDK_DIR}/build.sh"
TOOLCHAIN_ENV="${SDK_DIR}/tools/linux/toolchain/arm-rockchip830-linux-uclibcgnueabihf/env_install_toolchain.sh"
TOOLCHAIN_BIN="${SDK_DIR}/tools/linux/toolchain/arm-rockchip830-linux-uclibcgnueabihf/bin"

need_cmd sed
need_cmd tail
sync_sdk_repo "${SDK_REPO}" "${SDK_REF}" "${SDK_DIR}"

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
