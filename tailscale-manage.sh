#!/bin/sh
set -eu

TAILSCALE_TRACK="${TAILSCALE_TRACK:-stable}"
TAILSCALE_VERSION="${TAILSCALE_VERSION:-latest}"
INSTALL_BASE="${INSTALL_BASE:-/opt/tailscale}"
STATE_DIR="${STATE_DIR:-/var/lib/tailscale}"
LOG_DIR="${LOG_DIR:-/var/log/tailscale}"
RUN_DIR="${RUN_DIR:-/var/run}"
PIDFILE="${RUN_DIR}/tailscaled.pid"
LOGFILE="${LOG_DIR}/tailscaled.log"
SERVICE_SCRIPT="${SERVICE_SCRIPT:-/etc/init.d/S85tailscaled}"
FLAGS_FILE="${FLAGS_FILE:-/etc/default/tailscaled}"
TS_USERSPACE="${TS_USERSPACE:-0}"
TS_SOCKET="${TS_SOCKET:-${RUN_DIR}/tailscale/tailscaled.sock}"

stage() {
  printf '\n==> %s\n' "$1"
}

info() {
  printf '  - %s\n' "$1"
}

fail() {
  printf '%s\n' "$1" >&2
  exit 1
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || fail "Missing required command: $1"
}

ensure_root() {
  [ "$(id -u 2>/dev/null || echo 1)" = "0" ] || fail "This command must be run as root."
}

detect_arch() {
  case "$(uname -m)" in
    armv7*|armv6*|armhf|arm)
      printf '%s\n' arm
      ;;
    aarch64|arm64)
      printf '%s\n' arm64
      ;;
    x86_64|amd64)
      printf '%s\n' amd64
      ;;
    i?86)
      printf '%s\n' 386
      ;;
    *)
      fail "Unsupported architecture: $(uname -m)"
      ;;
  esac
}

fetch_url() {
  url="$1"
  if command -v wget >/dev/null 2>&1; then
    wget -4 -qO- "$url"
  elif command -v curl >/dev/null 2>&1; then
    curl -4 -fsSL "$url"
  else
    fail "Missing wget or curl"
  fi
}

download_file() {
  url="$1"
  dest="$2"
  if command -v wget >/dev/null 2>&1; then
    wget -4 -O "$dest" "$url"
  elif command -v curl >/dev/null 2>&1; then
    curl -4 -fL "$url" -o "$dest"
  else
    fail "Missing wget or curl"
  fi
}

verify_checksum() {
  archive_path="$1"
  checksum_path="$2"

  expected=$(tr -d ' \t\r\n' < "$checksum_path")
  [ -n "$expected" ] || fail "Downloaded checksum file is empty."

  actual=$(sha256sum "$archive_path" | awk '{print $1}')
  [ "$actual" = "$expected" ] || fail "SHA256 checksum mismatch for $(basename "$archive_path")."
}

resolve_version() {
  arch="$1"
  if [ "$TAILSCALE_VERSION" != "latest" ]; then
    printf '%s\n' "$TAILSCALE_VERSION"
    return 0
  fi

  fetch_url "https://pkgs.tailscale.com/${TAILSCALE_TRACK}/" \
    | sed -n "s/.*tailscale_\\([0-9][0-9.]*\\)_${arch}\\.tgz.*/\\1/p" \
    | head -n 1
}

version_dir() {
  printf '%s\n' "${INSTALL_BASE}/$1"
}

current_dir() {
  if [ -L "${INSTALL_BASE}/current" ]; then
    readlink "${INSTALL_BASE}/current"
  else
    printf '%s\n' ""
  fi
}

current_version() {
  dir=$(current_dir)
  [ -n "$dir" ] || return 1
  basename "$dir"
}

tailscale_bin() {
  printf '%s\n' "${INSTALL_BASE}/current/tailscale"
}

tailscaled_bin() {
  printf '%s\n' "${INSTALL_BASE}/current/tailscaled"
}

is_installed() {
  [ -x "$(tailscale_bin)" ] && [ -x "$(tailscaled_bin)" ]
}

is_running() {
  [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null
}

get_default_flags() {
  if [ "$TS_USERSPACE" = "1" ]; then
    printf '%s\n' "--tun=userspace-networking --socks5-server=127.0.0.1:1055 --state=${STATE_DIR}/tailscaled.state --socket=${TS_SOCKET}"
  else
    printf '%s\n' "--state=${STATE_DIR}/tailscaled.state --socket=${TS_SOCKET}"
  fi
}

write_flags_file() {
  mkdir -p "$(dirname "$FLAGS_FILE")"
  cat > "$FLAGS_FILE" <<EOF
TAILSCALED_FLAGS="${TAILSCALED_FLAGS:-$(get_default_flags)}"
EOF
}

write_service_script() {
  cat > "$SERVICE_SCRIPT" <<'EOF'
#!/bin/sh
PIDFILE="__PIDFILE__"
LOGFILE="__LOGFILE__"
STATE_DIR="__STATE_DIR__"
RUN_DIR="__RUN_DIR__"
TAILSCALED_BIN="__TAILSCALED_BIN__"
FLAGS_FILE="__FLAGS_FILE__"
SERVICE_NAME="tailscaled"

[ -f "$FLAGS_FILE" ] && . "$FLAGS_FILE"
TAILSCALED_FLAGS="${TAILSCALED_FLAGS:-__DEFAULT_FLAGS__}"

start() {
  mkdir -p "$STATE_DIR" "$(dirname "$PIDFILE")" "$(dirname "$LOGFILE")" "$RUN_DIR/tailscale"
  if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
    echo "$SERVICE_NAME is already running."
    return 0
  fi
  start-stop-daemon --start --quiet --background --make-pidfile --pidfile "$PIDFILE" \
    --exec "$TAILSCALED_BIN" -- $TAILSCALED_FLAGS >>"$LOGFILE" 2>&1
}

stop() {
  if [ ! -f "$PIDFILE" ]; then
    echo "$SERVICE_NAME is not running."
    return 0
  fi
  start-stop-daemon --stop --quiet --retry 5 --pidfile "$PIDFILE" >/dev/null 2>&1 || true
  rm -f "$PIDFILE"
}

status() {
  if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
    echo "$SERVICE_NAME is running."
    return 0
  fi
  echo "$SERVICE_NAME is stopped."
  return 1
}

case "${1:-}" in
  start) start ;;
  stop) stop ;;
  restart) stop; start ;;
  status) status ;;
  *)
    echo "Usage: $0 {start|stop|restart|status}"
    exit 1
    ;;
esac
EOF

  sed -i \
    -e "s|__PIDFILE__|${PIDFILE}|g" \
    -e "s|__LOGFILE__|${LOGFILE}|g" \
    -e "s|__STATE_DIR__|${STATE_DIR}|g" \
    -e "s|__RUN_DIR__|${RUN_DIR}|g" \
    -e "s|__TAILSCALED_BIN__|$(tailscaled_bin)|g" \
    -e "s|__FLAGS_FILE__|${FLAGS_FILE}|g" \
    -e "s|__DEFAULT_FLAGS__|$(get_default_flags | sed 's/[&|]/\\\\&/g')|g" \
    "$SERVICE_SCRIPT"
  chmod 0755 "$SERVICE_SCRIPT"
}

install_tailscale() {
  ensure_root
  need_cmd tar
  need_cmd sha256sum
  need_cmd gzip
  arch=$(detect_arch)
  version=$(resolve_version "$arch")
  [ -n "$version" ] || fail "Could not resolve Tailscale version for arch ${arch}"

  target_dir=$(version_dir "$version")
  archive="tailscale_${version}_${arch}.tgz"
  url="https://pkgs.tailscale.com/${TAILSCALE_TRACK}/${archive}"
  checksum_url="${url}.sha256"
  tmpdir=$(mktemp -d)
  trap 'rm -rf "$tmpdir"' EXIT INT TERM

  stage "Downloading Tailscale ${version}"
  download_file "$url" "${tmpdir}/${archive}"
  download_file "$checksum_url" "${tmpdir}/${archive}.sha256"
  verify_checksum "${tmpdir}/${archive}" "${tmpdir}/${archive}.sha256"

  stage "Installing Tailscale ${version}"
  mkdir -p "$INSTALL_BASE" "$STATE_DIR" "$LOG_DIR" "$RUN_DIR/tailscale"
  rm -rf "$target_dir"
  mkdir -p "$target_dir"
  gzip -dc "${tmpdir}/${archive}" | tar xvf - -C "$target_dir" --strip-components=1 >/dev/null
  ln -snf "$target_dir" "${INSTALL_BASE}/current"
  ln -snf "$(tailscale_bin)" /usr/local/bin/tailscale
  ln -snf "$(tailscaled_bin)" /usr/local/bin/tailscaled
  write_flags_file
  write_service_script

  info "installed version ${version}"
}

show_version() {
  if is_installed; then
    "$(tailscale_bin)" version || true
  else
    fail "Tailscale is not installed."
  fi
}

service_action() {
  ensure_root
  is_installed || fail "Tailscale is not installed."
  "$SERVICE_SCRIPT" "$1"
}

ts_cli() {
  is_installed || fail "Tailscale is not installed."
  "$(tailscale_bin)" --socket="$TS_SOCKET" "$@"
}

upgrade_tailscale() {
  ensure_root
  was_running=0
  if is_running; then
    was_running=1
    "$SERVICE_SCRIPT" stop
  fi

  old_version=$(current_version || true)
  install_tailscale
  new_version=$(current_version || true)

  if [ "$was_running" = "1" ]; then
    "$SERVICE_SCRIPT" start
  fi

  info "upgraded from ${old_version:-none} to ${new_version:-unknown}"
}

show_status() {
  if ! is_installed; then
    printf 'Installation Status: Not Installed\n'
    return 0
  fi

  printf 'Install Directory: %s\n' "$(current_dir)"
  printf 'State Directory: %s\n' "$STATE_DIR"
  printf 'Socket: %s\n' "$TS_SOCKET"
  if is_running; then
    printf 'Service Status: Running\n'
  else
    printf 'Service Status: Stopped\n'
  fi
  ts_cli status || true
}

show_logs() {
  mkdir -p "$LOG_DIR"
  touch "$LOGFILE"
  tail -f "$LOGFILE"
}

uninstall_tailscale() {
  ensure_root
  is_running && "$SERVICE_SCRIPT" stop || true
  rm -f "$SERVICE_SCRIPT" /usr/local/bin/tailscale /usr/local/bin/tailscaled "$FLAGS_FILE"
  rm -rf "$INSTALL_BASE"
}

usage() {
  cat <<'EOF'
Usage: sh tailscale-manage.sh <command>

Commands:
  install     Download and install the official Tailscale static binaries
  start       Start tailscaled via /etc/init.d/S85tailscaled
  stop        Stop tailscaled
  restart     Restart tailscaled
  status      Show service and tailscale status
  up          Run tailscale up with any extra flags you pass through
  down        Run tailscale down
  logs        Tail the tailscaled log file
  version     Show installed tailscale version
  upgrade     Stop, replace with newest stable tarball, and start again
  uninstall   Remove Tailscale binaries and init script

Environment:
  TAILSCALE_TRACK=stable|unstable
  TAILSCALE_VERSION=latest|<version>
  TS_USERSPACE=1 to default the service to userspace networking mode
  TAILSCALED_FLAGS="..." to override daemon flags in /etc/default/tailscaled
EOF
}

cmd="${1:-}"
case "$cmd" in
  install)
    install_tailscale
    ;;
  start|stop|restart)
    service_action "$cmd"
    ;;
  status)
    show_status
    ;;
  up)
    shift
    ts_cli up "$@"
    ;;
  down)
    shift
    ts_cli down "$@"
    ;;
  logs)
    show_logs
    ;;
  version)
    show_version
    ;;
  upgrade)
    upgrade_tailscale
    ;;
  uninstall)
    uninstall_tailscale
    ;;
  ""|help|-h|--help)
    usage
    ;;
  *)
    fail "Unknown command: $cmd"
    ;;
esac
