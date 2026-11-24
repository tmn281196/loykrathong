<#
  Bật / tắt tự chạy Loy Krathong mỗi khi đăng nhập Windows.
  Tạo shortcut trong thư mục Startup của bạn (không cần quyền admin), cửa sổ chạy thu nhỏ.

  Bật : powershell -ExecutionPolicy Bypass -File autostart.ps1
  Tắt : powershell -ExecutionPolicy Bypass -File autostart.ps1 -Remove
#>
param([switch]$Remove)

[Console]::OutputEncoding = [Text.Encoding]::UTF8
$startup = [Environment]::GetFolderPath('Startup')
$lnk = Join-Path $startup 'Loy Krathong.lnk'

if ($Remove) {
  if (Test-Path $lnk) { Remove-Item $lnk -Force; Write-Host 'Đã tắt tự chạy khi mở máy.' -ForegroundColor Green }
  else { Write-Host 'Tự chạy chưa được bật.' -ForegroundColor Yellow }
  return
}

$ps = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$script = Join-Path $PSScriptRoot 'start.ps1'
$shell = New-Object -ComObject WScript.Shell
$s = $shell.CreateShortcut($lnk)
$s.TargetPath = $ps
$s.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$script`" -NoBrowser"
$s.WorkingDirectory = $PSScriptRoot
$s.WindowStyle = 7          # thu nhỏ
$s.Description = 'Loy Krathong: server + Cloudflare Tunnel'
$s.Save()
Write-Host "Đã bật tự chạy khi mở máy: $lnk" -ForegroundColor Green
Write-Host 'Mỗi lần mở máy, link mới nằm trong LINK.txt và trên thanh tiêu đề cửa sổ.' -ForegroundColor Gray
