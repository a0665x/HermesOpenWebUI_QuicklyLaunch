# HermesOpenWebUI QuicklyLaunch

一鍵啟動 Hermes Agent + Open WebUI + Tailscale Serve 的薄操作層。

這個 repo 只保存安裝與啟動腳本，不 vendoring Hermes Agent 或 Open WebUI 原始碼：

- Hermes Agent 會在 `./run.sh install` 時從 `https://github.com/NousResearch/hermes-agent.git` clone 到本機 `./hermes-agent/`。
- Open WebUI 會使用官方容器映像 `ghcr.io/open-webui/open-webui:main`，資料保存在 Docker volume `open-webui`。
- Tailscale 使用 user-space daemon，預設放在 `~/.local/tailscale`，用 HTTPS Serve 將 tailnet URL 反代到本機 `http://127.0.0.1:3000`。

## 快速開始

```bash
git clone https://github.com/a0665x/HermesOpenWebUI_QuicklyLaunch.git
cd HermesOpenWebUI_QuicklyLaunch
./run.sh install
./run.sh up
```

第一次 Tailscale 可能會印出登入或 Serve approval URL。照提示用瀏覽器核准後，再跑一次：

```bash
./run.sh up
```

## 常用指令

```bash
./run.sh install      # 下載/建立 Hermes、Open WebUI、Tailscale 基本環境
./run.sh up           # 啟動或修復整個 stack
./run.sh restart      # 停掉再啟動
./run.sh rebuild      # pull/recreate Open WebUI container，更新 Hermes checkout，保留 Docker volume
./run.sh status       # 狀態摘要
./run.sh doctor       # 檢查路徑與依賴
./run.sh logs         # 近期 logs
./run.sh stop         # 停止 Hermes、Tailscale daemon、Open WebUI
./healthcheck.sh      # 深度健康檢查
./healthcheck.sh --fix-dns  # 本機 MagicDNS 解析失敗時嘗試修復 accept-dns
```

也支援你原本提到的 wrapper 形式：

```bash
./run.sh --command restart
./run.sh --commend restart
```

## 預設 endpoints

- Open WebUI local: `http://127.0.0.1:3000`
- Hermes API health: `http://127.0.0.1:8642/health`
- OpenAI-compatible Hermes API base for Open WebUI container: `http://host.docker.internal:8642/v1`
- Tailscale hostname: `agx-openwebui`，實際 HTTPS URL 會由 Tailscale status 的 MagicDNS name 決定。

## Open WebUI 與 Hermes 串接方式

`./run.sh install` 會：

1. 確保 `~/.hermes/.env` 有 `API_SERVER_KEY`，沒有就自動產生。
2. 建立 Open WebUI container 時把以下環境變數放進容器：
   - `OPENAI_API_BASE_URL=http://host.docker.internal:8642/v1`
   - `OPENAI_API_BASE_URLS=http://host.docker.internal:8642/v1`
   - `OPENAI_API_KEY=<API_SERVER_KEY>`
   - `OPENAI_API_KEYS=<API_SERVER_KEY>`
3. Hermes gateway 使用 `python -m hermes_cli.main gateway run` 啟動，API server health 預設在 `http://127.0.0.1:8642/health`。

## 不會上傳的內容

`.gitignore` 已排除：

- `hermes-agent/`
- Open WebUI/Hermes runtime state、logs、backups
- `.env` 與 `.env.*`
- Python venv/cache、node_modules、build artifacts
- Tailscale socket/state/log artifacts

因此這個 repo 只保留快速安裝/啟動/健康檢查的方法，避開把 Hermes Agent 或 Open WebUI 專案源碼直接上傳到此 repo。

## 重要環境變數

```bash
HERMES_REPO_URL=https://github.com/NousResearch/hermes-agent.git
HERMES_REF=main
HERMES_REPO=$PWD/hermes-agent
HERMES_ENV=$HOME/.hermes/.env
TS_HOSTNAME=agx-openwebui
OPENWEBUI_CONTAINER=open-webui
OPENWEBUI_LOCAL_URL=http://127.0.0.1:3000
OPENWEBUI_IMAGE=ghcr.io/open-webui/open-webui:main
```

## 需求

- Linux
- Docker
- git
- curl
- python3
- 可選：uv，可加速 Hermes venv 安裝
- Tailscale 帳號與 tailnet 權限

## 安全提醒

不要把 `~/.hermes/.env`、API keys、Tailscale state、Open WebUI data volume 或 logs commit 到 repo。
