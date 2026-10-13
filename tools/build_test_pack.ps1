# Тест порядка загрузки: два movie-пака с кровью разного цвета.
#   !gore_test_blue.pack     (по алфавиту ДО паков DMN_*)    -> синяя кровь
#   zz_gore_test_green.pack  (по алфавиту ПОСЛЕ паков DMN_*) -> зелёная кровь
# Какой цвет виден в игре, тот пак и перекрывает DarthMod. Обычная красная кровь значит,
# что DarthMod перекрывает оба пака.
# Берёт effects\landbattle.xml и текстуру крови из DMN_Darth_Effects_Napoleon.pack (сам пак не меняет).
# Запуск:  powershell -ExecutionPolicy Bypass -File tools\build_test_pack.ps1
# Удаление: powershell -ExecutionPolicy Bypass -File tools\build_test_pack.ps1 -Uninstall

param(
    [string]$GameDir = 'E:\Steam\steamapps\common\Napoleon Total War',
    [switch]$NoInstall,
    [switch]$Uninstall
)

$ErrorActionPreference = 'Stop'
$Data    = Join-Path $GameDir 'data'
$Source  = Join-Path $Data 'DMN_Darth_Effects_Napoleon.pack'
$OutDir  = Join-Path $PSScriptRoot '..\build'
New-Item -ItemType Directory -Force $OutDir | Out-Null
$Latin1  = [Text.Encoding]::GetEncoding(28591)   # байт-в-байт, файл чисто ASCII

$Variants = @(
    @{ Pack = '!gore_test_blue.pack';    Tex = 'gore_test_blue';  R = 0;  G = 80;  B = 255 },
    @{ Pack = 'zz_gore_test_green.pack'; Tex = 'gore_test_green'; R = 0;  G = 255; B = 0 }
)
$Obsolete = @('zz_gore_test.pack')   # первая тестовая сборка

if ($Uninstall) {
    foreach ($n in @($Variants | ForEach-Object { $_.Pack }) + $Obsolete) {
        $f = Join-Path $Data $n
        if (Test-Path -LiteralPath $f) { Remove-Item -LiteralPath $f; Write-Host "Удалён: $f" }
    }
    return
}

# ---------- чтение файла из PFH0 без распаковки всего пака ----------
function Read-PackFile([string]$pack, [string]$entry) {
    $fs = [IO.File]::OpenRead($pack); $br = New-Object IO.BinaryReader($fs)
    try {
        $magic = [Text.Encoding]::ASCII.GetString($br.ReadBytes(4))
        if ($magic -ne 'PFH0') { throw "$pack : неожиданный формат $magic" }
        $null = $br.ReadUInt32(); $null = $br.ReadUInt32(); $depSize = $br.ReadUInt32()
        $count = $br.ReadUInt32(); $idxSize = $br.ReadUInt32()
        $null = $br.ReadBytes($depSize); $idx = $br.ReadBytes($idxSize)
        $offset = [int64](24 + $depSize + $idxSize); $p = 0
        for ($i = 0; $i -lt $count; $i++) {
            $size = [BitConverter]::ToUInt32($idx, $p); $p += 4
            $e = [Array]::IndexOf($idx, [byte]0, $p)
            $name = [Text.Encoding]::ASCII.GetString($idx, $p, $e - $p); $p = $e + 1
            if ($name -eq $entry) { $fs.Position = $offset; return $br.ReadBytes($size) }
            $offset += $size
        }
        throw "$entry не найден в $pack"
    } finally { $br.Close() }
}

# ---------- запись PFH0 (без сжатия) ----------
function Write-Pack([string]$path, [int]$type, [hashtable]$files) {
    $names = $files.Keys | Sort-Object
    $idx = New-Object IO.MemoryStream
    foreach ($n in $names) {
        $idx.Write([BitConverter]::GetBytes([uint32]$files[$n].Length), 0, 4)
        $nb = [Text.Encoding]::ASCII.GetBytes($n); $idx.Write($nb, 0, $nb.Length); $idx.WriteByte(0)
    }
    $fs = [IO.File]::Create($path); $bw = New-Object IO.BinaryWriter($fs)
    try {
        $bw.Write([Text.Encoding]::ASCII.GetBytes('PFH0'))
        $bw.Write([uint32]$type); $bw.Write([uint32]0); $bw.Write([uint32]0)
        $bw.Write([uint32]$names.Count); $bw.Write([uint32]$idx.Length)
        $bw.Write($idx.ToArray())
        foreach ($n in $names) { $bw.Write([byte[]]$files[$n]) }
    } finally { $bw.Close() }
}

# ---------- правки XML ----------
# Меняет атрибуты внутри одного <SCRIPTED_EFFECT_INFO name='...'> ... </SCRIPTED_EFFECT_INFO>
function Edit-Effect([string]$xml, [string]$effect, [hashtable]$attrs) {
    $start = $xml.IndexOf("<SCRIPTED_EFFECT_INFO name='$effect'")
    if ($start -lt 0) { throw "Эффект $effect не найден" }
    $end = $xml.IndexOf('</SCRIPTED_EFFECT_INFO>', $start)
    $block = $xml.Substring($start, $end - $start)
    foreach ($a in $attrs.Keys) {
        $re = " $a='[^']*'"
        if ($block -notmatch $re) { throw "У $effect нет атрибута $a" }
        $block = [regex]::Replace($block, $re, " $a='$($attrs[$a])'")
    }
    $xml.Substring(0, $start) + $block + $xml.Substring($end)
}

function Add-GroupEntry([string]$xml, [string]$group, [string]$effect) {
    $start = $xml.IndexOf("<SCRIPTED_EFFECT_GROUP name='$group'")
    if ($start -lt 0) { throw "Группа $group не найдена" }
    $end = $xml.IndexOf('</SCRIPTED_EFFECT_GROUP>', $start)
    if ($xml.Substring($start, $end - $start).Contains("effect='$effect'")) { return $xml }
    $line = "    <SCRIPTED_EFFECT_GROUP_ENTRY name='$effect' effect='$effect' />`r`n        "
    $xml.Substring(0, $end) + $line + $xml.Substring($end)
}


# ---------- текстура: альфа из оригинальной капли, цвет свой ----------
# Оригинал: TGA type 10 (RLE), 32 bpp. Пишем несжатый TGA type 2 с тем же размером и альфой.
function New-TintedTga([byte[]]$src, [int]$r, [int]$g, [int]$b) {
    if ($src[2] -ne 10 -or $src[16] -ne 32) { throw "Ожидался RLE TGA 32 bpp, а не type=$($src[2]) bpp=$($src[16])" }
    $w = [BitConverter]::ToUInt16($src, 12); $h = [BitConverter]::ToUInt16($src, 14)
    $out = New-Object byte[] (18 + $w * $h * 4)
    [Array]::Copy($src, 0, $out, 0, 18); $out[0] = 0; $out[2] = 2
    $i = 18 + $src[0]; $o = 18; $end = $out.Length
    while ($o -lt $end) {
        $hdr = $src[$i]; $i++; $cnt = ($hdr -band 0x7F) + 1
        for ($k = 0; $k -lt $cnt; $k++) {
            $a = if ($hdr -band 0x80) { $src[$i + 3] } else { $src[$i + 4 * $k + 3] }
            $out[$o] = $b; $out[$o + 1] = $g; $out[$o + 2] = $r; $out[$o + 3] = $a; $o += 4
        }
        $i += if ($hdr -band 0x80) { 4 } else { 4 * $cnt }
    }
    $out
}

Write-Host '== Чтение landbattle.xml и текстуры крови из DarthMod ==' -ForegroundColor Cyan
$baseXml = $Latin1.GetString((Read-PackFile $Source 'effects\landbattle.xml'))
$baseTex = Read-PackFile $Source 'effects\textures\emp_humanhit_diffuse2.tga'

foreach ($v in $Variants) {
    $texPath = "effects\textures\$($v.Tex).tga"
    $xml = $baseXml
    # Белый множитель цвета: цвет задаёт текстура, освещение не затемняет
    $look = @{
        start_colour_range_r = 'variance(255,0)'; start_colour_range_g = 'variance(255,0)'; start_colour_range_b = 'variance(255,0)'
        end_colour_range_r   = 'variance(255,0)'; end_colour_range_g   = 'variance(255,0)'; end_colour_range_b   = 'variance(255,0)'
        colour_range_a       = 'variance(255,0)'
        lighting             = 'variance(0.000000,0.000000)'
        texture_1            = $texPath
    }
    foreach ($e in 'small_bloodspray1', 'small_bloodspray2', 'small_bloodspray3', 'blood_mist') {
        $xml = Edit-Effect $xml $e $look
    }
    $xml = Edit-Effect $xml 'small_bloodspray1' @{
        initial_scale_range_metres = 'vector(variance(0.500000,0.300000),variance(0.050000,0.100000))'
    }
    # Пули: к одиночной струйке добавляем более заметный bloodspray2
    $xml = Add-GroupEntry $xml 'Musket_impact_human' 'small_bloodspray2'

    $doc = New-Object Xml.XmlDocument; $doc.LoadXml($xml)   # проверка, что XML не сломан

    $packPath = Join-Path $OutDir $v.Pack
    Write-Pack $packPath 4 @{                                 # 4 = movie, грузится без user.script
        'effects\landbattle.xml' = $Latin1.GetBytes($xml)
        $texPath                 = New-TintedTga $baseTex $v.R $v.G $v.B
    }
    Write-Host "Собран: $packPath" -ForegroundColor Green
}

if (-not $NoInstall) {
    foreach ($n in $Obsolete) {
        $f = Join-Path $Data $n
        if (Test-Path -LiteralPath $f) { Remove-Item -LiteralPath $f; Write-Host "Удалён старый тест: $f" }
    }
    foreach ($v in $Variants) {
        Copy-Item -LiteralPath (Join-Path $OutDir $v.Pack) -Destination (Join-Path $Data $v.Pack) -Force
        Write-Host "Установлен: $(Join-Path $Data $v.Pack)" -ForegroundColor Green
    }
}
