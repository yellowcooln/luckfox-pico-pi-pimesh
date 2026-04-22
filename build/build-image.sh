#!/bin/sh
set -eu

usage() {
  cat <<'EOF'
Usage: ./build/build-image.sh <vendor-buildroot-dir> <vendor-defconfig>

Example:
  ./build/build-image.sh ~/src/luckfox-buildroot luckfox_pico_pi_defconfig

Environment:
  MAKE_JOBS   Parallel make jobs. Default: detected CPU count, else 1.
EOF
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
  usage
  exit 0
fi

[ $# -eq 2 ] || {
  usage >&2
  exit 1
}

VENDOR_DIR=$1
DEFCONFIG=$2
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd -- "${SCRIPT_DIR}/.." && pwd)
FRAGMENT="${REPO_ROOT}/build/luckfox_pico_pi_pymc.fragment"
MERGE_CONFIG="${VENDOR_DIR}/support/kconfig/merge_config.sh"

if [ ! -d "${VENDOR_DIR}" ]; then
  printf 'Vendor Buildroot directory not found: %s\n' "${VENDOR_DIR}" >&2
  exit 1
fi

if [ ! -f "${VENDOR_DIR}/Makefile" ]; then
  printf 'Not a Buildroot tree: %s\n' "${VENDOR_DIR}" >&2
  exit 1
fi

if [ ! -x "${MERGE_CONFIG}" ]; then
  printf 'Missing merge_config.sh in vendor tree: %s\n' "${MERGE_CONFIG}" >&2
  exit 1
fi

if [ ! -f "${FRAGMENT}" ]; then
  printf 'Missing config fragment: %s\n' "${FRAGMENT}" >&2
  exit 1
fi

if [ -n "${MAKE_JOBS:-}" ]; then
  JOBS=${MAKE_JOBS}
else
  JOBS=$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 1)
fi

printf '\n==> Loading vendor defconfig: %s\n' "${DEFCONFIG}"
make -C "${VENDOR_DIR}" BR2_EXTERNAL="${REPO_ROOT}" "${DEFCONFIG}"

printf '\n==> Merging pyMC package fragment\n'
"${MERGE_CONFIG}" -m "${VENDOR_DIR}/.config" "${FRAGMENT}"

printf '\n==> Expanding merged config\n'
make -C "${VENDOR_DIR}" BR2_EXTERNAL="${REPO_ROOT}" olddefconfig

printf '\n==> Building image\n'
make -C "${VENDOR_DIR}" BR2_EXTERNAL="${REPO_ROOT}" -j"${JOBS}"

printf '\n==> Build complete\n'
printf 'Images: %s/output/images\n' "${VENDOR_DIR}"
