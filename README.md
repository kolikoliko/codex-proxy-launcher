# Codex Proxy Launcher

A Windows-only Codex skill that creates a local-proxy launcher for the Codex desktop app.

It helps when Codex desktop occasionally shows `reconnecting` before answering and the user wants Codex itself to start through a local proxy such as Clash or verge-mihomo.

## Platform

This repository is Windows-only.

The bundled setup script depends on:

- Windows PowerShell
- Windows `.lnk` desktop shortcuts
- COM `WScript.Shell`
- Windows Codex desktop install paths
- Local proxy ports such as `127.0.0.1:7890`

macOS and Linux are not supported by this script.

## What It Does

- Finds a local proxy port, defaulting to common ports such as `7890`.
- Finds the Codex desktop `Codex.exe`.
- Generates a launcher under:

```text
%LOCALAPPDATA%\OpenAI\CodexProxyLauncher
```

- Optionally creates or refreshes a desktop shortcut named `Codex Proxy.lnk`.
- Starts Codex with process-scoped proxy environment variables and Electron/Chromium proxy flags.

It does not change Windows global proxy, permanent user environment variables, git config, npm config, or WinHTTP settings.

## Install As A Codex Skill

Copy this folder to the user's Codex skills directory:

```text
C:\Users\<user>\.codex\skills\codex-proxy-launcher
```

Then restart Codex.

Use it with:

```text
Use $codex-proxy-launcher to set up my Codex proxy launcher and desktop shortcut.
```

## Manual Setup

From this repository:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\setup-codex-proxy-launcher.ps1 -CreateDesktopShortcut
```

Use a specific proxy port:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\setup-codex-proxy-launcher.ps1 -ProxyPort 7890 -CreateDesktopShortcut
```

Use a specific Codex executable:

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\setup-codex-proxy-launcher.ps1 -CodexExe "C:\path\to\Codex.exe" -CreateDesktopShortcut
```

## Verify

After launching Codex from the generated shortcut, check the running command line:

```powershell
Get-CimInstance Win32_Process -Filter "name = 'Codex.exe'" |
  Select-Object ProcessId,CommandLine
```

Look for `--proxy-server=...`.

## Recovery

Close Codex and start it normally from the Start Menu to avoid using the launcher.

To remove generated files:

- Delete `Codex Proxy.lnk` from the desktop.
- Delete `%LOCALAPPDATA%\OpenAI\CodexProxyLauncher`.

No global network settings are changed.
