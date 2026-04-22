# Build Image

This folder contains the repo-local pieces needed to build a Luckfox Pico Pi image with stock upstream `pyMC` support layered onto the official Luckfox Pico SDK.

This repo is still not the board support package by itself. The final bootable eMMC image comes from the Luckfox SDK for your exact board. This repo provides:

- the `BR2_EXTERNAL` layer
- the extra Python package definitions
- the rootfs overlay
- the post-build install step
- the `pyMC` package fragment
- a small kernel fragment to make the image Tailscale-ready by default
- a helper script that downloads the SDK into a repo-local workspace and drives the full build

## What You Need

- an Ubuntu 22.04 x86_64 machine
- this repo checked out locally

## SDK Prerequisites

Install the host packages Luckfox documents for Ubuntu 22.04:

```sh
sudo apt-get update
sudo apt-get install -y git ssh make gcc gcc-multilib g++-multilib module-assistant expect g++ gawk texinfo libssl-dev bison flex fakeroot cmake unzip gperf autoconf device-tree-compiler libncurses5-dev pkg-config bc python-is-python3 passwd openssl openssh-server openssh-client vim file cpio rsync curl
```

The validated Pico Pi eMMC Buildroot board config in the official SDK is:

```text
project/cfg/BoardConfig_IPC/BoardConfig-EMMC-Buildroot-RV1106_Luckfox_Pico_Pi-IPC.mk
```

That board config uses:

```text
RK_BUILDROOT_DEFCONFIG=luckfox_pico_w_defconfig
```

## Build Flow

From a fresh VM:

```sh
git clone https://github.com/yellowcooln/luckfox-pico-pi-pimesh.git
cd luckfox-pico-pi-pimesh/build
./build-image.sh
```

What the script does:

1. clones or refreshes the official Luckfox SDK into `build/.work/luckfox-pico`
2. selects `project/cfg/BoardConfig_IPC/BoardConfig-EMMC-Buildroot-RV1106_Luckfox_Pico_Pi-IPC.mk`
3. writes `config/buildroot_defconfig` from Luckfox's `luckfox_pico_w_defconfig` plus [luckfox_pico_pi_pymc.fragment](/home/yellowcooln/luckfox-pico-pi-pimesh/build/luckfox_pico_pi_pymc.fragment:1)
4. installs [luckfox_pico_pi_tailscale_kernel.fragment](/home/yellowcooln/luckfox-pico-pi-pimesh/build/luckfox_pico_pi_tailscale_kernel.fragment:1) into the SDK and appends it to the Pico Pi kernel fragment list
5. exports this repo as `BR2_EXTERNAL`
6. runs `./build.sh check`
7. runs `./build.sh info`
8. runs `./build.sh`
9. runs `./build.sh firmware`

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

The completed image artifacts will be in the SDK tree under:

```text
build/.work/luckfox-pico/output/image/
```

Luckfox's flash documentation expects `update.img` to be present for eMMC flashing.

## Manual Flow

If you want to do the same process by hand:

```sh
git clone https://github.com/LuckfoxTECH/luckfox-pico.git build/.work/luckfox-pico
cd build/.work/luckfox-pico
ln -snf project/cfg/BoardConfig_IPC/BoardConfig-EMMC-Buildroot-RV1106_Luckfox_Pico_Pi-IPC.mk .BoardConfig.mk
mkdir -p config
cat sysdrv/tools/board/buildroot/luckfox_pico_w_defconfig \
  /path/to/luckfox-pico-pi-pimesh/build/luckfox_pico_pi_pymc.fragment \
  > config/buildroot_defconfig
export BR2_EXTERNAL=/path/to/luckfox-pico-pi-pimesh
export PATH="$PWD/tools/linux/toolchain/arm-rockchip830-linux-uclibcgnueabihf/bin:$PATH"
./build.sh check
./build.sh info
./build.sh
./build.sh firmware
```

## Flashing

Flashing to eMMC is still Luckfox-specific. Use the normal Luckfox Pico Pi flashing path for the image files generated in `build/.work/luckfox-pico/output/image/`.

This repo does not replace the vendor bootloader, kernel, partitioning, or flash tooling.

Official references:

- https://wiki.luckfox.com/Luckfox-Pico-Pi/SDK
- https://wiki.luckfox.com/Luckfox-Pico-Pi/Flash-image/
- https://github.com/LuckfoxTECH/luckfox-pico
