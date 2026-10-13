# Тестовая сборка: заметно красная кровь, чтобы проверить, что наш пак перекрывает DarthMod.
# Берёт effects\landbattle.xml из DMN_Darth_Effects_Napoleon.pack (сам пак не меняет),
# правит только эффекты крови и собирает отдельный movie-пак в data\.
# Запуск:  powershell -ExecutionPolicy Bypass -File tools\build_test_pack.ps1
# Удаление мода: удалить data\zz_gore_test.pack

param(
    [string]$GameDir  = 'E:\Steam\steamapps\common\Napoleon Total War',
    [string]$PackName = 'zz_gore_test.pack',
    [switch]$NoInstall
)

$ErrorActionPreference = 'Stop'
$Data    = Join-Path $GameDir 'data'
$Source  = Join-Path $Data 'DMN_Darth_Effects_Napoleon.pack'
$OutDir  = Join-Path $PSScriptRoot '..\build'
New-Item -ItemType Directory -Force $OutDir | Out-Null
$Latin1  = [Text.Encoding]::GetEncoding(28591)   # байт-в-байт, файл чисто ASCII

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

Write-Host '== Чтение landbattle.xml из DarthMod ==' -ForegroundColor Cyan
$xml = $Latin1.GetString((Read-PackFile $Source 'effects\landbattle.xml'))
$origLen = $xml.Length

# ТЕСТ: чисто красный цвет, крупнее капли. Лимиты частиц не повышаем.
$red = @{
    start_colour_range_r = 'variance(255,0)'; start_colour_range_g = 'variance(0,0)'; start_colour_range_b = 'variance(0,0)'
    end_colour_range_r   = 'variance(255,0)'; end_colour_range_g   = 'variance(0,0)'; end_colour_range_b   = 'variance(0,0)'
    colour_range_a       = 'variance(255,0)'
}
foreach ($e in 'small_bloodspray1', 'small_bloodspray2', 'small_bloodspray3', 'blood_mist') {
    $xml = Edit-Effect $xml $e $red
}
$xml = Edit-Effect $xml 'small_bloodspray1' @{
    initial_scale_range_metres = 'vector(variance(0.500000,0.300000),variance(0.050000,0.100000))'
    lighting = 'variance(0.000000,0.000000)'
}
# Пули: к одиночной струйке добавляем более заметный bloodspray2
$xml = Add-GroupEntry $xml 'Musket_impact_human' 'small_bloodspray2'

Write-Host "Размер XML: $origLen -> $($xml.Length) символов"
$xmlBytes = $Latin1.GetBytes($xml)
[IO.File]::WriteAllBytes((Join-Path $OutDir 'landbattle.xml'), $xmlBytes)

# Проверка, что XML не сломан
$doc = New-Object Xml.XmlDocument; $doc.LoadXml($xml)
Write-Host 'XML валиден.' -ForegroundColor Green

$packPath = Join-Path $OutDir $PackName
Write-Pack $packPath 4 @{ 'effects\landbattle.xml' = $xmlBytes }   # 4 = movie, грузится без user.script
Write-Host "Собран: $packPath" -ForegroundColor Green

if (-not $NoInstall) {
    Copy-Item $packPath (Join-Path $Data $PackName) -Force
    Write-Host "Установлен: $(Join-Path $Data $PackName)" -ForegroundColor Green
}
