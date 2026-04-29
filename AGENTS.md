# Repository Guidelines

## What This Repo Is

This repo is a Luckfox Pico SDK `BR2_EXTERNAL` layer plus a small set of
image-side helpers for shipping a usable Luckfox Pico Pi Buildroot image that
can bootstrap stock upstream `pyMC_Repeater`.

It is not:

- a replacement for the Luckfox SDK
- a full standalone board support package
- the long-term home of `pyMC_Repeater` runtime UX
- the place to carry large local forks of `pyMC_core` or `pyMC_Repeater`

Core model:

- this repo builds and hardens the image
- the image ships a thin bootstrap helper at `/root/scripts/buildroot-manage.sh`
- that helper manages `pyMC_Repeater` under `/opt/pymc_repeater/pyMC_Repeater`
- the real runtime flow then hands off to the upstream repo's own
  `buildroot-manage.sh`

## Current Image Contract

Built images from this repo are expected to ship with:

- SSH enabled
- bootstrap login `root / luckfox`
- Telnet removed
- `dhcpcd` startup removed so vendor `udhcpc` is the only DHCP client
- `/var/empty` fixed so `sshd` starts reliably
- `/etc/pymc-image-build-id` containing:
  - `image_name=Luckfox pyMC Repeater Buildroot`
  - `image_version=0.6.9`
- `/opt/scripts` populated with the image bootstrap helpers
- `/root/scripts -> /opt/scripts`
- `yq` present on-device so Buildroot config flows can preserve comments in
  `/etc/pymc_repeater/config.yaml`
- Python SQLite runtime support present and validated at build time

For the preinstalled-image variant, built images are also expected to ship with:

- `/opt/pymc_repeater/venv`
- `/opt/pymc_repeater/pyMC_Repeater`
- `/etc/pymc_repeater`
- `/etc/init.d/S80pymc-repeater`
- no `/root/pyMC_core`
- no first-boot installer hook

Do not make changes that silently regress any of those image guarantees.

## Project Structure & Module Organization

Key paths:

- `build/`
  image build entrypoints, Docker wrappers, and config fragments
- `build/build-image.sh`
  primary image build wrapper around the vendor Luckfox SDK
- `build/build-image-docker.sh`
  Docker/Podman wrapper for building on faster host hardware
- `build/build-image-pico-zero.sh`
  alternate board wrapper for Pico Zero SDK config selection
- `build/build-image-pico-zero-docker.sh`
  Docker wrapper for the Pico Zero build path
- `build/build-docker-embed-pico-pi.sh`
  Docker wrapper for the preinstalled-runtime Pico Pi image
- `build/luckfox_pico_pi_pymc.fragment`
  canonical Buildroot fragment for this repo
- `board/luckfox/pico-pi/rootfs-overlay/`
  static files copied into the target rootfs
- `board/luckfox/pico-pi/post-build.sh`
  final image staging, vendor overlay restore, hardening, metadata, helper copy,
  and SQLite fallback staging
- `board/luckfox/pico-pi/post-fakeroot.sh`
  final ownership/device-node fixups required for working SSH
- `package/luckfox-pico-pi/`
  external Buildroot packages needed by this image, including `yq`
- `configs/luckfox_pico_pi_pimesh_packages.config`
  secondary config copy that must stay aligned with the canonical fragment
- `buildroot-manage.sh`
  thin on-image bootstrap/proxy script shipped into `/root/scripts`

Do not commit:

- `build/.work/`
- generated SDK output
- generated zip images

## Important Architecture Rules

Keep these boundaries clear:

1. image repo responsibility
- ship a bootable, SSH-accessible image
- ship the bootstrap helper, network helpers, metadata, and base packages
- keep vendor SDK integration working
- harden the image enough for first boot and upstream install

2. upstream repo responsibility after install
- repeater config UX
- radio profile selection UX
- API/UI behavior
- service lifecycle details
- ongoing runtime feature work

Embedded-image exception:

- this repo may bundle upstream `pyMC_Repeater` and `pyMC_core` source
  checkouts into the image
- but it should still install them into the standard upstream runtime paths
  rather than inventing a parallel runtime layout

Do not bloat the image bootstrap into a second copy of upstream runtime logic.
If the feature belongs in `pyMC_Repeater`, keep it there and only ship what the
image needs to bootstrap it.

## Build, Test, and Development Commands

- `cd build && ./build-image.sh`
  clones or refreshes the Luckfox SDK in `build/.work/` and builds
  `output/image/update.img`
- `cd build && SKIP_BUILD=1 ./build-image.sh`
  validates host prerequisites and SDK wiring without running the full image
  build
- `cd build && ./build-image-docker.sh`
  runs the same build inside Docker/Podman while reusing host `build/.work`
- `cd build && ./build-image-pico-zero.sh`
  uses the Pico Zero board config from the same SDK
- `cd build && ./build-image-pico-zero-docker.sh`
  Docker wrapper for the Pico Zero build
- `sh -n buildroot-manage.sh`
  syntax-check the on-device bootstrap helper
- `sh -n board/luckfox/pico-pi/post-build.sh`
  syntax-check the post-build hook
- `sh -n board/luckfox/pico-pi/post-fakeroot.sh`
  syntax-check the post-fakeroot hook

After flashing, the normal device flow is:

```sh
cd /root/scripts
sh buildroot-manage.sh doctor
sh buildroot-manage.sh install
sh buildroot-manage.sh start
sh buildroot-manage.sh wait-ready
sh buildroot-manage.sh advert
```

## Build Gotchas

- `build/luckfox_pico_pi_pymc.fragment` is the canonical config input. If the
  same symbols are also mirrored in `configs/luckfox_pico_pi_pimesh_packages.config`,
  keep both copies aligned.
- A build that completes and produces a zip is not enough by itself. The wrapper
  now intentionally fails if target Python SQLite runtime files are missing.
- `post-build.sh` restores vendor overlays before installing repo files. Do not
  remove that without understanding the Luckfox SDK overlay chain.
- `post-fakeroot.sh` is required for correct `/var/empty` and `/dev/tty` state.
  Removing it will break SSH on shipped images.
- Docker builds write into the local repo because the repo is bind-mounted into
  the container at `/workspace`.
- The container wrapper reuses `build/.work/`; it does not rebuild the SDK from
  scratch every run unless you wipe that tree.

## Runtime Gotchas

- `/root/scripts/buildroot-manage.sh` is only a bootstrap/proxy. It is not the
  full runtime manager.
- It clones `pyMC_Repeater` from:
  - `PYMC_REPEATER_REPO=https://github.com/rightup/pyMC_Repeater.git`
  - `PYMC_REPEATER_REF=dev`
- On shipped images running as `root`, the managed checkout lives under:
  - `/opt/pymc_repeater/pyMC_Repeater`
- It prefers the repo checkout's `buildroot-manage.sh`, and falls back to
  `manage.sh` only if the Buildroot-specific helper is absent.
- `doctor` checks for the baseline runtime modules and tools the upstream
  Buildroot install path expects.
- `wait-ready` exists because a running process is not the same thing as API
  readiness on port `8000`.
- `advert` is a known-good smoke test wrapper around `pymc-cli advert`.
- preinstalled images bake the runtime into `/opt/pymc_repeater` and ship the
  managed repeater checkout under `/opt/pymc_repeater/pyMC_Repeater`

## Current Upstream Integration Assumptions

- `pyMC_Repeater` Buildroot config flow uses `yq` to preserve comments when
  rewriting `/etc/pymc_repeater/config.yaml`
- Buildroot radio profiles in upstream `pyMC_Repeater` now inject:
  - `sx1262.radio_timing_delay: 0.012`
  for Pico Pi profiles
- the current minimal Pico Pi SX1262 timing fix is now config-driven from the
  upstream repo, not hardcoded in this image repo

Do not reintroduce image-side or local-core board detection for that timing
override unless explicitly required.

## Coding Style & Naming Conventions

Use POSIX shell where possible. Prefer short functions, explicit variables, and
2-space indentation in shell blocks. Keep file and variable names descriptive:

- `luckfox_pico_pi_pymc.fragment`
- `PYMC_REPEATER_REF`
- `BOARD_CONFIG_REL`
- `IMAGE_ARCHIVE_PREFIX`

Use `apply_patch` for manual edits.

Keep the image stock. Avoid board-specific `pyMC` patches here unless the image
cannot function without them and the change truly belongs in the image layer.

## Testing Guidelines

There is no formal test suite yet. Validate changes with:

- shell syntax checks (`sh -n`)
- `SKIP_BUILD=1 ./build/build-image.sh`
- Docker wrapper sanity checks when changing container build flow
- a full image build for build-system changes
- `buildroot-manage.sh doctor` on real hardware for runtime changes

For image-build changes, prefer validating both:

- the config/wrapper path
- the actual built rootfs invariants the change is meant to protect

Document any hardware-only validation in the PR.

## Commit & Pull Request Guidelines

Recent history uses short imperative subjects such as:

- `Fix sshd startup on shipped image`
- `Add optional image zip step to build helper`
- `Ship yq and image version metadata`

Follow that pattern.

PRs should include:

- what changed and why
- whether it affects image build, first-boot runtime, runtime bootstrap, or flashing
- exact validation commands run
- any board-specific assumptions or risks
- whether the change touches the canonical fragment, post-build path, or shipped
  bootstrap/runtime contract

## Security & Configuration Notes

The shipped image currently expects `root / luckfox` for first login. Treat
this as temporary bootstrap credentialing and call out any change to login,
SSH, Telnet, metadata, or flash behavior clearly in the PR.

Be especially careful with:

- `/etc/init.d/S50telnet`
- `/etc/init.d/S41dhcpcd`
- `/etc/shadow`
- `/etc/passwd`
- `/etc/pymc-image-build-id`
- `/var/empty`

Those are all part of the current known-good shipped-image behavior.
