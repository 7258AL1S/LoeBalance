param(
  [Parameter(Mandatory = $true)][int]$ProcessId,
  [int]$MoveToX = [int]::MinValue,
  [int]$MoveToY = [int]::MinValue
)

Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
using System.Text;

public static class LoeWindowInspect
{
    public delegate bool EnumProc(IntPtr hWnd, IntPtr lParam);

    [StructLayout(LayoutKind.Sequential)]
    public struct RECT { public int Left, Top, Right, Bottom; }

    [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc callback, IntPtr lParam);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);
    [DllImport("user32.dll")] public static extern int GetWindowLong(IntPtr hWnd, int index);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetWindowText(IntPtr hWnd, StringBuilder text, int count);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetClassName(IntPtr hWnd, StringBuilder text, int count);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT rect);
    [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hWnd);
    [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr hWnd, IntPtr after, int x, int y, int cx, int cy, uint flags);
    [DllImport("user32.dll")] public static extern IntPtr GetWindow(IntPtr hWnd, uint command);
    [DllImport("user32.dll")] public static extern IntPtr MonitorFromWindow(IntPtr hWnd, uint flags);
    [DllImport("user32.dll")] public static extern bool GetMonitorInfo(IntPtr monitor, ref MONITORINFO info);

    [StructLayout(LayoutKind.Sequential)]
    public struct MONITORINFO
    {
        public int cbSize;
        public RECT rcMonitor;
        public RECT rcWork;
        public uint dwFlags;
    }
}
"@

$windows = New-Object System.Collections.ArrayList
$callback = [LoeWindowInspect+EnumProc]{
  param($hWnd, $lParam)
  $pidValue = 0
  [void][LoeWindowInspect]::GetWindowThreadProcessId($hWnd, [ref]$pidValue)
  if ($pidValue -eq $ProcessId) {
    $title = New-Object System.Text.StringBuilder 256
    [void][LoeWindowInspect]::GetWindowText($hWnd, $title, 256)
    $class = New-Object System.Text.StringBuilder 256
    [void][LoeWindowInspect]::GetClassName($hWnd, $class, 256)
    $rect = New-Object LoeWindowInspect+RECT
    [void][LoeWindowInspect]::GetWindowRect($hWnd, [ref]$rect)
    $exStyle = [LoeWindowInspect]::GetWindowLong($hWnd, -20)
    $monitor = [LoeWindowInspect]::MonitorFromWindow($hWnd, 2)
    $monitorInfo = New-Object LoeWindowInspect+MONITORINFO
    $monitorInfo.cbSize = [System.Runtime.InteropServices.Marshal]::SizeOf($monitorInfo)
    $hasMonitor = [LoeWindowInspect]::GetMonitorInfo($monitor, [ref]$monitorInfo)
    $workArea = if ($hasMonitor) { "$($monitorInfo.rcWork.Left),$($monitorInfo.rcWork.Top) $($monitorInfo.rcWork.Right - $monitorInfo.rcWork.Left)x$($monitorInfo.rcWork.Bottom - $monitorInfo.rcWork.Top)" } else { '?' }
    $inside = $hasMonitor -and
      $rect.Left -ge $monitorInfo.rcWork.Left -and
      $rect.Top -ge $monitorInfo.rcWork.Top -and
      $rect.Right -le $monitorInfo.rcWork.Right -and
      $rect.Bottom -le $monitorInfo.rcWork.Bottom
    [void]$windows.Add([pscustomobject]@{
      Handle     = $hWnd
      Title      = $title.ToString()
      Class      = $class.ToString()
      Visible    = [LoeWindowInspect]::IsWindowVisible($hWnd)
      ExStyleHex = ('0x{0:X8}' -f $exStyle)
      ToolWindow = [bool]($exStyle -band 0x00000080)
      AppWindow  = [bool]($exStyle -band 0x00040000)
      NoActivate = [bool]($exStyle -band 0x08000000)
      Topmost    = [bool]($exStyle -band 0x00000008)
      Rect       = "$($rect.Left),$($rect.Top) $($rect.Right - $rect.Left)x$($rect.Bottom - $rect.Top)"
      Owner      = [LoeWindowInspect]::GetWindow($hWnd, 4)
      WorkArea   = $workArea
      InsideWork = $inside
    })
  }
  return $true
}

[void][LoeWindowInspect]::EnumWindows($callback, [IntPtr]::Zero)
$windows | Format-Table -AutoSize | Out-String -Width 220

if ($MoveToX -ne [int]::MinValue) {
  $target = $windows | Where-Object { $_.ToolWindow -and $_.Title -ne '' } | Select-Object -First 1
  if ($target) {
    $rect = New-Object LoeWindowInspect+RECT
    [void][LoeWindowInspect]::GetWindowRect($target.Handle, [ref]$rect)
    $width = $rect.Right - $rect.Left
    $height = $rect.Bottom - $rect.Top
    [void][LoeWindowInspect]::SetWindowPos($target.Handle, [IntPtr]::Zero, $MoveToX, $MoveToY, $width, $height, 0x0014)
    Write-Output "moved handle $($target.Handle) to $MoveToX,$MoveToY (size ${width}x${height})"
  }
}
