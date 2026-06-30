param(
  [switch]$FunBlocker
)

$ErrorActionPreference = "Stop"
$root = Resolve-Path (Join-Path $PSScriptRoot "..")
$serverDir = if ($FunBlocker) {
  Join-Path $root "local-server-funblocker"
} else {
  Join-Path $root "local-server"
}

$configSource = if ($FunBlocker) {
  Join-Path $root "ServerConfig.public-funblocker.example.toml"
} else {
  Join-Path $root "ServerConfig.public.example.toml"
}
$configPath = Join-Path $serverDir "ServerConfig.toml"
if (-not (Test-Path $configPath)) {
  Copy-Item -LiteralPath $configSource -Destination $configPath
}

Start-Process -FilePath (Join-Path $serverDir "BeamMP-Server.exe") -WorkingDirectory $serverDir -WindowStyle Hidden
Write-Host "Started DragMP public server at $serverDir"
