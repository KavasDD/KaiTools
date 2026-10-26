# SPDX-License-Identifier: GPL-3.0-only
# 给自研工具画图标。
#
# 为什么是代码画而不是找个 png 转:图标要在 16px 下还认得出来。16px 上
# 一个细节就是一个像素,所以每种尺寸都单独画,粗细跟着尺寸走 —— 直接把
# 256px 缩到 16px 出来的是一团糊。
#
# 配色跟工具箱同一套(Toolbox.cs 的 Palette),放在一起像一家的:
#   底 #14476B(FootBg) / 主 #2E8BB8(GridBg) / 亮 #3E9ECB(HintBg)
# 立创那半边用绿色,是它自己的品牌色,一眼能看出"从立创来"。
#
#   powershell -NoProfile -File toolbox\make-icons.ps1
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$sizes = 16, 24, 32, 48, 64, 128, 256

function New-Bitmap([int]$s) {
    $bmp = New-Object System.Drawing.Bitmap($s, $s,
        [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.SmoothingMode = 'AntiAlias'
    $g.InterpolationMode = 'HighQualityBicubic'
    $g.TextRenderingHint = 'AntiAliasGridFit'
    # 不能写 ", $bmp, $g" —— 开头那个逗号会把 $bmp 单独包成一个数组,
    # 接收端 $bmp, $g = ... 拿到的第一个值就是 Object[] 而不是 Bitmap,
    # 报错要到后面某个 $s * 0.5 上才炸出来,离现场很远。
    $bmp
    $g
}

# 圆角底板。16px 上圆角只有 2px,再大就啃掉了本来就不多的可用面积。
function Add-Plate($g, [int]$s, $color) {
    $r = [Math]::Max(2, [int]($s * 0.16))
    $p = New-Object System.Drawing.Drawing2D.GraphicsPath
    $d = $r * 2
    $p.AddArc(0, 0, $d, $d, 180, 90)
    $p.AddArc($s - $d - 1, 0, $d, $d, 270, 90)
    $p.AddArc($s - $d - 1, $s - $d - 1, $d, $d, 0, 90)
    $p.AddArc(0, $s - $d - 1, $d, $d, 90, 90)
    $p.CloseFigure()
    $b = New-Object System.Drawing.SolidBrush($color)
    $g.FillPath($b, $p)
    $b.Dispose()
    $p
}

# ---- 图标一:lceda2orcad ------------------------------------------------
# 立创 -> OrCAD。左绿右蓝,中间一个白箭头穿过去。转换方向是这个工具的
# 全部意思,所以箭头占主体,不画元件符号那类"跟原理图有关"的通用图形 ——
# 那种图形放在一堆 Cadence 图标里根本分不出来。
function New-ConvertIcon([int]$s) {
    $bmp, $g = New-Bitmap $s
    $plate = Add-Plate $g $s ([System.Drawing.Color]::FromArgb(255, 0x14, 0x47, 0x6B))

    # 左半边斜切成绿色。斜线而不是直线:直着切像两个色块拼一起,
    # 斜着切有"从这边过去"的方向感。
    $g.SetClip($plate)
    $green = New-Object System.Drawing.SolidBrush(
        [System.Drawing.Color]::FromArgb(255, 0x2F, 0x9E, 0x5A))
    # 每个坐标都得自己套一层括号并转 float。PowerShell 里逗号比 * 结合得紧,
    # 写成 PointF($s * 0.62, 0) 会被读成 $s * (0.62, 0) —— 拿 int 去乘一个
    # 数组,报的错是"Object[] 没有 op_Multiply",看着像 $s 的类型不对。
    $g.FillPolygon($green, @(
            (New-Object System.Drawing.PointF(([float]0), ([float]0))),
            (New-Object System.Drawing.PointF(([float]($s * 0.62)), ([float]0))),
            (New-Object System.Drawing.PointF(([float]($s * 0.38)), ([float]$s))),
            (New-Object System.Drawing.PointF(([float]0), ([float]$s)))))
    $green.Dispose()
    $g.ResetClip()

    # 箭头。宽度按尺寸缩放,16px 时杆子只有 2px —— 再细就在深色底上消失。
    $w = [Math]::Max(2, [int]($s * 0.12))
    $y = [int]($s * 0.5)
    $x1 = $s * 0.2
    $x2 = $s * 0.72
    $white = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::White)
    $g.FillRectangle($white, [float]$x1, [float]($y - $w / 2), [float]($x2 - $x1), [float]$w)
    # 箭头尖:实心三角。16px 下描边画的箭头会糊成一个点。
    $h = [Math]::Max(4, [int]($s * 0.26))
    $g.FillPolygon($white, @(
            (New-Object System.Drawing.PointF([float]($x2 - $w * 0.2), [float]($y - $h / 2))),
            (New-Object System.Drawing.PointF([float]($s * 0.9), [float]$y)),
            (New-Object System.Drawing.PointF([float]($x2 - $w * 0.2), [float]($y + $h / 2)))))

    # 32px 以上才加引脚小横线,表示"符号/封装"。16px 加了就是噪点。
    if ($s -ge 32) {
        $pin = [Math]::Max(1, [int]($s * 0.045))
        $len = $s * 0.13
        $pb = New-Object System.Drawing.SolidBrush(
            [System.Drawing.Color]::FromArgb(215, 0xE8, 0xF2, 0xF8))
        foreach ($fy in 0.26, 0.74) {
            $g.FillRectangle($pb, [float]($s * 0.1), [float]($s * $fy), [float]$len, [float]$pin)
            $g.FillRectangle($pb, [float]($s * 0.77), [float]($s * $fy), [float]$len, [float]$pin)
        }
        $pb.Dispose()
    }
    $white.Dispose()
    $plate.Dispose()
    $g.Dispose()
    $bmp
}

# ---- 图标二:元器件规格描述生成器 --------------------------------------
# 一张纸 + 几行字,最上面一行是高亮的 —— "生成出来的规格描述"。
# 纸张这个隐喻不用解释,而右下角那支笔说明是"生成"而不是"查看"。
function New-SpecIcon([int]$s) {
    $bmp, $g = New-Bitmap $s
    $plate = Add-Plate $g $s ([System.Drawing.Color]::FromArgb(255, 0x14, 0x47, 0x6B))
    $plate.Dispose()

    # 纸。留边不能太小,不然在浅色桌面背景上底板看不出来。
    $px = $s * 0.22; $py = $s * 0.15
    $pw = $s * 0.56; $ph = $s * 0.7
    $paper = New-Object System.Drawing.SolidBrush(
        [System.Drawing.Color]::FromArgb(255, 0xF2, 0xF8, 0xFC))
    $g.FillRectangle($paper, [float]$px, [float]$py, [float]$pw, [float]$ph)
    $paper.Dispose()

    # 折角。用底色画,像纸被翻起来一角,不用额外颜色。
    if ($s -ge 24) {
        $c = $s * 0.18
        $fold = New-Object System.Drawing.SolidBrush(
            [System.Drawing.Color]::FromArgb(255, 0x14, 0x47, 0x6B))
        $g.FillPolygon($fold, @(
                (New-Object System.Drawing.PointF([float]($px + $pw - $c), [float]$py)),
                (New-Object System.Drawing.PointF([float]($px + $pw), [float]$py)),
                (New-Object System.Drawing.PointF([float]($px + $pw), [float]($py + $c)))))
        $fold.Dispose()
    }

    # 文字行。第一行用亮蓝加粗,后面几行灰。16px 只画得下 2 行 ——
    # 硬塞 4 行的话行距不足 1px,会糊成一个色块。
    $rows = if ($s -le 16) { 2 } elseif ($s -le 24) { 3 } else { 4 }
    $lh = [Math]::Max(1, [int]($s * 0.055))
    $gap = $ph / ($rows + 1.6)
    $lx = $px + $pw * 0.14
    $accent = New-Object System.Drawing.SolidBrush(
        [System.Drawing.Color]::FromArgb(255, 0x2E, 0x8B, 0xB8))
    $grey = New-Object System.Drawing.SolidBrush(
        [System.Drawing.Color]::FromArgb(255, 0x8F, 0xA6, 0xB4))
    for ($i = 0; $i -lt $rows; $i++) {
        $ly = $py + $gap * ($i + 0.85)
        # 行长交替,看着像真的文字段落而不是等长条纹
        $frac = if ($i -eq 0) { 0.72 } elseif ($i % 2 -eq 0) { 0.66 } else { 0.5 }
        $b = if ($i -eq 0) { $accent } else { $grey }
        $th = if ($i -eq 0) { [Math]::Max(2, [int]($lh * 1.5)) } else { $lh }
        $g.FillRectangle($b, [float]$lx, [float]$ly, [float]($pw * $frac), [float]$th)
    }
    $accent.Dispose()
    $grey.Dispose()

    # 笔。48px 以上才画,小尺寸下它和文字行挤在一起分不开。
    if ($s -ge 48) {
        $pen = New-Object System.Drawing.SolidBrush(
            [System.Drawing.Color]::FromArgb(255, 0x3E, 0x9E, 0xCB))
        $tipx = $s * 0.86; $tipy = $s * 0.88
        $g.FillPolygon($pen, @(
                (New-Object System.Drawing.PointF([float]($s * 0.6), [float]($s * 0.72))),
                (New-Object System.Drawing.PointF([float]($s * 0.7), [float]($s * 0.62))),
                (New-Object System.Drawing.PointF([float]$tipx, [float]($tipy - $s * 0.1))),
                (New-Object System.Drawing.PointF([float]($tipx - $s * 0.1), [float]$tipy))))
        $pen.Dispose()
        $nib = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::White)
        $g.FillPolygon($nib, @(
                (New-Object System.Drawing.PointF([float]($s * 0.58), [float]($s * 0.74))),
                (New-Object System.Drawing.PointF([float]($s * 0.64), [float]($s * 0.8))),
                (New-Object System.Drawing.PointF([float]($s * 0.55), [float]($s * 0.83)))))
        $nib.Dispose()
    }
    $g.Dispose()
    $bmp
}

# ---- 图标三:嘉立创 3D 模型下载器 --------------------------------------
# 一个等轴立方体 + 一支向下的箭头。立方体三个面用三档绿(立创的品牌色),
# 靠明暗区分面 —— 不描边,16px 上一条 1px 的描边会把面吃掉一半。
# 箭头 24px 以上才画:16px 时立方体占满才认得出是个立体的东西,
# 再塞一个箭头两样都糊了。
function New-Jlc3dIcon([int]$s) {
    $bmp, $g = New-Bitmap $s
    $plate = Add-Plate $g $s ([System.Drawing.Color]::FromArgb(255, 0x14, 0x47, 0x6B))
    $plate.Dispose()

    # 不画箭头的尺寸(<=24)让立方体居中占满;要画箭头的给下面让出位置。
    if ($s -lt 32) { $cy = $s * 0.5; $r = $s * 0.36 }
    else { $cy = $s * 0.38; $r = $s * 0.26 }
    $cx = $s * 0.5
    $w = $r * 0.866          # 等轴投影:横向 cos(30°)
    $h = $r * 0.5            # 纵向 sin(30°)

    function P($x, $y) { New-Object System.Drawing.PointF([float]$x, [float]$y) }

    # 顶面(最亮)、左面(基色)、右面(压暗)。同一个绿的三档明度,
    # 比换三个色相干净 —— 换色相看着像三块贴纸拼的。
    $top = New-Object System.Drawing.SolidBrush(
        [System.Drawing.Color]::FromArgb(255, 0x5F, 0xC8, 0x83))
    $left = New-Object System.Drawing.SolidBrush(
        [System.Drawing.Color]::FromArgb(255, 0x2F, 0x9E, 0x5A))
    $right = New-Object System.Drawing.SolidBrush(
        [System.Drawing.Color]::FromArgb(255, 0x1F, 0x71, 0x40))

    $g.FillPolygon($top, @(
            (P $cx ($cy - $r)), (P ($cx + $w) ($cy - $h)),
            (P $cx $cy), (P ($cx - $w) ($cy - $h))))
    $g.FillPolygon($left, @(
            (P ($cx - $w) ($cy - $h)), (P $cx $cy),
            (P $cx ($cy + $r)), (P ($cx - $w) ($cy + $h))))
    $g.FillPolygon($right, @(
            (P ($cx + $w) ($cy - $h)), (P $cx $cy),
            (P $cx ($cy + $r)), (P ($cx + $w) ($cy + $h))))
    $top.Dispose(); $left.Dispose(); $right.Dispose()

    # 箭头 32px 起才画。24px 上箭头只剩两三个像素高,是个贴在底边的小疙瘩,
    # 比没有更糟 —— 那两档就让立方体占满,靠形状本身认。
    if ($s -ge 32) {
        # 向下箭头:杆 + 实心三角。表示"下载",和立方体的"3D 模型"合起来
        # 就是这个工具干的事。三角要比杆宽一倍以上才看得出是箭头。
        $white = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::White)
        $sw = [Math]::Max(2, [int]($s * 0.09))
        $ax = $s * 0.5
        $g.FillRectangle($white, [float]($ax - $sw / 2), [float]($s * 0.63),
            [float]$sw, [float]($s * 0.17))
        # 尖端停在 0.90,不顶到圆角底板的边上。
        $hw = [Math]::Max(3, [int]($s * 0.15))
        $g.FillPolygon($white, @(
                (P ($ax - $hw) ($s * 0.76)), (P ($ax + $hw) ($s * 0.76)),
                (P $ax ($s * 0.90))))
        $white.Dispose()
    }
    $g.Dispose()
    $bmp
}

# ---- 图标四:DWG 转 DXF -------------------------------------------------
# 一张图纸 + 上面的线稿(折线 + 一个圆),表示"2D CAD 图形"。这三个转换工具
# 靠源格式的形状区分:DWG 画直线线稿、STEP 画立方体、Gerber 画焊盘。都往 DXF
# 转,但把"→DXF"画进 16px 只会糊,方向交给分类页和名字说明。
function New-Dwg2DxfIcon([int]$s) {
    $bmp, $g = New-Bitmap $s
    $plate = Add-Plate $g $s ([System.Drawing.Color]::FromArgb(255, 0x14, 0x47, 0x6B))
    $plate.Dispose()

    # 图纸
    $px = $s * 0.2; $py = $s * 0.16
    $pw = $s * 0.6; $ph = $s * 0.68
    $paper = New-Object System.Drawing.SolidBrush(
        [System.Drawing.Color]::FromArgb(255, 0xF2, 0xF8, 0xFC))
    $g.FillRectangle($paper, [float]$px, [float]$py, [float]$pw, [float]$ph)
    $paper.Dispose()

    # 折角
    if ($s -ge 24) {
        $c = $s * 0.16
        $fold = New-Object System.Drawing.SolidBrush(
            [System.Drawing.Color]::FromArgb(255, 0x14, 0x47, 0x6B))
        $g.FillPolygon($fold, @(
                (New-Object System.Drawing.PointF([float]($px + $pw - $c), [float]$py)),
                (New-Object System.Drawing.PointF([float]($px + $pw), [float]$py)),
                (New-Object System.Drawing.PointF([float]($px + $pw), [float]($py + $c)))))
        $fold.Dispose()
    }

    # 线稿:折线 + 圆。用蓝色主色,像技术图纸上的图形。
    $lw = [float]([Math]::Max(1, $s * 0.05))
    $ink = New-Object System.Drawing.Pen(
        [System.Drawing.Color]::FromArgb(255, 0x2E, 0x8B, 0xB8), $lw)
    $ink.StartCap = 'Round'; $ink.EndCap = 'Round'; $ink.LineJoin = 'Round'
    $g.DrawLines($ink, @(
            (New-Object System.Drawing.PointF([float]($px + $pw * 0.16), [float]($py + $ph * 0.74))),
            (New-Object System.Drawing.PointF([float]($px + $pw * 0.44), [float]($py + $ph * 0.32))),
            (New-Object System.Drawing.PointF([float]($px + $pw * 0.7), [float]($py + $ph * 0.58)))))
    $g.DrawEllipse($ink,
        [float]($px + $pw * 0.5), [float]($py + $ph * 0.52),
        [float]($pw * 0.26), [float]($pw * 0.26))
    $ink.Dispose()
    $g.Dispose()
    $bmp
}

# ---- 图标五:STEP 转 DXF ------------------------------------------------
# 等轴立方体(蓝色三档,和嘉立创下载器的绿立方体区分开)+ 下方一个扁平的
# 投影面,表示"3D 模型投影成 2D 视图"。
function New-Step2DxfIcon([int]$s) {
    $bmp, $g = New-Bitmap $s
    $plate = Add-Plate $g $s ([System.Drawing.Color]::FromArgb(255, 0x14, 0x47, 0x6B))
    $plate.Dispose()

    if ($s -lt 32) { $cy = $s * 0.5; $r = $s * 0.34 }
    else { $cy = $s * 0.4; $r = $s * 0.26 }
    $cx = $s * 0.5
    $w = $r * 0.866
    $h = $r * 0.5

    function P($x, $y) { New-Object System.Drawing.PointF([float]$x, [float]$y) }

    # 蓝色三档:顶亮、左基、右暗
    $top = New-Object System.Drawing.SolidBrush(
        [System.Drawing.Color]::FromArgb(255, 0x62, 0xB9, 0xE0))
    $left = New-Object System.Drawing.SolidBrush(
        [System.Drawing.Color]::FromArgb(255, 0x2E, 0x8B, 0xB8))
    $right = New-Object System.Drawing.SolidBrush(
        [System.Drawing.Color]::FromArgb(255, 0x1C, 0x5E, 0x82))
    $g.FillPolygon($top, @(
            (P $cx ($cy - $r)), (P ($cx + $w) ($cy - $h)),
            (P $cx $cy), (P ($cx - $w) ($cy - $h))))
    $g.FillPolygon($left, @(
            (P ($cx - $w) ($cy - $h)), (P $cx $cy),
            (P $cx ($cy + $r)), (P ($cx - $w) ($cy + $h))))
    $g.FillPolygon($right, @(
            (P ($cx + $w) ($cy - $h)), (P $cx $cy),
            (P $cx ($cy + $r)), (P ($cx + $w) ($cy + $h))))
    $top.Dispose(); $left.Dispose(); $right.Dispose()

    # 32px 起画投影面:立方体正下方一个白色扁菱形,像投在 XY 面上的 2D 视图。
    if ($s -ge 32) {
        $pline = New-Object System.Drawing.Pen(
            [System.Drawing.Color]::FromArgb(190, 0xE8, 0xF2, 0xF8),
            [float]([Math]::Max(1, $s * 0.02)))
        $g.DrawLine($pline, [float]$cx, [float]($cy + $r), [float]$cx, [float]($s * 0.78))
        $pline.Dispose()

        $proj = New-Object System.Drawing.SolidBrush(
            [System.Drawing.Color]::FromArgb(235, 0xF2, 0xF8, 0xFC))
        $py = $s * 0.86
        $pw = $s * 0.22
        $ph = $s * 0.055
        $g.FillPolygon($proj, @(
                (P $cx ($py - $ph)), (P ($cx + $pw) $py),
                (P $cx ($py + $ph)), (P ($cx - $pw) $py)))
        $proj.Dispose()
    }
    $g.Dispose()
    $bmp
}

# ---- 图标六:Gerber 转 DXF ----------------------------------------------
# 一块绿色 PCB,上面两个焊盘用一条走线连起来 —— 绿板 + 圆焊盘是 PCB 最一眼
# 认得出的样子,和另外两个转换工具(图纸、立方体)彻底分开。
function New-Gerber2DxfIcon([int]$s) {
    $bmp, $g = New-Bitmap $s
    $plate = Add-Plate $g $s ([System.Drawing.Color]::FromArgb(255, 0x14, 0x47, 0x6B))
    $plate.Dispose()

    # 绿板
    $bx = $s * 0.17; $by = $s * 0.22
    $bw = $s * 0.66; $bh = $s * 0.56
    $board = New-Object System.Drawing.SolidBrush(
        [System.Drawing.Color]::FromArgb(255, 0x2F, 0x9E, 0x5A))
    $g.FillRectangle($board, [float]$bx, [float]$by, [float]$bw, [float]$bh)
    $board.Dispose()

    # 走线:亮绿,斜穿过板子
    $trace = New-Object System.Drawing.Pen(
        [System.Drawing.Color]::FromArgb(255, 0x8F, 0xDD, 0xAC),
        [float]([Math]::Max(2, $s * 0.06)))
    $trace.StartCap = 'Round'; $trace.EndCap = 'Round'
    $p1x = $bx + $bw * 0.24; $p1y = $by + $bh * 0.3
    $p2x = $bx + $bw * 0.76; $p2y = $by + $bh * 0.7
    $g.DrawLine($trace, [float]$p1x, [float]$p1y, [float]$p2x, [float]$p2y)
    $trace.Dispose()

    # 焊盘:浅色圆
    $pad = New-Object System.Drawing.SolidBrush(
        [System.Drawing.Color]::FromArgb(255, 0xE8, 0xF2, 0xF8))
    $pr = [float]([Math]::Max(2, $s * 0.11))
    $g.FillEllipse($pad, [float]($p1x - $pr), [float]($p1y - $pr), [float]($pr * 2), [float]($pr * 2))
    $g.FillEllipse($pad, [float]($p2x - $pr), [float]($p2y - $pr), [float]($pr * 2), [float]($pr * 2))
    $pad.Dispose()

    # 32px 起加钻孔(暗心),更像真的焊盘
    if ($s -ge 32) {
        $drill = New-Object System.Drawing.SolidBrush(
            [System.Drawing.Color]::FromArgb(255, 0x14, 0x47, 0x6B))
        $dr = [float]($s * 0.04)
        $g.FillEllipse($drill, [float]($p1x - $dr), [float]($p1y - $dr), [float]($dr * 2), [float]($dr * 2))
        $g.FillEllipse($drill, [float]($p2x - $dr), [float]($p2y - $dr), [float]($dr * 2), [float]($dr * 2))
        $drill.Dispose()
    }
    $g.Dispose()
    $bmp
}

# ---- 打包成 .ico -------------------------------------------------------
# 手写 ICO 头。System.Drawing 的 Icon.Save 只写单张图,多尺寸得自己拼。
#
# 每张存成 32bpp DIB,不用 PNG。PNG 内嵌是 Vista 起支持的,资源管理器认,
# **但 GDI+ 不认** —— 工具箱走 Icon.ExtractAssociatedIcon 拿图标,PNG 那种
# 条目一画就抛 "Requested range extends past the end of the array"。所以图标
# 在桌面上好好的,在工具箱里是空白。DIB 从 XP 起处处都认,代价只是文件大些。
#
# DIB 的两个坑:行是**自下而上**存的,而且高度字段要写**两倍** —— 那是
# 颜色位图加一张 AND 掩码的总高。32bpp 有 alpha,掩码用不上,但字段还得对,
# 后面那张全 0 的掩码也还得写。
function Get-DibBytes($bmp, [int]$s) {
    $ms = New-Object System.IO.MemoryStream
    $bw = New-Object System.IO.BinaryWriter($ms)
    $bw.Write([UInt32]40)                 # BITMAPINFOHEADER 大小
    $bw.Write([Int32]$s)                  # 宽
    $bw.Write([Int32]($s * 2))            # 高 = 颜色 + 掩码
    $bw.Write([UInt16]1)                  # planes
    $bw.Write([UInt16]32)                 # bpp
    $bw.Write([UInt32]0)                  # BI_RGB,不压缩
    $bw.Write([UInt32]0)                  # 图像字节数,BI_RGB 可以填 0
    $bw.Write([Int32]0); $bw.Write([Int32]0)
    $bw.Write([UInt32]0); $bw.Write([UInt32]0)
    # 像素:BGRA,从最后一行往上写
    for ($y = $s - 1; $y -ge 0; $y--) {
        for ($x = 0; $x -lt $s; $x++) {
            $c = $bmp.GetPixel($x, $y)
            $bw.Write([Byte]$c.B); $bw.Write([Byte]$c.G)
            $bw.Write([Byte]$c.R); $bw.Write([Byte]$c.A)
        }
    }
    # AND 掩码:1bpp,每行按 4 字节对齐。全 0 = 全不透明,透明交给 alpha。
    $stride = [int](([Math]::Floor(($s + 31) / 32)) * 4)
    $zero = New-Object 'Byte[]' ($stride * $s)
    $bw.Write($zero)
    $bw.Flush()
    $out = $ms.ToArray()
    $bw.Dispose(); $ms.Dispose()
    # 前面这个逗号是必须的:PowerShell 会把 Byte[] 从管道里摊开,接收端拿到的
    # 是 Object[]。那样 BinaryWriter.Write 就不会绑到 Write(byte[]) 上,而是
    # 挑了别的重载,写出来的字节数不对 —— 文件小了三分之二,而且不报错。
    , $out
}

# 小尺寸用 DIB,128 以上用 PNG。理由是两边的短板刚好互补:GDI+ 读不了 PNG
# 条目,而 256 的 DIB 是 256KB 一张 —— 两个图标就给安装包加了半兆多。
# 工具箱要的是 32/48,落在 DIB 这边;资源管理器的超大图标要 256,落在 PNG
# 这边,它认。分界线放在 64/128 之间,是因为 GDI+ 那条路径不会去要 128。
$dibMax = 64

function Save-Ico([string]$path, [scriptblock]$draw) {
    # List[byte[]] 而不是 PowerShell 数组:元素类型钉死,取出来一定还是 Byte[],
    # 不会在某一步悄悄变成 Object[] 让 Write 挑错重载。
    $pngs = New-Object 'System.Collections.Generic.List[byte[]]'
    foreach ($s in $sizes) {
        $bmp = & $draw $s
        if ($s -le $dibMax) {
            $pngs.Add((Get-DibBytes $bmp $s))
        }
        else {
            $ms = New-Object System.IO.MemoryStream
            $bmp.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
            $pngs.Add($ms.ToArray())
            $ms.Dispose()
        }
        $bmp.Dispose()
    }
    $fs = [System.IO.File]::Create($path)
    $bw = New-Object System.IO.BinaryWriter($fs)
    $bw.Write([UInt16]0)                  # reserved
    $bw.Write([UInt16]1)                  # type 1 = icon
    $bw.Write([UInt16]$sizes.Count)
    # 目录项固定 16 字节,数据从所有目录项之后开始
    $offset = 6 + 16 * $sizes.Count
    for ($i = 0; $i -lt $sizes.Count; $i++) {
        # 256 在 ICO 里写 0 —— 这个字段只有一个字节,装不下 256
        $b = if ($sizes[$i] -ge 256) { 0 } else { $sizes[$i] }
        $bw.Write([Byte]$b)               # width
        $bw.Write([Byte]$b)               # height
        $bw.Write([Byte]0)                # 调色板色数,32bpp 没有调色板
        $bw.Write([Byte]0)                # reserved
        $bw.Write([UInt16]1)              # color planes
        $bw.Write([UInt16]32)             # bpp
        $bw.Write([UInt32]$pngs[$i].Length)
        $bw.Write([UInt32]$offset)
        $offset += $pngs[$i].Length
    }
    foreach ($p in $pngs) { $bw.Write($p) }
    $bw.Flush(); $bw.Dispose(); $fs.Dispose()
    "  {0}  {1} bytes, {2} sizes" -f (Split-Path -Leaf $path), (Get-Item $path).Length, $sizes.Count
}

Write-Host "writing icons into $here"
Save-Ico (Join-Path $here 'lceda2orcad.ico') ${function:New-ConvertIcon}
Save-Ico (Join-Path $here 'specgen.ico')     ${function:New-SpecIcon}
Save-Ico (Join-Path $here 'jlc3d.ico')       ${function:New-Jlc3dIcon}
Save-Ico (Join-Path $here 'dwg2dxf.ico')     ${function:New-Dwg2DxfIcon}
Save-Ico (Join-Path $here 'step2dxf.ico')    ${function:New-Step2DxfIcon}
Save-Ico (Join-Path $here 'gerber2dxf.ico')  ${function:New-Gerber2DxfIcon}
