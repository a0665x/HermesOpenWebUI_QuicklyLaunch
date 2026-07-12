#!/usr/bin/env bash
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
HOME_DIR="${HOME:-/home/a0665x}"

OPENWEBUI_CONTAINER="${OPENWEBUI_CONTAINER:-open-webui}"
OPENWEBUI_LOCAL_URL="${OPENWEBUI_LOCAL_URL:-http://127.0.0.1:3000}"
HERMES_API_HEALTH_URL="${HERMES_API_HEALTH_URL:-http://127.0.0.1:8642/health}"
TS_ROOT="${TS_ROOT:-$HOME_DIR/.local/tailscale}"
TS_DIR="$(find "$TS_ROOT" -maxdepth 1 -type d -name 'tailscale_*' 2>/dev/null | sort | tail -n 1 || true)"
TS_BIN="${TS_BIN:-${TS_DIR:+$TS_DIR/tailscale}}"
TS_SOCKET="${TS_SOCKET:-$TS_ROOT/tailscaled.sock}"
TS_STATUS_TIMEOUT="${TS_STATUS_TIMEOUT:-5}"
EXPECTED_PROXY="${EXPECTED_PROXY:-$OPENWEBUI_LOCAL_URL}"
FIX_DNS="0"

for arg in "$@"; do
  case "$arg" in
    --fix-dns) FIX_DNS="1" ;;
    -h|--help)
      cat <<EOF
Usage: $0 [--fix-dns]

One-shot health check for this Hermes + Open WebUI + Tailscale Serve stack.

Environment overrides:
  OPENWEBUI_CONTAINER      default: open-webui
  OPENWEBUI_LOCAL_URL      default: http://127.0.0.1:3000
  HERMES_API_HEALTH_URL    default: http://127.0.0.1:8642/health
  TS_ROOT                  default: ~/.local/tailscale
  TS_BIN                   default: newest ~/.local/tailscale/tailscale_*_arm64/tailscale
  TS_SOCKET                default: ~/.local/tailscale/tailscaled.sock

Options:
  --fix-dns    If MagicDNS lookup fails, also try: tailscale set --accept-dns=true
EOF
      exit 0
      ;;
    *) echo "Unknown argument: $arg" >&2; exit 2 ;;
  esac
done

GREEN=$'\033[32m'; YELLOW=$'\033[33m'; RED=$'\033[31m'; BLUE=$'\033[34m'; NC=$'\033[0m'
PASS=0; WARN=0; FAIL=0

section() { printf '\n%s%s%s\n' "$BLUE" "$1" "$NC"; }
ok() { PASS=$((PASS+1)); printf '%b[ OK ]%b %s\n' "$GREEN" "$NC" "$1"; }
warn() { WARN=$((WARN+1)); printf '%b[WARN]%b %s\n' "$YELLOW" "$NC" "$1"; }
fail() { FAIL=$((FAIL+1)); printf '%b[FAIL]%b %s\n' "$RED" "$NC" "$1"; }
info() { printf '       %s\n' "$1"; }
have() { command -v "$1" >/dev/null 2>&1; }

curl_code() {
  local url="$1"
  curl -k -L --connect-timeout 4 --max-time 10 -sS -o /tmp/hermes_openwebui_health_body.$$ -w '%{http_code}' "$url" 2>/tmp/hermes_openwebui_health_curlerr.$$ || true
}

page_title() {
  python3 - "$1" <<'PY' 2>/dev/null || true
from pathlib import Path
from html.parser import HTMLParser
import sys
class P(HTMLParser):
    def __init__(self):
        super().__init__(); self.in_title=False; self.parts=[]
    def handle_starttag(self, tag, attrs):
        if tag.lower() == 'title': self.in_title=True
    def handle_endtag(self, tag):
        if tag.lower() == 'title': self.in_title=False
    def handle_data(self, data):
        if self.in_title: self.parts.append(data.strip())
p=P()
p.feed(Path(sys.argv[1]).read_text(errors='ignore'))
print(' '.join([x for x in p.parts if x])[:120])
PY
}

json_field() {
  local path="$1"
  python3 -c '
import json, sys
parts=[p for p in sys.argv[1].split(".") if p]
try:
    obj=json.load(sys.stdin)
except Exception:
    sys.exit(1)
for part in parts:
    if isinstance(obj, dict): obj=obj.get(part)
    else: obj=None; break
if obj is None: print("")
elif isinstance(obj, bool): print("true" if obj else "false")
else: print(obj)
' "$path"
}

resolve_host() {
  local host="$1"
  if have resolvectl; then
    resolvectl query "$host" 2>/dev/null | sed -nE 's/^.*: ([0-9a-fA-F:.]+)[[:space:]].*$/\1/p' | head -n 5
  elif have getent; then
    getent ahosts "$host" | awk '{print $1}' | sort -u | head -n 5
  else
    python3 - "$host" <<'PY' 2>/dev/null || true
import socket, sys
for item in socket.getaddrinfo(sys.argv[1], None):
    print(item[4][0])
PY
  fi
}

check_prereqs() {
  section "Prerequisites"
  have curl && ok "curl is available" || fail "curl not found"
  have python3 && ok "python3 is available" || fail "python3 not found"
  have docker && ok "docker is available" || fail "docker not found"
  [[ -n "${TS_BIN:-}" && -x "${TS_BIN:-}" ]] && ok "Tailscale CLI: $TS_BIN" || fail "Tailscale CLI not found under $TS_ROOT"
  [[ -S "$TS_SOCKET" ]] && ok "Tailscale socket exists: $TS_SOCKET" || warn "Tailscale socket missing: $TS_SOCKET"
}

check_openwebui() {
  section "Open WebUI"
  local running policy code title
  if have docker; then
    running="$(docker inspect -f '{{.State.Running}}' "$OPENWEBUI_CONTAINER" 2>/dev/null || true)"
    policy="$(docker inspect -f '{{.HostConfig.RestartPolicy.Name}}' "$OPENWEBUI_CONTAINER" 2>/dev/null || true)"
    [[ -n "$running" ]] && ok "container '$OPENWEBUI_CONTAINER' exists" || fail "container '$OPENWEBUI_CONTAINER' not found"
    [[ "$running" == "true" ]] && ok "container is running" || fail "container is not running"
    [[ "$policy" == "always" ]] && ok "restart policy is always" || warn "restart policy is '${policy:-unknown}'"
  fi
  code="$(curl_code "$OPENWEBUI_LOCAL_URL")"
  if [[ "$code" =~ ^[23] ]]; then
    ok "local URL responds: $OPENWEBUI_LOCAL_URL ($code)"
    title="$(page_title /tmp/hermes_openwebui_health_body.$$)"
    [[ -n "$title" ]] && info "title: $title"
  else
    fail "local URL failed: $OPENWEBUI_LOCAL_URL (http=${code:-none}, err=$(tr '\n' ' ' </tmp/hermes_openwebui_health_curlerr.$$ 2>/dev/null))"
  fi
}

check_hermes() {
  section "Hermes API"
  local code body
  code="$(curl_code "$HERMES_API_HEALTH_URL")"
  body="$(tr '\n' ' ' </tmp/hermes_openwebui_health_body.$$ 2>/dev/null | cut -c1-240)"
  if [[ "$code" =~ ^[23] ]]; then
    ok "Hermes health responds: $HERMES_API_HEALTH_URL ($code)"
    [[ -n "$body" ]] && info "body: $body"
  else
    fail "Hermes health failed: $HERMES_API_HEALTH_URL (http=${code:-none}, err=$(tr '\n' ' ' </tmp/hermes_openwebui_health_curlerr.$$ 2>/dev/null))"
  fi
}

check_tailscale() {
  section "Tailscale"
  local status_json backend dns_name ips serve_json serve_proxy serve_text host url code title resolved
  if [[ ! -x "${TS_BIN:-}" ]]; then
    fail "skip Tailscale checks: TS_BIN missing"
    return
  fi

  if have timeout; then
    status_json="$(timeout "$TS_STATUS_TIMEOUT" "$TS_BIN" --socket="$TS_SOCKET" status --json 2>/dev/null || true)"
  else
    status_json="$($TS_BIN --socket="$TS_SOCKET" status --json 2>/dev/null || true)"
  fi

  if [[ -z "$status_json" ]] || ! printf '%s' "$status_json" | python3 -m json.tool >/dev/null 2>&1; then
    fail "tailscale status --json failed via socket $TS_SOCKET"
    return
  fi

  backend="$(printf '%s' "$status_json" | json_field BackendState || true)"
  dns_name="$(printf '%s' "$status_json" | json_field Self.DNSName | sed 's/\.$//' || true)"
  ips="$(printf '%s' "$status_json" | json_field TailscaleIPs || true)"
  [[ "$backend" == "Running" ]] && ok "backend is Running" || fail "backend is '${backend:-unknown}'"
  [[ -n "$dns_name" ]] && ok "MagicDNS name: $dns_name" || fail "Self.DNSName missing"
  [[ -n "$ips" ]] && info "Tailscale IPs: $ips"

  serve_json="$($TS_BIN --socket="$TS_SOCKET" serve status --json 2>/dev/null || true)"
  if [[ -n "$serve_json" ]] && printf '%s' "$serve_json" | python3 -m json.tool >/dev/null 2>&1; then
    serve_proxy="$(printf '%s' "$serve_json" | python3 -c '
import json, sys
obj=json.load(sys.stdin)
for web in obj.get("Web", {}).values():
    for handler in web.get("Handlers", {}).values():
        proxy=handler.get("Proxy")
        if proxy:
            print(proxy)
            raise SystemExit
' 2>/dev/null || true)"
    [[ "$serve_proxy" == "$EXPECTED_PROXY" ]] && ok "Tailscale Serve proxies / to $serve_proxy" || warn "Tailscale Serve proxy is '${serve_proxy:-missing}', expected $EXPECTED_PROXY"
  else
    serve_text="$($TS_BIN --socket="$TS_SOCKET" serve status 2>&1 || true)"
    if grep -q "proxy $EXPECTED_PROXY" <<<"$serve_text"; then
      ok "Tailscale Serve proxies / to $EXPECTED_PROXY"
    else
      warn "Could not confirm Tailscale Serve proxy. Output: ${serve_text//$'\n'/ }"
    fi
  fi

  if [[ -n "$dns_name" ]]; then
    host="$dns_name"
    resolved="$(resolve_host "$host" | tr '\n' ' ' | sed 's/ *$//')"
    if [[ -n "$resolved" ]]; then
      ok "local DNS resolves $host"
      info "resolved IPs: $resolved"
    else
      fail "local DNS cannot resolve $host"
      info "Likely fix: tailscale set --accept-dns=true"
      if [[ "$FIX_DNS" == "1" ]]; then
        if command -v tailscale >/dev/null 2>&1 && tailscale set --accept-dns=true >/dev/null 2>&1; then
          ok "ran: tailscale set --accept-dns=true"
        elif "$TS_BIN" --socket="$TS_SOCKET" set --accept-dns=true >/dev/null 2>&1; then
          ok "ran: $TS_BIN --socket=$TS_SOCKET set --accept-dns=true"
        else
          warn "--fix-dns was requested but accept-dns command failed"
        fi
      fi
    fi

    url="https://$host/"
    code="$(curl_code "$url")"
    if [[ "$code" =~ ^[23] ]]; then
      ok "Conduit HTTPS responds from this machine: $url ($code)"
      title="$(page_title /tmp/hermes_openwebui_health_body.$$)"
      [[ -n "$title" ]] && info "title: $title"
    else
      fail "Conduit HTTPS failed from this machine: $url (http=${code:-none}, err=$(tr '\n' ' ' </tmp/hermes_openwebui_health_curlerr.$$ 2>/dev/null))"
    fi
  fi
}

main() {
  printf 'Hermes OpenWebUI one-click health check\n'
  printf 'Project root: %s\n' "$SCRIPT_DIR"
  check_prereqs
  check_openwebui
  check_hermes
  check_tailscale

  rm -f /tmp/hermes_openwebui_health_body.$$ /tmp/hermes_openwebui_health_curlerr.$$ 2>/dev/null || true

  section "Summary"
  printf 'PASS=%s WARN=%s FAIL=%s\n' "$PASS" "$WARN" "$FAIL"
  if [[ "$FAIL" -gt 0 ]]; then
    printf '%bHealth check failed.%b\n' "$RED" "$NC"
    exit 1
  fi
  if [[ "$WARN" -gt 0 ]]; then
    printf '%bHealth check passed with warnings.%b\n' "$YELLOW" "$NC"
    exit 0
  fi
  printf '%bEverything looks healthy.%b\n' "$GREEN" "$NC"
}

main "$@"
