# SPDX-License-Identifier: GPL-3.0-only
param([string]$Root = (Split-Path -Parent $PSScriptRoot), [switch]$AllowGeneratedChanges, [string]$Python = 'python')
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath($Root)
Push-Location $root
try {
    $status = & git status --porcelain
    if ($LASTEXITCODE -ne 0) { throw 'Not a Git working tree' }
    if ($status -and -not $AllowGeneratedChanges) { throw 'Commit all source and license changes before packaging.' }
    $version = [regex]::Match([IO.File]::ReadAllText((Join-Path $root 'toolbox/Toolbox.cs')),
        'public const string Version\s*=\s*"([\d.]+)"').Groups[1].Value
    if (-not $version) { throw 'Cannot determine version' }
    $outDir = Join-Path $root 'artifacts'
    New-Item -ItemType Directory -Force -Path $outDir | Out-Null
    $sourceZip = Join-Path $outDir "XKGJX-source-v$version.zip"
    if ($AllowGeneratedChanges) {
        $changed = @(& git diff --name-only HEAD) + @(& git ls-files --others --exclude-standard)
        foreach ($name in $changed) {
            if ($name -notmatch '^(autoload/|LICENSES/|BUILD_ENVIRONMENT\.json$)') {
                throw "Unexpected source change in build snapshot: $name"
            }
        }
        & $Python scripts/archive-source.py $sourceZip "XKGJX-$version"
    } else {
        & git archive --format=zip "--prefix=XKGJX-$version/" "--output=$sourceZip" HEAD
    }
    if ($LASTEXITCODE -ne 0) { throw 'Corresponding source archive failed' }
    $files = @($sourceZip)
    foreach ($name in @("XiaokaiToolbox-setup-v$version.exe", "XiaokaiToolbox-portable-v$version.zip")) {
        $source = Join-Path $root "toolbox/dist/$name"
        if (-not (Test-Path -LiteralPath $source)) { throw "Build first: $source" }
        $target = Join-Path $outDir $name
        Copy-Item -LiteralPath $source -Destination $target -Force
        $files += $target
    }
    $lines = foreach ($file in $files) {
        $hash = (Get-FileHash -LiteralPath $file -Algorithm SHA256).Hash.ToLowerInvariant()
        $hash + '  ' + [IO.Path]::GetFileName($file)
    }
    [IO.File]::WriteAllLines((Join-Path $outDir 'SHA256SUMS.txt'), $lines, (New-Object Text.UTF8Encoding($false)))
    Get-ChildItem -LiteralPath $outDir | Select-Object Name, Length
} finally { Pop-Location }
