#!/bin/sh
set -eu

CONFIG_FILE=${NETWORK_PRIORITY_CONFIG:-/etc/default/network-priority}
WIFI_NETWORKS_FILE=${WIFI_NETWORKS_FILE:-/etc/network-priority.wifi}
HELPER_DIR=${HELPER_DIR:-/opt/scripts}
NETWORK_PRIORITY_SH="${NETWORK_PRIORITY_SH:-/usr/local/sbin/network-priority.sh}"
WIFI_SETUP_SH="${HELPER_DIR}/wifi-setup.sh"

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

pause_return() {
  local tty_path="/dev/tty"

  if dialog_enabled; then
    dialog --title "Network Setup" --msgbox "Done.\n\nPress Enter to return to the menu." 7 44 >/dev/null 2>&1 || true
    return 0
  fi

  if [ -r "$tty_path" ] && [ -w "$tty_path" ]; then
    printf '\nPress Enter to return to the menu...' >"$tty_path"
    IFS= read -r _ <"$tty_path" || true
    printf '\n' >"$tty_path"
  else
    printf '\nPress Enter to return to the menu...'
    IFS= read -r _ || true
    printf '\n'
  fi
}

load_config() {
  [ -f "$CONFIG_FILE" ] || fail "Missing config: $CONFIG_FILE"
  # shellcheck disable=SC1090
  . "$CONFIG_FILE"
}

ensure_wifi_networks_file() {
  if [ ! -f "$WIFI_NETWORKS_FILE" ]; then
    mkdir -p "$(dirname "$WIFI_NETWORKS_FILE")"
    cat >"$WIFI_NETWORKS_FILE" <<'EOF'
# One Wi-Fi network per line:
#   SSID|PSK|PRIORITY
EOF
  fi
}

dialog_enabled() {
  [ -t 0 ] && [ -t 1 ] && command -v dialog >/dev/null 2>&1
}

dialog_input() {
  local title="$1"
  local prompt="$2"
  local default_value="${3:-}"
  local tmp
  tmp=$(mktemp)
  if dialog --stdout --title "$title" --inputbox "$prompt" 10 60 "$default_value" >"$tmp"; then
    cat "$tmp"
    rm -f "$tmp"
    return 0
  fi
  rm -f "$tmp"
  return 1
}

dialog_password() {
  local title="$1"
  local prompt="$2"
  local tmp
  tmp=$(mktemp)
  if dialog --stdout --title "$title" --insecure --passwordbox "$prompt" 10 60 >"$tmp"; then
    cat "$tmp"
    rm -f "$tmp"
    return 0
  fi
  rm -f "$tmp"
  return 1
}

prompt_value() {
  local prompt="$1"
  local default_value="${2:-}"
  local reply

  if dialog_enabled; then
    dialog_input "Network Setup" "$prompt" "$default_value" || return 1
    return 0
  fi

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

  if dialog_enabled; then
    dialog_password "Network Setup" "$prompt" || return 1
    return 0
  fi

  python3 - "$prompt" <<'PY'
import os
import sys
import termios
import tty

prompt = sys.argv[1]
tty_fd = os.open("/dev/tty", os.O_RDWR)
os.write(tty_fd, f"{prompt}: ".encode())
original = termios.tcgetattr(tty_fd)
chars = []
try:
    tty.setraw(tty_fd)
    while True:
        ch = os.read(tty_fd, 1)
        if ch in (b"\r", b"\n"):
            os.write(tty_fd, b"\r\n")
            break
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
    os.close(tty_fd)

print("".join(chars))
PY
}

confirm_yes_no() {
  local prompt="$1"
  local answer

  if dialog_enabled; then
    dialog --title "Network Setup" --yesno "$prompt" 8 60
    return $?
  fi

  printf '%s [y/N]: ' "$prompt" >&2
  IFS= read -r answer || true
  case "${answer:-}" in
    y|Y|yes|YES) return 0 ;;
    *) return 1 ;;
  esac
}

set_config_value() {
  local key="$1"
  local value="$2"
  local tmp
  tmp=$(mktemp)
  python3 - "$CONFIG_FILE" "$key" "$value" <<'PY' >"$tmp"
import re
import sys

path, key, value = sys.argv[1:4]
pattern = re.compile(rf"^{re.escape(key)}=")
lines = []
found = False
with open(path, "r", encoding="utf-8") as fh:
    for raw in fh:
        if pattern.match(raw):
            lines.append(f'{key}="{value}"\n' if " " in value else f'{key}={value}\n')
            found = True
        else:
            lines.append(raw)
if not found:
    lines.append(f'{key}="{value}"\n' if " " in value else f'{key}={value}\n')
sys.stdout.writelines(lines)
PY
  install -m 0644 "$tmp" "$CONFIG_FILE"
  rm -f "$tmp"
}

list_wifi_networks() {
  ensure_wifi_networks_file
  awk -F'|' '
    /^[[:space:]]*#/ || NF == 0 { next }
    {
      printf "%-3d %-30s priority=%s\n", ++n, $1, ($3 ? $3 : "50")
    }
    END {
      if (n == 0) {
        print "No Wi-Fi networks saved."
      }
    }
  ' "$WIFI_NETWORKS_FILE"
}

add_wifi_network() {
  [ -x "$WIFI_SETUP_SH" ] || fail "Missing helper: $WIFI_SETUP_SH"
  "$WIFI_SETUP_SH"
}

edit_wifi_network() {
  [ -x "$WIFI_SETUP_SH" ] || fail "Missing helper: $WIFI_SETUP_SH"
  "$WIFI_SETUP_SH" edit
}

remove_wifi_network() {
  local selection ssid tmp

  ensure_wifi_networks_file
  list_wifi_networks
  selection=$(prompt_value "SSID to remove")
  [ -n "$selection" ] || return 0

  tmp=$(mktemp)
  awk -F'|' -v ssid="$selection" '
    /^[[:space:]]*#/ || NF == 0 { print; next }
    $1 == ssid { next }
    { print }
  ' "$WIFI_NETWORKS_FILE" >"$tmp"
  install -m 0600 "$tmp" "$WIFI_NETWORKS_FILE"
  rm -f "$tmp"
  info "Removed Wi-Fi network: $selection"
}

show_iface_ipv4_summary() {
  local iface="$1"
  local addrs addr_count

  addrs=$(ip -4 -o addr show dev "$iface" 2>/dev/null | awk '{print $4}' | paste -sd ' ' -)
  [ -n "$addrs" ] || return 0
  printf '%s ipv4: %s\n' "$iface" "$addrs"

  addr_count=$(printf '%s\n' "$addrs" | wc -w | tr -d ' ')
  if [ "${addr_count:-0}" -gt 1 ]; then
    printf 'warning: %s has multiple IPv4 addresses\n' "$iface"
  fi
}

configure_policy() {
  local enabled wifi_enabled lte_enabled block_lte_inbound eth_prio wifi_prio lte_prio

  load_config

  if confirm_yes_no "Enable network priority service?"; then
    enabled=1
  else
    enabled=0
  fi
  if confirm_yes_no "Enable Wi-Fi management?"; then
    wifi_enabled=1
  else
    wifi_enabled=0
  fi
  if confirm_yes_no "Enable LTE fallback?"; then
    lte_enabled=1
  else
    lte_enabled=0
  fi
  if confirm_yes_no "Block new inbound connections on LTE interfaces?"; then
    block_lte_inbound=1
  else
    block_lte_inbound=0
  fi

  eth_prio=$(prompt_value "Ethernet priority metric" "${ETH_PRIORITY:-100}") || return 0
  wifi_prio=$(prompt_value "Wi-Fi priority metric" "${WIFI_PRIORITY:-200}") || return 0
  lte_prio=$(prompt_value "LTE priority metric" "${LTE_PRIORITY:-300}") || return 0

  set_config_value ENABLED "$enabled"
  set_config_value ENABLE_WIFI "$wifi_enabled"
  set_config_value ENABLE_LTE_FALLBACK "$lte_enabled"
  set_config_value BLOCK_LTE_INBOUND "$block_lte_inbound"
  set_config_value ETH_PRIORITY "$eth_prio"
  set_config_value WIFI_PRIORITY "$wifi_prio"
  set_config_value LTE_PRIORITY "$lte_prio"

  info "Saved network priority policy."
}

apply_now() {
  [ -x "$NETWORK_PRIORITY_SH" ] || fail "Missing helper: $NETWORK_PRIORITY_SH"
  "$NETWORK_PRIORITY_SH" once
  /etc/init.d/S41network-priority restart >/dev/null 2>&1 || true
  info "Applied network policy."
}

show_status() {
  [ -x "$NETWORK_PRIORITY_SH" ] || fail "Missing helper: $NETWORK_PRIORITY_SH"
  "$NETWORK_PRIORITY_SH" status
  printf '\nIPv4 addresses:\n'
  load_config
  for iface in "${ETH_INTERFACE:-eth0}" "${WIFI_INTERFACE:-wlan0}" ${LTE_INTERFACES:-}; do
    iface_exists "$iface" || continue
    show_iface_ipv4_summary "$iface"
  done
  printf '\nSaved Wi-Fi networks:\n'
  list_wifi_networks
}

main_menu() {
  local choice
  local action_ok

  while :; do
    if dialog_enabled; then
      choice=$(dialog --stdout --title "Network Setup" --menu "Choose an action" 18 72 8 \
        status "Show current network status" \
        policy "Configure Ethernet/Wi-Fi/LTE priority policy" \
        add-wifi "Add or update a Wi-Fi network" \
        edit-wifi "Edit a saved Wi-Fi network" \
        remove-wifi "Remove a saved Wi-Fi network" \
        list-wifi "List saved Wi-Fi networks" \
        apply "Render config and apply policy now" \
        exit "Exit network setup") || break
    else
      cat <<'EOF'
1) Show current network status
2) Configure Ethernet/Wi-Fi/LTE priority policy
3) Add or update a Wi-Fi network
4) Edit a saved Wi-Fi network
5) Remove a saved Wi-Fi network
6) List saved Wi-Fi networks
7) Render config and apply policy now
8) Exit
EOF
      choice=$(prompt_value "Selection" "8") || break
      case "$choice" in
        1) choice=status ;;
        2) choice=policy ;;
        3) choice=add-wifi ;;
        4) choice=edit-wifi ;;
        5) choice=remove-wifi ;;
        6) choice=list-wifi ;;
        7) choice=apply ;;
        *) choice=exit ;;
      esac
    fi

    action_ok=1
    case "$choice" in
      status)
        if ! show_status; then
          action_ok=0
        fi
        ;;
      policy)
        if ! configure_policy; then
          action_ok=0
        fi
        ;;
      add-wifi)
        if ! add_wifi_network; then
          action_ok=0
        fi
        ;;
      edit-wifi)
        if ! edit_wifi_network; then
          action_ok=0
        fi
        ;;
      remove-wifi)
        if ! remove_wifi_network; then
          action_ok=0
        fi
        ;;
      list-wifi)
        if ! list_wifi_networks; then
          action_ok=0
        fi
        ;;
      apply)
        if ! apply_now; then
          action_ok=0
        fi
        ;;
      exit)
        break
        ;;
    esac

    if [ "$action_ok" -ne 1 ]; then
      printf '\nAction failed.\n' >&2
    fi
    pause_return
  done
}

case "${1:-menu}" in
  status)
    show_status
    ;;
  policy)
    configure_policy
    ;;
  add-wifi)
    add_wifi_network
    ;;
  edit-wifi)
    edit_wifi_network
    ;;
  remove-wifi)
    remove_wifi_network
    ;;
  list-wifi)
    list_wifi_networks
    ;;
  apply)
    apply_now
    ;;
  menu)
    main_menu
    ;;
  *)
    echo "Usage: $0 {menu|status|policy|add-wifi|edit-wifi|remove-wifi|list-wifi|apply}"
    exit 1
    ;;
esac
