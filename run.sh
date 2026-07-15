#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-up}"
if [[ "$MODE" == "--command" || "$MODE" == "--commend" ]]; then
  shift || true
  MODE="${1:-up}"
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOME_DIR="${HOME:-$PWD}"

HERMES_REPO_URL="${HERMES_REPO_URL:-https://github.com/NousResearch/hermes-agent.git}"
HERMES_REF="${HERMES_REF:-main}"
HERMES_REPO="${HERMES_REPO:-$SCRIPT_DIR/hermes-agent}"
HERMES_VENV="${HERMES_VENV:-$HERMES_REPO/venv}"
HERMES_PY="${HERMES_PY:-$HERMES_VENV/bin/python}"
HERMES_HOME="${HERMES_HOME:-$HOME_DIR/.hermes}"
HERMES_ENV="${HERMES_ENV:-$HERMES_HOME/.env}"
HERMES_LOG_DIR="${HERMES_LOG_DIR:-$HERMES_HOME/logs}"
HERMES_BOOTSTRAP_LOG="$HERMES_LOG_DIR/gateway-bootstrap.log"
HERMES_API_HEALTH_URL="${HERMES_API_HEALTH_URL:-http://127.0.0.1:8642/health}"
HERMES_API_BASE_URL="${HERMES_API_BASE_URL:-http://host.docker.internal:8642/v1}"

OPENWEBUI_IMAGE="${OPENWEBUI_IMAGE:-ghcr.io/open-webui/open-webui:main}"
OPENWEBUI_CONTAINER="${OPENWEBUI_CONTAINER:-open-webui}"
OPENWEBUI_VOLUME="${OPENWEBUI_VOLUME:-open-webui}"
OPENWEBUI_LOCAL_URL="${OPENWEBUI_LOCAL_URL:-http://127.0.0.1:3000}"
OPENWEBUI_HOST_PORT="${OPENWEBUI_HOST_PORT:-3000}"
OPENWEBUI_CONTAINER_PORT="${OPENWEBUI_CONTAINER_PORT:-8080}"

TS_ROOT="${TS_ROOT:-$HOME_DIR/.local/tailscale}"
TS_HOSTNAME="${TS_HOSTNAME:-agx-openwebui}"
TS_SERVE_PORT="${TS_SERVE_PORT:-3000}"
TS_STATUS_TIMEOUT="${TS_STATUS_TIMEOUT:-5}"
TS_SOCKET="${TS_SOCKET:-$TS_ROOT/tailscaled.sock}"
TS_STATE_DIR="$TS_ROOT/state"
TS_STATE="$TS_STATE_DIR/tailscaled.state"
TS_LOG="$TS_ROOT/tailscaled.log"
TS_PID_FILE="$TS_ROOT/tailscaled.pid"
TS_DIR="$(find "$TS_ROOT" -maxdepth 1 -type d -name 'tailscale_*' 2>/dev/null | sort | tail -n 1 || true)"
TS_BIN="${TS_BIN:-${TS_DIR:+$TS_DIR/tailscale}}"
TSD_BIN="${TSD_BIN:-${TS_DIR:+$TS_DIR/tailscaled}}"

NGROK_PORT="${NGROK_PORT:-3000}"
NGROK_LOG="${NGROK_LOG:-$HERMES_LOG_DIR/ngrok-openwebui.log}"

AUTOSTART_DIR="$HOME_DIR/.config/autostart"
AUTOSTART_FILE="$AUTOSTART_DIR/hermes-openwebui-tailscale.desktop"
USER_BIN_DIR="$HOME_DIR/.local/bin"
HERMES_CLI_WRAPPER="$USER_BIN_DIR/hermes"

GREEN=$'\033[32m'; YELLOW=$'\033[33m'; RED=$'\033[31m'; BLUE=$'\033[34m'; NC=$'\033[0m'
step() { printf '%b[STEP]%b %s\n' "$BLUE" "$NC" "$1"; }
ok() { printf '%b[ OK ]%b %s\n' "$GREEN" "$NC" "$1"; }
warn() { printf '%b[WARN]%b %s\n' "$YELLOW" "$NC" "$1"; }
fail() { printf '%b[FAIL]%b %s\n' "$RED" "$NC" "$1"; exit 1; }
have() { command -v "$1" >/dev/null 2>&1; }
require_command() { have "$1" || fail "$1 not found in PATH"; }

json_field() {
  local path="$1"
  python3 -c 'import json,sys
parts=[p for p in sys.argv[1].split(".") if p]
obj=json.load(sys.stdin)
for p in parts:
    obj=obj.get(p) if isinstance(obj,dict) else None
print("" if obj is None else obj)' "$path"
}

read_env_value() {
  local key="$1"
  python3 - "$HERMES_ENV" "$key" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1]); key=sys.argv[2]; val=""
if p.exists():
    for line in p.read_text(errors="ignore").splitlines():
        s=line.strip()
        if s and not s.startswith("#") and "=" in s:
            k,v=s.split("=",1)
            if k.strip()==key:
                val=v.strip().strip('"').strip("'"); break
print(val)
PY
}

write_env_value_if_missing() {
  local key="$1" value="$2"
  mkdir -p "$(dirname "$HERMES_ENV")"
  touch "$HERMES_ENV"
  if [[ -n "$(read_env_value "$key")" ]]; then
    return 0
  fi
  {
    printf '\n# Added by HermesOpenWebUI_QuicklyLaunch\n'
    printf '%s=%s\n' "$key" "$value"
  } >>"$HERMES_ENV"
}

api_key() {
  local key
  key="$(read_env_value API_SERVER_KEY)"
  if [[ -z "$key" ]]; then
    key="$(openssl rand -hex 32 2>/dev/null || python3 -c 'import secrets; print(secrets.token_hex(32))')"
    write_env_value_if_missing API_SERVER_KEY "$key"
    ok "Generated API_SERVER_KEY in $HERMES_ENV"
  fi
  printf '%s' "$key"
}

load_env_for_process() {
  if [[ -f "$HERMES_ENV" ]]; then
    set -a
    # shellcheck disable=SC1090
    source "$HERMES_ENV"
    set +a
  fi
}

install_hermes_repo() {
  step "Installing/updating Hermes Agent source"
  require_command git
  require_command python3
  if [[ ! -d "$HERMES_REPO/.git" ]]; then
    git clone "$HERMES_REPO_URL" "$HERMES_REPO"
  fi
  git -C "$HERMES_REPO" fetch origin "$HERMES_REF" --depth 1 || true
  if git -C "$HERMES_REPO" rev-parse --verify "origin/$HERMES_REF" >/dev/null 2>&1; then
    git -C "$HERMES_REPO" checkout -B "$HERMES_REF" "origin/$HERMES_REF"
  else
    git -C "$HERMES_REPO" checkout "$HERMES_REF" || true
  fi
  if [[ ! -x "$HERMES_PY" ]]; then
    if have uv; then
      (cd "$HERMES_REPO" && uv venv "$HERMES_VENV" && uv pip install -p "$HERMES_PY" -e .)
    else
      python3 -m venv "$HERMES_VENV"
      "$HERMES_PY" -m pip install --upgrade pip
      (cd "$HERMES_REPO" && "$HERMES_PY" -m pip install -e .)
    fi
  fi
  ok "Hermes repo ready: $HERMES_REPO"
}

install_tailscale_static() {
  if [[ -n "${TS_BIN:-}" && -x "${TS_BIN:-}" && -n "${TSD_BIN:-}" && -x "${TSD_BIN:-}" ]]; then
    ok "Tailscale binaries already present: $TS_BIN"
    return 0
  fi
  step "Installing user-space Tailscale binaries"
  require_command curl
  require_command tar
  mkdir -p "$TS_ROOT"
  local machine arch url tmp
  machine="$(uname -m)"
  case "$machine" in
    aarch64|arm64) arch="arm64" ;;
    x86_64|amd64) arch="amd64" ;;
    armv7l) arch="arm" ;;
    *) fail "Unsupported architecture for static Tailscale install: $machine" ;;
  esac
  url="${TAILSCALE_TGZ_URL:-https://pkgs.tailscale.com/stable/tailscale_latest_${arch}.tgz}"
  tmp="$(mktemp -d)"
  curl -fsSL "$url" -o "$tmp/tailscale.tgz"
  tar -xzf "$tmp/tailscale.tgz" -C "$TS_ROOT"
  TS_DIR="$(find "$TS_ROOT" -maxdepth 1 -type d -name 'tailscale_*' | sort | tail -n 1)"
  TS_BIN="$TS_DIR/tailscale"
  TSD_BIN="$TS_DIR/tailscaled"
  [[ -x "$TS_BIN" && -x "$TSD_BIN" ]] || fail "Tailscale install did not produce tailscale/tailscaled"
  ok "Installed Tailscale: $TS_BIN"
}

ensure_prereqs() {
  step "Checking local prerequisites"
  require_command curl
  require_command python3
  require_command docker
  [[ -d "$HERMES_REPO" ]] || fail "Hermes repo missing. Run: $0 install"
  [[ -x "$HERMES_PY" ]] || fail "Hermes Python missing. Run: $0 install"
  mkdir -p "$HERMES_LOG_DIR" "$TS_STATE_DIR" "$AUTOSTART_DIR"
  api_key >/dev/null
  if [[ -z "${TS_BIN:-}" || ! -x "${TS_BIN:-}" || -z "${TSD_BIN:-}" || ! -x "${TSD_BIN:-}" ]]; then
    fail "Tailscale binaries missing. Run: $0 install"
  fi
  ok "Prerequisites look good"
}

install_openwebui_container() {
  step "Installing/creating Open WebUI container"
  require_command docker
  local key exists
  key="$(api_key)"
  docker volume create "$OPENWEBUI_VOLUME" >/dev/null
  exists="$(docker inspect -f '{{.Name}}' "$OPENWEBUI_CONTAINER" 2>/dev/null || true)"
  if [[ -n "$exists" ]]; then
    ok "Open WebUI container already exists: $OPENWEBUI_CONTAINER"
    docker update --restart always "$OPENWEBUI_CONTAINER" >/dev/null || true
    return 0
  fi
  docker pull "$OPENWEBUI_IMAGE"
  docker run -d \
    --name "$OPENWEBUI_CONTAINER" \
    --restart always \
    -p "$OPENWEBUI_HOST_PORT:$OPENWEBUI_CONTAINER_PORT" \
    --add-host=host.docker.internal:host-gateway \
    -v "$OPENWEBUI_VOLUME:/app/backend/data" \
    -e "OPENAI_API_BASE_URL=$HERMES_API_BASE_URL" \
    -e "OPENAI_API_BASE_URLS=$HERMES_API_BASE_URL" \
    -e "OPENAI_API_KEY=$key" \
    -e "OPENAI_API_KEYS=$key" \
    -e "ENABLE_OLLAMA_API=false" \
    "$OPENWEBUI_IMAGE" >/dev/null
  ok "Open WebUI container created: $OPENWEBUI_CONTAINER"
}

rebuild_openwebui_container() {
  step "Rebuilding Open WebUI container without deleting its Docker volume"
  require_command docker
  docker pull "$OPENWEBUI_IMAGE"
  docker stop "$OPENWEBUI_CONTAINER" >/dev/null 2>&1 || true
  docker rm "$OPENWEBUI_CONTAINER" >/dev/null 2>&1 || true
  install_openwebui_container
}

ensure_openwebui() {
  step "Checking Open WebUI"
  local running policy
  if ! docker inspect "$OPENWEBUI_CONTAINER" >/dev/null 2>&1; then
    install_openwebui_container
  fi
  policy="$(docker inspect -f '{{.HostConfig.RestartPolicy.Name}}' "$OPENWEBUI_CONTAINER" 2>/dev/null || true)"
  [[ "$policy" == "always" ]] || docker update --restart always "$OPENWEBUI_CONTAINER" >/dev/null
  running="$(docker inspect -f '{{.State.Running}}' "$OPENWEBUI_CONTAINER" 2>/dev/null || true)"
  [[ "$running" == "true" ]] || docker start "$OPENWEBUI_CONTAINER" >/dev/null
  for _ in $(seq 1 45); do
    if curl -fsSL "$OPENWEBUI_LOCAL_URL" >/dev/null 2>&1; then
      ok "Open WebUI reachable: $OPENWEBUI_LOCAL_URL"
      return 0
    fi
    sleep 2
  done
  fail "Open WebUI did not become reachable: $OPENWEBUI_LOCAL_URL"
}

ts_status_json() {
  if have timeout; then
    timeout "$TS_STATUS_TIMEOUT" "$TS_BIN" --socket="$TS_SOCKET" status --json 2>/dev/null
  else
    "$TS_BIN" --socket="$TS_SOCKET" status --json 2>/dev/null
  fi
}

system_ts_status_json() {
  local system_ts_bin
  system_ts_bin="$(command -v tailscale 2>/dev/null || true)"
  [[ -n "$system_ts_bin" ]] || return 1
  if have timeout; then
    timeout "$TS_STATUS_TIMEOUT" "$system_ts_bin" status --json 2>/dev/null
  else
    "$system_ts_bin" status --json 2>/dev/null
  fi
}

print_tailscale_node_summary() {
  local label="$1" status_json="$2" socket_label="$3"
  local backend host dns ips online
  backend="$(printf '%s' "$status_json" | json_field BackendState)"
  host="$(printf '%s' "$status_json" | json_field Self.HostName)"
  dns="$(printf '%s' "$status_json" | json_field Self.DNSName | sed 's/\.$//')"
  ips="$(printf '%s' "$status_json" | json_field TailscaleIPs)"
  online="$(printf '%s' "$status_json" | json_field Self.Online)"
  printf '%-20s: backend=%s host=%s online=%s\n' "$label" "${backend:-unknown}" "${host:-unknown}" "${online:-unknown}"
  printf '  DNS / IPs         : %s / %s\n' "${dns:-unknown}" "${ips:-unknown}"
  printf '  Socket            : %s\n' "$socket_label"
}

get_valid_ts_status_json() {
  local attempts="${1:-8}" out
  for _ in $(seq 1 "$attempts"); do
    out="$(ts_status_json || true)"
    if [[ -n "$out" ]] && printf '%s' "$out" | python3 -m json.tool >/dev/null 2>&1; then
      printf '%s' "$out"
      return 0
    fi
    sleep 1
  done
  return 1
}

get_settled_ts_status_json() {
  local attempts="${1:-10}" out="" backend=""
  for _ in $(seq 1 "$attempts"); do
    out="$(ts_status_json || true)"
    if [[ -n "$out" ]] && printf '%s' "$out" | python3 -m json.tool >/dev/null 2>&1; then
      backend="$(printf '%s' "$out" | json_field BackendState)"
      if [[ -n "$backend" && "$backend" != "NoState" && "$backend" != "Starting" ]]; then
        printf '%s' "$out"
        return 0
      fi
    fi
    sleep 1
  done
  if [[ -n "$out" ]] && printf '%s' "$out" | python3 -m json.tool >/dev/null 2>&1; then
    printf '%s' "$out"
    return 0
  fi
  return 1
}

start_tailscaled() {
  step "Starting user-space Tailscale daemon"
  mkdir -p "$TS_STATE_DIR"
  nohup "$TSD_BIN" \
    --tun=userspace-networking \
    --socket="$TS_SOCKET" \
    --statedir="$TS_STATE_DIR" \
    --state="$TS_STATE" \
    --socks5-server=127.0.0.1:1055 \
    --outbound-http-proxy-listen=127.0.0.1:1055 \
    >"$TS_LOG" 2>&1 &
  echo $! >"$TS_PID_FILE"
}

ensure_tailscaled() {
  step "Checking Tailscale daemon"
  if get_valid_ts_status_json 2 >/dev/null 2>&1; then
    ok "Tailscale daemon reachable"
    return 0
  fi
  start_tailscaled
  if get_valid_ts_status_json 20 >/dev/null 2>&1; then
    ok "Tailscale daemon started"
    return 0
  fi
  tail -n 40 "$TS_LOG" 2>/dev/null || true
  fail "Tailscale daemon failed to start"
}

ensure_tailscale_login() {
  step "Checking Tailscale login state"
  local status backend auth_url
  status="$(get_settled_ts_status_json)"
  backend="$(printf '%s' "$status" | json_field BackendState)"
  if [[ "$backend" == "Running" ]]; then
    ok "Tailscale node is logged in"
    return 0
  fi
  "$TS_BIN" --socket="$TS_SOCKET" up --hostname="$TS_HOSTNAME" >/dev/null 2>&1 || true
  sleep 2
  status="$(get_valid_ts_status_json || true)"
  backend="$(printf '%s' "$status" | json_field BackendState 2>/dev/null || true)"
  auth_url="$(printf '%s' "$status" | json_field AuthURL 2>/dev/null || true)"
  if [[ "$backend" == "Running" ]]; then
    ok "Tailscale login completed"
  elif [[ -n "$auth_url" ]]; then
    warn "Open this URL, approve the node, then rerun: $0 up"
    printf '%s\n' "$auth_url"
    exit 2
  else
    fail "Tailscale is not logged in and no auth URL was returned"
  fi
}

ensure_tailscale_serve() {
  step "Checking Tailscale HTTPS Serve"
  local output
  output="$("$TS_BIN" --socket="$TS_SOCKET" serve --bg "$TS_SERVE_PORT" 2>&1 || true)"
  if grep -q 'https://login.tailscale.com/f/serve' <<<"$output"; then
    warn "Open this URL, enable Serve, then rerun: $0 up"
    grep -o 'https://login.tailscale.com/f/serve[^[:space:]]*' <<<"$output" | head -n 1
    exit 3
  fi
  ok "Tailscale Serve requested for local port $TS_SERVE_PORT"
}

ensure_hermes_api() {
  step "Checking Hermes API server"
  if curl -fsSL "$HERMES_API_HEALTH_URL" >/dev/null 2>&1; then
    ok "Hermes API reachable: $HERMES_API_HEALTH_URL"
    return 0
  fi
  load_env_for_process
  pkill -f 'python.*hermes_cli[.]main.*gateway run' >/dev/null 2>&1 || true
  (cd "$HERMES_REPO" && nohup "$HERMES_PY" -m hermes_cli.main gateway run >"$HERMES_BOOTSTRAP_LOG" 2>&1 &)
  for _ in $(seq 1 45); do
    if curl -fsSL "$HERMES_API_HEALTH_URL" >/dev/null 2>&1; then
      ok "Hermes API started: $HERMES_API_HEALTH_URL"
      return 0
    fi
    sleep 2
  done
  tail -n 80 "$HERMES_BOOTSTRAP_LOG" 2>/dev/null || true
  fail "Hermes API did not become healthy"
}

status_summary() {
  step "Current summary"
  local running policy system_status status dns url
  running="$(docker inspect -f '{{.State.Running}}' "$OPENWEBUI_CONTAINER" 2>/dev/null || true)"
  policy="$(docker inspect -f '{{.HostConfig.RestartPolicy.Name}}' "$OPENWEBUI_CONTAINER" 2>/dev/null || true)"
  printf 'Open WebUI container : running=%s restart=%s\n' "${running:-missing}" "${policy:-missing}"
  if curl -fsSL "$OPENWEBUI_LOCAL_URL" >/dev/null 2>&1; then printf 'Open WebUI local     : healthy (%s)\n' "$OPENWEBUI_LOCAL_URL"; else printf 'Open WebUI local     : not healthy\n'; fi
  if curl -fsSL "$HERMES_API_HEALTH_URL" >/dev/null 2>&1; then printf 'Hermes API           : healthy (%s)\n' "$HERMES_API_HEALTH_URL"; else printf 'Hermes API           : not healthy\n'; fi
  if system_status="$(system_ts_status_json)" && [[ -n "$system_status" ]] && printf '%s' "$system_status" | python3 -m json.tool >/dev/null 2>&1; then
    print_tailscale_node_summary "Tailscale system" "$system_status" "default system socket"
  else
    printf '%-20s: unavailable (plain tailscale CLI/system daemon)\n' "Tailscale system"
  fi
  if status="$(get_valid_ts_status_json 2 2>/dev/null)"; then
    dns="$(printf '%s' "$status" | json_field Self.DNSName | sed 's/\.$//')"
    print_tailscale_node_summary "Tailscale project" "$status" "$TS_SOCKET"
    [[ -n "$dns" ]] && printf 'Conduit HTTPS URL    : https://%s\n' "$dns"
  else
    printf '%-20s: unavailable\n' "Tailscale project"
    printf '  Socket            : %s\n' "$TS_SOCKET"
  fi
  url="$(ngrok_public_url || true)"
  if [[ -n "$url" ]]; then
    printf 'ngrok HTTPS URL      : %s\n' "$url"
  fi
}

ngrok_public_url() {
  curl --max-time 3 -fsSL http://127.0.0.1:4040/api/tunnels 2>/dev/null | python3 -c 'import json,sys
for t in json.load(sys.stdin).get("tunnels",[]):
    u=t.get("public_url","")
    if u.startswith("https://"):
        print(u); break' 2>/dev/null || true
}

start_stack() {
  ensure_prereqs
  ensure_openwebui
  ensure_tailscaled
  ensure_tailscale_login
  ensure_tailscale_serve
  ensure_hermes_api
  status_summary
  ok "Everything is up"
}

stop_stack() {
  ensure_prereqs
  step "Stopping Hermes API, ngrok, Tailscale daemon, and Open WebUI"
  pkill -f 'python.*hermes_cli[.]main.*gateway run' >/dev/null 2>&1 || true
  pkill -f "ngrok http $NGROK_PORT" >/dev/null 2>&1 || true
  if [[ -f "$TS_PID_FILE" ]]; then kill "$(cat "$TS_PID_FILE")" >/dev/null 2>&1 || true; rm -f "$TS_PID_FILE"; fi
  pkill -f "tailscaled.*$TS_SOCKET" >/dev/null 2>&1 || true
  docker stop "$OPENWEBUI_CONTAINER" >/dev/null 2>&1 || true
  ok "Stop requested"
}

install_all() {
  mkdir -p "$HERMES_HOME" "$HERMES_LOG_DIR" "$USER_BIN_DIR"
  api_key >/dev/null
  install_hermes_repo
  install_tailscale_static
  install_openwebui_container
  install_cli_wrapper
  ok "Install completed. Next run: $0 up"
}

install_cli_wrapper() {
  step "Installing hermes CLI wrapper"
  mkdir -p "$USER_BIN_DIR"
  cat >"$HERMES_CLI_WRAPPER" <<EOF
#!/usr/bin/env bash
set -euo pipefail
cd "$HERMES_REPO"
exec "$HERMES_PY" -m hermes_cli.main "\$@"
EOF
  chmod +x "$HERMES_CLI_WRAPPER"
  ok "Installed $HERMES_CLI_WRAPPER"
}

install_autostart() {
  mkdir -p "$AUTOSTART_DIR"
  cat >"$AUTOSTART_FILE" <<EOF
[Desktop Entry]
Type=Application
Name=Hermes OpenWebUI Tailscale Bootstrap
Exec=$SCRIPT_DIR/run.sh up
Terminal=true
X-GNOME-Autostart-enabled=true
EOF
  ok "Autostart file written: $AUTOSTART_FILE"
}

show_logs() {
  step "Open WebUI logs"; docker logs --tail 80 "$OPENWEBUI_CONTAINER" 2>&1 || true
  step "Hermes gateway logs"; tail -n 100 "$HERMES_BOOTSTRAP_LOG" 2>/dev/null || true
  step "Tailscale logs"; tail -n 100 "$TS_LOG" 2>/dev/null || true
}

start_ngrok() {
  ensure_prereqs
  ensure_openwebui
  require_command ngrok
  if ! curl -fsSL http://127.0.0.1:4040/api/tunnels >/dev/null 2>&1; then
    nohup ngrok http "$NGROK_PORT" >"$NGROK_LOG" 2>&1 &
    sleep 3
  fi
  ensure_hermes_api
  status_summary
}

usage() {
  cat <<EOF
Usage: ./run.sh <command>

Main:
  install                    Download Hermes, create Open WebUI container, install Tailscale binaries
  up, start                  Start/repair Open WebUI + Hermes API + Tailscale Serve
  restart                    Stop then start
  rebuild                    Pull/recreate Open WebUI container, update Hermes checkout, then start
  status                     Print health summary
  doctor                     Check prerequisites and paths
  logs                       Print recent logs
  stop, down                 Stop local stack

Service:
  hermes-start|hermes-stop|hermes-restart
  tailscale-start|tailscale-stop|tailscale-status
  docker-start|docker-stop|docker-restart|docker-logs
  up-ngrok                   Optional ngrok fallback

Install helpers:
  install-cli                Install ~/.local/bin/hermes wrapper
  install-autostart          Start stack on GUI login
  help                       Show this help

Overrides:
  HERMES_REPO_URL=$HERMES_REPO_URL
  HERMES_REF=$HERMES_REF
  HERMES_REPO=$HERMES_REPO
  TS_HOSTNAME=$TS_HOSTNAME
  OPENWEBUI_CONTAINER=$OPENWEBUI_CONTAINER
EOF
}

doctor() {
  step "Doctor"
  printf 'Project root         : %s\n' "$SCRIPT_DIR"
  printf 'Hermes repo URL      : %s\n' "$HERMES_REPO_URL"
  printf 'Hermes repo          : %s\n' "$HERMES_REPO"
  printf 'Hermes Python        : %s\n' "$HERMES_PY"
  printf 'Hermes env           : %s\n' "$HERMES_ENV"
  printf 'Open WebUI image     : %s\n' "$OPENWEBUI_IMAGE"
  printf 'Open WebUI local     : %s\n' "$OPENWEBUI_LOCAL_URL"
  printf 'Tailscale root       : %s\n' "$TS_ROOT"
  printf 'Tailscale CLI        : %s\n' "${TS_BIN:-missing}"
  have git && ok "git available" || warn "git missing"
  have docker && ok "docker available" || warn "docker missing"
  have python3 && ok "python3 available" || warn "python3 missing"
  [[ -d "$HERMES_REPO" ]] && ok "Hermes repo exists" || warn "Hermes repo missing; run install"
  [[ -x "$HERMES_PY" ]] && ok "Hermes Python exists" || warn "Hermes Python missing; run install"
  [[ -n "${TS_BIN:-}" && -x "${TS_BIN:-}" ]] && ok "Tailscale CLI exists" || warn "Tailscale missing; run install"
}

case "$MODE" in
  install|setup|bootstrap) install_all ;;
  up|start) start_stack ;;
  restart) stop_stack; start_stack ;;
  rebuild) install_hermes_repo; rebuild_openwebui_container; start_stack ;;
  status) ensure_prereqs; status_summary ;;
  doctor) doctor ;;
  logs) ensure_prereqs; show_logs ;;
  stop|down) stop_stack ;;
  up-ngrok|start-ngrok) start_ngrok ;;
  install-cli) install_cli_wrapper ;;
  install-autostart) install_autostart ;;
  hermes-start) ensure_prereqs; ensure_hermes_api ;;
  hermes-stop) pkill -f 'python.*hermes_cli[.]main.*gateway run' >/dev/null 2>&1 || true; ok "Hermes stop requested" ;;
  hermes-restart) pkill -f 'python.*hermes_cli[.]main.*gateway run' >/dev/null 2>&1 || true; ensure_prereqs; ensure_hermes_api ;;
  tailscale-start) ensure_prereqs; ensure_tailscaled; ensure_tailscale_login; ensure_tailscale_serve ;;
  tailscale-stop) [[ -f "$TS_PID_FILE" ]] && kill "$(cat "$TS_PID_FILE")" >/dev/null 2>&1 || true; pkill -f "tailscaled.*$TS_SOCKET" >/dev/null 2>&1 || true; ok "Tailscale stop requested" ;;
  tailscale-status) ensure_prereqs; ts_status_json ;;
  docker-start) ensure_openwebui ;;
  docker-stop) docker stop "$OPENWEBUI_CONTAINER" >/dev/null 2>&1 || true; ok "Open WebUI stop requested" ;;
  docker-restart) docker stop "$OPENWEBUI_CONTAINER" >/dev/null 2>&1 || true; ensure_openwebui ;;
  docker-logs) docker logs --tail 100 "$OPENWEBUI_CONTAINER" ;;
  help|-h|--help) usage ;;
  *) usage; exit 1 ;;
esac
