# Luckfox Pico Pi pyMC Repeater Buildroot Setup

This repo packages a Buildroot-friendly `pyMC_Repeater` setup for a Luckfox Pico Pi, aimed at the upstream `pyMC_Repeater` `dev` branch and not tied to a single radio model.

It does not use `systemd`.

It installs a repo-local runtime, runs `pyMC_Repeater` from checked-out source, and manages the process with a BusyBox-friendly shell script.

Radio-specific configuration is intentionally deferred to the normal `pyMC_Repeater` setup flow.

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
- `install-init-script`
- `uninstall-init-script`

## Radio Selection

`buildroot-manage.sh` does not force any radio hardware or board profile.

That matches the direction of `pyMC_Repeater/manage.sh`: install the app and let repeater-side config choose the hardware during setup.

The intent here is to keep the Buildroot side generic and stock, then let `pyMC_Repeater` ask for the radio during its own configuration flow.

## Scope

This repo is about building a usable Luckfox Pico Pi Buildroot image for stock upstream `pyMC_Repeater`.

It is intentionally not carrying local `pyMC_core` or `pyMC_Repeater` patches at this stage.
