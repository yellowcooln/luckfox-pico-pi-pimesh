# Scripts

This repo ships a small set of helper scripts into the Luckfox image.

User-facing helper directory on the board:

- `/root/scripts`

Backed by:

- `/opt/scripts`

## Main Scripts

### `buildroot-manage.sh`

Location on the board:

- `/root/scripts/buildroot-manage.sh`

Purpose:

- thin bootstrap/proxy for `pyMC_Repeater`
- clones or refreshes `pyMC_Repeater`
- hands off to the repo's own `buildroot-manage.sh` when present

Typical use:

```sh
cd /root/scripts
sh buildroot-manage.sh doctor
sh buildroot-manage.sh install
sh buildroot-manage.sh start
```

Important note:

- this script is intentionally thin
- the real Buildroot install/config/runtime logic lives in the pulled
  `pyMC_Repeater` repo

### `tailscale-manage.sh`

Location on the board:

- `/root/scripts/tailscale-manage.sh`

Purpose:

- install and manage Tailscale on the Buildroot image
- handles download, install, start, status, upgrade, and login flow

Typical use:

```sh
cd /root/scripts
sh tailscale-manage.sh install
sh tailscale-manage.sh start
sh tailscale-manage.sh up
```

### `wifi-setup.sh`

Location on the board:

- `/root/scripts/wifi-setup.sh`

Purpose:

- basic interactive Wi-Fi join helper
- scans visible SSIDs
- prompts for SSID, password, and priority
- writes an entry into `/etc/network-priority.wifi`
- renders `wpa_supplicant.conf`
- restarts the Wi-Fi client

Typical use:

```sh
cd /root/scripts
sh wifi-setup.sh
```

Status check:

```sh
sh wifi-setup.sh status
```

### `network-setup.sh`

Location on the board:

- `/root/scripts/network-setup.sh`

Purpose:

- menu-driven setup for network policy
- wraps the lower-level network-priority backend
- avoids manual editing for common cases

It can:

- show current network status
- configure Ethernet / Wi-Fi / LTE priority metrics
- enable or disable LTE fallback
- add or remove saved Wi-Fi networks
- apply the policy immediately

Typical use:

```sh
cd /root/scripts
sh network-setup.sh
```

## Backend Script

### `network-priority.sh`

Location on the board:

- `/usr/local/sbin/network-priority.sh`

Purpose:

- backend policy engine for route preference
- reads:
  - `/etc/default/network-priority`
  - `/etc/network-priority.wifi`
- renders Wi-Fi config
- applies route metrics
- supports the preference model:
  - Ethernet first
  - Wi-Fi second
  - LTE third

Important note:

- this is not the main user entrypoint
- users should generally run `network-setup.sh` from `/root/scripts`

Useful commands:

```sh
/usr/local/sbin/network-priority.sh status
/usr/local/sbin/network-priority.sh once
/etc/init.d/S41network-priority restart
```

## Config Files

### `/etc/default/network-priority`

Controls:

- whether the policy service is enabled
- interface names
- Ethernet / Wi-Fi / LTE metrics
- whether LTE fallback is enabled

### `/etc/network-priority.wifi`

Stores Wi-Fi networks in this format:

```text
SSID|PSK|PRIORITY
```

Higher priority values are preferred by `wpa_supplicant`.

## Recommended First-boot Flow

```sh
cd /root/scripts
sh buildroot-manage.sh doctor
sh buildroot-manage.sh install
sh wifi-setup.sh
sh network-setup.sh
```
