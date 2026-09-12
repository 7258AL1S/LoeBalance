# Publishes the WPF app for each runtime identifier and wraps it in a per-user installer.
#
#   pwsh -File windows\tools\build-installers.ps1
#   pwsh -File windows\tools\build-installers.ps1 -Version 0.2.0 -Rids win-x64
#
# Requires the .NET 8 SDK and Inno Setup 6 (winget install JRSoftware.InnoSetup --scope user).
param(
  [string]$Version = '0.1.0',
  [string[]]$Rids = @('win-x64', 'win-x86'),
  [string]$Configuration = 'Release'
)

$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$project = Join-Path $repoRoot 'windows\src\LoeBalance.Desktop.Wpf\LoeBalance.Desktop.Wpf.csproj'
$script = Join-Path $repoRoot 'windows\installer\LoeBalance.iss'
$publishRoot = Join-Path $repoRoot 'work\publish'
$outputRoot = Join-Path $repoRoot 'work\installer'

function Get-DotNet {
  $candidates = @(@(
    $env:LOEBALANCE_DOTNET,
    (Join-Path $repoRoot '..\work\dotnet\dotnet.exe'),
    (Join-Path $repoRoot 'work\dotnet\dotnet.exe'),
    (Get-Command dotnet -ErrorAction SilentlyContinue).Source
  ) | Where-Object { $_ -and (Test-Path $_) })

  foreach ($candidate in $candidates) {
    $sdks = & $candidate --list-sdks 2>$null
    if ($LASTEXITCODE -eq 0 -and $sdks) { return $candidate }
  }

  throw 'A .NET SDK was not found. Install .NET 8, set LOEBALANCE_DOTNET, or place it in work\dotnet.'
}

function Get-Iscc {
  $candidates = @(@(
    (Join-Path $env:LOCALAPPDATA 'Programs\Inno Setup 6\ISCC.exe'),
    'C:\Program Files (x86)\Inno Setup 6\ISCC.exe',
    'C:\Program Files\Inno Setup 6\ISCC.exe'
  ) | Where-Object { Test-Path $_ })
  if (-not $candidates) {
    throw 'Inno Setup 6 was not found. Install it with: winget install JRSoftware.InnoSetup --scope user'
  }
  return $candidates[0]
}

$dotnet = Get-DotNet
$iscc = Get-Iscc

# The installer references the icon, so make sure it exists before compiling.
$icon = Join-Path $repoRoot 'windows\installer\LoeBalance.ico'
if (-not (Test-Path $icon)) {
  & (Join-Path $PSScriptRoot 'make-app-icon.ps1') -OutputPath $icon
}

foreach ($rid in $Rids) {
  $publishDir = Join-Path $publishRoot $rid
  Write-Host "== publish $rid =="
  # 2>&1 keeps dotnet's progress output on stderr from tripping $ErrorActionPreference.
  & $dotnet publish $project -c $Configuration -r $rid --self-contained true -o $publishDir 2>&1 | Out-Host
  if ($LASTEXITCODE -ne 0) { throw "dotnet publish failed for $rid" }

  Write-Host "== installer $rid =="
  & $iscc "/DSourceDir=$publishDir" "/DRid=$rid" "/DAppVersion=$Version" "/DOutputDir=$outputRoot" $script 2>&1 | Out-Host
  if ($LASTEXITCODE -ne 0) { throw "ISCC failed for $rid" }
}

Get-ChildItem $outputRoot -Filter 'LoeBalance-Setup-*.exe' |
  Sort-Object Name |
  ForEach-Object {
    $hash = (Get-FileHash -Algorithm SHA256 -Path $_.FullName).Hash.ToLowerInvariant()
    "$($_.Name)  $hash"
    Set-Content -Path "$($_.FullName).sha256" -Value "$hash  $($_.Name)" -Encoding ascii
  }
