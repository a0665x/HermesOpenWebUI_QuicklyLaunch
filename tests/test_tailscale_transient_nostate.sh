#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

mkdir -p "$TMP_DIR/bin" "$TMP_DIR/hermes/venv/bin" "$TMP_DIR/tailscale/tailscale_9.9.9_arm64" "$TMP_DIR/tailscale/state" "$TMP_DIR/hermes-home"
ln -s "$(command -v python3)" "$TMP_DIR/hermes/venv/bin/python"

cat >"$TMP_DIR/bin/docker" <<'SH'
#!/usr/bin/env bash
exit 0
SH
cat >"$TMP_DIR/bin/curl" <<'SH'
#!/usr/bin/env bash
exit 0
SH
cat >"$TMP_DIR/tailscale/tailscale_9.9.9_arm64/tailscaled" <<'SH'
#!/usr/bin/env bash
sleep 60
SH
cat >"$TMP_DIR/tailscale/tailscale_9.9.9_arm64/tailscale" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
root="${TS_TEST_ROOT:?}"
args=" $* "
if [[ "$args" == *" status --json "* ]]; then
  count=0
  [[ -f "$root/status-count" ]] && count="$(<"$root/status-count")"
  count=$((count + 1))
  printf '%s' "$count" >"$root/status-count"
  if (( count <= 3 )); then
    printf '{"BackendState":"NoState","AuthURL":"","Self":{}}\n'
  else
    printf '{"BackendState":"Running","AuthURL":"","Self":{"DNSName":"agx-openwebui.example.ts.net."}}\n'
  fi
  exit 0
fi
if [[ "$args" == *" up "* ]]; then
  printf 'unexpected up invocation\n' >>"$root/up-called"
  exit 0
fi
if [[ "$args" == *" serve --bg "* ]]; then
  printf 'Serve started and running in the background\n'
  exit 0
fi
exit 0
SH
chmod +x "$TMP_DIR/bin/docker" "$TMP_DIR/bin/curl" \
  "$TMP_DIR/tailscale/tailscale_9.9.9_arm64/tailscale" \
  "$TMP_DIR/tailscale/tailscale_9.9.9_arm64/tailscaled"

set +e
output="$(
  PATH="$TMP_DIR/bin:$PATH" \
  HOME="$TMP_DIR" \
  HERMES_HOME="$TMP_DIR/hermes-home" \
  HERMES_REPO="$TMP_DIR/hermes" \
  TS_ROOT="$TMP_DIR/tailscale" \
  TS_TEST_ROOT="$TMP_DIR" \
  TS_STATUS_TIMEOUT=1 \
  "$PROJECT_ROOT/run.sh" tailscale-start
)"
set -e

if [[ -e "$TMP_DIR/up-called" ]]; then
  printf 'FAIL: transient NoState caused tailscale up/login request\n%s\n' "$output" >&2
  exit 1
fi
if [[ "$output" != *"Tailscale node is logged in"* ]]; then
  printf 'FAIL: settled Running state was not recognized\n%s\n' "$output" >&2
  exit 1
fi

printf 'PASS: transient NoState settles without requesting login\n'
