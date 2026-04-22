# Luckfox Pico Pi pyMC Repeater Buildroot Integration

This repository now doubles as a `br2-external` tree for a Luckfox Buildroot image that is usable for stock upstream `pyMC_Repeater` on first boot.

Goals:

- SSH server enabled so `ssh` and `scp` work
- `git` present on-device
- Python 3 present with the MeshCore runtime dependencies built into the image
- pyMC Repeater helper files preloaded at `/opt/pymc-repeater-buildroot`
- convenience symlink at `/root/pymc-repeater-buildroot`

## What This Repo Adds

- `external.desc`, `external.mk`, `Config.in`
  Buildroot external tree registration
- `configs/luckfox_pico_pi_pimesh_packages.config`
  package/config fragment to merge into the vendor Luckfox Buildroot config
- `board/luckfox/pico-pi-pimesh/rootfs-overlay`
  static files copied into the target rootfs
- `board/luckfox/pico-pi-pimesh/post-build.sh`
  copies this repo's runtime files into `/opt/pymc-repeater-buildroot` inside the image
- `package/yellowcooln/*`
  custom Buildroot Python packages for dependencies missing from upstream Buildroot

## Vendor Buildroot Workflow

This repo is not a full standalone board port. It is meant to be layered on top of a vendor Buildroot tree, such as the Luckfox vendor Buildroot tree.

Typical flow:

```sh
git clone <luckfox-vendor-buildroot> buildroot-luckfox
git clone https://github.com/yellowcooln/luckfox-pico-pi-pimesh.git
cd buildroot-luckfox
make BR2_EXTERNAL=../luckfox-pico-pi-pimesh <vendor_board_defconfig>
```

Then merge the package fragment values from:

```text
../luckfox-pico-pi-pimesh/build/luckfox_pico_pi_pymc.fragment
```

The repo also includes a helper script that runs that flow for you:

```sh
../luckfox-pico-pi-pimesh/build/build-image.sh "$(pwd)" <vendor_board_defconfig>
```

The simplest manual path is:

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

- `/opt/pymc-repeater-buildroot/buildroot-manage.sh`
- `/opt/pymc-repeater-buildroot/README.md`
- `/opt/pymc-repeater-buildroot/BUILDROOT.md`
It also creates:

- `/root/pymc-repeater-buildroot -> /opt/pymc-repeater-buildroot`

## Notes

- `buildroot-manage.sh` now detects when the image already contains the required Python modules and skips the `pip` bootstrap path.
- `buildroot-manage.sh` leaves radio hardware unset so `pyMC_Repeater` can ask during setup.
- The package fragment intentionally focuses on "usable first boot" rather than replacing Luckfox board support or bootloader settings.
- The runtime manager clones stock upstream `pyMC_core` and `pyMC_Repeater` from their `dev` branches and does not apply local patches.
