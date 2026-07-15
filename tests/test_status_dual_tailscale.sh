#!/usr/bin/env bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUN_SH="${TARGET_RUN_SH:-$PROJECT_ROOT/run.sh}"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

mkdir -p "$TMP_DIR/bin" "$TMP_DIR/hermes/venv/bin" \
  "$TMP_DIR/tailscale/tailscale_9.9.9_arm64" "$TMP_DIR/tailscale/state"
: >"$TMP_DIR/hermes-env"
ln -s "$(command -v python3)" "$TMP_DIR/hermes/venv/bin/python"

cat >"$TMP_DIR/bin/docker" <<'SH'
#!/usr/bin/env bash
if [[ "$*" == *".State.Running"* ]]; then printf 'true\n'; else printf 'always\n'; fi
SH
cat >"$TMP_DIR/bin/curl" <<'SH'
#!/usr/bin/env bash
exit 0
SH
cat >"$TMP_DIR/bin/tailscale" <<'SH'
#!/usr/bin/env bash
if [[ " $* " == *" status --json "* ]]; then
  printf '%s\n' '{"BackendState":"Running","TailscaleIPs":["100.94.21.85"],"Self":{"HostName":"ubuntu","DNSName":"ubuntu.example.ts.net.","Online":true}}'
  exit 0
fi
exit 1
SH
cat >"$TMP_DIR/tailscale/tailscale_9.9.9_arm64/tailscale" <<'SH'
#!/usr/bin/env bash
if [[ " $* " == *" status --json "* ]]; then
  printf '%s\n' '{"BackendState":"Running","TailscaleIPs":["100.107.48.126"],"Self":{"HostName":"agx-openwebui","DNSName":"agx-openwebui.example.ts.net.","Online":true}}'
  exit 0
fi
exit 1
SH
cat >"$TMP_DIR/tailscale/tailscale_9.9.9_arm64/tailscaled" <<'SH'
#!/usr/bin/env bash
exit 0
SH
chmod +x "$TMP_DIR/bin/docker" "$TMP_DIR/bin/curl" "$TMP_DIR/bin/tailscale" \
  "$TMP_DIR/tailscale/tailscale_9.9.9_arm64/tailscale" \
  "$TMP_DIR/tailscale/tailscale_9.9.9_arm64/tailscaled"

set +e
output="$(
  PATH="$TMP_DIR/bin:$PATH" \
  HOME="$TMP_DIR" \
  HERMES_REPO="$TMP_DIR/hermes" \
  HERMES_ENV="$TMP_DIR/hermes-env" \
  TS_ROOT="$TMP_DIR/tailscale" \
  TS_STATUS_TIMEOUT=1 \
  "$RUN_SH" status
)"
run_rc=$?
set -e
if [[ "$run_rc" -ne 0 ]] && [[ "$output" != *"Tailscale project"* ]]; then
  printf 'FAIL: status command exited %s before printing Tailscale nodes\n%s\n' "$run_rc" "$output" >&2
  exit 1
fi

assert_contains() {
  local expected="$1"
  if [[ "$output" != *"$expected"* ]]; then
    printf 'FAIL: missing expected status text: %s\n--- output ---\n%s\n' "$expected" "$output" >&2
    exit 1
  fi
}

assert_contains 'Tailscale system'
assert_contains 'host=ubuntu'
assert_contains '100.94.21.85'
assert_contains 'Tailscale project'
assert_contains 'host=agx-openwebui'
assert_contains '100.107.48.126'
assert_contains "$TMP_DIR/tailscale/tailscaled.sock"

printf 'PASS: status clearly distinguishes system and project Tailscale nodes\n'
