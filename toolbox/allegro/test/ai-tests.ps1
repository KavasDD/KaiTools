param([string]$Root = 'D:/selfsoftware/toolbox/allegro')
$ErrorActionPreference = 'Stop'
$adapter = [IO.File]::ReadAllText((Join-Path $Root 'skill/xiaokaiAllegroMenu.il'))
# IPC is an internal SKILL primitive. Replace only that transport in the
# isolated test copy; production procedures and dispatch remain identical.
$adapter = $adapter.Replace('ipcWriteProcess(', 'xkTestWriteProcess(')
[IO.File]::WriteAllText('D:/selfsoftware/out/ai-skill-test-adapter.il', $adapter, [Text.Encoding]::ASCII)
$result = & 'C:/orcad/Cadence/SPB_17.4/tools/bin/cnskill.exe' -nongraph (Join-Path $Root 'test/ai-commands.il') 2>&1
$log = $result -join "`n"
if ($LASTEXITCODE -ne 0 -or $log -match '\*Error\*' -or $log -notmatch 'PASS: generated Allegro SKILL') {
    throw "Allegro command adapter checks failed: $log"
}
$result
