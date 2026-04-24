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
  RK_BUILDROOT_DEFCONFIG
                     Override the Buildroot defconfig if the SDK board file is
                     missing or cannot be parsed.
  RK_KERNEL_DTS      Override the kernel DTS if the SDK board file is missing
                     or cannot be parsed.
  RK_KERNEL_DEFCONFIG
                     Override the kernel defconfig if the SDK board file is
                     missing or cannot be parsed.
  PYMC_BUILDROOT_FRAGMENT
                     Buildroot config fragment to append.
                     Default: <repo>/build/luckfox_pico_pi_pymc.fragment
  PYMC_KERNEL_FRAGMENT
                     Kernel config fragment for pyMC/base board support.
                     Default: <repo>/build/luckfox_pico_pi_pymc_kernel.fragment
  TAILSCALE_KERNEL_FRAGMENT
                     Kernel config fragment for Tailscale-specific support.
                     Default: <repo>/build/luckfox_pico_pi_tailscale_kernel.fragment
  AUTO_ZIP           Set to 1 to always zip the image output into <repo>/build.
                     Set to 0 to skip zipping without prompting.
  RK_JOBS            Parallel build job count for the Luckfox SDK build.
                     Default: detected via nproc/getconf, else 1.
  RESET_PYTHON_STATE Set to 1 to clear cached target Python build/output state.
                     Default: 0
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

prompt_yes_no() {
  prompt_text=$1
  default_answer=${2:-n}
  answer=""

  if [ ! -t 0 ]; then
    [ "${default_answer}" = "y" ]
    return
  fi

  case "${default_answer}" in
    y) printf '%s [Y/n]: ' "${prompt_text}" ;;
    *) printf '%s [y/N]: ' "${prompt_text}" ;;
  esac
  IFS= read -r answer
  if [ -z "${answer}" ]; then
    answer="${default_answer}"
  fi

  case "${answer}" in
    y|Y|yes|YES) return 0 ;;
    *) return 1 ;;
  esac
}

maybe_zip_artifacts() {
  image_dir="${SDK_DIR}/output/image"
  archive_name="luckfox-pico-pi-pymc-image-$(date +%Y%m%d-%H%M%S).zip"
  archive_path="${REPO_ROOT}/build/${archive_name}"

  [ -d "${image_dir}" ] || fail "Missing image output directory: ${image_dir}"

  case "${AUTO_ZIP:-ask}" in
    1)
      do_zip=1
      ;;
    0)
      do_zip=0
      ;;
    *)
      if prompt_yes_no "Create a zip archive of output/image in build/?" "n"; then
        do_zip=1
      else
        do_zip=0
      fi
      ;;
  esac

  [ "${do_zip}" -eq 1 ] || return 0

  need_cmd zip
  stage "Creating image archive"
  rm -f "${archive_path}"
  (
    cd "${SDK_DIR}/output"
    zip -r "${archive_path}" image >/dev/null
  )
  printf 'Archive: %s\n' "${archive_path}"
}

read_board_var() {
  var_name=$1
  config_path="${BOARD_CONFIG_SOURCE_PATH:-${BOARD_CONFIG_PATH}}"
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
  ' "${config_path}"
}

default_board_var() {
  var_name=$1
  case "${BOARD_CONFIG_REL}:${var_name}" in
    project/cfg/BoardConfig_IPC/BoardConfig-EMMC-Buildroot-RV1106_Luckfox_Pico_Pi-IPC.mk:RK_BUILDROOT_DEFCONFIG)
      printf '%s' 'luckfox_pico_w_defconfig'
      ;;
    project/cfg/BoardConfig_IPC/BoardConfig-EMMC-Buildroot-RV1106_Luckfox_Pico_Pi-IPC.mk:RK_KERNEL_DTS)
      printf '%s' 'rv1106g-luckfox-pico-pi.dts'
      ;;
    project/cfg/BoardConfig_IPC/BoardConfig-EMMC-Buildroot-RV1106_Luckfox_Pico_Pi-IPC.mk:RK_KERNEL_DEFCONFIG)
      printf '%s' 'luckfox_rv1106_linux_defconfig'
      ;;
    *)
      return 1
      ;;
  esac
}

board_var_or_default() {
  var_name=$1
  env_value=$(eval "printf '%s' \"\${${var_name}:-}\"")
  if [ -n "${env_value}" ]; then
    printf '%s' "${env_value}"
    return 0
  fi
  value=$(read_board_var "${var_name}" || true)
  if [ -n "${value}" ]; then
    printf '%s' "${value}"
    return 0
  fi
  default_board_var "${var_name}" || return 1
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
  kernel_dts=$(board_var_or_default RK_KERNEL_DTS)
  kernel_defconfig=$(board_var_or_default RK_KERNEL_DEFCONFIG)

  [ -n "${kernel_dts}" ] || fail "Could not determine RK_KERNEL_DTS from ${BOARD_CONFIG_PATH}. Set RK_KERNEL_DTS explicitly."
  [ -n "${kernel_defconfig}" ] || fail "Could not determine RK_KERNEL_DEFCONFIG from ${BOARD_CONFIG_PATH}. Set RK_KERNEL_DEFCONFIG explicitly."

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
  [ -f "${SDK_PYMC_KERNEL_FRAGMENT_PATH}" ] || fail "Missing injected pyMC kernel fragment: ${SDK_PYMC_KERNEL_FRAGMENT_PATH}"
  [ -f "${SDK_TAILSCALE_KERNEL_FRAGMENT_PATH}" ] || fail "Missing injected tailscale kernel fragment: ${SDK_TAILSCALE_KERNEL_FRAGMENT_PATH}"
  [ -f "${SDK_DIR}/config/kernel_defconfig" ] || fail "Missing kernel defconfig symlink in SDK config/"
  [ -f "${SDK_DIR}/config/dts_config" ] || fail "Missing DTS config symlink in SDK config/"

  printf 'Check [OK]: %s\n' "${SDK_BOARD_CONFIG_LINK}"
  printf 'Check [OK]: %s\n' "${SDK_BUILDROOT_DEFCONFIG}"
  printf 'Check [OK]: %s\n' "${SDK_PYMC_KERNEL_FRAGMENT_PATH}"
  printf 'Check [OK]: %s\n' "${SDK_TAILSCALE_KERNEL_FRAGMENT_PATH}"
  printf 'Check [OK]: %s\n' "${SDK_DIR}/config/kernel_defconfig"
  printf 'Check [OK]: %s\n' "${SDK_DIR}/config/dts_config"
}

reset_cached_python_state() {
  if [ "${RESET_PYTHON_STATE:-0}" != "1" ]; then
    return 0
  fi

  buildroot_src_dir="${SDK_DIR}/sysdrv/source/buildroot"
  buildroot_tree=$(find "${buildroot_src_dir}" -maxdepth 1 -mindepth 1 -type d -name 'buildroot-*' | head -n 1 || true)
  [ -n "${buildroot_tree}" ] || return 0

  buildroot_output_dir="${buildroot_tree}/output"
  [ -d "${buildroot_output_dir}" ] || return 0

  stage "Resetting cached target Python state"

  find "${buildroot_output_dir}/build" -maxdepth 1 -mindepth 1 -type d \
    \( -name 'python-*' -o -name 'python3-*' \) \
    ! -name 'host-python*' \
    -exec rm -rf {} +

  for python_root in "${buildroot_output_dir}/target/usr/lib" "${buildroot_output_dir}/staging/usr/lib"; do
    [ -d "${python_root}" ] || continue
    find "${python_root}" -maxdepth 1 -mindepth 1 -type d -name 'python3.*' | while IFS= read -r python_dir; do
      rm -rf "${python_dir}/site-packages" "${python_dir}/lib-dynload"
    done
  done

  rm -f \
    "${buildroot_output_dir}/build/packages-file-list.txt" \
    "${buildroot_output_dir}/build/packages-file-list-staging.txt"
}

detect_job_count() {
  if [ -n "${RK_JOBS:-}" ]; then
    printf '%s\n' "${RK_JOBS}"
    return 0
  fi
  if command -v nproc >/dev/null 2>&1; then
    nproc
    return 0
  fi
  if command -v getconf >/dev/null 2>&1; then
    getconf _NPROCESSORS_ONLN
    return 0
  fi
  printf '%s\n' 1
}

prepare_custom_pimesh_dts() {
  vendor_dts_name=$(read_board_var RK_KERNEL_DTS || true)
  [ -n "${vendor_dts_name}" ] || vendor_dts_name=$(default_board_var RK_KERNEL_DTS)
  vendor_dts_path="${SDK_DIR}/sysdrv/source/kernel/arch/arm/boot/dts/${vendor_dts_name}"
  vendor_dtsi_name="rv1106-luckfox-pico-pi-ipc.dtsi"
  vendor_dtsi_path="${SDK_DIR}/sysdrv/source/kernel/arch/arm/boot/dts/${vendor_dtsi_name}"

  [ -f "${vendor_dts_path}" ] || fail "Missing vendor DTS: ${vendor_dts_path}"
  [ -f "${vendor_dtsi_path}" ] || fail "Missing vendor DTS include: ${vendor_dtsi_path}"

  custom_dts_name="${PYMC_CUSTOM_DTS_NAME:-${vendor_dts_name%.dts}-pimesh.dts}"
  custom_dtsi_name="${PYMC_CUSTOM_DTSI_NAME:-rv1106-luckfox-pico-pi-pimesh-ipc.dtsi}"
  custom_dts_path="${SDK_DIR}/sysdrv/source/kernel/arch/arm/boot/dts/${custom_dts_name}"
  custom_dtsi_path="${SDK_DIR}/sysdrv/source/kernel/arch/arm/boot/dts/${custom_dtsi_name}"

  cp "${vendor_dtsi_path}" "${custom_dtsi_path}"
  tmp_file=$(mktemp)
  awk '
    function indent_of(line,   out) {
      match(line, /^[[:space:]]*/)
      out = substr(line, 1, RLENGTH)
      return out
    }

    {
      if ($0 ~ /bootargs = "/) {
        gsub(/earlycon=uart8250,mmio32,0xff4c0000[[:space:]]*/, "")
        gsub(/console=ttyFIQ0[[:space:]]*/, "")
        gsub(/  +/, " ")
        gsub(/ root=/, " root=")
      }

      if ($0 ~ /^&i2c[1-4][[:space:]]*\{/) {
        in_i2c = 1
        i2c_indent = indent_of($0) "    "
        i2c_has_status = 0
      }
      if (in_i2c && $0 ~ /^[[:space:]]*status[[:space:]]*=/) {
        i2c_has_status = 1
      }
      if (in_i2c && $0 ~ /^[[:space:]]*};[[:space:]]*$/) {
        if (!i2c_has_status) {
          print i2c_indent "status = \"okay\";"
        }
        in_i2c = 0
      }

      print
    }
  ' "${custom_dtsi_path}" > "${tmp_file}"
  mv "${tmp_file}" "${custom_dtsi_path}"

  cp "${vendor_dts_path}" "${custom_dts_path}"
  tmp_file=$(mktemp)
  awk -v custom_include="${custom_dtsi_name}" '
    function indent_of(line,   out) {
      match(line, /^[[:space:]]*/)
      out = substr(line, 1, RLENGTH)
      return out
    }

    {
      if ($0 ~ /^#include "rv1106-luckfox-pico-pi-ipc\.dtsi"$/) {
        print "#include \"" custom_include "\""
        next
      }

      if ($0 ~ /^&fiq_debugger[[:space:]]*\{/) {
        in_fiq = 1
      }
      if (in_fiq && $0 ~ /^[[:space:]]*status[[:space:]]*=[[:space:]]*"okay";/) {
        sub(/"okay"/, "\"disabled\"")
      }

      if ($0 ~ /^&spi0[[:space:]]*\{/) {
        in_spi = 1
      }
      if (in_spi && $0 ~ /^[[:space:]]*status[[:space:]]*=[[:space:]]*"disabled";/) {
        sub(/"disabled"/, "\"okay\"")
      }
      if (in_spi && $0 ~ /^[[:space:]]*spidev@0[[:space:]]*\{/) {
        in_spidev = 1
        spidev_indent = indent_of($0) "    "
        spidev_has_status = 0
      }
      if (in_spidev && $0 ~ /^[[:space:]]*status[[:space:]]*=/) {
        spidev_has_status = 1
      }
      if (in_spidev && $0 ~ /^[[:space:]]*};[[:space:]]*$/) {
        if (!spidev_has_status) {
          print spidev_indent "status = \"okay\";"
        }
        in_spidev = 0
      }

      print

      if (in_fiq && $0 ~ /^[[:space:]]*};[[:space:]]*$/) {
        in_fiq = 0
      }
      if (in_spi && !in_spidev && $0 ~ /^[[:space:]]*};[[:space:]]*$/) {
        in_spi = 0
      }
    }
  ' "${custom_dts_path}" > "${tmp_file}"
  mv "${tmp_file}" "${custom_dts_path}"

  awk '
    /^&fiq_debugger[[:space:]]*\{/ { in_fiq = 1 }
    in_fiq && /status[[:space:]]*=[[:space:]]*"disabled";/ { fiq_ok = 1 }
    in_fiq && /^[[:space:]]*};[[:space:]]*$/ { in_fiq = 0 }
    /^&spi0[[:space:]]*\{/ { in_spi = 1 }
    in_spi && /status[[:space:]]*=[[:space:]]*"okay";/ { spi_ok = 1 }
    in_spi && /spidev@0[[:space:]]*\{/ { in_spidev = 1 }
    in_spidev && /status[[:space:]]*=[[:space:]]*"okay";/ { spidev_ok = 1 }
    in_spidev && /^[[:space:]]*};[[:space:]]*$/ { in_spidev = 0 }
    in_spi && !in_spidev && /^[[:space:]]*};[[:space:]]*$/ { in_spi = 0 }
    END { exit !(fiq_ok && spi_ok && spidev_ok) }
  ' "${custom_dts_path}" || fail "Failed to generate custom PiMesh DTS: ${custom_dts_path}"

  awk '
    /bootargs = "/ {
      if ($0 ~ /console=ttyFIQ0/ || $0 ~ /earlycon=uart8250,mmio32,0xff4c0000/) {
        exit 1
      }
      bootargs_ok = 1
    }
    /^&i2c[1-4][[:space:]]*\{/ { in_i2c = 1; seen_i2c++ }
    in_i2c && /status[[:space:]]*=[[:space:]]*"okay";/ { i2c_ok++ ; in_i2c = 0 }
    in_i2c && /^[[:space:]]*};[[:space:]]*$/ { in_i2c = 0 }
    END { exit !(bootargs_ok && seen_i2c >= 4 && i2c_ok >= 4) }
  ' "${custom_dtsi_path}" || fail "Failed to generate custom PiMesh DTS include: ${custom_dtsi_path}"

  printf '\nexport RK_KERNEL_DTS="%s"\n' "${custom_dts_name}" >> "${SDK_GENERATED_BOARD_CONFIG}"
  printf 'Custom DTS: %s\n' "${custom_dts_path}"
  printf 'Custom DTS include: %s\n' "${custom_dtsi_path}"
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
FRAGMENT="${PYMC_BUILDROOT_FRAGMENT:-${REPO_ROOT}/build/luckfox_pico_pi_pymc.fragment}"
PYMC_KERNEL_FRAGMENT="${PYMC_KERNEL_FRAGMENT:-${REPO_ROOT}/build/luckfox_pico_pi_pymc_kernel.fragment}"
TAILSCALE_KERNEL_FRAGMENT="${TAILSCALE_KERNEL_FRAGMENT:-${REPO_ROOT}/build/luckfox_pico_pi_tailscale_kernel.fragment}"
SDK_REPO="${SDK_REPO:-https://github.com/LuckfoxTECH/luckfox-pico.git}"
SDK_REF="${SDK_REF:-main}"
SDK_WORK_DIR="${SDK_WORK_DIR:-${REPO_ROOT}/build/.work/luckfox-pico}"
BOARD_CONFIG_REL="${BOARD_CONFIG_REL:-project/cfg/BoardConfig_IPC/BoardConfig-EMMC-Buildroot-RV1106_Luckfox_Pico_Pi-IPC.mk}"
SDK_DIR="${1:-${SDK_WORK_DIR}}"
BOARD_CONFIG_PATH="${SDK_DIR}/${BOARD_CONFIG_REL}"
BOARD_CONFIG_SOURCE_PATH="${BOARD_CONFIG_PATH}"
SDK_BOARD_CONFIG_LINK="${SDK_DIR}/.BoardConfig.mk"
SDK_GENERATED_BOARD_CONFIG="${SDK_DIR}/config/pymc_board_config.mk"
SDK_BUILDROOT_DEFCONFIG="${SDK_DIR}/config/buildroot_defconfig"
SDK_BUILDSH="${SDK_DIR}/build.sh"
TOOLCHAIN_ENV="${SDK_DIR}/tools/linux/toolchain/arm-rockchip830-linux-uclibcgnueabihf/env_install_toolchain.sh"
TOOLCHAIN_BIN="${SDK_DIR}/tools/linux/toolchain/arm-rockchip830-linux-uclibcgnueabihf/bin"
SDK_PYMC_KERNEL_FRAGMENT_NAME="luckfox_pymc.config"
SDK_PYMC_KERNEL_FRAGMENT_PATH="${SDK_DIR}/sysdrv/source/kernel/arch/arm/configs/${SDK_PYMC_KERNEL_FRAGMENT_NAME}"
SDK_TAILSCALE_KERNEL_FRAGMENT_NAME="luckfox_tailscale.config"
SDK_TAILSCALE_KERNEL_FRAGMENT_PATH="${SDK_DIR}/sysdrv/source/kernel/arch/arm/configs/${SDK_TAILSCALE_KERNEL_FRAGMENT_NAME}"

need_cmd sed
need_cmd tail
sync_sdk_repo "${SDK_REPO}" "${SDK_REF}" "${SDK_DIR}"

[ -f "${SDK_BUILDSH}" ] || fail "Missing Luckfox SDK build script: ${SDK_BUILDSH}"
[ -f "${BOARD_CONFIG_PATH}" ] || fail "Missing board config: ${BOARD_CONFIG_PATH}. Set BOARD_CONFIG_REL to the Luckfox SDK board config you want to build."
[ -f "${FRAGMENT}" ] || fail "Missing config fragment: ${FRAGMENT}"
[ -f "${PYMC_KERNEL_FRAGMENT}" ] || fail "Missing pyMC kernel fragment: ${PYMC_KERNEL_FRAGMENT}"
[ -f "${TAILSCALE_KERNEL_FRAGMENT}" ] || fail "Missing tailscale kernel fragment: ${TAILSCALE_KERNEL_FRAGMENT}"
[ -f "${TOOLCHAIN_ENV}" ] || fail "Missing Luckfox toolchain env script: ${TOOLCHAIN_ENV}"
[ -d "${TOOLCHAIN_BIN}" ] || fail "Missing Luckfox toolchain bin directory: ${TOOLCHAIN_BIN}"

BASE_DEFCONFIG=$(board_var_or_default RK_BUILDROOT_DEFCONFIG)
[ -n "${BASE_DEFCONFIG}" ] || fail "Could not determine RK_BUILDROOT_DEFCONFIG from ${BOARD_CONFIG_PATH}. Set RK_BUILDROOT_DEFCONFIG explicitly."

BASE_DEFCONFIG_PATH="${SDK_DIR}/sysdrv/tools/board/buildroot/${BASE_DEFCONFIG}"
[ -f "${BASE_DEFCONFIG_PATH}" ] || fail "Missing base Buildroot defconfig: ${BASE_DEFCONFIG_PATH}"

stage "Selecting Luckfox board config"
mkdir -p "${SDK_DIR}/config"
cat "${BOARD_CONFIG_PATH}" > "${SDK_GENERATED_BOARD_CONFIG}"
printf '\nexport RK_KERNEL_DEFCONFIG_FRAGMENT="${RK_KERNEL_DEFCONFIG_FRAGMENT} %s %s"\n' "${SDK_PYMC_KERNEL_FRAGMENT_NAME}" "${SDK_TAILSCALE_KERNEL_FRAGMENT_NAME}" >> "${SDK_GENERATED_BOARD_CONFIG}"
BOARD_CONFIG_SOURCE_PATH="${SDK_GENERATED_BOARD_CONFIG}"
ln -snf "${SDK_GENERATED_BOARD_CONFIG}" "${SDK_BOARD_CONFIG_LINK}"
printf 'Board config: %s\n' "${BOARD_CONFIG_REL}"
printf 'Generated board config: %s\n' "${SDK_GENERATED_BOARD_CONFIG}"

stage "Installing kernel fragments"
install -m 0644 "${PYMC_KERNEL_FRAGMENT}" "${SDK_PYMC_KERNEL_FRAGMENT_PATH}"
install -m 0644 "${TAILSCALE_KERNEL_FRAGMENT}" "${SDK_TAILSCALE_KERNEL_FRAGMENT_PATH}"
printf 'pyMC kernel fragment: %s\n' "${SDK_PYMC_KERNEL_FRAGMENT_PATH}"
printf 'Tailscale kernel fragment: %s\n' "${SDK_TAILSCALE_KERNEL_FRAGMENT_PATH}"

stage "Generating custom PiMesh DTS profile"
prepare_custom_pimesh_dts

stage "Linking SDK kernel configuration"
link_sdk_config_files
printf 'Kernel defconfig link: %s\n' "${SDK_DIR}/config/kernel_defconfig"
printf 'DTS config link: %s\n' "${SDK_DIR}/config/dts_config"

stage "Writing merged Buildroot defconfig"
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
reset_cached_python_state
RK_JOBS_VALUE=$(detect_job_count)
case "${RK_JOBS_VALUE}" in
  ''|*[!0-9]*)
    fail "Invalid RK_JOBS value: ${RK_JOBS_VALUE}"
    ;;
esac
if [ "${RK_JOBS_VALUE}" -lt 1 ]; then
  RK_JOBS_VALUE=1
fi
(
  cd "${SDK_DIR}"
  export BR2_EXTERNAL="${REPO_ROOT}"
  export PATH="${TOOLCHAIN_BIN}:${PATH}"
  export RK_JOBS="${RK_JOBS_VALUE}"
  printf 'Board config: %s\n' "${BOARD_CONFIG_REL}"
  printf 'Buildroot defconfig: %s\n' "${BASE_DEFCONFIG}"
  printf 'Buildroot fragment: %s\n' "${FRAGMENT}"
  printf 'pyMC kernel fragment: %s\n' "${PYMC_KERNEL_FRAGMENT}"
  printf 'Tailscale kernel fragment: %s\n' "${TAILSCALE_KERNEL_FRAGMENT}"
  printf 'RK_JOBS: %s\n' "${RK_JOBS}"
  if [ "${RESET_PYTHON_STATE:-0}" = "1" ]; then
    printf 'Reset target Python state: yes\n'
  else
    printf 'Reset target Python state: no\n'
  fi
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
  export RK_JOBS="${RK_JOBS_VALUE}"
  ./build.sh
  ./build.sh firmware
)

stage "Build complete"
printf 'Artifacts: %s/output/image\n' "${SDK_DIR}"
printf 'Expected flash image: %s/output/image/update.img\n' "${SDK_DIR}"
maybe_zip_artifacts
