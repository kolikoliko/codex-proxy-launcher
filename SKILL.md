---
name: codex-proxy-launcher
description: Create, verify, or repair a Windows-only launcher for the Codex desktop app that starts Codex with local proxy environment variables and Electron/Chromium proxy flags. Use on Windows when Codex itself shows reconnecting, the user wants Codex to use Clash/verge-mihomo/127.0.0.1 proxy, or the user asks for a desktop shortcut to start Codex through a proxy without changing global Windows, git, npm, or system proxy settings. Do not use on macOS or Linux except to explain that the bundled script is Windows-specific.
---

# Codex Proxy Launcher

Use this Windows-only skill to make Codex desktop networking use a local proxy without changing global proxy settings.

This skill depends on Windows PowerShell, Windows `.lnk` shortcuts, COM `WScript.Shell`, and Windows Codex install paths. On macOS or Linux, explain that the bundled automation is not supported and do not run the script.

## Workflow

1. Detect or choose the proxy endpoint.
   - First confirm the host OS is Windows. Stop if it is not Windows.
   - Prefer an active local proxy listener if present.
   - Common ports: `7890`, `7897`, `7899`, `1080`, `10808`, `10809`, `20171`, `2080`, `8080`, `8118`.
   - For `verge-mihomo`, `127.0.0.1:7890` is a common HTTP/SOCKS mixed port.

2. Locate Codex.
   - Prefer the currently running `Codex.exe` path from `Get-Process -Name Codex`.
   - Fall back to installed WindowsApps paths matching `OpenAI.Codex_*`.

3. Create or refresh a launcher script.
   - Use `scripts/setup-codex-proxy-launcher.ps1`.
   - The launcher should scope proxy settings to the Codex process tree only.
   - Do not set global Windows proxy, `git config`, `npm config`, or permanent user environment variables unless the user explicitly asks.

4. Create a desktop shortcut when requested.
   - The shortcut should point to a generated `.cmd` shim, not directly to a fragile one-off terminal command.
   - If a shortcut already exists, update it in place.

5. Verify.
   - Confirm the proxy port is reachable with `Test-NetConnection`.
   - Start Codex with the launcher if the user wants.
   - Check running Codex command lines with `Get-CimInstance Win32_Process -Filter "name = 'Codex.exe'"` and look for `--proxy-server=...`.

## Script

Run the bundled setup script from the skill directory:

```powershell
powershell -ExecutionPolicy Bypass -File scripts\setup-codex-proxy-launcher.ps1 -CreateDesktopShortcut
```

Useful options:

```powershell
# Use a specific port.
powershell -ExecutionPolicy Bypass -File scripts\setup-codex-proxy-launcher.ps1 -ProxyPort 7890 -CreateDesktopShortcut

# Use a specific Codex executable path.
powershell -ExecutionPolicy Bypass -File scripts\setup-codex-proxy-launcher.ps1 -CodexExe "C:\path\to\Codex.exe" -CreateDesktopShortcut
```

## Recovery

To stop using the launcher, close Codex and start it normally from Start Menu. To remove the shortcut, delete `Codex Proxy.lnk` from the desktop. The launcher does not modify global proxy settings.
