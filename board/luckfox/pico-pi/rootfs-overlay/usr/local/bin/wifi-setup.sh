#!/bin/sh
set -eu

IFACE="${WIFI_IFACE:-wlan0}"
NETWORKS_FILE="${WIFI_NETWORKS_FILE:-/etc/network-priority.wifi}"
WPA_CONF="${WPA_CONF:-/etc/wpa_supplicant.conf}"
NETWORK_PRIORITY_CONFIG="${NETWORK_PRIORITY_CONFIG:-/etc/default/network-priority}"

info() {
  printf '%s\n' "$1"
}

fail() {
  printf '%s\n' "$1" >&2
  exit 1
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || fail "Missing required command: $1"
}

get_default_wifi_priority() {
  local default_priority="200"

  if [ -f "$NETWORK_PRIORITY_CONFIG" ]; then
    # shellcheck disable=SC1090
    . "$NETWORK_PRIORITY_CONFIG"
    printf '%s\n' "${WIFI_PRIORITY:-$default_priority}"
    return 0
  fi

  printf '%s\n' "$default_priority"
}

prompt_value() {
  local prompt="$1"
  local default_value="${2:-}"
  local reply=""

  if [ -n "$default_value" ]; then
    printf '%s [%s]: ' "$prompt" "$default_value" >&2
  else
    printf '%s: ' "$prompt" >&2
  fi
  IFS= read -r reply || true
  reply=${reply:-$default_value}
  printf '%s\n' "$reply"
}

get_network_field() {
  local ssid="$1"
  local field_index="$2"

  ensure_networks_file
  awk -F'|' -v ssid="$ssid" -v field_index="$field_index" '
    /^[[:space:]]*#/ || NF == 0 { next }
    $1 == ssid { print $field_index; exit }
  ' "$NETWORKS_FILE"
}

prompt_secret() {
  local prompt="$1"

  python3 - "$prompt" <<'PY'
import os
import sys
import termios
import tty

prompt = sys.argv[1]
tty_fd = os.open("/dev/tty", os.O_RDWR)

def read_secret(label: str) -> str:
    os.write(tty_fd, f"{label}: ".encode())
    original = termios.tcgetattr(tty_fd)
    chars = []
    try:
        tty.setraw(tty_fd)
        while True:
            ch = os.read(tty_fd, 1)
            if ch in (b"\r", b"\n"):
                os.write(tty_fd, b"\r\n")
                return "".join(chars)
            if ch == b"\x03":
                raise KeyboardInterrupt
            if ch in (b"\x7f", b"\x08"):
                if chars:
                    chars.pop()
                    os.write(tty_fd, b"\b \b")
                continue
            if not ch or ch[0] < 32:
                continue
            chars.append(ch.decode(errors="ignore"))
            os.write(tty_fd, b"*")
    finally:
        termios.tcsetattr(tty_fd, termios.TCSADRAIN, original)

value = read_secret(prompt)
print(value)
os.close(tty_fd)
PY
}

ensure_networks_file() {
  if [ ! -f "$NETWORKS_FILE" ]; then
    mkdir -p "$(dirname "$NETWORKS_FILE")"
    cat >"$NETWORKS_FILE" <<'EOF'
# One Wi-Fi network per line:
#   SSID|PSK|PRIORITY
EOF
  fi
}

show_scan() {
  need_cmd iw
  ip link set "$IFACE" up >/dev/null 2>&1 || true
  iw dev "$IFACE" scan 2>/dev/null | awk '
    /signal:/ { signal=$2 " " $3 }
    /SSID:/ {
      ssid=substr($0, index($0, ":") + 2)
      if (ssid != "") {
        printf "%-32s %s\n", ssid, signal
      }
    }
  ' | awk '!seen[$0]++'
}

choose_ssid_entry_mode() {
  local choice

  info "Built-in Luckfox Wi-Fi is 2.4 GHz only." >&2
  info "" >&2
  info "1) Scan for nearby SSIDs" >&2
  info "2) Enter SSID manually" >&2
  choice=$(prompt_value "Selection" "1")
  case "$choice" in
    2) printf '%s\n' "manual" ;;
    *) printf '%s\n' "scan" ;;
  esac
}

prompt_ssid_from_user() {
  local mode="$1"
  local default_ssid="${2:-}"
  local ssid=""

  case "$mode" in
    scan)
      info "Scanning for 2.4 GHz Wi-Fi networks on $IFACE..." >&2
      show_scan >&2 || true
      printf '\n' >&2
      ssid=$(prompt_value "SSID" "$default_ssid")
      ;;
    manual)
      info "Manual SSID entry selected." >&2
      ssid=$(prompt_value "SSID" "$default_ssid")
      ;;
    *)
      ssid=$(prompt_value "SSID" "$default_ssid")
      ;;
  esac

  printf '%s\n' "$ssid"
}

set_network() {
  local ssid="$1"
  local psk="$2"
  local priority="$3"
  local tmp_file

  ensure_networks_file
  tmp_file=$(mktemp)
  awk -F'|' -v ssid="$ssid" '
    BEGIN { written = 0 }
    /^[[:space:]]*#/ || NF == 0 { print; next }
    $1 == ssid { next }
    { print }
    END { }
  ' "$NETWORKS_FILE" >"$tmp_file"
  printf '%s|%s|%s\n' "$ssid" "$psk" "$priority" >>"$tmp_file"
  install -m 0600 "$tmp_file" "$NETWORKS_FILE"
  rm -f "$tmp_file"
}

remove_network() {
  local ssid="$1"
  local tmp_file

  ensure_networks_file
  tmp_file=$(mktemp)
  awk -F'|' -v ssid="$ssid" '
    /^[[:space:]]*#/ || NF == 0 { print; next }
    $1 == ssid { next }
    { print }
  ' "$NETWORKS_FILE" >"$tmp_file"
  install -m 0600 "$tmp_file" "$NETWORKS_FILE"
  rm -f "$tmp_file"
}

render_wpa() {
  if [ -x /usr/local/sbin/network-priority.sh ]; then
    NETWORK_PRIORITY_CONFIG="$NETWORK_PRIORITY_CONFIG" \
      /usr/local/sbin/network-priority.sh render-wifi
    return 0
  fi

  python3 - "$NETWORKS_FILE" "$WPA_CONF" <<'PY'
import sys

src, dst = sys.argv[1:3]
entries = []
with open(src, "r", encoding="utf-8") as fh:
    for raw in fh:
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        parts = line.split("|")
        if len(parts) < 2:
            continue
        ssid, psk = parts[0], parts[1]
        priority = parts[2] if len(parts) > 2 and parts[2] else "50"
        entries.append((ssid, psk, priority))

with open(dst, "w", encoding="utf-8") as fh:
    fh.write("ctrl_interface=/var/run/wpa_supplicant\n")
    fh.write("update_config=1\n")
    fh.write("country=US\n")
    for ssid, psk, priority in entries:
        fh.write("\nnetwork={\n")
        fh.write(f'  ssid="{ssid}"\n')
        fh.write(f'  psk="{psk}"\n')
        fh.write("  key_mgmt=WPA-PSK\n")
        fh.write(f"  priority={priority}\n")
        fh.write("}\n")
PY
}

restart_wifi() {
  /etc/init.d/S39wpa-client restart >/dev/null 2>&1 || true
  sleep 2
}

show_status() {
  info "Interface: $IFACE"
  ip -4 addr show dev "$IFACE" 2>/dev/null || true
  if command -v wpa_cli >/dev/null 2>&1; then
    printf '\n'
    wpa_cli -i "$IFACE" status 2>/dev/null || true
  fi
}

add_or_update_network() {
  local ssid psk priority mode

  need_cmd python3
  need_cmd iw

  [ -d "/sys/class/net/$IFACE" ] || fail "Wi-Fi interface not found: $IFACE"

  mode=$(choose_ssid_entry_mode)
  ssid=$(prompt_ssid_from_user "$mode")
  [ -n "$ssid" ] || fail "SSID is required."

  psk=${WIFI_PASSWORD:-}
  if [ -z "$psk" ]; then
    psk=$(prompt_secret "Wi-Fi password")
  fi
  [ -n "$psk" ] || fail "Wi-Fi password is required."

  priority=$(prompt_value "Wi-Fi Priority" "$(get_default_wifi_priority)")
  [ -n "$priority" ] || priority="$(get_default_wifi_priority)"

  set_network "$ssid" "$psk" "$priority"
  render_wpa
  restart_wifi

  info ""
  info "Saved Wi-Fi network: $ssid"
  show_status
}

edit_network() {
  local current_ssid ssid psk priority mode

  need_cmd python3
  need_cmd iw
  ensure_networks_file

  info "Saved Wi-Fi networks:"
  awk -F'|' '
    /^[[:space:]]*#/ || NF == 0 { next }
    { printf "  - %s (priority=%s)\n", $1, ($3 ? $3 : "50") }
  ' "$NETWORKS_FILE"
  printf '\n'

  current_ssid=$(prompt_value "SSID to edit")
  [ -n "$current_ssid" ] || return 0

  if [ -z "$(get_network_field "$current_ssid" 1)" ]; then
    fail "Saved Wi-Fi network not found: $current_ssid"
  fi

  mode=$(choose_ssid_entry_mode)
  ssid=$(prompt_ssid_from_user "$mode" "$current_ssid")
  [ -n "$ssid" ] || fail "SSID is required."

  psk=$(prompt_secret "Wi-Fi password for $ssid")
  [ -n "$psk" ] || fail "Wi-Fi password is required."

  priority=$(prompt_value "Wi-Fi Priority" "$(get_network_field "$current_ssid" 3)")
  [ -n "$priority" ] || priority="$(get_default_wifi_priority)"

  if [ "$ssid" != "$current_ssid" ]; then
    remove_network "$current_ssid"
  fi
  set_network "$ssid" "$psk" "$priority"

  render_wpa
  restart_wifi

  info ""
  info "Updated Wi-Fi network: $ssid"
  show_status
}

case "${1:-}" in
  status)
    show_status
    ;;
  edit)
    edit_network
    ;;
  *)
    add_or_update_network
    ;;
esac
