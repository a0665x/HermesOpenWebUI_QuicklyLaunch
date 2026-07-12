# Architecture

## Summary

This repository is an operations layer, not a fork of Hermes Agent or Open WebUI. The local operator runs `./run.sh install` once, then uses `./run.sh up`, `restart`, `rebuild`, and `status` to keep the stack usable.

## Boundaries

Owns:

- install/start/rebuild shell scripts
- health check script
- documentation and spec index

Does not own or commit:

- Hermes Agent source code
- Open WebUI source code or Docker image contents
- local `.env` secrets
- Tailscale state
- Open WebUI data volume

## Components

### Hermes Agent

Fetched from `HERMES_REPO_URL`, default `https://github.com/NousResearch/hermes-agent.git`, into ignored local path `./hermes-agent/`. The gateway is started with:

```bash
python -m hermes_cli.main gateway run
```

The OpenAI-compatible API server is expected at:

```text
http://127.0.0.1:8642/health
http://127.0.0.1:8642/v1
```

### Open WebUI

Created as Docker container `open-webui` from `ghcr.io/open-webui/open-webui:main`. It exposes container port `8080` on host port `3000`, and keeps persistent data in Docker volume `open-webui`.

The container is configured to call Hermes through Docker's host gateway:

```text
http://host.docker.internal:8642/v1
```

### Tailscale

Runs as user-space `tailscaled` under `~/.local/tailscale`, using a local socket and state directory. Tailscale Serve maps the node's tailnet HTTPS URL to local Open WebUI port `3000`.

## Startup Flow

`./run.sh up`:

1. Validates local prerequisites.
2. Starts or creates Open WebUI container.
3. Starts user-space Tailscale daemon.
4. Ensures the node is logged into Tailscale, printing approval URL if needed.
5. Ensures Tailscale Serve points HTTPS to local port 3000.
6. Starts Hermes gateway/API if health is down.
7. Prints local and private HTTPS endpoints.

`./run.sh rebuild` updates the Hermes checkout and recreates the Open WebUI container while preserving its Docker volume.
