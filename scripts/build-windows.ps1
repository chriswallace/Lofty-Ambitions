# Windows 11 x64 build/verification handoff. This script has not been run on Windows
# in the Mac authoring environment. Run it on the PC and return its diagnostics ZIP.
[CmdletBinding()]
param([string]$OutputDirectory = (Join-Path $PSScriptRoot '..\dist\windows'))
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if ($env:OS -ne 'Windows_NT' -or ![Environment]::Is64BitProcess -or $env:PROCESSOR_ARCHITECTURE -ne 'AMD64') {
    throw 'Run this script in 64-bit PowerShell on Windows 11 x64.'
}
$project = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..'))
$OutputDirectory = [IO.Path]::GetFullPath($OutputDirectory)
$stamp = (Get-Date).ToUniversalTime().ToString('yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N').Substring(0,8)
$diagnostics = Join-Path $OutputDirectory "diagnostics-$stamp"
New-Item -ItemType Directory -Force $diagnostics | Out-Null
$status = [ordered]@{ status = 'failed'; windowsExecution = 'started'; cleanMachineValidation = 'pending'; version = ''; error = ''; startedUTC = (Get-Date).ToUniversalTime().ToString('o') }
$failure = $null
$transcribing = $false
$oldLocation = Get-Location

function Invoke-Checked([string]$File, [string[]]$Arguments, [string]$LogName) {
    Write-Host "Running: $File $($Arguments -join ' ')"
    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try {
        & $File @Arguments 2>&1 | Tee-Object -FilePath (Join-Path $diagnostics $LogName) | Out-Host
        $code = $LASTEXITCODE
    } finally { $ErrorActionPreference = $previousPreference }
    if ($code -ne 0) { throw "$File failed with exit code $code. See $LogName." }
}
function Get-CheckedOutput([string]$File, [string[]]$Arguments, [string]$LogName) {
    $previousPreference = $ErrorActionPreference
    $ErrorActionPreference = 'Continue'
    try { $lines = @(& $File @Arguments 2> (Join-Path $diagnostics "$LogName.stderr.txt")); $code = $LASTEXITCODE }
    finally { $ErrorActionPreference = $previousPreference }
    $text = ($lines | ForEach-Object { $_.ToString() }) -join [Environment]::NewLine
    $text | Set-Content -Encoding UTF8 (Join-Path $diagnostics $LogName)
    if ($code -ne 0) { throw "$File failed with exit code $code. See $LogName." }
    return $text
}
function Initialize-DeveloperTools {
    if (Get-Command dumpbin.exe -ErrorAction SilentlyContinue) { return }
    $vswhere = Join-Path ${env:ProgramFiles(x86)} 'Microsoft Visual Studio\Installer\vswhere.exe'
    if (!(Test-Path $vswhere)) { throw 'Install Visual Studio 2022 C++ x64 build tools and a Windows 11 SDK; see docs/porting/WINDOWS.md.' }
    $installation = Get-CheckedOutput $vswhere @('-latest','-products','*','-requires','Microsoft.VisualStudio.Component.VC.Tools.x86.x64','-property','installationPath') 'visual-studio-location.txt'
    $devcmd = Join-Path $installation.Trim() 'Common7\Tools\VsDevCmd.bat'
    if (!(Test-Path $devcmd)) { throw 'Visual Studio x64 C++ developer tools were not found.' }
    # Only import the environment produced by the installed VS developer shell.
    $command = "call `"$devcmd`" -no_logo -arch=x64 -host_arch=x64 >nul && set"
    $environment = @(& $env:ComSpec /d /c $command)
    if ($LASTEXITCODE -ne 0) { throw 'Could not initialize the Visual Studio developer environment.' }
    foreach ($line in $environment) {
        $separator = $line.IndexOf('=')
        if ($separator -gt 0) { [Environment]::SetEnvironmentVariable($line.Substring(0,$separator), $line.Substring($separator+1), 'Process') }
    }
}
function Find-Swift {
    if (Get-Command swiftc.exe -ErrorAction SilentlyContinue) { return }
    foreach ($root in @((Join-Path $env:LOCALAPPDATA 'Programs\Swift'), (Join-Path $env:ProgramFiles 'Swift'))) {
        if (!(Test-Path $root)) { continue }
        $compiler = Get-ChildItem -LiteralPath $root -Filter swiftc.exe -Recurse -File | Sort-Object FullName -Descending | Select-Object -First 1
        if ($compiler) { $env:PATH = "$($compiler.DirectoryName);$env:PATH"; return }
    }
    throw 'Swift 6.4.1 was not found. Install the official Windows toolchain, reopen PowerShell, and retry.'
}
function Invoke-Application([string]$Executable, [string[]]$Arguments, [string]$Directory, [string]$Name) {
    $stdout = Join-Path $diagnostics "$Name.stdout.txt"
    $stderr = Join-Path $diagnostics "$Name.stderr.txt"
    # Start-Process needs explicit quoting for arguments containing spaces on PS 5.1.
    $quoted = @($Arguments | ForEach-Object { '"' + $_.Replace('"','\"') + '"' })
    $process = Start-Process -FilePath $Executable -ArgumentList $quoted -WorkingDirectory $Directory -RedirectStandardOutput $stdout -RedirectStandardError $stderr -WindowStyle Hidden -PassThru
    if (!$process.WaitForExit(120000)) {
        $process.Kill(); $process.WaitForExit()
        throw "$Name exceeded the 120-second timeout. See its stdout/stderr logs."
    }
    $process.WaitForExit()
    if ($process.ExitCode -ne 0) { throw "$Name failed with exit code $($process.ExitCode). See its stdout/stderr logs." }
    Get-Content -LiteralPath $stdout | ForEach-Object { Write-Host $_ }
}
function Save-VerifiedNotice([string]$Name,[string]$URL,[string]$SHA256,[string]$LicenseDirectory) {
    $destination = Join-Path $LicenseDirectory $Name
    Invoke-WebRequest -UseBasicParsing -Uri $URL -OutFile $destination
    if ((Get-FileHash -Algorithm SHA256 $destination).Hash.ToLowerInvariant() -ne $SHA256) {
        throw "Pinned upstream notice checksum mismatch: $Name"
    }
}

try {
    Start-Transcript -Path (Join-Path $diagnostics 'build-transcript.txt') | Out-Null
    $transcribing = $true
    Set-Location $project
    $version = (Get-Content -LiteralPath (Join-Path $project 'VERSION') -Raw).Trim()
    if ($version -notmatch '^\d+\.\d+\.\d+$') { throw 'VERSION must contain a numeric major.minor.patch release version.' }
    $status.version = $version
    Initialize-DeveloperTools
    Find-Swift
    foreach ($tool in @('swift.exe','swiftc.exe','dumpbin.exe','editbin.exe')) {
        if (!(Get-Command $tool -ErrorAction SilentlyContinue)) { throw "Required developer tool missing: $tool" }
    }
    $compiler = (Get-Command swiftc.exe).Source
    $swift = (Get-Command swift.exe).Source
    $swiftVersion = Get-CheckedOutput $swift @('--version') 'swift-version.txt'
    if ($swiftVersion -notmatch '\b6\.4\.1\b') { throw "This package builder pins Swift 6.4.1. Found: $swiftVersion" }
    $targetJSON = Get-CheckedOutput $compiler @('-print-target-info') 'swift-target-info.json'
    $target = $targetJSON | ConvertFrom-Json
    if ($target.target.triple -notmatch '^x86_64-.*windows') { throw "Expected an x64 Windows Swift target, found $($target.target.triple)." }
    Get-CimInstance Win32_OperatingSystem | Select-Object Caption,Version,BuildNumber,OSArchitecture | ConvertTo-Json | Set-Content -Encoding UTF8 (Join-Path $diagnostics 'windows.json')
    Get-CimInstance Win32_VideoController | Select-Object Name,DriverVersion | ConvertTo-Json | Set-Content -Encoding UTF8 (Join-Path $diagnostics 'graphics.json')

    & (Join-Path $PSScriptRoot 'bootstrap-desktop.ps1')
    $env:LOFTY_DESKTOP = '1'
    $env:LOFTY_SDL_ROOT = $env:SDL3_ROOT
    Invoke-Checked $swift @('test','-c','release') 'swift-test.log'
    Invoke-Checked $swift @('build','-c','release','--product','LoftyDesktop') 'swift-build-desktop.log'
    Invoke-Checked $swift @('build','-c','release','--product','TowerReplay') 'swift-build-replay.log'
    $products = (Get-CheckedOutput $swift @('build','-c','release','--show-bin-path') 'swift-products.txt').Trim()
    $desktop = Join-Path $products 'LoftyDesktop.exe'
    $replay = Join-Path $products 'TowerReplay.exe'
    foreach ($executable in @($desktop,$replay)) { if (!(Test-Path $executable)) { throw "Build product missing: $executable" } }
    $fixture = Join-Path $project 'Tests\Fixtures\construction-transit-fire-v1.json'
    $baseline = Join-Path $project 'Tests\Fixtures\construction-transit-fire-v1.snapshot.json'
    $snapshot = Join-Path $diagnostics 'replay.snapshot.json'
    Invoke-Checked $replay @('--self-check','--fixture',$fixture,'--output',$snapshot) 'replay.log'
    $python = Get-Command python.exe -ErrorAction SilentlyContinue
    if (!$python) { throw 'Python is required for the build-time parity check; install it as described in docs/porting/WINDOWS.md.' }
    Invoke-Checked $python.Source @((Join-Path $PSScriptRoot 'check-parity.py'),'--actual',$snapshot,'--report',(Join-Path $diagnostics 'parity.json')) 'parity.log'
    $sourceSmoke = Join-Path $diagnostics 'source-smoke'
    Invoke-Application $desktop @('--smoke','--smoke-output',$sourceSmoke) $diagnostics 'source-smoke'

    # Each run gets a new staging directory. Never clear an installed application
    # or the output root. No ordinary game save directory is opened by --smoke.
    $packageName = "Lofty-Ambitions-$version-windows-x86_64-$stamp"
    $package = Join-Path $OutputDirectory $packageName
    New-Item -ItemType Directory $package | Out-Null
    Copy-Item -LiteralPath $desktop -Destination (Join-Path $package 'LoftyDesktop.exe')
    Copy-Item -LiteralPath $replay -Destination (Join-Path $package 'TowerReplay.exe')
    Copy-Item -LiteralPath (Join-Path $env:SDL3_LIB 'SDL3.dll') -Destination $package
    # Discover SwiftPM's actual adjacent resource directory rather than assuming
    # the Mac .bundle or Windows .resources suffix. Preserve its exact basename.
    $resources = @(Get-ChildItem -LiteralPath $products -Directory | Where-Object { $_.Name -match 'TowerArt' -and $_.Extension -in @('.resources','.bundle') })
    if ($resources.Count -ne 1) { throw "Expected exactly one TowerArt resource directory beside the built executable; found $($resources.Count)." }
    Copy-Item -LiteralPath $resources[0].FullName -Destination $package -Recurse
    $resourceFiles = @(Get-ChildItem -LiteralPath (Join-Path $package $resources[0].Name) -File -Recurse)
    if (!($resourceFiles | Where-Object Name -eq 'atlas.json') -or !($resourceFiles | Where-Object Name -eq 'TitleScreen.png') -or !($resourceFiles | Where-Object Extension -eq '.png')) { throw 'The packaged TowerArt resource directory is incomplete.' }

    $swiftBin = Split-Path $compiler -Parent
    $candidates = [Collections.Generic.List[string]]::new()
    foreach ($path in @($target.paths.runtimeLibraryPaths) + @($target.paths.runtimeResourcePath)) {
        if (!$path) { continue }
        foreach ($relative in @('.', '..\bin','..\..\bin','..\..\..\bin')) {
            $candidate = [IO.Path]::GetFullPath((Join-Path $path $relative))
            if (Test-Path $candidate -PathType Container) { $candidates.Add($candidate) }
        }
    }
    # Derive install ancestors from the compiler, never from a guessed drive or
    # user name. The official installer stores runtimes separately from tools.
    $ancestor = Get-Item -LiteralPath $swiftBin
    $installRoot = $null
    while ($ancestor) {
        if (Test-Path (Join-Path $ancestor.FullName 'Runtimes')) { $installRoot = $ancestor.FullName; break }
        $ancestor = $ancestor.Parent
    }
    if ($installRoot) {
        foreach ($runtime in @(Get-ChildItem -LiteralPath (Join-Path $installRoot 'Runtimes') -Directory | Where-Object Name -like '6.4.1*')) {
            $candidate = Join-Path $runtime.FullName 'usr\bin'
            if (Test-Path $candidate) { $candidates.Add($candidate) }
        }
    }
    $candidates.Add($swiftBin)
    if ($env:SDKROOT -and (Test-Path (Join-Path $env:SDKROOT 'usr\bin'))) { $candidates.Add((Join-Path $env:SDKROOT 'usr\bin')) }
    $runtimeBin = $candidates | Where-Object { Test-Path (Join-Path $_ 'swiftCore.dll') } | Select-Object -First 1
    if (!$runtimeBin) { throw 'No Swift runtime directory containing swiftCore.dll was found via target info or the installed compiler layout.' }
    Get-ChildItem -LiteralPath $runtimeBin -Filter '*.dll' -File | Copy-Item -Destination $package
    $search = [Collections.Generic.List[string]]::new()
    $search.Add($package); $search.Add($runtimeBin)
    foreach ($candidate in $candidates) { $search.Add($candidate) }
    $search.Add($env:SDL3_LIB)
    if ($env:VCToolsRedistDir) {
        $redist = Join-Path $env:VCToolsRedistDir 'x64'
        if (Test-Path $redist) { foreach ($dir in @(Get-ChildItem -LiteralPath $redist -Directory)) { $search.Add($dir.FullName) } }
    }
    $dependencies = [ordered]@{}
    $pending = [Collections.Generic.Queue[string]]::new()
    Get-ChildItem -LiteralPath $package -File | Where-Object Extension -in @('.exe','.dll') | ForEach-Object { $pending.Enqueue($_.FullName) }
    $visited = @{}
    while ($pending.Count -gt 0) {
        $binary = $pending.Dequeue(); $name = [IO.Path]::GetFileName($binary)
        if ($visited.ContainsKey($name.ToLowerInvariant())) { continue }
        $visited[$name.ToLowerInvariant()] = $true
        $headers = Get-CheckedOutput 'dumpbin.exe' @('/NOLOGO','/HEADERS',$binary) "headers-$name.txt"
        if ($headers -notmatch '(?im)^\s*8664 machine') { throw "Non-x64 binary discovered: $binary" }
        $imports = Get-CheckedOutput 'dumpbin.exe' @('/NOLOGO','/DEPENDENTS',$binary) "dependencies-$name.txt"
        $names = @([regex]::Matches($imports,'(?im)^\s*([^\s]+\.dll)\s*$') | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique)
        $dependencies[$name] = $names
        foreach ($dependency in $names) {
            if ($dependency -match '^(api-ms-win-|ext-ms-win-)') { continue }
            $resolved = $null
            foreach ($dir in $search) {
                $candidate = Join-Path $dir $dependency
                if (Test-Path $candidate -PathType Leaf) { $resolved = $candidate; break }
            }
            if ($resolved) {
                $destination = Join-Path $package $dependency
                if ([IO.Path]::GetFullPath($resolved) -ne [IO.Path]::GetFullPath($destination)) { Copy-Item -LiteralPath $resolved -Destination $destination }
                $pending.Enqueue($destination)
            } elseif ($dependency -match '^(vcruntime|msvcp|concrt|vcomp)') {
                throw "MSVC redistributable $dependency was not found in the installed x64 redistributable files. Do not copy it from System32."
            } elseif (!(Test-Path (Join-Path $env:SystemRoot "System32\$dependency"))) {
                throw "Unresolved runtime dependency $dependency required by $name."
            }
        }
    }
    $dependencies | ConvertTo-Json -Depth 20 | Set-Content -Encoding UTF8 (Join-Path $diagnostics 'runtime-dependencies.json')
    # Keep the compiler-selected entry point and change only the packaged game's
    # PE subsystem, allowing ordinary Explorer launches without a console window.
    Invoke-Checked 'editbin.exe' @('/NOLOGO','/SUBSYSTEM:WINDOWS',(Join-Path $package 'LoftyDesktop.exe')) 'gui-subsystem.log'
    $guiHeaders = Get-CheckedOutput 'dumpbin.exe' @('/NOLOGO','/HEADERS',(Join-Path $package 'LoftyDesktop.exe')) 'packaged-gui-headers.txt'
    if ($guiHeaders -notmatch '(?im)^\s*2 subsystem') { throw 'The packaged game did not retain the Windows GUI subsystem.' }

    $licenses = Join-Path $package 'Licenses'
    New-Item -ItemType Directory $licenses | Out-Null
    Copy-Item -LiteralPath (Join-Path $project 'Sources\CDesktop\SDL-LICENSE.txt') -Destination (Join-Path $licenses 'SDL3.txt')
    Copy-Item -LiteralPath (Join-Path $project 'Vendor\stb\LICENSE') -Destination (Join-Path $licenses 'stb.txt')
    # Runtime notices are exact-release upstream files, checksum-verified. Copy
    # any additional installed notices as well, keeping their relative locations.
    $noticePins = @(
        @('Swift.txt','swiftlang/swift/swift-6.4.1-RELEASE/LICENSE.txt','770af8291f708538d8ff885a0bbc4e045cd700531741c4f99528d435c14d7f55'),
        @('Foundation.txt','swiftlang/swift-corelibs-foundation/swift-6.4.1-RELEASE/LICENSE','0ca84095d1de77cad1a866ebbad28f8db98a0826c6055d92b0608c5baa1643e2'),
        @('FoundationEssentials.txt','swiftlang/swift-foundation/swift-6.4.1-RELEASE/LICENSE.md','2245a990b635558be210fb3eb4f8a6f7a49aebc0fefbf5859146a65ddc7ddcf3'),
        @('Foundation-NOTICE.txt','swiftlang/swift-foundation/swift-6.4.1-RELEASE/NOTICE.txt','c2e757911b86a76230099804831d8d847a865e88b5912171627492a7a49f0456'),
        @('Dispatch.txt','swiftlang/swift-corelibs-libdispatch/swift-6.4.1-RELEASE/LICENSE','0ca84095d1de77cad1a866ebbad28f8db98a0826c6055d92b0608c5baa1643e2'),
        @('FoundationICU.txt','swiftlang/swift-foundation-icu/swift-6.4.1-RELEASE/LICENSE.md','2245a990b635558be210fb3eb4f8a6f7a49aebc0fefbf5859146a65ddc7ddcf3'),
        @('ICU-76.1.txt','unicode-org/icu/release-76-1/LICENSE','01edac20612b1e590c1c1cfb02b7218c6adc7b0a944eda7a1e03aeee10725aed')
    )
    foreach ($pin in $noticePins) { Save-VerifiedNotice $pin[0] "https://raw.githubusercontent.com/$($pin[1])" $pin[2] $licenses }
    if ($installRoot) {
        $installedNotices = @(Get-ChildItem -LiteralPath $installRoot -Recurse -File | Where-Object { $_.Name -match '^(LICENSE|NOTICE|COPYING|THIRD.PARTY)' })
        foreach ($notice in $installedNotices) {
            $relative = $notice.FullName.Substring($installRoot.Length).TrimStart('\')
            $destination = Join-Path (Join-Path $licenses 'InstalledSwift') $relative
            New-Item -ItemType Directory -Force (Split-Path $destination -Parent) | Out-Null
            Copy-Item -LiteralPath $notice.FullName -Destination $destination
        }
    }
    $verification = Join-Path $package 'Verification'
    New-Item -ItemType Directory $verification | Out-Null
    Copy-Item -LiteralPath $fixture,$baseline -Destination $verification
    Copy-Item -LiteralPath (Join-Path $project 'VERSION') -Destination $package
    @"
Lofty Ambitions $version — Windows x64 verification build

Double-click LoftyDesktop.exe. Keep all adjacent DLLs and the TowerArt resource
folder together. No Swift toolchain, Homebrew, Python, or source checkout is
needed to play this package. Windows 11 x64 is the supported platform.

This build completed automated checks on its builder. A separate clean Windows
machine and manual gameplay checks are still required before a public release.
The developer instructions and verification checklist are in docs/porting/WINDOWS.md
in the source archive. Third-party licenses are in Licenses.
"@ | Set-Content -Encoding UTF8 (Join-Path $package 'README.txt')

    $isolated = Join-Path $diagnostics 'unrelated-working-directory'
    New-Item -ItemType Directory $isolated | Out-Null
    $oldPath = $env:PATH
    try {
        # Verify app-local DLL resolution without the build machine's Swift/SDL
        # PATH. This is useful evidence, but does not replace a clean-PC run.
        $env:PATH = "$env:SystemRoot\System32;$env:SystemRoot;$env:SystemRoot\System32\Wbem"
        Invoke-Application (Join-Path $package 'TowerReplay.exe') @('--self-check','--fixture',(Join-Path $verification ([IO.Path]::GetFileName($fixture))),'--output',(Join-Path $diagnostics 'packaged-replay.snapshot.json')) $isolated 'packaged-replay'
        Invoke-Application (Join-Path $package 'LoftyDesktop.exe') @('--smoke','--smoke-output',(Join-Path $diagnostics 'packaged-smoke')) $isolated 'packaged-smoke'
        Invoke-Application (Join-Path $package 'LoftyDesktop.exe') @('--performance-smoke','--tower',(Join-Path $project 'Examples\Express & Local.loftyambitions'),'--smoke-output',(Join-Path $diagnostics 'resize-performance')) $isolated 'resize-performance'
    } finally { $env:PATH = $oldPath }
    foreach ($png in @('desktop-gameplay.png','desktop-progression.png','desktop-building.png')) {
        if (!(Test-Path (Join-Path $diagnostics "packaged-smoke\$png"))) { throw "Packaged smoke screenshot missing: $png" }
    }
    Invoke-Checked $python.Source @((Join-Path $PSScriptRoot 'check-parity.py'),'--actual',(Join-Path $diagnostics 'packaged-replay.snapshot.json'),'--report',(Join-Path $diagnostics 'packaged-parity.json')) 'packaged-parity.log'
    Invoke-Checked $python.Source @((Join-Path $PSScriptRoot 'check-parity.py'),'--actual',(Join-Path $diagnostics 'packaged-smoke\snapshot.json'),'--report',(Join-Path $diagnostics 'desktop-parity.json')) 'desktop-parity.log'
    $files = [ordered]@{}
    foreach ($file in @(Get-ChildItem -LiteralPath $package -Recurse -File | Sort-Object FullName)) {
        $relative = $file.FullName.Substring($package.Length+1).Replace('\','/')
        $files[$relative] = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    }
    $sourceRevision = if ($env:GITHUB_SHA) { $env:GITHUB_SHA } else { 'unversioned-source-archive' }
    [ordered]@{ version=$version; platform='windows-x86_64'; sourceRevision=$sourceRevision; swift=$swiftVersion; sdl='3.4.16'; checks='tests, replay parity, source smoke, packaged smoke and maximized 50-floor resize performance with developer PATH removed'; cleanMachineValidation='pending'; files=$files } | ConvertTo-Json -Depth 20 | Set-Content -Encoding UTF8 (Join-Path $package 'manifest.json')
    $zip = Join-Path $OutputDirectory "$packageName.zip"
    Compress-Archive -LiteralPath $package -DestinationPath $zip
    (Get-FileHash -LiteralPath $zip -Algorithm SHA256).Hash.ToLowerInvariant() + '  ' + [IO.Path]::GetFileName($zip) | Set-Content -Encoding ASCII "$zip.sha256"
    $status.status = 'passed'; $status['package'] = $zip; $status['manifest'] = Join-Path $package 'manifest.json'
    Write-Host "Package created: $zip"
} catch {
    $failure = $_
    $status.error = $_.ToString()
    Write-Host "BUILD FAILED: $failure" -ForegroundColor Red
} finally {
    $status['finishedUTC'] = (Get-Date).ToUniversalTime().ToString('o')
    $status | ConvertTo-Json -Depth 10 | Set-Content -Encoding UTF8 (Join-Path $diagnostics 'status.json')
    if ($transcribing) { Stop-Transcript | Out-Null }
    Set-Location $oldLocation
    $diagnosticsZip = Join-Path $OutputDirectory "Lofty-Windows-Diagnostics-$stamp.zip"
    Compress-Archive -LiteralPath $diagnostics -DestinationPath $diagnosticsZip
    Write-Host "Return this diagnostics ZIP: $diagnosticsZip"
}
if ($failure) { throw $failure }
