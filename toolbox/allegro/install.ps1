param(
    [string]$HomeDirectory = $env:HOME,
    [switch]$Uninstall
)
$ErrorActionPreference = 'Stop'

if (-not $HomeDirectory) { throw 'Cadence HOME is not set. Specify -HomeDirectory.' }
$allegroHome = [IO.Path]::GetFullPath($HomeDirectory)
if (-not (Test-Path -LiteralPath $allegroHome -PathType Container)) {
    throw "Cadence HOME does not exist: $allegroHome"
}
$pcbEnv = Join-Path $allegroHome 'pcbenv'
$payloadDir = $pcbEnv
$initFile = Join-Path $pcbEnv 'allegro.ilinit'
$begin = '; BEGIN XIAOKAI ALLEGRO SELECTED TOOLS'
$end = '; END XIAOKAI ALLEGRO SELECTED TOOLS'
$files = @('film_reorder.il', 'Auto_artwork.il', 'Quick_ColorS.il', 'x_change_via_net.il',
    'Find_Component.il', 'Find_DRC.il', 'quick_grids.il', 'quick_display.il',
    'conv.il', 'highlight_padstack.il', 'show_library.il', 'show_height.il',
    'fTextTuneTools.il', 'check_no_refdes.il', 'gxl_wdzcheck_text_overlap.il', 'jkcheck_refdes_cross.il', 'x_silk_in_out.il', 'xiaokaiTextTools.il',
    'lgs_hilight_no_fanout.il', 'lgs_check_solder_to_line_V1_0.il', 'quick_chSmd2ThrP.il', 'find_pin_no_past.il', 'find_pin_no_solder.il',
            'xiaokaiDanglings.il', 'xiaokaiAllegroHotkey.exe', 'xiaokaiAllegroMenu.il', 'xiaokaiAiBridge.exe')
$retiredFiles = @('find_stubs.il', 'lgs_loop90_check.il', 'checkWidth.il', 'StackVias.il')
$identityEncoding = [Text.Encoding]::GetEncoding(28591)
$original = [byte[]]@()
$initExisted = Test-Path -LiteralPath $initFile
if ($initExisted) { $original = [IO.File]::ReadAllBytes($initFile) }
# The managed block is ASCII. A byte-preserving encoding keeps all pre-existing
# Chinese comments and every other startup setting exactly as they were.
if ($original.Length -ge 2 -and (($original[0] -eq 255 -and $original[1] -eq 254) -or
    ($original[0] -eq 254 -and $original[1] -eq 255))) {
    throw 'UTF-16 allegro.ilinit is unsupported; no files changed.'
}
$initText = $identityEncoding.GetString($original)
$blockPattern = '(?ms)^' + [regex]::Escape($begin) + '\r?\n.*?^' + [regex]::Escape($end) + '(?:\r?\n|$)'
$hasBegin = $initText.Contains($begin)
$hasEnd = $initText.Contains($end)
$blocks = [regex]::Matches($initText, $blockPattern)
if ($hasBegin -ne $hasEnd -or (($hasBegin -or $hasEnd) -and $blocks.Count -ne 1)) {
    throw 'Ambiguous Xiaokai startup block; no files changed.'
}
if ($Uninstall -and -not $hasBegin) {
    Write-Host 'Xiaokai startup block is not installed.'
    return
}
if (-not $Uninstall) {
    foreach ($name in $files) {
        if (-not (Test-Path -LiteralPath (Join-Path $PSScriptRoot "skill\$name") -PathType Leaf)) {
            throw "Missing payload: $name"
        }
    }
}
New-Item -ItemType Directory -Path $pcbEnv -Force | Out-Null
$stamp = (Get-Date -Format 'yyyyMMdd-HHmmss-fff') + '-' + [guid]::NewGuid().ToString('N').Substring(0, 8)
$backupDir = Join-Path $pcbEnv "xiaokai-allegro-backup\$stamp"
New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
if (Test-Path -LiteralPath $initFile) {
    [IO.File]::WriteAllBytes((Join-Path $backupDir 'allegro.ilinit'), $original)
}
$cleanText = [regex]::Replace($initText, $blockPattern, '')
if ($Uninstall) {
    [IO.File]::WriteAllBytes($initFile, $identityEncoding.GetBytes($cleanText))
    Write-Host "Startup entries removed. Scripts retained at $payloadDir"
    Write-Host "Backup: $backupDir"
    return
}

$oldPayloads = @{}
$changedPayloads = New-Object 'System.Collections.Generic.List[string]'
$movedPayloads = @{}
$retiredPayloads = @{}
try {
    New-Item -ItemType Directory -Path $payloadDir -Force | Out-Null
    foreach ($name in $files) {
        $destination = Join-Path $payloadDir $name
        if (Test-Path -LiteralPath $destination) {
            $oldPayloads[$name] = [IO.File]::ReadAllBytes($destination)
            [IO.File]::WriteAllBytes((Join-Path $backupDir $name), $oldPayloads[$name])
        }
    }
    foreach ($name in $files) {
        $destination = Join-Path $payloadDir $name
        $expected = (Get-FileHash -LiteralPath (Join-Path $PSScriptRoot "skill\$name") -Algorithm SHA256).Hash
        if ((Test-Path -LiteralPath $destination) -and
            (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash -eq $expected) {
            continue
        }
        $changedPayloads.Add($name)
        # An active Allegro instance may still map the previous helper image.
        # Rename that image within pcbenv; it can finish normally on restart.
        if ($name -eq 'xiaokaiAllegroHotkey.exe' -and (Test-Path -LiteralPath $destination)) {
            $retired = Join-Path $backupDir ('running-' + $name)
            Move-Item -LiteralPath $destination -Destination $retired
            $movedPayloads[$name] = $retired
        }
        Copy-Item -LiteralPath (Join-Path $PSScriptRoot "skill\$name") -Destination $destination -Force
        if ((Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash -ne $expected) {
            throw "Installed payload verification failed: $name"
        }
    }
    # Retire withdrawn tools into the upgrade backup, never load them again.
    foreach ($name in $retiredFiles) {
        $destination = Join-Path $payloadDir $name
        if (Test-Path -LiteralPath $destination -PathType Leaf) {
            $retired = Join-Path $backupDir $name
            Move-Item -LiteralPath $destination -Destination $retired
            $retiredPayloads[$name] = $retired
        }
    }
    $rootPath = $payloadDir.Replace('\', '/').Replace('"', '\"')
    if ($rootPath -match '[^\x20-\x7e]') { throw 'Cadence HOME must use an ASCII path for this installer.' }
    $block = @($begin, ('xkAllegroInstallRoot = "' + $rootPath + '"'))
    foreach ($name in ($files | Where-Object { $_ -like '*.il' })) {
        $skillPath = (Join-Path $payloadDir $name).Replace('\', '/').Replace('"', '\"')
        # ASCII keeps startup parsing independent of the user's codepage.
        if ($skillPath -match '[^\x20-\x7e]') {
            throw 'Cadence HOME must use an ASCII path for this installer.'
        }
        if ($name -eq 'x_silk_in_out.il') {
            $block += 'load("' + $skillPath + '" "deargds")'
        } elseif ($name -in @('find_pin_no_past.il', 'find_pin_no_solder.il')) {
            $block += 'load("' + $skillPath + '" "www.allegro-skill.com")'
        } else {
            $block += 'load("' + $skillPath + '")'
        }
    }
    $block += $end
    if ($hasBegin) {
        $updated = [regex]::Replace($initText, $blockPattern, (($block -join "`r`n") + "`r`n"))
    } else {
        $separator = ''
        if ($cleanText.Length -gt 0 -and -not $cleanText.EndsWith("`n")) { $separator = "`r`n" }
        $updated = $cleanText + $separator + ($block -join "`r`n") + "`r`n"
    }
    [IO.File]::WriteAllBytes($initFile, $identityEncoding.GetBytes($updated))
    Write-Host 'Installed selected Allegro tools with the Xiaokai SKILL toolbox; SHA-256 verified.'
    Write-Host "Cadence HOME: $allegroHome"
    Write-Host "Startup: $initFile"
    Write-Host "Backup: $backupDir"
    Write-Host 'Restart Allegro. Open toolbox: Alt+K or xk_skill.'
} catch {
    foreach ($name in $retiredPayloads.Keys) {
        Move-Item -LiteralPath $retiredPayloads[$name] -Destination (Join-Path $payloadDir $name)
    }
    foreach ($name in $changedPayloads) {
        $destination = Join-Path $payloadDir $name
        if ($movedPayloads.ContainsKey($name)) {
            if (Test-Path -LiteralPath $destination) { Remove-Item -LiteralPath $destination -Force }
            Move-Item -LiteralPath $movedPayloads[$name] -Destination $destination
        } elseif ($oldPayloads.ContainsKey($name)) {
            [IO.File]::WriteAllBytes($destination, $oldPayloads[$name])
        } elseif (Test-Path -LiteralPath $destination) {
            Remove-Item -LiteralPath $destination -Force
        }
    }
    if ($initExisted) {
        [IO.File]::WriteAllBytes($initFile, $original)
    } elseif (Test-Path -LiteralPath $initFile) {
        Remove-Item -LiteralPath $initFile -Force
    }
    throw
}
