#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
REPO_ROOT=$(CDPATH= cd -- "${SCRIPT_DIR}/.." && pwd)

usage() {
  cat <<'EOF'
Usage: ./build-image-docker.sh [build-image.sh args...]

Examples:
  ./build-image-docker.sh
  SKIP_BUILD=1 ./build-image-docker.sh
  BOARD_CONFIG_REL=project/cfg/BoardConfig_IPC/BoardConfig-EMMC-Buildroot-RV1106_Luckfox_Pico_Zero-IPC.mk ./build-image-docker.sh

Environment:
  CONTAINER_TOOL   Container runtime to use.
                   Default: docker, fallback: podman
  DOCKER_IMAGE     Builder image tag.
                   Default: luckfox-pymc-builder:22.04
  DOCKER_PLATFORM  Optional platform override, e.g. linux/amd64
EOF
}

find_container_tool() {
  if [ -n "${CONTAINER_TOOL:-}" ]; then
    command -v "${CONTAINER_TOOL}" >/dev/null 2>&1 || {
      printf '%s\n' "Missing container runtime: ${CONTAINER_TOOL}" >&2
      exit 1
    }
    printf '%s\n' "${CONTAINER_TOOL}"
    return 0
  fi

  if command -v docker >/dev/null 2>&1; then
    printf '%s\n' docker
    return 0
  fi
  if command -v podman >/dev/null 2>&1; then
    printf '%s\n' podman
    return 0
  fi

  printf '%s\n' "Missing container runtime: docker or podman" >&2
  exit 1
}

container_tool=$(find_container_tool)
image_tag=${DOCKER_IMAGE:-luckfox-pymc-builder:22.04}
host_uid=$(id -u)
host_gid=$(id -g)
platform_args=""

case "${1:-}" in
  -h|--help)
    usage
    exit 0
    ;;
esac

if [ -n "${DOCKER_PLATFORM:-}" ]; then
  platform_args="--platform ${DOCKER_PLATFORM}"
fi

printf '\n==> Building builder image\n'
# shellcheck disable=SC2086
"${container_tool}" build ${platform_args} \
  -t "${image_tag}" \
  -f "${SCRIPT_DIR}/Dockerfile" \
  "${REPO_ROOT}"

printf '\n==> Running image build in container\n'
# shellcheck disable=SC2086
exec "${container_tool}" run --rm -it ${platform_args} \
  --user "${host_uid}:${host_gid}" \
  -v "${REPO_ROOT}:/workspace" \
  -w /workspace/build \
  -e HOME=/tmp/pymc-build-home \
  -e SDK_REPO="${SDK_REPO:-}" \
  -e SDK_REF="${SDK_REF:-}" \
  -e SDK_WORK_DIR="${SDK_WORK_DIR:-}" \
  -e BOARD_CONFIG_REL="${BOARD_CONFIG_REL:-}" \
  -e RK_BUILDROOT_DEFCONFIG="${RK_BUILDROOT_DEFCONFIG:-}" \
  -e RK_KERNEL_DTS="${RK_KERNEL_DTS:-}" \
  -e RK_KERNEL_DEFCONFIG="${RK_KERNEL_DEFCONFIG:-}" \
  -e PYMC_BUILDROOT_FRAGMENT="${PYMC_BUILDROOT_FRAGMENT:-}" \
  -e PYMC_KERNEL_FRAGMENT="${PYMC_KERNEL_FRAGMENT:-}" \
  -e CONNECTIVITY_KERNEL_FRAGMENT="${CONNECTIVITY_KERNEL_FRAGMENT:-}" \
  -e TAILSCALE_KERNEL_FRAGMENT="${TAILSCALE_KERNEL_FRAGMENT:-}" \
  -e PYMC_GENERATE_CUSTOM_DTS="${PYMC_GENERATE_CUSTOM_DTS:-}" \
  -e IMAGE_ARCHIVE_PREFIX="${IMAGE_ARCHIVE_PREFIX:-}" \
  -e AUTO_ZIP="${AUTO_ZIP:-}" \
  -e RK_JOBS="${RK_JOBS:-}" \
  -e RESET_PYTHON_STATE="${RESET_PYTHON_STATE:-}" \
  -e PYMC_EMBED_INSTALL="${PYMC_EMBED_INSTALL:-}" \
  -e PYMC_EMBED_STAGE_DIR="${PYMC_EMBED_STAGE_DIR:-}" \
  -e PYMC_EMBED_REPEATER_REPO="${PYMC_EMBED_REPEATER_REPO:-}" \
  -e PYMC_EMBED_REPEATER_REF="${PYMC_EMBED_REPEATER_REF:-}" \
  -e PYMC_EMBED_CORE_REPO="${PYMC_EMBED_CORE_REPO:-}" \
  -e PYMC_EMBED_CORE_REF="${PYMC_EMBED_CORE_REF:-}" \
  -e PYMC_EMBED_NODE_NAME="${PYMC_EMBED_NODE_NAME:-}" \
  -e PYMC_EMBED_ADMIN_PASSWORD="${PYMC_EMBED_ADMIN_PASSWORD:-}" \
  -e PYMC_EMBED_BUILDROOT_BOARD="${PYMC_EMBED_BUILDROOT_BOARD:-}" \
  -e PYMC_EMBED_RADIO_PRESET="${PYMC_EMBED_RADIO_PRESET:-}" \
  -e SKIP_BUILD="${SKIP_BUILD:-}" \
  "${image_tag}" \
  ./build-image.sh "$@"
