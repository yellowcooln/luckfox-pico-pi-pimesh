# Repository Guidelines

## Project Structure & Module Organization

This repository layers stock upstream `pyMC` support onto the official Luckfox Pico SDK. Key paths:

- `build/`: image build entrypoints and fragments. Use `build/build-image.sh` for full image builds.
- `board/luckfox/pico-pi/`: rootfs overlay and post-build hook copied into the final image.
- `package/yellowcooln/`: custom Buildroot package definitions for Python dependencies not covered upstream.
- `configs/`: Buildroot config fragments merged into the vendor SDK config.
- `buildroot-manage.sh`: on-device runtime helper shipped inside the image at `/root/scripts`.

Do not commit repo-local SDK artifacts from `build/.work/` or generated zip images.

## Build, Test, and Development Commands

- `cd build && ./build-image.sh`
  Clones or refreshes the Luckfox SDK in `build/.work/` and builds `output/image/update.img`.
- `cd build && SKIP_BUILD=1 ./build-image.sh`
  Validates host prerequisites and SDK wiring without running the full image build.
- `sh -n buildroot-manage.sh`
  Syntax-check the on-device management script.
- `sh -n board/luckfox/pico-pi/post-build.sh`
  Syntax-check the post-build hook.

After flashing, the normal device flow is:

```sh
cd /root/scripts
sh buildroot-manage.sh doctor
sh buildroot-manage.sh install
```

## Coding Style & Naming Conventions

Use POSIX shell where possible. Prefer short functions, explicit variables, and 2-space indentation in shell blocks. Keep file and variable names descriptive: `luckfox_pico_pi_pymc.fragment`, `PYMC_REPEATER_REF`, `BOARD_CONFIG_REL`.

Use `apply_patch` for manual edits. Keep the image stock: avoid board-specific `pyMC` patches unless explicitly required.

## Testing Guidelines

There is no formal test suite yet. Validate changes with:

- shell syntax checks (`sh -n`)
- `SKIP_BUILD=1 ./build/build-image.sh`
- a full image build for build-system changes
- `buildroot-manage.sh doctor` on real hardware for runtime changes

Document any hardware-only validation in the PR.

## Commit & Pull Request Guidelines

Recent history uses short imperative subjects, e.g. `Fix sshd startup on shipped image` and `Add optional image zip step to build helper`. Follow that pattern.

PRs should include:

- what changed and why
- whether it affects image build, first-boot runtime, or flashing
- exact validation commands run
- any board-specific assumptions or risks

## Security & Configuration Notes

The shipped image currently expects `root / luckfox` for first login. Treat this as a temporary bootstrap credential and call out any change to login, SSH, or flash behavior clearly in the PR.
