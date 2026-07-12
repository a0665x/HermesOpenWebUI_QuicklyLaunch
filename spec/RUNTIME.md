# Runtime

## Primary Commands

```bash
./run.sh install
./run.sh up
./run.sh restart
./run.sh rebuild
./run.sh status
./run.sh doctor
./run.sh logs
./run.sh stop
./healthcheck.sh
./healthcheck.sh --fix-dns
```

`./run.sh --command restart` and `./run.sh --commend restart` are accepted aliases for wrapper compatibility.

## Default Paths

- Project root: repository checkout directory
- Hermes runtime clone: `./hermes-agent/` ignored by git
- Hermes env file: `~/.hermes/.env`
- Hermes logs: `~/.hermes/logs/`
- Tailscale root: `~/.local/tailscale`
- Open WebUI Docker volume: `open-webui`

## Default URLs

- Open WebUI local: `http://127.0.0.1:3000`
- Hermes API health: `http://127.0.0.1:8642/health`
- Hermes OpenAI-compatible base: `http://127.0.0.1:8642/v1`
- Open WebUI container-to-host base: `http://host.docker.internal:8642/v1`
- Tailscale HTTPS URL: printed by `./run.sh status`, based on MagicDNS name.

## Safe Rebuild Semantics

`./run.sh rebuild` pulls/recreates the Open WebUI container and updates the Hermes checkout. It does not delete the `open-webui` Docker volume, so Open WebUI data should remain intact.

## Health Check Success Signal

`./healthcheck.sh` should end with:

```text
PASS=<n> WARN=0 FAIL=0
Everything looks healthy.
```

Warnings can still be acceptable for optional items; any FAIL should be fixed before relying on the HTTPS URL.
