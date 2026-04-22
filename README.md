# Luckfox Pico Pi pyMC Repeater Buildroot Setup

This repo packages a Buildroot-friendly `pyMC_Repeater` setup for a Luckfox Pico Pi, aimed at the `pyMC_Repeater` `dev` branch first and not tied to a single radio model.

It does not use `systemd`.

It installs a repo-local runtime, runs `pyMC_Repeater` from checked-out source, and manages the process with a BusyBox-friendly shell script.

Radio-specific configuration is intentionally deferred to:

- the `pyMC_Repeater` web setup flow
- `radio-settings.json`

## What It Assumes

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
sh buildroot-manage.sh start logs
sh buildroot-manage.sh probe
```

Main commands:

- `install`
- `configure`
- `doctor`
- `run`
- `start`
- `stop`
- `restart`
- `status`
- `logs`
- `probe`
- `install-init-script`
- `uninstall-init-script`

## Hardware Profiles

By default, `buildroot-manage.sh` does not force any hardware profile.

That matches the direction of `pyMC_Repeater/manage.sh`: install the app and let repeater-side config choose the board during setup.

If you explicitly need to preseed a board profile for testing, you can still do that by exporting `PYMC_HARDWARE_PROFILE`, but the normal path is to leave it unset.

The current `pyMC_core` test patches included here are still the Luckfox-oriented ones that were used for split-chip SX1262 testing:

- split-gpiochip SX1262 support
- old-kernel IRQ fallback
- forced `python-periphery` SX1262 path
- direct RX probe script

## Important Caveat

This repo is now primarily about building a usable Buildroot image for `pyMC_Repeater dev`.

It does not by itself solve the underlying RF issue from the earlier Luckfox/PiMesh tests. Those findings still apply to that specific hardware path:

- the Luckfox can initialize the SX1262
- GPIO control looks correct
- RF TX/RX was still dead on the tested Pico Pi boards

So treat the image work as the generic deployment foundation, and the included Luckfox patches as test support for current hardware experiments.
