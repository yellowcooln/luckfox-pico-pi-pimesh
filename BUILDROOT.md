# Buildroot Integration

This repository now doubles as a `br2-external` tree for a Luckfox Pico Pi image that is usable on first boot.

Goals:

- SSH server enabled so `ssh` and `scp` work
- `git` present on-device
- Python 3 present with the MeshCore runtime dependencies built into the image
- PiMesh helper files preloaded at `/opt/luckfox-pico-pi-pimesh`
- convenience symlink at `/root/luckfox-pico-pi-pimesh`

## What This Repo Adds

- `external.desc`, `external.mk`, `Config.in`
  Buildroot external tree registration
- `configs/luckfox_pico_pi_pimesh_packages.config`
  package/config fragment to merge into the vendor Luckfox Buildroot config
- `board/luckfox/pico-pi-pimesh/rootfs-overlay`
  static files copied into the target rootfs
- `board/luckfox/pico-pi-pimesh/post-build.sh`
  copies this repo's runtime files into `/opt/luckfox-pico-pi-pimesh` inside the image
- `package/yellowcooln/*`
  custom Buildroot Python packages for dependencies missing from upstream Buildroot

## Vendor Buildroot Workflow

This repo is not a full standalone board port. It is meant to be layered on top of the Luckfox vendor Buildroot tree.

Typical flow:

```sh
git clone <luckfox-vendor-buildroot> buildroot-luckfox
git clone https://github.com/yellowcooln/luckfox-pico-pi-pimesh.git
cd buildroot-luckfox
make BR2_EXTERNAL=../luckfox-pico-pi-pimesh <vendor_board_defconfig>
```

Then merge the package fragment values from:

```text
../luckfox-pico-pi-pimesh/configs/luckfox_pico_pi_pimesh_packages.config
```

The simplest path is:

1. `make menuconfig`
2. set the options listed in the fragment
3. save
4. build with `make`

If you already have a working vendor `.config`, you can also copy the relevant symbol lines from the fragment into it and run:

```sh
make olddefconfig
```

## Files Installed Into The Image

The post-build script copies these into the target rootfs:

- `/opt/luckfox-pico-pi-pimesh/buildroot-manage.sh`
- `/opt/luckfox-pico-pi-pimesh/README.md`
- `/opt/luckfox-pico-pi-pimesh/BUILDROOT.md`
- `/opt/luckfox-pico-pi-pimesh/patches/*.patch`

It also creates:

- `/root/luckfox-pico-pi-pimesh -> /opt/luckfox-pico-pi-pimesh`

## Notes

- `buildroot-manage.sh` now detects when the image already contains the required Python modules and skips the `pip` bootstrap path.
- The package fragment intentionally focuses on "usable first boot" rather than replacing Luckfox board-specific kernel or bootloader settings.
