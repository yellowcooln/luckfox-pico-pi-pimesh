# pymc-repeater-buildroot-pico-pi

Buildroot image and first-boot tooling for running `pyMC_Repeater` on a
Luckfox Pico Pi.

This repo packages a Buildroot-friendly `pyMC_Repeater` setup for a Luckfox Pico Pi, aimed at the upstream `pyMC_Repeater` `dev` branch and not tied to a single radio model.

The shipped image is a normal Buildroot appliance using the Luckfox vendor init
and networking stack.

The image-side helper in `/root/scripts` is only a
bootstrap/proxy. It clones `pyMC_Repeater` into the current user's home
directory, then runs the repo's own `buildroot-manage.sh` when present.

GitHub repo:

- `https://github.com/yellowcooln/pymc-repeater-buildroot-pico-pi`

For building a flashable Luckfox image with this repo layered onto the vendor Buildroot tree, use the files in `build/`.

Helper script overview:

- [SCRIPTS.md](./SCRIPTS.md)

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
- `install` clones `pyMC_Repeater` into `~/pyMC_Repeater` and hands off to the repo's own `buildroot-manage.sh install`
- `start` proxies to the repo's Buildroot service wrapper
- `wait-ready` waits for the local API to come up
- `advert` runs the known-good `pymc-cli advert` test path

The image also ships with:

- Buildroot init scripts
- Luckfox vendor networking
- `wpa_supplicant`, `iw`, and `htop`

The helper files are preloaded in the image at:

- `/opt/scripts`
- `/root/scripts`

The upstream repo checkout is expected to live at:

- `/root/pyMC_Repeater`

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

The repo-side Buildroot installer supports Luckfox-specific radio profile selection after install.

Current choices:

- `PiMesh V2`
- `PiMesh V1 / MeshAdv`

During install, the repo-side Buildroot manager asks for:

- repeater name
- admin password
- radio settings

and writes those directly into `/etc/pymc_repeater/config.yaml` so the service
does not need to rely on the web setup wizard.

You can rerun the full config flow later with:

```sh
sh buildroot-manage.sh configure
```

Or just reapply the Luckfox pin mapping with:

```sh
sh buildroot-manage.sh radio-profile
```

## Runtime Notes

The runtime helper now treats process start and API readiness as separate things.

That matches the failure mode seen during bring-up: `pyMC_Repeater` can have a live process before port `8000` is actually ready to accept `pymc-cli` connections. Use `wait-ready` before CLI-driven smoke tests, and `advert` if you want the known-good `pymc-cli advert` path wrapped into one command.

Board-specific radio pin mapping, DTS edits, and any temporary DEBUG-mode
bring-up steps should stay outside the default image and runtime scripts.
Luckfox GPIO handling that previously required local `pyMC_core` patching is
now expected to come from upstream `pyMC_core`, not this repo. The baseline
here is: boot a stock upstream-ready `pyMC` image, run the repo's
`buildroot-manage.sh install`, start the service cleanly, wait for the API to
be ready, and only then do radio-specific testing.

## Scope

This repo is about building a usable Luckfox Pico Pi Buildroot image for stock upstream `pyMC_Repeater`.

It intentionally keeps the image-side helper thin and expects ongoing runtime
behavior to come from the pulled `pyMC_Repeater` repo, not from baked image
scripts.
