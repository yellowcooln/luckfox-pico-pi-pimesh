# Luckfox Pico Pi Buildroot PiMesh Setup

This repo packages a Buildroot-friendly `pyMC_Repeater` setup for a `Luckfox Pico Pi` using the split-gpio `PiMesh 1W v1` / `MeshAdv` wiring that was documented in `/home/yellowcooln/luckfox-pimesh.md`.

It does not use `systemd`.

It installs a repo-local runtime, runs `pyMC_Repeater` from checked-out source, and manages the process with a BusyBox-friendly shell script.

## What It Assumes

- Buildroot image on the Luckfox
- Python `3.10+`
- `python3 -m pip`
- Python development headers (`Python.h`)
- native build tools (`gcc`, `make`)
- `git`
- writable filesystem
- radio device nodes present:
  - `/dev/spidev0.0`
  - `/dev/gpiochip1`
  - `/dev/gpiochip3`
  - `/dev/gpiochip4`

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

## Defaults

The default hardware profile is `pimesh-1w-v1`.

That maps the Luckfox pins as:

- `CS` -> `gpiochip4 line 17`
- `RESET` -> `gpiochip1 line 22`
- `BUSY` -> `gpiochip3 line 27`
- `IRQ` -> `gpiochip1 line 23`
- `TXEN` -> `gpiochip1 line 20`
- `RXEN` -> `gpiochip1 line 21`

The script also applies the local `pyMC_core` Luckfox patches that were not fully available upstream:

- split-gpiochip SX1262 support
- old-kernel IRQ fallback
- forced `python-periphery` SX1262 path
- direct RX probe script

## Important Caveat

This gets the software stack into the known-good test state from the handoff notes.

It does not solve the underlying RF issue described in `luckfox-pimesh.md`. The prior conclusion was:

- the Luckfox can initialize the SX1262
- GPIO control looks correct
- RF TX/RX was still dead on the tested Pico Pi boards

So this repo is the right install/test harness, not proof that the hardware path is fixed.
