param(
  [string]$Root = (Resolve-Path (Join-Path $PSScriptRoot "..")).Path
)

$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.IO.Compression.FileSystem

function New-ZipFromFolder {
  param(
    [string]$SourceDir,
    [string]$ZipPath
  )

  if (Test-Path $ZipPath) {
    Remove-Item -LiteralPath $ZipPath -Force
  }

  $archive = [System.IO.Compression.ZipFile]::Open($ZipPath, [System.IO.Compression.ZipArchiveMode]::Create)
  try {
    $prefix = (Resolve-Path $SourceDir).Path.TrimEnd("\", "/") + [IO.Path]::DirectorySeparatorChar
    Get-ChildItem -LiteralPath $SourceDir -Recurse -File | Sort-Object FullName | ForEach-Object {
      $entryName = $_.FullName.Substring($prefix.Length).Replace([IO.Path]::DirectorySeparatorChar, "/").Replace("\", "/")
      [System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile(
        $archive,
        $_.FullName,
        $entryName,
        [System.IO.Compression.CompressionLevel]::Optimal
      ) | Out-Null
    }
  } finally {
    $archive.Dispose()
  }
}

function Write-ModsJson {
  param(
    [string]$ZipPath,
    [string]$ModsJsonPath
  )

  $item = Get-Item -LiteralPath $ZipPath
  $hash = (Get-FileHash -LiteralPath $ZipPath -Algorithm SHA256).Hash.ToLowerInvariant()
  $mods = [ordered]@{
    "DragMP.zip" = [ordered]@{
      filesize = $item.Length
      hash = $hash
      lastwrite = $item.LastWriteTimeUtc.ToFileTimeUtc()
      protected = $false
    }
  }
  $mods | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $ModsJsonPath -Encoding ASCII
}

$dist = Join-Path $Root "dist"
New-Item -ItemType Directory -Force -Path $dist | Out-Null

New-ZipFromFolder (Join-Path $Root "client") (Join-Path $dist "DragMP-Public.zip")
New-ZipFromFolder (Join-Path $Root "client-funblocker") (Join-Path $dist "DragMP-Public-FunBlocker.zip")

Copy-Item -LiteralPath (Join-Path $dist "DragMP-Public.zip") -Destination (Join-Path $Root "local-server\Resources\Client\DragMP.zip") -Force
Copy-Item -LiteralPath (Join-Path $dist "DragMP-Public-FunBlocker.zip") -Destination (Join-Path $Root "local-server-funblocker\Resources\Client\DragMP.zip") -Force

Write-ModsJson (Join-Path $Root "local-server\Resources\Client\DragMP.zip") (Join-Path $Root "local-server\Resources\Client\mods.json")
Write-ModsJson (Join-Path $Root "local-server-funblocker\Resources\Client\DragMP.zip") (Join-Path $Root "local-server-funblocker\Resources\Client\mods.json")

Write-Host "Packaged public DragMP client variants."
