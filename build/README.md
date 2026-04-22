# Build Image

This folder contains the repo-local pieces needed to build a Luckfox Pico Pi image with stock upstream `pyMC` support layered onto the official Luckfox Pico SDK.

This repo is still not the board support package by itself. The final bootable eMMC image comes from the Luckfox SDK for your exact board. This repo provides:

- the `BR2_EXTERNAL` layer
- the extra Python package definitions
- the rootfs overlay
- the post-build install step
- the `pyMC` package fragment
- a helper script that drives the build

## What You Need

- an Ubuntu 22.04 x86_64 machine
- the official Luckfox Pico SDK
- this repo checked out locally

## SDK Prerequisites

Install the host packages Luckfox documents for Ubuntu 22.04:

```sh
sudo apt-get update
sudo apt-get install -y git ssh make gcc gcc-multilib g++-multilib module-assistant expect g++ gawk texinfo libssl-dev bison flex fakeroot cmake unzip gperf autoconf device-tree-compiler libncurses5-dev pkg-config bc python-is-python3 passwd openssl openssh-server openssh-client vim file cpio rsync curl
```

Clone the official SDK:

```sh
git clone https://github.com/LuckfoxTECH/luckfox-pico.git
```

Load the Luckfox cross-toolchain environment:

```sh
cd luckfox-pico/tools/linux/toolchain/arm-rockchip830-linux-uclibcgnueabihf
source env_install_toolchain.sh
cd ~/luckfox-pico
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

Select the Luckfox Pico Pi eMMC Buildroot board in the SDK:

```sh
./build.sh lunch
```

If the board is not shown directly in the first menu, choose `custom` and then select:

```text
BoardConfig_IPC/BoardConfig-EMMC-Buildroot-RV1106_Luckfox_Pico_Pi-IPC.mk
```

Verify the SDK environment:

```sh
./build.sh check
./build.sh info
```

Then run the helper from this repo:

```sh
./build/build-image.sh /path/to/luckfox-pico
```

Example:

```sh
./build/build-image.sh ~/src/luckfox-pico
```

To validate the setup without starting a full build:

```sh
SKIP_BUILD=1 ./build/build-image.sh ~/src/luckfox-pico
```

What it does:

1. selects `project/cfg/BoardConfig_IPC/BoardConfig-EMMC-Buildroot-RV1106_Luckfox_Pico_Pi-IPC.mk`
2. writes `config/buildroot_defconfig` from Luckfox's `luckfox_pico_w_defconfig` plus [luckfox_pico_pi_pymc.fragment](/home/yellowcooln/luckfox-pico-pi-pimesh/build/luckfox_pico_pi_pymc.fragment:1)
3. exports this repo as `BR2_EXTERNAL`
4. runs `./build.sh check`
5. runs `./build.sh info`
6. runs `./build.sh`
7. runs `./build.sh firmware`

If you are building only with the official Luckfox SDK flow first, use:

```sh
./build.sh
./build.sh firmware
```

The completed image artifacts will be in the SDK tree under:

```text
output/image/
```

Luckfox's flash documentation expects `output/image/update.img` to be present for eMMC flashing.

## Manual Flow

If you want to do the same process by hand:

```sh
cd /path/to/luckfox-pico
ln -snf project/cfg/BoardConfig_IPC/BoardConfig-EMMC-Buildroot-RV1106_Luckfox_Pico_Pi-IPC.mk .BoardConfig.mk
mkdir -p config
cat sysdrv/tools/board/buildroot/luckfox_pico_w_defconfig \
  /path/to/luckfox-pico-pi-pimesh/build/luckfox_pico_pi_pymc.fragment \
  > config/buildroot_defconfig
export BR2_EXTERNAL=/path/to/luckfox-pico-pi-pimesh
. tools/linux/toolchain/arm-rockchip830-linux-uclibcgnueabihf/env_install_toolchain.sh
./build.sh check
./build.sh info
./build.sh
./build.sh firmware
```

## Flashing

Flashing to eMMC is still Luckfox-specific. Use the normal Luckfox Pico Pi flashing path for the image files generated in `output/image/`.

This repo does not replace the vendor bootloader, kernel, partitioning, or flash tooling.

Official references:

- https://wiki.luckfox.com/Luckfox-Pico-Pi/SDK
- https://wiki.luckfox.com/Luckfox-Pico-Pi/Flash-image/
- https://github.com/LuckfoxTECH/luckfox-pico
