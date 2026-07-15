# HermesOpenWebUI QuicklyLaunch

[繁體中文](README.zh-TW.md)

HermesOpenWebUI QuicklyLaunch is a Linux quick-start toolkit for running Hermes Agent, Open WebUI, and Tailscale HTTPS Serve together. After installation, use `./run.sh` to start, restart, update, inspect status, and read logs.

<table>
  <tr>
    <td align="center">
      <a href="img/openwebui.png">
        <img src="img/openwebui.png" alt="Open WebUI after setup" width="92%">
      </a>
      <br>
      <sub><strong>Open WebUI ready after setup</strong></sub>
    </td>
  </tr>
</table>

<table>
  <tr>
    <td align="center">
      <a href="img/run-command.png">
        <img src="img/run-command.png" alt="run.sh command example" width="78%">
      </a>
      <br>
      <sub><strong>One-command startup workflow</strong></sub>
    </td>
  </tr>
</table>

## What it installs and starts

| Component | How it runs | Purpose |
| --- | --- | --- |
| Hermes Agent | Cloned from the official GitHub repository and started in a Python virtual environment | Provides an OpenAI-compatible API |
| Open WebUI | Started from the official Docker image `ghcr.io/open-webui/open-webui:main` | Provides the chat web interface |
| Tailscale Serve | Runs through a local user-space Tailscale daemon | Provides a tailnet HTTPS entrypoint |

This project does not need a Dockerfile. Open WebUI uses its official Docker image directly; Hermes Agent is downloaded and started by `run.sh` in a Python environment.

## Requirements

- Linux
- Docker
- git
- curl
- python3
- Tailscale account and tailnet access
- Optional: uv, for faster Python environment setup

## Quick start

```bash
git clone https://github.com/a0665x/HermesOpenWebUI_QuicklyLaunch.git
cd HermesOpenWebUI_QuicklyLaunch
./run.sh install
./run.sh up
```

On the first Tailscale startup, the terminal may show a login or authorization URL. After authorizing, run:

```bash
./run.sh up
```

After startup, the default endpoints are:

```text
Open WebUI local : http://127.0.0.1:3000
Hermes health    : http://127.0.0.1:8642/health
Tailscale HTTPS  : the Conduit URL shown by ./run.sh status
```

## Common commands

```bash
./run.sh install      # Install Hermes, Open WebUI container, and Tailscale basics
./run.sh up           # Start or repair the full stack
./run.sh restart      # Stop and start again
./run.sh rebuild      # Pull Open WebUI image, recreate container, and refresh Hermes checkout
./run.sh status       # Show services, URLs, and both system/project Tailscale nodes
./run.sh doctor       # Check dependencies and paths
./run.sh logs         # Show recent logs
./run.sh stop         # Stop Hermes, Tailscale daemon, and Open WebUI
```

Wrapper syntax is also supported:

```bash
./run.sh --command restart
./run.sh --commend restart
```

## Health check

```bash
./healthcheck.sh
```

The health check verifies:

- Open WebUI container existence and local reachability
- Hermes API health endpoint
- Tailscale backend state
- Tailscale Serve target
- Tailscale MagicDNS resolution
- HTTPS entrypoint reachability

If the HTTPS URL works from another device but not from this machine, MagicDNS may not be connected locally. Try:

```bash
./healthcheck.sh --fix-dns
```

## Hermes and Open WebUI integration

`./run.sh install` prepares the Hermes API key and configures the Open WebUI container with this OpenAI-compatible API base:

```text
http://host.docker.internal:8642/v1
```

The Open WebUI container uses that address to call the Hermes gateway.

## Update

```bash
./run.sh rebuild
./run.sh up
./healthcheck.sh
```

`rebuild` pulls the Open WebUI image and recreates the container while keeping the Open WebUI Docker volume.

## Configuration

You can override defaults with environment variables:

```bash
HERMES_REPO_URL=https://github.com/NousResearch/hermes-agent.git
HERMES_REF=main
TS_HOSTNAME=agx-openwebui
OPENWEBUI_CONTAINER=open-webui
OPENWEBUI_LOCAL_URL=http://127.0.0.1:3000
OPENWEBUI_IMAGE=ghcr.io/open-webui/open-webui:main
```

API keys can be placed in:

```text
~/.hermes/.env
```

Use `.env.example` as a reference, but do not commit real keys to GitHub.
