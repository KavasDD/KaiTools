# SPDX-License-Identifier: GPL-3.0-only
# ==========================================================================
#  生成 toolbox.ico —— 工具箱的 exe 图标
# ==========================================================================
#
#      powershell -NoProfile -File make-icon.ps1
#
#  只在想改图标样式时才需要跑。产物 toolbox.ico 是要留在目录里的,build.ps1
#  用 /win32icon: 把它编进 exe。
#
#  为什么手写 ICO 容器:System.Drawing 的 Icon 存不了多尺寸 ico,Save() 出来
#  只有一张图。任务栏要 32、资源管理器大图标要 256、Alt+Tab 又是别的尺寸,
#  少了哪个 Windows 就会拿最近的那张缩放,边缘糊成一团。所以按 ICO 格式
#  自己拼:6 张 PNG + 一个目录表。
#
#  PNG 压缩的 ico 从 Vista 起就认,不用管 BMP+AND掩码那套老格式。
# ==========================================================================

Add-Type -AssemblyName System.Drawing

$sizes = @(16, 24, 32, 48, 64, 256)
$out = Join-Path $PSScriptRoot 'toolbox.ico'

# 和界面同一套蓝:侧栏深蓝到提示栏亮蓝,图标和窗口是一家的。
$c1 = [System.Drawing.Color]::FromArgb(0x0E, 0x4D, 0x6E)
$c2 = [System.Drawing.Color]::FromArgb(0x2E, 0x8F, 0xBE)

$pngs = @()
foreach ($s in $sizes) {
    $bmp = New-Object System.Drawing.Bitmap($s, $s,
        [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = 'AntiAlias'
    $g.TextRenderingHint = 'AntiAliasGridFit'
    $g.InterpolationMode = 'HighQualityBicubic'

    # 圆角方块。半径按尺寸走,小图标上圆角太大会啃掉本来就不多的像素。
    $r = [Math]::Max(2, [int]($s * 0.18))
    $pad = [Math]::Max(0, [int]($s * 0.04))
    $w = $s - 1 - $pad * 2
    $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    $path.AddArc($pad, $pad, $r * 2, $r * 2, 180, 90)
    $path.AddArc($pad + $w - $r * 2, $pad, $r * 2, $r * 2, 270, 90)
    $path.AddArc($pad + $w - $r * 2, $pad + $w - $r * 2, $r * 2, $r * 2, 0, 90)
    $path.AddArc($pad, $pad + $w - $r * 2, $r * 2, $r * 2, 90, 90)
    $path.CloseFigure()

    $rect = New-Object System.Drawing.Rectangle($pad, $pad, $w, $w)
    $br = New-Object System.Drawing.Drawing2D.LinearGradientBrush(
        $rect, $c2, $c1, 90.0)
    $g.FillPath($br, $path)

    # 白色的"开"。四笔全是直线,是这个名字里唯一在 16px 上还认得出的字 ——
    # "小"和"箱"缩到那个尺寸只剩几团灰。所以图标画字不画词。
    # 用 GraphicsPath 描边而不是 DrawString:字体渲染在小尺寸上会被 hinting
    # 拧变形,直接画矩形条反而更稳、也不依赖机器上装了哪套中文字体。
    $wh = [Math]::Max(1, [int][Math]::Round($s * 0.075))   # 笔画粗细
    $bx = $pad + $w * 0.22                                  # 字的左边
    $by = $pad + $w * 0.24                                  # 字的上边
    $bw = $w * 0.56                                         # 字宽
    $bh = $w * 0.52                                         # 字高
    $wb = [System.Drawing.Brushes]::White

    # 两横。第二横略窄一点,和真的字形一样,也让下面两竖看起来是穿出去的。
    $g.FillRectangle($wb, [float]$bx, [float]($by + $bh * 0.06), [float]$bw, [float]$wh)
    $g.FillRectangle($wb, [float]($bx + $bw * 0.04), [float]($by + $bh * 0.42),
        [float]($bw * 0.92), [float]$wh)
    # 两竖:从第一横起笔穿过第二横,一直到底。只挂在第二横下面的话字会散,
    # 看着像"廾"上面盖了一条,不像"开"。
    $g.FillRectangle($wb, [float]($bx + $bw * 0.20), [float]($by + $bh * 0.06),
        [float]$wh, [float]($bh * 0.94))
    $g.FillRectangle($wb, [float]($bx + $bw * 0.68), [float]($by + $bh * 0.06),
        [float]$wh, [float]($bh * 0.94))

    $g.Dispose()
    $ms = New-Object System.IO.MemoryStream
    $bmp.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
    $pngs += , $ms.ToArray()
    $ms.Dispose(); $bmp.Dispose(); $br.Dispose(); $path.Dispose()
}

# ICO 容器:6 字节头 + 每张图 16 字节目录项 + 各张 PNG 数据。
$fs = New-Object System.IO.FileStream($out, [System.IO.FileMode]::Create)
$bw2 = New-Object System.IO.BinaryWriter($fs)
$bw2.Write([uint16]0)                 # reserved
$bw2.Write([uint16]1)                 # type 1 = icon
$bw2.Write([uint16]$sizes.Count)

# 数据从目录表后面开始。
$offset = 6 + 16 * $sizes.Count
for ($i = 0; $i -lt $sizes.Count; $i++) {
    # 256 在这个字节里写 0 —— 一个字节存不下 256,格式规定用 0 表示。
    $d = if ($sizes[$i] -ge 256) { 0 } else { $sizes[$i] }
    $bw2.Write([byte]$d)              # width
    $bw2.Write([byte]$d)              # height
    $bw2.Write([byte]0)               # 调色板颜色数,真彩色写 0
    $bw2.Write([byte]0)               # reserved
    $bw2.Write([uint16]1)             # color planes
    $bw2.Write([uint16]32)            # bits per pixel
    $bw2.Write([uint32]$pngs[$i].Length)
    $bw2.Write([uint32]$offset)
    $offset += $pngs[$i].Length
}
foreach ($p in $pngs) { $bw2.Write($p) }
$bw2.Close(); $fs.Close()

Write-Output "wrote $out"
Write-Output "  sizes : $($sizes -join ', ')"
Write-Output "  size  : $((Get-Item $out).Length) bytes"
