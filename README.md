<div align="center">

# HermesOpenWebUI QuicklyLaunch

Run Hermes Agent, Open WebUI, and Tailscale HTTPS Serve from one simple command interface.

<p>
  <a href="README.zh-TW.md"><strong>繁體中文</strong></a>
  ·
  <a href="README.en.md"><strong>English</strong></a>
</p>

<p>
  <img alt="Linux" src="https://img.shields.io/badge/Linux-supported-111827?style=flat-square&logo=linux&logoColor=white">
  <img alt="Open WebUI" src="https://img.shields.io/badge/Open%20WebUI-Docker-2563eb?style=flat-square&logo=docker&logoColor=white">
  <img alt="Tailscale" src="https://img.shields.io/badge/Tailscale-HTTPS%20Serve-111827?style=flat-square&logo=tailscale&logoColor=white">
</p>

</div>

<table>
  <tr>
    <td width="50%" valign="top">
      <h3>繁體中文說明</h3>
      <p>從安裝、啟動到健康檢查，使用中文完成整套 Hermes + Open WebUI + Tailscale HTTPS Serve 快速部署。</p>
      <p><a href="README.zh-TW.md"><strong>開啟中文版指南 →</strong></a></p>
    </td>
    <td width="50%" valign="top">
      <h3>English guide</h3>
      <p>Install, start, and verify Hermes + Open WebUI + Tailscale HTTPS Serve with a concise English setup guide.</p>
      <p><a href="README.en.md"><strong>Open English guide →</strong></a></p>
    </td>
  </tr>
</table>

## Preview

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

## Quick start

```bash
git clone https://github.com/a0665x/HermesOpenWebUI_QuicklyLaunch.git
cd HermesOpenWebUI_QuicklyLaunch
./run.sh install
./run.sh up
./healthcheck.sh
```

## Command interface

```bash
./run.sh install    # install required components
./run.sh up         # start or repair the stack
./run.sh restart    # restart everything
./run.sh rebuild    # update and recreate runtime services
./run.sh status     # show services, URLs, and both Tailscale nodes
./healthcheck.sh    # verify Open WebUI, Hermes, Tailscale Serve, and DNS
```

Choose a language above for the full guide.
