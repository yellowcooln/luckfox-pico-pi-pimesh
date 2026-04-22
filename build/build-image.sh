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

read_board_var() {
  var_name=$1
  need_cmd awk
  awk -F= -v key="${var_name}" '
    $0 ~ "^[[:space:]]*export[[:space:]]+" key "=" {
      value = substr($0, index($0, "=") + 1)
      gsub(/^[[:space:]]+/, "", value)
      gsub(/[[:space:]]+$/, "", value)
      gsub(/^"/, "", value)
      gsub(/"$/, "", value)
      gsub(/^'\''/, "", value)
      gsub(/'\''$/, "", value)
      print value
      exit
    }
  ' "${BOARD_CONFIG_PATH}"
}

check_host_deps() {
  stage "Checking host dependencies"

  need_cmd dtc
  printf 'Check [OK]: dtc --version\n'

  need_cmd makeinfo
  printf 'Check [OK]: makeinfo --version\n'

  need_cmd gperf
  printf 'Check [OK]: gperf --version\n'

  if dpkg --list | grep 'g++-.*-multilib' >/dev/null 2>&1; then
    printf 'Check [OK]: dpkg --list | grep g++-.*-multilib\n'
  else
    fail 'Missing required package: g++-multilib'
  fi

  if dpkg --list | grep 'gcc-.*-multilib' >/dev/null 2>&1; then
    printf 'Check [OK]: dpkg --list | grep gcc-.*-multilib\n'
  else
    fail 'Missing required package: gcc-multilib'
  fi

  need_cmd make
  printf 'Check [OK]: make -v\n'
}

link_sdk_config_files() {
  kernel_dts=$(read_board_var RK_KERNEL_DTS)
  kernel_defconfig=$(read_board_var RK_KERNEL_DEFCONFIG)

  [ -n "${kernel_dts}" ] || fail "Could not read RK_KERNEL_DTS from ${BOARD_CONFIG_PATH}"
  [ -n "${kernel_defconfig}" ] || fail "Could not read RK_KERNEL_DEFCONFIG from ${BOARD_CONFIG_PATH}"

  kernel_dts_path="${SDK_DIR}/sysdrv/source/kernel/arch/arm/boot/dts/${kernel_dts}"
  kernel_defconfig_path="${SDK_DIR}/sysdrv/source/kernel/arch/arm/configs/${kernel_defconfig}"

  [ -f "${kernel_dts_path}" ] || fail "Missing kernel DTS: ${kernel_dts_path}"
  [ -f "${kernel_defconfig_path}" ] || fail "Missing kernel defconfig: ${kernel_defconfig_path}"

  mkdir -p "${SDK_DIR}/config"
  ln -snf "${kernel_dts_path}" "${SDK_DIR}/config/dts_config"
  ln -snf "${kernel_defconfig_path}" "${SDK_DIR}/config/kernel_defconfig"
}

check_sdk_layout() {
  stage "Checking SDK configuration"

  [ -f "${SDK_BOARD_CONFIG_LINK}" ] || fail "Missing .BoardConfig.mk: ${SDK_BOARD_CONFIG_LINK}"
  [ -f "${SDK_BUILDROOT_DEFCONFIG}" ] || fail "Missing buildroot defconfig: ${SDK_BUILDROOT_DEFCONFIG}"
  [ -f "${SDK_KERNEL_FRAGMENT_PATH}" ] || fail "Missing injected kernel fragment: ${SDK_KERNEL_FRAGMENT_PATH}"
  [ -f "${SDK_DIR}/config/kernel_defconfig" ] || fail "Missing kernel defconfig symlink in SDK config/"
  [ -f "${SDK_DIR}/config/dts_config" ] || fail "Missing DTS config symlink in SDK config/"

  printf 'Check [OK]: %s\n' "${SDK_BOARD_CONFIG_LINK}"
  printf 'Check [OK]: %s\n' "${SDK_BUILDROOT_DEFCONFIG}"
  printf 'Check [OK]: %s\n' "${SDK_KERNEL_FRAGMENT_PATH}"
  printf 'Check [OK]: %s\n' "${SDK_DIR}/config/kernel_defconfig"
  printf 'Check [OK]: %s\n' "${SDK_DIR}/config/dts_config"
}

sync_sdk_repo() {
  repo_url=$1
  repo_ref=$2
  dest_dir=$3

  need_cmd git
  git config --global --add safe.directory "${dest_dir}" >/dev/null 2>&1 || true

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
KERNEL_FRAGMENT="${REPO_ROOT}/build/luckfox_pico_pi_tailscale_kernel.fragment"
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
SDK_KERNEL_FRAGMENT_NAME="luckfox_pymc_tailscale.config"
SDK_KERNEL_FRAGMENT_PATH="${SDK_DIR}/sysdrv/source/kernel/arch/arm/configs/${SDK_KERNEL_FRAGMENT_NAME}"

need_cmd sed
need_cmd tail
sync_sdk_repo "${SDK_REPO}" "${SDK_REF}" "${SDK_DIR}"

[ -f "${SDK_BUILDSH}" ] || fail "Missing Luckfox SDK build script: ${SDK_BUILDSH}"
[ -f "${BOARD_CONFIG_PATH}" ] || fail "Missing board config: ${BOARD_CONFIG_PATH}"
[ -f "${FRAGMENT}" ] || fail "Missing config fragment: ${FRAGMENT}"
[ -f "${KERNEL_FRAGMENT}" ] || fail "Missing kernel fragment: ${KERNEL_FRAGMENT}"
[ -f "${TOOLCHAIN_ENV}" ] || fail "Missing Luckfox toolchain env script: ${TOOLCHAIN_ENV}"
[ -d "${TOOLCHAIN_BIN}" ] || fail "Missing Luckfox toolchain bin directory: ${TOOLCHAIN_BIN}"

BASE_DEFCONFIG=$(read_board_var RK_BUILDROOT_DEFCONFIG)
[ -n "${BASE_DEFCONFIG}" ] || fail "Could not read RK_BUILDROOT_DEFCONFIG from ${BOARD_CONFIG_PATH}"

BASE_DEFCONFIG_PATH="${SDK_DIR}/sysdrv/tools/board/buildroot/${BASE_DEFCONFIG}"
[ -f "${BASE_DEFCONFIG_PATH}" ] || fail "Missing base Buildroot defconfig: ${BASE_DEFCONFIG_PATH}"

stage "Selecting Luckfox board config"
cat > "${SDK_BOARD_CONFIG_LINK}" <<EOF
#!/bin/bash
. "${BOARD_CONFIG_PATH}"
export RK_KERNEL_DEFCONFIG_FRAGMENT="\${RK_KERNEL_DEFCONFIG_FRAGMENT:-} ${SDK_KERNEL_FRAGMENT_NAME}"
EOF
chmod +x "${SDK_BOARD_CONFIG_LINK}"
printf 'Board config: %s\n' "${BOARD_CONFIG_REL}"

stage "Installing tailscale-ready kernel fragment"
install -m 0644 "${KERNEL_FRAGMENT}" "${SDK_KERNEL_FRAGMENT_PATH}"
printf 'Kernel fragment: %s\n' "${SDK_KERNEL_FRAGMENT_PATH}"

stage "Linking SDK kernel configuration"
link_sdk_config_files
printf 'Kernel defconfig link: %s\n' "${SDK_DIR}/config/kernel_defconfig"
printf 'DTS config link: %s\n' "${SDK_DIR}/config/dts_config"

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
check_host_deps
check_sdk_layout
(
  cd "${SDK_DIR}"
  export BR2_EXTERNAL="${REPO_ROOT}"
  export PATH="${TOOLCHAIN_BIN}:${PATH}"
  printf 'Board config: %s\n' "${BOARD_CONFIG_REL}"
  printf 'Buildroot defconfig: %s\n' "${BASE_DEFCONFIG}"
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
