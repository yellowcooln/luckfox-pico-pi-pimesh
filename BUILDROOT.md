# Luckfox Pico Pi pyMC Repeater Buildroot Integration

This repository now doubles as a `br2-external` tree for a Luckfox Buildroot image that is usable for stock upstream `pyMC_Repeater` on first boot.

Goals:

- SSH server enabled so `ssh` and `scp` work
- `git` present on-device
- Python 3 present with the MeshCore runtime dependencies built into the image
- enough userland compatibility for stock upstream `pyMC_Repeater/manage.sh` to run on Buildroot
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
- `/opt/pymc-repeater-buildroot/shims/*`
It also creates:

- `/root/pymc-repeater-buildroot -> /opt/pymc-repeater-buildroot`

The intended user flow on a flashed image is:

1. SSH in as `root` with password `luckfox`
2. `cd /root/pymc-repeater-buildroot`
3. `sh buildroot-manage.sh doctor`
4. `sh buildroot-manage.sh install`
5. `sh buildroot-manage.sh start`
6. `sh buildroot-manage.sh wait-ready`
7. `sh buildroot-manage.sh advert`

## Notes

- `buildroot-manage.sh` is now a thin proxy: it clones `pyMC_Repeater` into `~/pyMC_Repeater` and calls upstream `manage.sh`.
- `buildroot-manage.sh` leaves radio hardware unset so `pyMC_Repeater` can ask during setup.
- The package fragment intentionally focuses on "usable first boot" rather than replacing Luckfox board support or bootloader settings.
- The runtime manager clones stock upstream `pyMC_core` and `pyMC_Repeater` from their `dev` branches and does not apply local patches.
- Luckfox-specific GPIO handling that previously lived in local `pyMC_core` patches is expected to be provided by upstream `pyMC_core`.
