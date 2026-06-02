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

  $appxPackages = Get-AppxPackage -Name OpenAI.Codex -ErrorAction SilentlyContinue |
    Where-Object { $_.InstallLocation } |
    Sort-Object Version -Descending

  foreach ($package in $appxPackages) {
    $candidate = Join-Path $package.InstallLocation "app\Codex.exe"
    if (Test-Path $candidate) {
      return $candidate
    }
  }

  $windowsApps = Join-Path $env:ProgramFiles "WindowsApps"
  $codexInstallCandidates = Get-ChildItem -Path $windowsApps -Directory -Filter "OpenAI.Codex_*" -ErrorAction SilentlyContinue |
    ForEach-Object {
      $candidate = Join-Path $_.FullName "app\Codex.exe"
      if (Test-Path $candidate) {
        $version = [version]"0.0.0.0"
        if ($_.Name -match "^OpenAI\.Codex_([0-9]+(?:\.[0-9]+){1,3})_") {
          $version = [version]$Matches[1]
        }
        [PSCustomObject]@{
          Path = $candidate
          Version = $version
        }
      }
    } |
    Sort-Object Version, Path -Descending

  if ($codexInstallCandidates) {
    return $codexInstallCandidates[0].Path
  }

  throw "Codex.exe was not found. Start Codex once normally, then run this setup again."
}

function Get-ImageSize {
  param([string]$Path)

  Add-Type -AssemblyName System.Drawing
  $image = [System.Drawing.Image]::FromFile($Path)
  try {
    [PSCustomObject]@{
      Width = $image.Width
      Height = $image.Height
    }
  } finally {
    $image.Dispose()
  }
}

function Find-CodexIconPngs {
  param([string]$CodexExePath)

  $packageRoot = Split-Path (Split-Path $CodexExePath -Parent) -Parent
  $assetsDir = Join-Path $packageRoot "Assets"
  if (-not (Test-Path $assetsDir)) {
    return @()
  }

  $preferredNames = @(
    "Square44x44Logo.targetsize-16_altform-unplated.png",
    "Square44x44Logo.targetsize-20_altform-unplated.png",
    "Square44x44Logo.targetsize-24_altform-unplated.png",
    "Square44x44Logo.targetsize-32_altform-unplated.png",
    "Square44x44Logo.targetsize-40_altform-unplated.png",
    "Square44x44Logo.targetsize-48_altform-unplated.png",
    "Square44x44Logo.targetsize-64_altform-unplated.png",
    "Square44x44Logo.targetsize-96_altform-unplated.png",
    "Square44x44Logo.targetsize-256_altform-unplated.png"
  )

  $icons = foreach ($name in $preferredNames) {
    $path = Join-Path $assetsDir $name
    if (Test-Path $path) {
      $size = Get-ImageSize -Path $path
      [PSCustomObject]@{
        Path = $path
        Width = $size.Width
        Height = $size.Height
      }
    }
  }

  if ($icons) {
    return @($icons)
  }

  $fallbacks = Get-ChildItem -LiteralPath $assetsDir -Filter "*.png" -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -match "Logo|icon" } |
    ForEach-Object {
      $size = Get-ImageSize -Path $_.FullName
      [PSCustomObject]@{
        Path = $_.FullName
        Width = $size.Width
        Height = $size.Height
      }
    } |
    Sort-Object Width, Height -Descending |
    Select-Object -First 1

  return @($fallbacks)
}

function Save-IcoFromPngs {
  param(
    [object[]]$Pngs,
    [string]$Destination
  )

  if (-not $Pngs -or $Pngs.Count -eq 0) {
    throw "No PNG icon assets were found."
  }

  $entries = @()
  foreach ($png in $Pngs) {
    $bytes = [System.IO.File]::ReadAllBytes($png.Path)
    $entries += [PSCustomObject]@{
      Width = [int]$png.Width
      Height = [int]$png.Height
      Bytes = $bytes
    }
  }

  $stream = New-Object System.IO.FileStream($Destination, [System.IO.FileMode]::Create)
  $writer = New-Object System.IO.BinaryWriter($stream)
  try {
    $writer.Write([uint16]0)
    $writer.Write([uint16]1)
    $writer.Write([uint16]$entries.Count)

    $offset = 6 + (16 * $entries.Count)
    foreach ($entry in $entries) {
      $writer.Write([byte]($(if ($entry.Width -ge 256) { 0 } else { $entry.Width })))
      $writer.Write([byte]($(if ($entry.Height -ge 256) { 0 } else { $entry.Height })))
      $writer.Write([byte]0)
      $writer.Write([byte]0)
      $writer.Write([uint16]1)
      $writer.Write([uint16]32)
      $writer.Write([uint32]$entry.Bytes.Length)
      $writer.Write([uint32]$offset)
      $offset += $entry.Bytes.Length
    }

    foreach ($entry in $entries) {
      $writer.Write($entry.Bytes)
    }
  } finally {
    $writer.Dispose()
    $stream.Dispose()
  }
}

function Save-StableCodexIcon {
  param(
    [string]$CodexExePath,
    [string]$Destination
  )

  $pngs = Find-CodexIconPngs -CodexExePath $CodexExePath
  if ($pngs) {
    Save-IcoFromPngs -Pngs $pngs -Destination $Destination
    return
  }

  Add-Type -AssemblyName System.Drawing
  $icon = [System.Drawing.Icon]::ExtractAssociatedIcon($CodexExePath)
  if (-not $icon) {
    throw "No associated icon was found."
  }

  $stream = New-Object System.IO.FileStream($Destination, [System.IO.FileMode]::Create)
  try {
    $icon.Save($stream)
  } finally {
    $stream.Dispose()
    $icon.Dispose()
  }
}

if ($ProxyPort -le 0) {
  $ProxyPort = Find-ProxyPort -Ports @(7890, 7897, 7899, 1080, 10808, 10809, 20171, 2080, 8080, 8118)
}

if (-not $CodexExe) {
  $CodexExe = Find-CodexExe
}

if (-not (Test-Path $CodexExe)) {
  Write-Warning "Codex executable does not exist: $CodexExe. Falling back to automatic discovery."
  $CodexExe = Find-CodexExe
}

if (-not $InstallDir) {
  $InstallDir = Join-Path $env:LOCALAPPDATA "OpenAI\CodexProxyLauncher"
}

New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null

$launcherPs1 = Join-Path $InstallDir "Launch-Codex-With-Proxy.ps1"
$launcherCmd = Join-Path $InstallDir "Launch-Codex-With-Proxy.cmd"
$stableIcon = Join-Path $InstallDir "CodexApp.ico"
$legacyIcon = Join-Path $InstallDir "Codex.ico"
$codexExeLiteral = $CodexExe.Replace("'", "''")
$proxyBypass = "localhost,127.0.0.1,::1"

$launcherContent = @"
function Find-CodexExe {
  `$running = Get-Process -Name Codex -ErrorAction SilentlyContinue |
    Where-Object { `$_.Path -and (Test-Path `$_.Path) -and ((Split-Path `$_.Path -Leaf) -ceq "Codex.exe") } |
    Select-Object -First 1

  if (`$running) {
    return `$running.Path
  }

  `$appxPackages = Get-AppxPackage -Name OpenAI.Codex -ErrorAction SilentlyContinue |
    Where-Object { `$_.InstallLocation } |
    Sort-Object Version -Descending

  foreach (`$package in `$appxPackages) {
    `$candidate = Join-Path `$package.InstallLocation "app\Codex.exe"
    if (Test-Path `$candidate) {
      return `$candidate
    }
  }

  `$windowsApps = Join-Path `$env:ProgramFiles "WindowsApps"
  `$codexInstallCandidates = Get-ChildItem -Path `$windowsApps -Directory -Filter "OpenAI.Codex_*" -ErrorAction SilentlyContinue |
    ForEach-Object {
      `$candidate = Join-Path `$_.FullName "app\Codex.exe"
      if (Test-Path `$candidate) {
        `$version = [version]"0.0.0.0"
        if (`$_.Name -match "^OpenAI\.Codex_([0-9]+(?:\.[0-9]+){1,3})_") {
          `$version = [version]`$Matches[1]
        }
        [PSCustomObject]@{
          Path = `$candidate
          Version = `$version
        }
      }
    } |
    Sort-Object Version, Path -Descending

  if (`$codexInstallCandidates) {
    return `$codexInstallCandidates[0].Path
  }

  throw "Codex.exe was not found. Start Codex once normally, then run this launcher again."
}

`$proxyHost = '$ProxyHost'
`$proxyPort = '$ProxyPort'
`$httpProxy = "http://`$(`$proxyHost):`$proxyPort"
`$socksProxy = "socks5://`$(`$proxyHost):`$proxyPort"
`$pinnedCodexExe = '$codexExeLiteral'
`$codexExe = `$null

if (`$pinnedCodexExe -and (Test-Path `$pinnedCodexExe)) {
  `$codexExe = `$pinnedCodexExe
}

if (-not `$codexExe -or -not (Test-Path `$codexExe)) {
  `$codexExe = Find-CodexExe
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

try {
  Save-StableCodexIcon -CodexExePath $CodexExe -Destination $stableIcon
  if ((Test-Path $legacyIcon) -and ($legacyIcon -ne $stableIcon)) {
    Remove-Item -LiteralPath $legacyIcon -Force
  }
} catch {
  Write-Warning "Could not extract a stable shortcut icon from Codex.exe: $($_.Exception.Message)"
}

if ($CreateDesktopShortcut) {
  $desktop = [Environment]::GetFolderPath("Desktop")
  $shortcutPath = Join-Path $desktop "Codex Proxy.lnk"
  $shell = New-Object -ComObject WScript.Shell
  $shortcut = $shell.CreateShortcut($shortcutPath)
  $shortcut.TargetPath = $launcherCmd
  $shortcut.WorkingDirectory = $InstallDir
  $shortcut.Description = "Start Codex through local proxy ${ProxyHost}:$ProxyPort"
  if (Test-Path $stableIcon) {
    $shortcut.IconLocation = "$stableIcon,0"
  } else {
    $shortcut.IconLocation = "$CodexExe,0"
  }
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
  StableIcon = if (Test-Path $stableIcon) { $stableIcon } else { "" }
  DesktopShortcut = if ($CreateDesktopShortcut) { Join-Path ([Environment]::GetFolderPath("Desktop")) "Codex Proxy.lnk" } else { "" }
}
