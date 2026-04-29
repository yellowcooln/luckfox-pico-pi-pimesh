# Luckfox Pico Pi pyMC Repeater Buildroot Integration

This repository is a `BR2_EXTERNAL` layer for building a Luckfox Pico Pi image
that can bootstrap stock upstream `pyMC_Repeater` on first boot.

Goals:

- SSH server enabled so `ssh` and `scp` work
- `git` present on-device
- Python 3 present with the runtime dependencies needed by the upstream
  Buildroot install flow
- the normal Luckfox/Buildroot init and networking stack
- pyMC Repeater helper files preloaded at `/opt/scripts`
- convenience symlink at `/root/scripts`
- image metadata exposed through `/etc/pymc-image-build-id`
- a comment-preserving Buildroot config flow via shipped `yq`

## What This Repo Adds

- `external.desc`, `external.mk`, `Config.in`
  Buildroot external tree registration
- `configs/luckfox_pico_pi_pimesh_packages.config`
  package/config fragment to merge into the vendor Luckfox Buildroot config
- `board/luckfox/pico-pi/rootfs-overlay`
  static files copied into the target rootfs
- `board/luckfox/pico-pi/post-build.sh`
  restores vendor overlays, copies this repo's runtime files into `/opt/scripts`,
  stages Python SQLite runtime pieces if needed, removes stale vendor services,
  and writes image metadata
- `board/luckfox/pico-pi/post-fakeroot.sh`
  fixes `/var/empty` and `/dev/tty` so `sshd` starts cleanly on shipped images
- `package/luckfox-pico-pi/*`
  external Buildroot packages not covered by the stock SDK config, including `yq`

## Vendor Buildroot Workflow

This repo is not a full standalone board port. It is meant to be layered on top of a vendor Buildroot tree, such as the Luckfox vendor Buildroot tree.

Typical flow:

```sh
git clone <luckfox-vendor-buildroot> buildroot-luckfox
git clone https://github.com/yellowcooln/pymc-repeater-buildroot-pico-pi.git
cd buildroot-luckfox
make BR2_EXTERNAL=../pymc-repeater-buildroot-pico-pi <vendor_board_defconfig>
```

Then merge the package fragment values from:

```text
../pymc-repeater-buildroot-pico-pi/build/luckfox_pico_pi_pymc.fragment
```

That fragment is the canonical image input for this repo. It wires in:

- this repo's `BR2_EXTERNAL` path
- the rootfs overlay
- the post-build hook
- the post-fakeroot hook
- required package symbols
- Python SQLite support checks

The repo also includes a helper script that runs that flow for you:

```sh
../pymc-repeater-buildroot-pico-pi/build/build-image.sh "$(pwd)" <vendor_board_defconfig>
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

- `/opt/scripts/buildroot-manage.sh`
- `/opt/scripts/README.md`
- `/opt/scripts/BUILDROOT.md`
- `/opt/scripts/network-setup.sh`
- `/opt/scripts/wifi-setup.sh`
- `/opt/scripts/tailscale-manage.sh`
- `/opt/scripts/pymc-console-webui.sh`

It also creates:

- `/root/scripts -> /opt/scripts`

And installs:

- `/usr/local/sbin/network-priority.sh`
- `/usr/local/bin/network-setup.sh -> /opt/scripts/network-setup.sh`
- `/usr/local/bin/wifi-setup.sh -> /opt/scripts/wifi-setup.sh`

The image also ships:

- `git`, `jq`, `wget`, `dialog`, `yq`
- Python 3 with the modules needed by the upstream Buildroot flow
- OpenSSH enabled
- Luckfox vendor init/networking
- `wpa_supplicant`, `iw`, `iptables`, and the baseline network/debug tools from
  the image fragment

The intended user flow on a flashed image is:

1. SSH in as `root` with password `luckfox`
2. `cd /root/scripts`
3. `sh buildroot-manage.sh doctor`
4. `sh buildroot-manage.sh install`
5. `sh buildroot-manage.sh start`
6. `sh buildroot-manage.sh wait-ready`
7. `sh buildroot-manage.sh advert`

## Notes

- the image-side `buildroot-manage.sh` is intentionally thin: it clones
  `pyMC_Repeater` into `~/pyMC_Repeater` and calls the repo's
  `buildroot-manage.sh` when available
- the image stays on the normal Luckfox Buildroot init/network stack rather than trying to force `systemd`
- the bootstrap flow leaves radio hardware selection to the upstream repo setup
  prompts and profile JSON
- the Buildroot config flow in upstream `pyMC_Repeater` now uses `yq` to merge
  values back into `config.yaml.example`, which preserves comments
- the package fragment intentionally focuses on "usable first boot" rather than
  replacing Luckfox board support, bootloader settings, or the vendor partition
  layout

Current image hardening in this repo includes:

- `/etc/init.d/S50telnet` removed
- `/etc/init.d/S41dhcpcd` removed to avoid duplicate-IP behavior with vendor
  `udhcpc`
- `/var/empty` ownership/mode fixed before packaging so `sshd` starts reliably
- `/etc/pymc-image-build-id` written with:
  - `image_name=Luckfox pyMC Repeater Buildroot`
  - `image_version=0.6.9`

Current runtime expectations:

- the on-device bootstrap clones stock upstream `pyMC_Repeater` from `dev`
- the actual runtime UX lives in that repo after install, not in this image repo
- Pico Pi radio timing is no longer hardcoded in this image repo; it is now
  applied by the upstream Buildroot radio profile data through:
  - `sx1262.radio_timing_delay: 0.012`
