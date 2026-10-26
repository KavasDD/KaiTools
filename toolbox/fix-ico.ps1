# SPDX-License-Identifier: GPL-3.0-only
# 把 ico 里 ≤64 的条目从 PNG 改成 DIB。
#
# 为什么要修:PNG 内嵌的 ico 条目资源管理器认,**GDI+ 不认**。Icon 对象能构造出
# 来、Size 也报得对,但 Graphics.DrawIcon 一画就抛
#     Requested range extends past the end of the array
# 所以图标在桌面上好好的,在程序里是空白或者直接崩。
#
# 128 和 256 保持 PNG:那两个尺寸的 DIB 是 256 KB 一张,而 GDI+ 只会去取小尺寸,
# 大的那两张是给资源管理器缩略图用的,它认 PNG。
#
# 用法:  powershell -NoProfile -File fix-ico.ps1
#
# make-icons.ps1 生成的图标已经是 DIB,不需要修;这个脚本是给早期
# make-icon.ps1 出的 toolbox.ico 用的,顺手也把别的都检查一遍。

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$here = Split-Path -Parent $MyInvocation.MyCommand.Path

# 抄 make-icons.ps1 的写法。DIB 的两个坑:行自下而上,高度字段写两倍(颜色位图
# 加一张 AND 掩码的总高)。32bpp 有 alpha 用不上掩码,但字段和那张全 0 的掩码
# 都还得写。
function Get-DibBytes($bmp, [int]$s) {
    $ms = New-Object System.IO.MemoryStream
    $bw = New-Object System.IO.BinaryWriter($ms)
    $bw.Write([UInt32]40); $bw.Write([Int32]$s); $bw.Write([Int32]($s * 2))
    $bw.Write([UInt16]1);  $bw.Write([UInt16]32)
    $bw.Write([UInt32]0);  $bw.Write([UInt32]0)
    $bw.Write([Int32]0);   $bw.Write([Int32]0)
    $bw.Write([UInt32]0);  $bw.Write([UInt32]0)
    for ($y = $s - 1; $y -ge 0; $y--) {
        for ($x = 0; $x -lt $s; $x++) {
            $c = $bmp.GetPixel($x, $y)
            $bw.Write([Byte]$c.B); $bw.Write([Byte]$c.G)
            $bw.Write([Byte]$c.R); $bw.Write([Byte]$c.A)
        }
    }
    $stride = [int](([Math]::Floor(($s + 31) / 32)) * 4)
    $bw.Write((New-Object 'Byte[]' ($stride * $s)))
    $bw.Flush(); $out = $ms.ToArray(); $bw.Dispose(); $ms.Dispose()
    # 逗号是必须的 —— 不然 Byte[] 出管道变 Object[],BinaryWriter 挑错重载,
    # 写出来的字节数不对而且不报错。
    , $out
}

function Repair($path) {
    $name = Split-Path $path -Leaf
    $b = [IO.File]::ReadAllBytes($path)
    if ($b.Length -lt 6 -or [BitConverter]::ToUInt16($b,2) -ne 1) {
        Write-Host "  $name : 不是 ico,跳过" -ForegroundColor Yellow; return
    }
    $n = [BitConverter]::ToUInt16($b,4)
    $entries = @()
    $needFix = $false
    for ($i = 0; $i -lt $n; $i++) {
        $o = 6 + $i * 16
        $w = $b[$o];   if ($w -eq 0) { $w = 256 }
        $h = $b[$o+1]; if ($h -eq 0) { $h = 256 }
        $len = [BitConverter]::ToInt32($b,$o+8)
        $off = [BitConverter]::ToInt32($b,$o+12)
        $data = New-Object 'Byte[]' $len
        [Array]::Copy($b,$off,$data,0,$len)
        $isPng = ($data[0] -eq 0x89 -and $data[1] -eq 0x50)
        # 只改 ≤64 的。大尺寸的 DIB 太占地方,而且 GDI+ 只会去取小的。
        if ($isPng -and $w -le 64) {
            $ms = New-Object IO.MemoryStream(,$data)
            $src = [System.Drawing.Image]::FromStream($ms)
            # 转成 32bppArgb 再逐点读:源图可能是别的像素格式,GetPixel 拿到的
            # alpha 会不对。
            $bmp = New-Object System.Drawing.Bitmap($w,$h,[System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
            $g = [System.Drawing.Graphics]::FromImage($bmp)
            $g.Clear([System.Drawing.Color]::Transparent)
            $g.DrawImage($src,0,0,$w,$h)
            $g.Dispose()
            $data = Get-DibBytes $bmp $w
            $bmp.Dispose(); $src.Dispose(); $ms.Dispose()
            $needFix = $true
        }
        $entries += [pscustomobject]@{ W=$w; H=$h; Data=$data
                                       Planes=[BitConverter]::ToUInt16($b,$o+4)
                                       Bpp=[BitConverter]::ToUInt16($b,$o+6) }
    }
    if (-not $needFix) { Write-Host "  $name : 已经是 DIB,不用改" -ForegroundColor DarkGray; return }

    $ms = New-Object IO.MemoryStream
    $bw = New-Object IO.BinaryWriter($ms)
    $bw.Write([UInt16]0); $bw.Write([UInt16]1); $bw.Write([UInt16]$entries.Count)
    $off = 6 + 16 * $entries.Count
    foreach ($e in $entries) {
        $bw.Write([Byte]$(if ($e.W -ge 256) { 0 } else { $e.W }))
        $bw.Write([Byte]$(if ($e.H -ge 256) { 0 } else { $e.H }))
        $bw.Write([Byte]0); $bw.Write([Byte]0)
        $bw.Write([UInt16]1); $bw.Write([UInt16]32)
        $bw.Write([UInt32]$e.Data.Length); $bw.Write([UInt32]$off)
        $off += $e.Data.Length
    }
    foreach ($e in $entries) { $bw.Write($e.Data) }
    $bw.Flush()
    $old = (Get-Item $path).Length
    [IO.File]::WriteAllBytes($path, $ms.ToArray())
    $bw.Dispose(); $ms.Dispose()
    Write-Host ("  {0} : {1:N0} -> {2:N0} 字节" -f $name, $old, (Get-Item $path).Length) -ForegroundColor Green
}

Write-Host "`n修 ico 里的 PNG 条目"
foreach ($f in Get-ChildItem -LiteralPath $here -Filter '*.ico') { Repair $f.FullName }

# 修完当场验:构造 Icon 再真画一遍,画不出来就是没修好。
Write-Host "`n验证 GDI+ 能不能画出来"
foreach ($f in Get-ChildItem -LiteralPath $here -Filter '*.ico') {
    $opaque = 0; $err = $null
    try {
        $fs = [IO.File]::OpenRead($f.FullName)
        $ic = New-Object System.Drawing.Icon($fs,48,48)
        $bmp = New-Object System.Drawing.Bitmap 48,48
        $g = [System.Drawing.Graphics]::FromImage($bmp)
        $g.DrawIcon($ic,(New-Object System.Drawing.Rectangle 0,0,48,48))
        $g.Dispose()
        for ($y=0;$y -lt 48;$y+=3) { for ($x=0;$x -lt 48;$x+=3) {
            if ($bmp.GetPixel($x,$y).A -gt 32) { $opaque++ } } }
        $bmp.Dispose(); $ic.Dispose(); $fs.Close()
    } catch { $err = $_.Exception.Message }
    if ($err)             { Write-Host ("  [FAIL] " + $f.Name + " : " + $err) -ForegroundColor Red }
    elseif ($opaque -gt 20) { Write-Host ("  [ok]   " + $f.Name + "  ($opaque/256 像素)") -ForegroundColor Green }
    else                  { Write-Host ("  [FAIL] " + $f.Name + " : 画出来是空的") -ForegroundColor Red }
}
Write-Host ""
