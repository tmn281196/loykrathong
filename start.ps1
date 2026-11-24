<#
  Chạy trang Loy Krathong: server Python + Cloudflare Tunnel, rồi in ra link công khai.
  Tunnel rớt thì tự mở lại (link mới được ghi vào LINK.txt).

  Cách dùng : nháy đúp start.bat
              hoặc: powershell -ExecutionPolicy Bypass -File start.ps1 [-Port 8780] [-NoBrowser]
  Dừng      : Ctrl+C, đóng cửa sổ, hoặc nháy đúp stop.bat
#>
param(
  [int]$Port = 8780,
  [switch]$NoBrowser,
  [switch]$Stop
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [Text.Encoding]::UTF8
[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
Set-Location -LiteralPath $PSScriptRoot

$logDir   = Join-Path $PSScriptRoot 'logs'
$pidFile  = Join-Path $logDir 'running.pids'
$linkFile = Join-Path $PSScriptRoot 'LINK.txt'
New-Item -ItemType Directory -Force -Path $logDir | Out-Null

function Say([string]$msg, [string]$color = 'Gray') { Write-Host $msg -ForegroundColor $color }

function Stop-Previous {
  if (-not (Test-Path $pidFile)) { return }
  # dừng cửa sổ start.ps1 cũ trước (để nó không tự chạy lại server), rồi tới server và tunnel
  foreach ($pattern in '^(powershell|pwsh)$', '^(python|pythonw|py|cloudflared)$') {
    foreach ($id in Get-Content $pidFile) {
      if ([int]$id -eq $PID) { continue }
      $p = Get-Process -Id $id -ErrorAction SilentlyContinue
      if ($p -and $p.ProcessName -match $pattern) { Stop-Process -Id $id -Force -ErrorAction SilentlyContinue }
    }
  }
  Remove-Item $pidFile -Force -ErrorAction SilentlyContinue
}

function Test-Port([int]$p) {
  $c = New-Object Net.Sockets.TcpClient
  try { $c.Connect('127.0.0.1', $p); return $true } catch { return $false } finally { $c.Dispose() }
}

function Find-Exe([string]$name, [string[]]$candidates) {
  $cmd = Get-Command $name -ErrorAction SilentlyContinue
  if ($cmd -and $cmd.Source -notmatch 'WindowsApps') { return $cmd.Source }
  foreach ($c in $candidates) { if ($c -and (Test-Path $c)) { return $c } }
  return $null
}

function Read-Shared([string]$path) {
  if (-not (Test-Path $path)) { return '' }
  $fs = [IO.File]::Open($path, 'Open', 'Read', 'ReadWrite')
  try { (New-Object IO.StreamReader($fs)).ReadToEnd() } finally { $fs.Dispose() }
}

function Save-Pids { Set-Content -Path $pidFile -Value (@($PID) + @(@($script:server, $script:tunnel) | Where-Object { $_ } | ForEach-Object { $_.Id })) }

Stop-Previous
if ($Stop) { Say 'Đã dừng server và tunnel (nếu đang chạy).' 'Green'; return }

# ---------- kiểm tra công cụ ----------
$python = Find-Exe 'python' @()
if (-not $python) { $python = Find-Exe 'py' @() }
if (-not $python) { Say 'Không tìm thấy Python. Cài Python từ https://www.python.org rồi chạy lại.' 'Red'; Read-Host 'Nhấn Enter để đóng'; exit 1 }

$cloudflared = Find-Exe 'cloudflared' @(
  "${env:ProgramFiles(x86)}\cloudflared\cloudflared.exe",
  "$env:ProgramFiles\cloudflared\cloudflared.exe")
if (-not $cloudflared) {
  Say 'Chưa cài cloudflared. Cài bằng lệnh sau rồi chạy lại:' 'Red'
  Say '  winget install --id Cloudflare.cloudflared' 'Yellow'
  Read-Host 'Nhấn Enter để đóng'; exit 1
}

if (Test-Port $Port) {
  Say "Cổng $Port đang được dùng (có thể server đang chạy ở cửa sổ khác)." 'Red'
  Say 'Đóng cửa sổ đó (hoặc chạy stop.bat), hoặc dùng cổng khác:  start.bat -Port 8781' 'Yellow'
  Read-Host 'Nhấn Enter để đóng'; exit 1
}

$Host.UI.RawUI.WindowTitle = 'Loy Krathong - đang khởi động'
Say ''
Say '  ลอยกระทง · Loy Krathong' 'Yellow'
Say ''

$env:PORT = "$Port"; $env:PYTHONUTF8 = '1'; $env:PYTHONUNBUFFERED = '1'
$srvLog = Join-Path $logDir 'server.log'
$srvErr = Join-Path $logDir 'server-error.log'
$tunLog = Join-Path $logDir 'tunnel.log'
$script:server = $null; $script:tunnel = $null

# Mở tunnel và chờ đến khi có link + link vào được. Thử lại mãi nếu mạng chưa sẵn sàng (ví dụ vừa mở máy).
function Start-Tunnel {
  $attempt = 0
  while ($true) {
    $attempt++
    if ($script:tunnel -and -not $script:tunnel.HasExited) { Stop-Process -Id $script:tunnel.Id -Force -ErrorAction SilentlyContinue }
    Remove-Item $tunLog -Force -ErrorAction SilentlyContinue
    $script:tunnel = Start-Process -FilePath $cloudflared `
      -ArgumentList @('tunnel', '--no-autoupdate', '--protocol', 'http2', '--url', "http://127.0.0.1:$Port") `
      -NoNewWindow -PassThru -RedirectStandardOutput (Join-Path $logDir 'tunnel-out.log') -RedirectStandardError $tunLog
    Save-Pids

    $url = $null
    for ($i = 0; $i -lt 60; $i++) {
      if ($script:tunnel.HasExited) { break }
      $m = [regex]::Match((Read-Shared $tunLog), 'https://[a-z0-9-]+\.trycloudflare\.com')
      if ($m.Success) { $url = $m.Value; break }
      Start-Sleep -Milliseconds 500
    }
    if ($url) {
      for ($i = 0; $i -lt 30; $i++) {
        if ($script:tunnel.HasExited) { break }
        try {
          $r = Invoke-WebRequest "$url/api/people" -UseBasicParsing -TimeoutSec 5
          if ($r.StatusCode -eq 200) { return $url }
        } catch { }
        Start-Sleep -Seconds 2
      }
    }
    $wait = [Math]::Min(60, 10 * $attempt)
    Say "  Chưa mở được tunnel (lần $attempt, có thể mạng chưa sẵn sàng). Thử lại sau $wait giây..." 'DarkYellow'
    Start-Sleep -Seconds $wait
  }
}

function Show-Link([string]$url) {
  Set-Content -Path $linkFile -Value $url
  try { Set-Clipboard -Value $url } catch { }
  $Host.UI.RawUI.WindowTitle = "Loy Krathong - $url"
  Say ''
  Say '  ==============================================================' 'DarkYellow'
  Say ('   Link gửi cho mọi người   (' + (Get-Date -Format 'HH:mm dd/MM') + ')') 'Yellow'
  Say "   $url" 'Cyan'
  Say '   (đã chép vào clipboard và lưu trong LINK.txt)' 'DarkGray'
  Say "   Xem trên máy này: http://127.0.0.1:$Port" 'DarkGray'
  Say '  ==============================================================' 'DarkYellow'
  Say ''
}

try {
  # ---------- server ----------
  Say "[1/2] Khởi động server ở cổng $Port..."
  $script:server = Start-Process -FilePath $python -ArgumentList 'server.py' -WorkingDirectory $PSScriptRoot `
    -NoNewWindow -PassThru -RedirectStandardOutput $srvLog -RedirectStandardError $srvErr
  Save-Pids
  $ok = $false
  for ($i = 0; $i -lt 40; $i++) {
    if ($script:server.HasExited) { break }
    if (Test-Port $Port) { $ok = $true; break }
    Start-Sleep -Milliseconds 250
  }
  if (-not $ok) { Say 'Server không khởi động được:' 'Red'; Read-Shared $srvErr | Write-Host; Read-Host 'Nhấn Enter để đóng'; exit 1 }

  # ---------- tunnel ----------
  Say '[2/2] Mở Cloudflare Tunnel...'
  $url = Start-Tunnel
  Show-Link $url
  Say '  Giữ cửa sổ này mở. Nhấn Ctrl+C hoặc đóng cửa sổ để dừng.' 'Gray'
  Say '  Lời chúc mới sẽ hiện ở dưới:' 'Gray'
  Say ''
  if (-not $NoBrowser) { Start-Process $url }

  # ---------- theo dõi ----------
  $seen = @((Read-Shared $srvLog) -split "`r?`n" | Where-Object { $_ -match '^\s+\+ ' }).Count
  while ($true) {
    if ($script:server.HasExited) {
      Say 'Server dừng bất ngờ, đang chạy lại... (chi tiết: logs\server-error.log)' 'Red'
      $script:server = Start-Process -FilePath $python -ArgumentList 'server.py' -WorkingDirectory $PSScriptRoot `
        -NoNewWindow -PassThru -RedirectStandardOutput $srvLog -RedirectStandardError $srvErr
      Save-Pids; $seen = 0; Start-Sleep -Seconds 2
    }
    if ($script:tunnel.HasExited) {
      Say 'Tunnel bị ngắt, đang mở lại (link sẽ đổi)...' 'Red'
      $url = Start-Tunnel
      Show-Link $url
    }
    $lines = @((Read-Shared $srvLog) -split "`r?`n" | Where-Object { $_ -match '^\s+\+ ' })
    for ($j = $seen; $j -lt $lines.Count; $j++) {
      Say ('  ✿ ' + $lines[$j].Trim().Substring(2) + '   (' + (Get-Date -Format 'HH:mm') + ')') 'Green'
    }
    $seen = $lines.Count
    Start-Sleep -Seconds 2
  }
}
finally {
  foreach ($p in @($script:tunnel, $script:server)) {
    if ($p -and -not $p.HasExited) { Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue }
  }
  Remove-Item $pidFile -Force -ErrorAction SilentlyContinue
  Say ''
  Say 'Đã dừng server và tunnel.' 'Yellow'
}
