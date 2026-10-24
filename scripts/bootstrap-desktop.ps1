[CmdletBinding()]
param([string]$Destination = (Join-Path $PSScriptRoot '..\Vendor\SDL3'))
$ErrorActionPreference = 'Stop'
$version = '3.4.0'
$expectedHash = '4489ba0070b8ce047b8717e4b71fa7e35ac71362e7a6bb2a90a7a27f624b3d5d'
$url = "https://github.com/libsdl-org/SDL/releases/download/release-$version/SDL3-devel-$version-VC.zip"
# Digest verified against official GitHub release metadata and downloaded bytes.
# SDL archive contains x64, x86 and ARM64; the supported game package uses x64.
$Destination = [IO.Path]::GetFullPath($Destination)
New-Item -ItemType Directory -Force -Path $Destination | Out-Null
$archive = Join-Path $Destination "SDL3-devel-$version-VC.zip"
if (!(Test-Path $archive)) {
    $partial = "$archive.partial"
    try {
        Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $partial
        if ((Get-FileHash -Algorithm SHA256 $partial).Hash.ToLowerInvariant() -ne $expectedHash) {
            throw 'SDL3 download checksum does not match the pinned official release.'
        }
        Move-Item -Force $partial $archive
    } finally {
        if (Test-Path $partial) { Remove-Item $partial }
    }
}
if ((Get-FileHash -Algorithm SHA256 $archive).Hash.ToLowerInvariant() -ne $expectedHash) {
    throw "SDL3 archive checksum mismatch: $archive. Remove that archive and retry."
}
$root = Join-Path $Destination "SDL3-$version"
# Re-extract from the verified archive so modified cached headers are replaced.
Expand-Archive -LiteralPath $archive -DestinationPath $Destination -Force
$include = Join-Path $root 'include'
$lib = Join-Path $root 'lib\x64'
foreach ($required in @((Join-Path $include 'SDL3\SDL.h'), (Join-Path $lib 'SDL3.lib'), (Join-Path $lib 'SDL3.dll'), (Join-Path $root 'LICENSE.txt'))) {
    if (!(Test-Path $required)) { throw "SDL archive missing expected file: $required" }
}
$env:SDL3_ROOT = $root
$env:SDL3_INCLUDE = $include
$env:SDL3_LIB = $lib
$env:PATH = "$lib;$env:PATH"
Write-Host "SDL $version verified and unpacked: $root"
Write-Host 'Build in the same PowerShell session; SDL3_ROOT, SDL3_INCLUDE, SDL3_LIB and PATH are set.'
