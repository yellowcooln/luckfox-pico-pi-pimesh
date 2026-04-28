#!/bin/sh
set -eu

CONFIG_FILE=${NETWORK_PRIORITY_CONFIG:-/etc/default/network-priority}
LTE_INPUT_CHAIN="NETWORK_PRIORITY_LTE_INPUT"

log() {
  printf '%s\n' "$1"
}

load_config() {
  [ -f "$CONFIG_FILE" ] || {
    log "Missing config: $CONFIG_FILE"
    exit 1
  }
  # shellcheck disable=SC1090
  . "$CONFIG_FILE"
}

is_enabled() {
  [ "${ENABLED:-0}" = "1" ]
}

iface_exists() {
  [ -d "/sys/class/net/$1" ]
}

iface_has_ipv4() {
  ip -4 addr show dev "$1" 2>/dev/null | grep -q 'inet '
}

iface_has_default_route() {
  ip route show default dev "$1" 2>/dev/null | grep -q '^default '
}

wifi_connected() {
  iface_exists "${WIFI_INTERFACE}" || return 1
  command -v wpa_cli >/dev/null 2>&1 || return 1
  wpa_cli -i "${WIFI_INTERFACE}" status 2>/dev/null | grep -q '^wpa_state=COMPLETED$'
}

render_wpa_conf() {
  local tmp_file ssid psk priority

  [ "${ENABLE_WIFI:-1}" = "1" ] || return 0
  [ -f "${WIFI_NETWORKS_FILE}" ] || return 0

  tmp_file=$(mktemp)
  cat >"$tmp_file" <<EOF
ctrl_interface=/var/run/wpa_supplicant
update_config=1
country=${COUNTRY:-US}
EOF

  while IFS='|' read -r ssid psk priority; do
    case "${ssid}" in
      ''|'#'*) continue ;;
    esac
    [ -n "${psk:-}" ] || continue
    [ -n "${priority:-}" ] || priority=50
    cat >>"$tmp_file" <<EOF

network={
  ssid="${ssid}"
  psk="${psk}"
  key_mgmt=WPA-PSK
  priority=${priority}
}
EOF
  done < "${WIFI_NETWORKS_FILE}"

  install -m 0600 "$tmp_file" "${WPA_CONF:-/etc/wpa_supplicant.conf}"
  rm -f "$tmp_file"
}

ensure_wifi_started() {
  [ "${ENABLE_WIFI:-1}" = "1" ] || return 0
  iface_exists "${WIFI_INTERFACE}" || return 0
  [ -f "${WPA_CONF:-/etc/wpa_supplicant.conf}" ] || return 0
  /etc/init.d/S39wpa-client restart >/dev/null 2>&1 || true
}

trim_route_line() {
  printf '%s\n' "$1" | sed -E 's/[[:space:]]+$//'
}

route_without_metric() {
  trim_route_line "$1" | sed -E 's/ metric [0-9]+//g'
}

route_src_from_line() {
  printf '%s\n' "$1" | awk '{
    for (i = 1; i <= NF; i++) {
      if ($i == "src" && (i + 1) <= NF) {
        print $(i + 1)
        exit
      }
    }
  }'
}

iface_primary_ipv4() {
  ip -4 addr show dev "$1" 2>/dev/null | awk '/inet / { sub(/\/.*/, "", $2); print $2; exit }'
}

sync_default_routes() {
  local iface="$1"
  local metric="$2"
  local routes first_line stripped desired line line route_src

  routes=$(ip route show default dev "$iface" 2>/dev/null || true)
  [ -n "$routes" ] || return 0

  first_line=$(printf '%s\n' "$routes" | sed -n '1p')
  stripped=$(route_without_metric "$first_line")
  route_src=$(route_src_from_line "$first_line")
  [ -n "$route_src" ] || route_src=$(iface_primary_ipv4 "$iface")
  stripped=$(printf '%s\n' "$stripped" | sed -E 's/ src [0-9.]+//g')
  desired=$(trim_route_line "$stripped${route_src:+ src $route_src} metric $metric")

  printf '%s\n' "$routes" | while IFS= read -r line; do
    line=$(trim_route_line "$line")
    [ -n "$line" ] || continue
    ip route del $line >/dev/null 2>&1 || true
  done

  ip route replace $desired >/dev/null 2>&1 || true
  return 0
}

iface_is_usable_eth() {
  iface_exists "${ETH_INTERFACE}" || return 1
  iface_has_ipv4 "${ETH_INTERFACE}" || return 1
  iface_has_default_route "${ETH_INTERFACE}" || return 1
}

iface_is_usable_wifi() {
  [ "${ENABLE_WIFI:-1}" = "1" ] || return 1
  wifi_connected || return 1
  iface_has_ipv4 "${WIFI_INTERFACE}" || return 1
  iface_has_default_route "${WIFI_INTERFACE}" || return 1
}

collect_usable_lte_ifaces() {
  local lte_iface

  [ "${ENABLE_LTE_FALLBACK:-0}" = "1" ] || return 0
  for lte_iface in ${LTE_INTERFACES:-}; do
    iface_exists "$lte_iface" || continue
    iface_has_ipv4 "$lte_iface" || continue
    iface_has_default_route "$lte_iface" || continue
    printf '%s\n' "$lte_iface"
  done
}

collect_lte_firewall_ifaces() {
  local lte_iface

  for lte_iface in ${LTE_INTERFACES:-}; do
    iface_exists "$lte_iface" || continue
    iface_has_ipv4 "$lte_iface" || continue
    iface_has_default_route "$lte_iface" || continue
    printf '%s\n' "$lte_iface"
  done
}

iface_in_list() {
  local needle="$1"
  shift
  for iface in "$@"; do
    [ "$iface" = "$needle" ] && return 0
  done
  return 1
}

iptables_cmd() {
  command -v iptables >/dev/null 2>&1 || return 1
  printf '%s\n' "$(command -v iptables)"
}

ensure_lte_input_chain() {
  local ipt="$1"

  "$ipt" -nL "$LTE_INPUT_CHAIN" >/dev/null 2>&1 || "$ipt" -N "$LTE_INPUT_CHAIN"
  "$ipt" -F "$LTE_INPUT_CHAIN"
  if ! "$ipt" -A "$LTE_INPUT_CHAIN" -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT 2>/dev/null; then
    "$ipt" -A "$LTE_INPUT_CHAIN" -m state --state ESTABLISHED,RELATED -j ACCEPT
  fi
  "$ipt" -A "$LTE_INPUT_CHAIN" -j DROP
}

remove_lte_input_jumps() {
  local ipt="$1"
  local lte_iface

  for lte_iface in ${LTE_INTERFACES:-}; do
    while "$ipt" -C INPUT -i "$lte_iface" -j "$LTE_INPUT_CHAIN" >/dev/null 2>&1; do
      "$ipt" -D INPUT -i "$lte_iface" -j "$LTE_INPUT_CHAIN" >/dev/null 2>&1 || break
    done
  done
}

apply_lte_input_policy() {
  local ipt lte_iface

  ipt=$(iptables_cmd) || return 0

  remove_lte_input_jumps "$ipt"

  if [ "${BLOCK_LTE_INBOUND:-1}" != "1" ]; then
    "$ipt" -F "$LTE_INPUT_CHAIN" >/dev/null 2>&1 || true
    "$ipt" -X "$LTE_INPUT_CHAIN" >/dev/null 2>&1 || true
    return 0
  fi

  ensure_lte_input_chain "$ipt"

  while IFS= read -r lte_iface; do
    [ -n "$lte_iface" ] || continue
    "$ipt" -C INPUT -i "$lte_iface" -j "$LTE_INPUT_CHAIN" >/dev/null 2>&1 || \
      "$ipt" -I INPUT 1 -i "$lte_iface" -j "$LTE_INPUT_CHAIN"
  done <<EOF
$(collect_lte_firewall_ifaces)
EOF
}

apply_metrics() {
  local active_ifaces="" iface metric inactive_metric lte_iface
  local first_metric="${ETH_PRIORITY:-100}"
  local second_metric="${WIFI_PRIORITY:-200}"
  local third_metric="${LTE_PRIORITY:-300}"
  local fourth_metric=$((third_metric + 100))
  local inactive_metric=$((fourth_metric + 100))

  if iface_is_usable_eth; then
    active_ifaces="${ETH_INTERFACE}"
  fi

  if iface_is_usable_wifi; then
    if [ -n "$active_ifaces" ]; then
      active_ifaces="${active_ifaces} ${WIFI_INTERFACE}"
    else
      active_ifaces="${WIFI_INTERFACE}"
    fi
  fi

  while IFS= read -r lte_iface; do
    [ -n "$lte_iface" ] || continue
    if [ -n "$active_ifaces" ]; then
      active_ifaces="${active_ifaces} ${lte_iface}"
    else
      active_ifaces="${lte_iface}"
    fi
  done <<EOF
$(collect_usable_lte_ifaces)
EOF

  metric="$first_metric"
  for iface in $active_ifaces; do
    sync_default_routes "$iface" "$metric"
    if [ "$metric" -eq "$first_metric" ]; then
      metric="$second_metric"
    elif [ "$metric" -eq "$second_metric" ]; then
      metric="$third_metric"
    else
      metric=$((metric + 100))
    fi
  done

  for iface in "${ETH_INTERFACE}" "${WIFI_INTERFACE}" ${LTE_INTERFACES:-}; do
    iface_exists "$iface" || continue
    iface_has_default_route "$iface" || continue
    if iface_in_list "$iface" $active_ifaces; then
      continue
    fi
    sync_default_routes "$iface" "$inactive_metric"
  done
}

show_status() {
  local ipt

  load_config
  printf 'enabled=%s\n' "${ENABLED:-0}"
  printf 'eth=%s wifi=%s lte=%s\n' "${ETH_INTERFACE:-eth0}" "${WIFI_INTERFACE:-wlan0}" "${LTE_INTERFACES:-}"
  printf 'metrics eth=%s wifi=%s lte=%s\n' "${ETH_PRIORITY:-100}" "${WIFI_PRIORITY:-200}" "${LTE_PRIORITY:-300}"
  printf 'block_lte_inbound=%s\n' "${BLOCK_LTE_INBOUND:-1}"
  printf '\nCurrent default routes:\n'
  ip route show default 2>/dev/null || true
  printf '\nLink state:\n'
  for iface in "${ETH_INTERFACE:-eth0}" "${WIFI_INTERFACE:-wlan0}" ${LTE_INTERFACES:-}; do
    iface_exists "$iface" || continue
    printf '%s: ' "$iface"
    cat "/sys/class/net/$iface/operstate" 2>/dev/null || printf 'unknown'
    printf '\n'
  done
  ipt=$(iptables_cmd || true)
  if [ -n "${ipt:-}" ]; then
    printf '\nLTE inbound firewall:\n'
    "$ipt" -S INPUT 2>/dev/null | grep "$LTE_INPUT_CHAIN" || printf 'no LTE INPUT jump rules\n'
    "$ipt" -S "$LTE_INPUT_CHAIN" 2>/dev/null || true
  fi
}

run_once() {
  load_config
  apply_lte_input_policy
  is_enabled || return 0
  render_wpa_conf
  ensure_wifi_started
  apply_metrics
}

run_daemon() {
  load_config
  if [ "${BLOCK_LTE_INBOUND:-1}" != "1" ] && ! is_enabled; then
    exit 0
  fi
  while :; do
    run_once
    sleep "${CHECK_INTERVAL:-15}"
  done
}

case "${1:-}" in
  render-wifi)
    load_config
    render_wpa_conf
    ;;
  once)
    run_once
    ;;
  daemon)
    run_daemon
    ;;
  status)
    show_status
    ;;
  *)
    echo "Usage: $0 {render-wifi|once|daemon|status}"
    exit 1
    ;;
esac
