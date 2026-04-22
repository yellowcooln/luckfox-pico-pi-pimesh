# Luckfox Pico Pi pyMC Repeater Buildroot Setup

This repo packages a Buildroot-friendly `pyMC_Repeater` setup for a Luckfox Pico Pi, aimed at the upstream `pyMC_Repeater` `dev` branch and not tied to a single radio model.

It does not use full native `systemd`. The shipped image includes a small compatibility wrapper so the stock upstream `pyMC_Repeater/manage.sh` install flow can run on Buildroot.

The image-side helper in `/root/pymc-repeater-buildroot` is only a bootstrap/proxy. It clones stock upstream `pyMC_Repeater` into the current user's home directory, then runs the repo's own `manage.sh`.

For building a flashable Luckfox image with this repo layered onto the vendor Buildroot tree, use the files in [build](/home/yellowcooln/luckfox-pico-pi-pimesh/build).

Radio-specific configuration is intentionally deferred to the normal `pyMC_Repeater` setup flow.

The built image is intended to ship with SSH login enabled and a known default credential:
`root` / `luckfox`.

## Using The Image

If you are using one of our prebuilt images, this is the normal first-boot flow.

1. Log in over SSH:

```sh
ssh root@<luckfox-ip>
```

Default login:

- user: `root`
- password: `luckfox`

2. Go to the helper directory that ships inside the image:

```sh
cd /root/pymc-repeater-buildroot
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

- `doctor` checks the image baseline needed by upstream `pyMC_Repeater/manage.sh`
- `install` clones stock upstream `pyMC_Repeater` into `~/pyMC_Repeater` and hands off to the repo's own `manage.sh install`
- `start` proxies to upstream `manage.sh start`
- `wait-ready` waits for the local API to come up
- `advert` runs the known-good `pymc-cli advert` test path

The helper files are preloaded in the image at:

- `/opt/pymc-repeater-buildroot`
- `/root/pymc-repeater-buildroot`

The upstream repo checkout is expected to live at:

- `/root/pyMC_Repeater`

When the image download is finalized, this README will be the main post-flash reference for users.

## What The Image Assumes

- Buildroot image with Python `3.10+`
- `git`
- writable filesystem
- if you want the fallback `pip` path:
  - `python3 -m pip`
  - Python development headers (`Python.h`)
  - native build tools (`gcc`, `make`)

## Commands

Run on the Luckfox:

```sh
sh buildroot-manage.sh install
sh buildroot-manage.sh doctor
sh buildroot-manage.sh start
sh buildroot-manage.sh wait-ready
sh buildroot-manage.sh advert
```

Main commands:

- `install`
- `upgrade`
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

`buildroot-manage.sh` does not force any radio hardware or board profile.

That matches the direction of `pyMC_Repeater/manage.sh`: install the app and let repeater-side config choose the hardware during setup.

The intent here is to keep the Buildroot side generic and stock, then let `pyMC_Repeater` ask for the radio during its own configuration flow.

## Runtime Notes

The runtime helper now treats process start and API readiness as separate things.

That matches the failure mode seen during bring-up: `pyMC_Repeater` can have a live process before port `8000` is actually ready to accept `pymc-cli` connections. Use `wait-ready` before CLI-driven smoke tests, and `advert` if you want the known-good `pymc-cli advert` path wrapped into one command.

Board-specific radio pin mapping, DTS edits, and any temporary DEBUG-mode bring-up steps should stay outside the default image and runtime scripts. Luckfox GPIO handling that previously required local `pyMC_core` patching is now expected to come from upstream `pyMC_core`, not this repo. The baseline here is: boot a stock upstream-ready `pyMC` image, run upstream `manage.sh install`, start the service cleanly, wait for the API to be ready, and only then do radio-specific testing.

## Scope

This repo is about building a usable Luckfox Pico Pi Buildroot image for stock upstream `pyMC_Repeater`.

It is intentionally not carrying local `pyMC_core` or `pyMC_Repeater` patches at this stage.
