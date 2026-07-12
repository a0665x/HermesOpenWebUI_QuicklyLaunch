# Project Map

## Name

HermesOpenWebUI QuicklyLaunch

## Description

Thin launcher repository for installing and operating Hermes Agent, Open WebUI, and Tailscale Serve together. It intentionally does not vendor Hermes Agent or Open WebUI source code; those are fetched at install/runtime from their upstream repositories/images.

## Read First

- [Runtime](./RUNTIME.md): commands, endpoints, and health checks.
- [Architecture](./ARCHITECTURE.md): component boundaries and startup flow.

## Major Concepts

- `run.sh`: one-command installer and operator entrypoint.
- `healthcheck.sh`: one-click verification for Open WebUI, Hermes API, Tailscale Serve, DNS, and HTTPS reachability.
- `hermes-agent/`: ignored runtime clone of upstream Hermes Agent.
- `open-webui`: Docker container from `ghcr.io/open-webui/open-webui:main`, not committed here.
- `Tailscale Serve`: private HTTPS reverse proxy from tailnet DNS to local Open WebUI port 3000.

## File Map

- `../run.sh`: install/start/restart/rebuild/status/log commands.
- `../healthcheck.sh`: deep health checker, optional `--fix-dns` repair.
- `../README.md`: public usage guide.
- `../.gitignore`: prevents vendored repos, secrets, runtime state, caches, and logs from being pushed.
