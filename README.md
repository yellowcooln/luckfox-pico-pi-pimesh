# pymc-repeater-buildroot-pico-pi

Buildroot image tooling and first-boot bootstrap for running `pyMC_Repeater`
on Luckfox Pico Pi hardware.

This repo is a Luckfox SDK `BR2_EXTERNAL` layer plus a small set of image-side
helpers. It does not replace the vendor SDK or board support package.

What this repo is responsible for:

- image build wrappers under `build/`
- Buildroot package/config fragments
- rootfs overlay files and post-build hooks
- the thin `/root/scripts/buildroot-manage.sh` bootstrap shipped inside the image
- first-boot image hardening and metadata

What it does not do:

- carry long-lived local forks of `pyMC_core` or `pyMC_Repeater`
- replace the Luckfox bootloader/kernel/partition layout
- own the full runtime UX after the upstream repo checkout is installed

The default shipped image uses the Luckfox vendor init/network stack and is
expected to allow first login over SSH with:

- user: `root`
- password: `luckfox`

## Using The Image

If you are using one of the flashed images built from this repo, this is the
normal first-boot flow.

1. Log in over SSH:

```sh
ssh root@<luckfox-ip>
```

Default login:

- user: `root`
- password: `luckfox`

2. Go to the shipped helper directory:

```sh
cd /root/scripts
```

3. Run the setup and first smoke test:

```sh
sh buildroot-manage.sh doctor
sh buildroot-manage.sh install
sh buildroot-manage.sh start
sh buildroot-manage.sh wait-ready
sh buildroot-manage.sh advert
```

What this does:

- `doctor` checks the image baseline needed by the Buildroot install flow
- `install` clones `pyMC_Repeater` into `~/pyMC_Repeater` and hands off to the repo checkout's own `buildroot-manage.sh install`
- `start` proxies to the repo-side Buildroot service wrapper
- `wait-ready` waits for the local API to come up
- `advert` runs the known-good `pymc-cli advert` test path

The image also ships with:

- Luckfox vendor init scripts
- Luckfox vendor networking
- OpenSSH enabled
- `git`, `jq`, `wget`, `dialog`, `yq`
- Python 3 with the native modules needed by the upstream Buildroot install flow
- `wpa_supplicant`, `iw`, and the other baseline networking/debug tools from the image fragment

The helper files are preloaded in the image at:

- `/opt/scripts`
- `/root/scripts`

The managed upstream repo checkout is expected to live at:

- `/opt/pymc_repeater/pyMC_Repeater`

The image also writes a small metadata marker at:

- `/etc/pymc-image-build-id`

Current fields:

- `image_name`
- `image_version`

That file is used as the Buildroot-image marker by `pyMC_Repeater`, and the
`image_version` is exposed through repeater stats/API when present.

There are now two image modes in this repo:

- bootstrap image
  - ships the thin `/root/scripts/buildroot-manage.sh` helper
  - clones or refreshes `pyMC_Repeater` into `/opt/pymc_repeater/pyMC_Repeater`
    when run as `root`
- preinstalled image
  - bakes the repeater runtime directly into `/opt/pymc_repeater`
  - ships the managed repo checkout at `/opt/pymc_repeater/pyMC_Repeater`
    for later updates
  - boots directly into the repeater web UI without a first-boot install step
  - leaves the default setup credentials in place so the device lands on
    `/setup`

## What The Image Assumes

- Buildroot image with Python `3.10+`
- writable filesystem
- a normal Luckfox vendor userspace
- radio-specific setup is still deferred to the upstream `pyMC_Repeater` repo flow

## Commands

Run on the Luckfox:

```sh
sh buildroot-manage.sh install
sh buildroot-manage.sh doctor
sh buildroot-manage.sh start
sh buildroot-manage.sh wait-ready
sh buildroot-manage.sh advert
```

Main commands exposed by the image bootstrap:

- `install`
- `upgrade`
- `configure`
- `radio-profile`
- `config`
- `doctor`
- `start`
- `wait-ready`
- `advert`
- `stop`
- `restart`
- `status`
- `logs`
- `uninstall`
- `repo-path`
- `repo-sync`

## Radio Selection

The repo-side Buildroot installer supports Luckfox-specific radio profile
selection after install.

Current choices:

- `PiMesh V2`
- `PiMesh V1 / MeshAdv`

During install, the repo-side Buildroot manager asks for:

- repeater name
- admin password
- radio settings

and writes those directly into `/etc/pymc_repeater/config.yaml` so the service
does not need to rely on the web setup wizard.

For Pico Pi profiles, the repo-side JSON currently also injects:

- `sx1262.radio_timing_delay: 0.012`

That is how the minimal Pico Pi SX1262 timing override is applied now. It is
config-driven from `pyMC_Repeater`, not hardcoded in this image repo.

You can rerun the full config flow later with:

```sh
sh buildroot-manage.sh configure
```

Or just reapply the Luckfox pin mapping with:

```sh
sh buildroot-manage.sh radio-profile
```

## Runtime Notes

The image-side `buildroot-manage.sh` is intentionally thin. It is only
responsible for:

- cloning or refreshing the upstream `pyMC_Repeater` checkout
- handing off to the repo checkout's `buildroot-manage.sh` when present
- providing a small set of bootstrap-only commands like `doctor`, `wait-ready`, and `advert`

The runtime helper treats process start and API readiness as separate things.

That matches the failure mode seen during bring-up: `pyMC_Repeater` can have a live process before port `8000` is actually ready to accept `pymc-cli` connections. Use `wait-ready` before CLI-driven smoke tests, and `advert` if you want the known-good `pymc-cli advert` path wrapped into one command.

Current image hardening also includes:

- `/etc/init.d/S50telnet` removed
- `/etc/init.d/S41dhcpcd` removed to avoid duplicate-IP behavior with vendor `udhcpc`
- `/var/empty` fixed in post-fakeroot so `sshd` starts cleanly

For the bootstrap image, the baseline expectation is:

1. flash the image
2. SSH in as `root`
3. run the bootstrap install flow
4. wait for the API to be ready
5. do radio-specific testing after the upstream repo install is live

For the preinstalled-image variant built from
`build/build-docker-embed-pico-pi.sh`, the image ships:

- `/opt/pymc_repeater/venv`
- `/opt/pymc_repeater/pyMC_Repeater`
- `/etc/pymc_repeater/config.yaml`
- `/etc/init.d/S80pymc-repeater`

That path is designed so the box boots straight into the web setup flow with no
first-boot install, no `/root/pyMC_core`, and no on-device dependency download.

## Scope

This repo is about building a usable Luckfox Pico Pi Buildroot image for stock
upstream `pyMC_Repeater`.

It intentionally keeps the image-side helper thin and expects ongoing runtime
behavior to come from the managed `pyMC_Repeater` repo checkout, not from large
image-only runtime forks.
