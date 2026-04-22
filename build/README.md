# Build Image

This folder contains the repo-local pieces needed to build a Luckfox Pico Pi image with stock upstream `pyMC` support layered onto a Luckfox vendor Buildroot tree.

This repo is still not the board support package by itself. The final bootable eMMC image comes from the Luckfox vendor Buildroot tree for your exact board. This repo provides:

- the `BR2_EXTERNAL` layer
- the extra Python package definitions
- the rootfs overlay
- the post-build install step
- the `pyMC` package fragment
- a helper script that drives the build

## What You Need

- a Luckfox vendor Buildroot tree for the target Pico Pi board
- this repo checked out locally
- the vendor board defconfig name

## Build Flow

Run the helper from this repo:

```sh
./build/build-image.sh /path/to/luckfox-vendor-buildroot <vendor_defconfig>
```

Example:

```sh
./build/build-image.sh ~/src/luckfox-buildroot luckfox_pico_pi_defconfig
```

What it does:

1. loads the vendor board defconfig
2. attaches this repo as `BR2_EXTERNAL`
3. merges [luckfox_pico_pi_pymc.fragment](/home/yellowcooln/luckfox-pico-pi-pimesh/build/luckfox_pico_pi_pymc.fragment:1)
4. runs `make olddefconfig`
5. builds the image

The completed image artifacts will be in the vendor tree under:

```text
output/images/
```

## Manual Flow

If you want to do the same process by hand:

```sh
cd /path/to/luckfox-vendor-buildroot
make BR2_EXTERNAL=/path/to/luckfox-pico-pi-pimesh <vendor_defconfig>
./support/kconfig/merge_config.sh -m .config /path/to/luckfox-pico-pi-pimesh/build/luckfox_pico_pi_pymc.fragment
make BR2_EXTERNAL=/path/to/luckfox-pico-pi-pimesh olddefconfig
make BR2_EXTERNAL=/path/to/luckfox-pico-pi-pimesh
```

## Flashing

Flashing to eMMC is still Luckfox-vendor-specific. Use the normal Luckfox flashing path for the image files generated in `output/images/`.

This repo does not replace the vendor bootloader, kernel, partitioning, or flash tooling.
