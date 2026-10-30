$ErrorActionPreference = 'Stop'
$root = Join-Path ([IO.Path]::GetTempPath()) ('xk-allegro-install-test-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path (Join-Path $root 'pcbenv') -Force | Out-Null
$installer = Join-Path $PSScriptRoot '..\install.ps1'
$initFile = Join-Path $root 'pcbenv\allegro.ilinit'
$originalText = "; Existing user code`r`nload(`"my-existing.il`")`r`n; " + [char]0x4e2d + [char]0x6587 + "`r`n"
$originalBytes = [Text.Encoding]::GetEncoding(936).GetBytes($originalText)
[IO.File]::WriteAllBytes($initFile, $originalBytes)
& $installer -HomeDirectory $root
$first = [IO.File]::ReadAllBytes($initFile)
for ($i = 0; $i -lt $originalBytes.Length; $i++) {
    if ($first[$i] -ne $originalBytes[$i]) { throw 'Existing startup bytes changed.' }
}
& $installer -HomeDirectory $root
$second = [IO.File]::ReadAllBytes($initFile)
if ([Convert]::ToBase64String($first) -ne [Convert]::ToBase64String($second)) {
    throw 'Repeated installation is not idempotent.'
}
& $installer -HomeDirectory $root -Uninstall
if ([Convert]::ToBase64String($originalBytes) -ne [Convert]::ToBase64String([IO.File]::ReadAllBytes($initFile))) {
    throw 'Uninstall changed unrelated startup content.'
}
# Verify corrupt block detection leaves every byte intact.
$corrupt = [Text.Encoding]::ASCII.GetBytes('; BEGIN XIAOKAI ALLEGRO SELECTED TOOLS')
[IO.File]::WriteAllBytes($initFile, $corrupt)
$rejected = $false
try { & $installer -HomeDirectory $root } catch { $rejected = $true }
if (-not $rejected) { throw 'Malformed managed block was accepted.' }
if ([Convert]::ToBase64String($corrupt) -ne [Convert]::ToBase64String([IO.File]::ReadAllBytes($initFile))) {
    throw 'Rejected installation mutated startup.'
}
Write-Host 'PASS: preserved GBK user content, repeated install, uninstall, corrupt-block rejection.'
Write-Host "Test directory: $root"
