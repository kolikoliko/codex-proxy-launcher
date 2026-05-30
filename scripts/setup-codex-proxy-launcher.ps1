param(
  [string]$ProxyHost = "127.0.0.1",
  [int]$ProxyPort = 0,
  [string]$CodexExe = "",
  [string]$InstallDir = "",
  [switch]$CreateDesktopShortcut,
  [switch]$StartCodex
)

$ErrorActionPreference = "Stop"

if (-not $IsWindows -and $PSVersionTable.PSEdition -eq "Core") {
  throw "codex-proxy-launcher only supports Windows."
}

function Find-ProxyPort {
  param([int[]]$Ports)

  $netstat = netstat -ano -p tcp
  foreach ($line in $netstat) {
    if ($line -match "^\s*TCP\s+\S+:(\d+)\s+\S+\s+LISTENING\s+(\d+)") {
      $port = [int]$matches[1]
      if ($Ports -contains $port) {
        return $port
      }
    }
  }

  return 7890
}

function Find-CodexExe {
  $running = Get-Process -Name Codex -ErrorAction SilentlyContinue |
    Where-Object { $_.Path -and (Test-Path $_.Path) -and ((Split-Path $_.Path -Leaf) -ceq "Codex.exe") } |
    Select-Object -First 1

  if ($running) {
    return $running.Path
  }

  $windowsApps = Join-Path $env:ProgramFiles "WindowsApps"
  $matches = Get-ChildItem -Path $windowsApps -Filter Codex.exe -Recurse -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -like "*OpenAI.Codex_*" } |
    Sort-Object FullName -Descending

  if ($matches) {
    return $matches[0].FullName
  }

  throw "Codex.exe was not found. Start Codex once normally, then run this setup again."
}

if ($ProxyPort -le 0) {
  $ProxyPort = Find-ProxyPort -Ports @(7890, 7897, 7899, 1080, 10808, 10809, 20171, 2080, 8080, 8118)
}

if (-not $CodexExe) {
  $CodexExe = Find-CodexExe
}

if (-not (Test-Path $CodexExe)) {
  throw "Codex executable does not exist: $CodexExe"
}

if (-not $InstallDir) {
  $InstallDir = Join-Path $env:LOCALAPPDATA "OpenAI\CodexProxyLauncher"
}

New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null

$launcherPs1 = Join-Path $InstallDir "Launch-Codex-With-Proxy.ps1"
$launcherCmd = Join-Path $InstallDir "Launch-Codex-With-Proxy.cmd"
$codexExeLiteral = $CodexExe.Replace("'", "''")
$proxyBypass = "localhost,127.0.0.1,::1"

$launcherContent = @"
`$proxyHost = '$ProxyHost'
`$proxyPort = '$ProxyPort'
`$httpProxy = "http://`$(`$proxyHost):`$proxyPort"
`$socksProxy = "socks5://`$(`$proxyHost):`$proxyPort"
`$codexExe = '$codexExeLiteral'

if (-not (Test-Path `$codexExe)) {
  `$process = Get-Process -Name Codex -ErrorAction SilentlyContinue |
    Where-Object { `$_.Path -and ((Split-Path `$_.Path -Leaf) -ceq "Codex.exe") } |
    Select-Object -First 1
  if (`$process) { `$codexExe = `$process.Path }
}

if (-not (Test-Path `$codexExe)) {
  throw "Codex.exe was not found. Start Codex once normally, then run this launcher again."
}

`$env:HTTP_PROXY = `$httpProxy
`$env:HTTPS_PROXY = `$httpProxy
`$env:ALL_PROXY = `$socksProxy
`$env:NO_PROXY = '$proxyBypass'
`$env:http_proxy = `$httpProxy
`$env:https_proxy = `$httpProxy
`$env:all_proxy = `$socksProxy
`$env:no_proxy = '$proxyBypass'

`$args = @(
  "--proxy-server=http=`$(`$proxyHost):`$proxyPort;https=`$(`$proxyHost):`$proxyPort;socks=`$(`$proxyHost):`$proxyPort",
  "--proxy-bypass-list=<-loopback>;localhost;127.0.0.1;::1"
)

Start-Process -FilePath `$codexExe -ArgumentList `$args
"@

Set-Content -LiteralPath $launcherPs1 -Value $launcherContent -Encoding UTF8
Set-Content -LiteralPath $launcherCmd -Value "@echo off`r`nsetlocal`r`npowershell -NoProfile -ExecutionPolicy Bypass -File ""%~dp0Launch-Codex-With-Proxy.ps1""`r`n" -Encoding ASCII

if ($CreateDesktopShortcut) {
  $desktop = [Environment]::GetFolderPath("Desktop")
  $shortcutPath = Join-Path $desktop "Codex Proxy.lnk"
  $shell = New-Object -ComObject WScript.Shell
  $shortcut = $shell.CreateShortcut($shortcutPath)
  $shortcut.TargetPath = $launcherCmd
  $shortcut.WorkingDirectory = $InstallDir
  $shortcut.Description = "Start Codex through local proxy ${ProxyHost}:$ProxyPort"
  $shortcut.IconLocation = "$CodexExe,0"
  $shortcut.Save()
}

$reachable = Test-NetConnection -ComputerName $ProxyHost -Port $ProxyPort -InformationLevel Quiet

if ($StartCodex) {
  Start-Process -FilePath $launcherCmd
}

[PSCustomObject]@{
  Proxy = "${ProxyHost}:$ProxyPort"
  ProxyReachable = $reachable
  CodexExe = $CodexExe
  Launcher = $launcherCmd
  DesktopShortcut = if ($CreateDesktopShortcut) { Join-Path ([Environment]::GetFolderPath("Desktop")) "Codex Proxy.lnk" } else { "" }
}
