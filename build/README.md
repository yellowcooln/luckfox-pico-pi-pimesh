# Build Image

This folder contains the repo-local pieces needed to build a Luckfox image with stock upstream `pyMC` support layered onto the official Luckfox Pico SDK.

This repo is still not the board support package by itself. The final bootable eMMC image comes from the Luckfox SDK for your exact board. This repo provides:

- the `BR2_EXTERNAL` layer
- the extra Python package definitions
- the rootfs overlay
- the post-build install step
- the post-fakeroot fixups
- the `pyMC` package fragment
- a small kernel fragment to make the image Tailscale-ready by default
- a helper script that downloads the SDK into a repo-local workspace and drives the full build

On the flashed image, `/root/scripts/buildroot-manage.sh` is
only a bootstrap/proxy. It clones `pyMC_Repeater` into `~/pyMC_Repeater` and
runs the repo's `buildroot-manage.sh` when present.

## What You Need

- an Ubuntu 22.04 x86_64 machine
- this repo checked out locally

## SDK Prerequisites

Install the host packages Luckfox documents for Ubuntu 22.04:

```sh
sudo apt-get update
sudo apt-get install -y git ssh make gcc gcc-multilib g++-multilib module-assistant expect g++ gawk texinfo libssl-dev bison flex fakeroot cmake unzip gperf autoconf device-tree-compiler libncurses5-dev pkg-config bc python-is-python3 passwd openssl openssh-server openssh-client vim file cpio rsync curl
```

The default board config used by this repo is:

```text
project/cfg/BoardConfig_IPC/BoardConfig-EMMC-Buildroot-RV1106_Luckfox_Pico_Pi-IPC.mk
```

That board config currently uses:

```text
RK_BUILDROOT_DEFCONFIG=luckfox_pico_w_defconfig
```

The canonical image fragment merged into that defconfig is:

```text
build/luckfox_pico_pi_pymc.fragment
```

That fragment is what enables:

- this repo's rootfs overlay
- `post-build.sh`
- `post-fakeroot.sh`
- the shipped package set, including `yq`
- Python SQLite support validation

## Build Flow

From a fresh VM:

```sh
git clone https://github.com/yellowcooln/pymc-repeater-buildroot-pico-pi.git
cd pymc-repeater-buildroot-pico-pi/build
./build-image.sh
```

## Docker Build

You can run the same build in Docker or Podman instead of a dedicated Ubuntu VM.
This is useful when you want to use faster host hardware while still keeping the
Luckfox SDK dependencies isolated.

From the repo root:

```sh
cd build
./build-image-docker.sh
```

For the embedded-runtime Pico Pi image:

```sh
cd build
./build-docker-embed-pico-pi.sh
```

What this wrapper does:

1. builds a local Ubuntu 22.04 builder image with the Luckfox SDK prerequisite packages
2. runs the container with your host UID/GID, so build outputs stay owned by you
3. bind-mounts this repo at `/workspace`
4. runs the normal `./build-image.sh` inside the container

Useful examples:

```sh
cd build
SKIP_BUILD=1 ./build-image-docker.sh
```

```sh
cd build
DOCKER_PLATFORM=linux/amd64 ./build-image-docker.sh
```

```sh
cd build
BOARD_CONFIG_REL=project/cfg/BoardConfig_IPC/BoardConfig-EMMC-Buildroot-RV1106_Luckfox_Pico_Zero-IPC.mk \
./build-image-docker.sh
```

For the dedicated Pico Zero Docker wrapper:

```sh
cd build
./build-image-pico-zero-docker.sh
```

For the embedded wrapper, these optional environment variables control the
bundled runtime checkout and first-boot defaults:

- `PYMC_EMBED_REPEATER_REPO`
- `PYMC_EMBED_REPEATER_REF`
- `PYMC_EMBED_CORE_REPO`
- `PYMC_EMBED_CORE_REF`
- `PYMC_EMBED_NODE_NAME`
- `PYMC_EMBED_ADMIN_PASSWORD`
- `PYMC_EMBED_BUILDROOT_BOARD`
- `PYMC_EMBED_RADIO_PRESET`

Notes:

- the container path is built for Ubuntu 22.04, same as the VM flow
- the Docker build context ignores `build/.work` so the SDK checkout is not copied into the image layer
- if your host is not x86_64, you may need `DOCKER_PLATFORM=linux/amd64`; that will work, but QEMU emulation may be slower
- the full SDK build still writes to this repo’s `build/.work/` directory, just from inside the container

What the script does:

1. clones or refreshes the official Luckfox SDK into `build/.work/luckfox-pico`
2. selects the Luckfox SDK board config from `BOARD_CONFIG_REL`, defaulting to the Pico Pi eMMC config above
3. writes `config/buildroot_defconfig` from the selected board's Buildroot defconfig plus `build/luckfox_pico_pi_pymc.fragment`
4. installs `build/luckfox_pico_pi_tailscale_kernel.fragment` into the SDK and appends it to the selected board's kernel fragment list
5. exports this repo as `BR2_EXTERNAL`
6. runs direct host prerequisite checks
7. links the SDK kernel and DTS config files directly
8. runs lightweight SDK sanity checks from the wrapper
9. runs `./build.sh`
10. runs `./build.sh firmware`
11. validates that the built target rootfs really contains Python `sqlite3`
    stdlib and `_sqlite3` extension support before allowing the build to pass

The full image build currently also patches the reused SDK tree as needed for:

- Python SQLite support under the vendor Buildroot/Python toolchain
- cached package rebuild resets when that SDK-side SQLite patch is first applied
- optional embedded `pyMC_Repeater` / `pyMC_core` source staging for the
  first-boot auto-install image variant

## Tailscale Baseline

The image now defaults to a Tailscale-ready baseline.

Userspace side:

- `iproute2`
- `iptables`
- `iptables` nft backend

Kernel side:

- `CONFIG_TUN=y`
- IPv6 enabled
- netfilter and iptables/NAT support forced on in the added kernel fragment

This does not bundle the `tailscale` binary itself. It makes the image ready to install and run Tailscale cleanly after flashing.

## Building a More Blank Image

If you want a more blank image without the shipped helper scripts in `/opt/scripts`
and `/root/scripts`, remove them from the repo before building:

- scripts staged by the rootfs overlay live under:
  - `board/luckfox/pico-pi/rootfs-overlay/`
- scripts copied in explicitly at image build time are installed from:
  - `board/luckfox/pico-pi/post-build.sh`

In practice, the main helpers currently come from:

- `board/luckfox/pico-pi/rootfs-overlay/usr/local/bin/`
- `board/luckfox/pico-pi/rootfs-overlay/usr/local/sbin/`
- repo-root helpers copied by `post-build.sh`, such as:
  - `buildroot-manage.sh`
  - `tailscale-manage.sh`
  - `pymc-console-webui.sh`

If you remove the rootfs overlay script files but leave `post-build.sh` unchanged,
the build will fail when it tries to install files that no longer exist.

If you want a more minimal runtime image, this is the main split to keep in mind:

- image repo responsibility:
  - bootstrap helper in `/root/scripts`
  - network helpers
  - image metadata
  - base packages and hardening
- upstream repo responsibility after install:
  - main repeater UX
  - radio profile flow
  - API/UI
  - service lifecycle details

To validate the setup without starting a full build:

```sh
cd build
SKIP_BUILD=1 ./build-image.sh
```

To use an already-existing SDK checkout instead of the repo-local workspace:

```sh
cd build
./build-image.sh /path/to/luckfox-pico
```

To pin a specific Luckfox SDK ref:

```sh
cd build
SDK_REF=main ./build-image.sh
```

To build a different Luckfox board from the same SDK:

```sh
cd build
BOARD_CONFIG_REL=project/cfg/BoardConfig_Whatever/BoardConfig-Whatever.mk ./build-image.sh
```

If the SDK board file does not expose the usual `RK_*` exports cleanly, you can override them directly:

```sh
cd build
BOARD_CONFIG_REL=project/cfg/BoardConfig_Whatever/BoardConfig-Whatever.mk \
RK_BUILDROOT_DEFCONFIG=my_board_defconfig \
RK_KERNEL_DEFCONFIG=my_kernel_defconfig \
RK_KERNEL_DTS=my-board.dts \
./build-image.sh
```

The completed image artifacts will be in the SDK tree under:

```text
build/.work/luckfox-pico/output/image/
```

Luckfox's flash documentation expects `update.img` to be present for eMMC flashing.

If `AUTO_ZIP=1` is enabled or you answer yes to the prompt, the wrapper also
creates a local archive in `build/` using:

- `luckfox-pico-pi-pymc-image-<timestamp>.zip`
- `luckfox-pico-zero-pymc-image-<timestamp>.zip`

The zip is created in your local repo checkout even when building inside Docker,
because the repo is bind-mounted into the container at `/workspace`.

## Manual Flow

If you want to do the same process by hand:

```sh
git clone https://github.com/LuckfoxTECH/luckfox-pico.git build/.work/luckfox-pico
cd build/.work/luckfox-pico
ln -snf <sdk-board-config> .BoardConfig.mk
mkdir -p config
cat sysdrv/tools/board/buildroot/<board-buildroot-defconfig> \
  /path/to/pymc-repeater-buildroot-pico-pi/build/luckfox_pico_pi_pymc.fragment \
  > config/buildroot_defconfig
export BR2_EXTERNAL=/path/to/pymc-repeater-buildroot-pico-pi
export PATH="$PWD/tools/linux/toolchain/arm-rockchip830-linux-uclibcgnueabihf/bin:$PATH"
./build.sh
./build.sh firmware
```

## Flashing

Flashing to eMMC is still Luckfox-specific. Use the normal Luckfox flashing path for the image files generated in `build/.work/luckfox-pico/output/image/`.

This repo does not replace the vendor bootloader, kernel, partitioning, or flash tooling.

Official references:

- https://wiki.luckfox.com/Luckfox-Pico-Pi/SDK
- https://wiki.luckfox.com/Luckfox-Pico-Pi/Flash-image/
- https://github.com/LuckfoxTECH/luckfox-pico

## Image Behavior

Current shipped image behavior from this repo:

- SSH enabled with bootstrap login `root / luckfox`
- Telnet removed
- `dhcpcd` startup removed so vendor `udhcpc` is the only DHCP client
- `/etc/pymc-image-build-id` written with:
  - `image_name=Luckfox pyMC Repeater Buildroot`
  - `image_version=0.6.9`
- `/root/scripts/buildroot-manage.sh` is only a bootstrap/proxy, not the full
  runtime manager
- `yq` is shipped in the image so upstream Buildroot config flows can preserve
  comments in `/etc/pymc_repeater/config.yaml`

Embedded-image variant behavior:

- bundles `pyMC_Repeater` and `pyMC_core` git checkouts into `/root`
- skips the first-boot network clone path
- runs the upstream Buildroot install locally on first boot
- installs repeater into the same `/opt/pymc_repeater` and `/etc/pymc_repeater`
  paths the normal upstream Buildroot flow expects
