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

main() {
  local ssid psk priority scan_choice

  need_cmd python3
  need_cmd iw

  [ -d "/sys/class/net/$IFACE" ] || fail "Wi-Fi interface not found: $IFACE"

  info "Scanning for Wi-Fi networks on $IFACE..."
  show_scan || true
  printf '\n'

  scan_choice=$(prompt_value "SSID")
  [ -n "$scan_choice" ] || fail "SSID is required."
  ssid="$scan_choice"

  psk=${WIFI_PASSWORD:-}
  if [ -z "$psk" ]; then
    psk=$(prompt_secret "Wi-Fi password")
  fi
  [ -n "$psk" ] || fail "Wi-Fi password is required."

  priority=$(prompt_value "Priority" "100")
  [ -n "$priority" ] || priority=100

  set_network "$ssid" "$psk" "$priority"
  render_wpa
  restart_wifi

  info ""
  info "Saved Wi-Fi network: $ssid"
  show_status
}

case "${1:-}" in
  status)
    show_status
    ;;
  *)
    main
    ;;
esac
