# Generates windows/installer/LoeBalance.ico, the icon used by the installer and shortcuts.
# The artwork matches the tray icon: a rounded slate tile with a green status dot.
param(
  [string]$OutputPath = (Join-Path $PSScriptRoot '..\installer\LoeBalance.ico'),
  [int]$Size = 256
)

Add-Type -AssemblyName System.Drawing

$bitmap = New-Object System.Drawing.Bitmap $Size, $Size
$graphics = [System.Drawing.Graphics]::FromImage($bitmap)
$graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$graphics.Clear([System.Drawing.Color]::Transparent)

$inset = [Math]::Round($Size * 0.06)
$tile = New-Object System.Drawing.Rectangle $inset, $inset, ($Size - 2 * $inset), ($Size - 2 * $inset)
$radius = [Math]::Round($Size * 0.22)
$path = New-Object System.Drawing.Drawing2D.GraphicsPath
$path.AddArc($tile.X, $tile.Y, $radius, $radius, 180, 90)
$path.AddArc(($tile.Right - $radius), $tile.Y, $radius, $radius, 270, 90)
$path.AddArc(($tile.Right - $radius), ($tile.Bottom - $radius), $radius, $radius, 0, 90)
$path.AddArc($tile.X, ($tile.Bottom - $radius), $radius, $radius, 90, 90)
$path.CloseFigure()

$tileBrush = New-Object System.Drawing.Drawing2D.LinearGradientBrush $tile, ([System.Drawing.Color]::FromArgb(255, 26, 38, 56)), ([System.Drawing.Color]::FromArgb(255, 15, 22, 34)), 45
$graphics.FillPath($tileBrush, $path)

# Balance bar (the "pill")
$pillHeight = [Math]::Round($Size * 0.16)
$pillWidth = [Math]::Round($Size * 0.56)
$pill = New-Object System.Drawing.Rectangle ([Math]::Round($Size * 0.16)), ([Math]::Round($Size * 0.42)), $pillWidth, $pillHeight
$pillBrush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 242, 244, 248))
$graphics.FillRectangle($pillBrush, $pill)

# Status dot
$dotSize = [Math]::Round($Size * 0.17)
$dotBrush = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255, 48, 209, 88))
$graphics.FillEllipse($dotBrush, ([Math]::Round($Size * 0.23)), ([Math]::Round($Size * 0.415)), $dotSize, $dotSize)

$graphics.Dispose()

$outputDirectory = Split-Path -Parent $OutputPath
if (-not (Test-Path $outputDirectory)) { New-Item -ItemType Directory -Force -Path $outputDirectory | Out-Null }

$handle = $bitmap.GetHicon()
try {
  $icon = [System.Drawing.Icon]::FromHandle($handle)
  $stream = [System.IO.File]::Create($OutputPath)
  try { $icon.Save($stream) } finally { $stream.Dispose(); $icon.Dispose() }
} finally {
  $bitmap.Dispose()
  Add-Type -Namespace LoeIcon -Name Cleanup -MemberDefinition '[DllImport("user32.dll")] public static extern bool DestroyIcon(IntPtr handle);'
  [void][LoeIcon.Cleanup]::DestroyIcon($handle)
}

Write-Output "icon written: $OutputPath ($((Get-Item $OutputPath).Length) bytes)"
