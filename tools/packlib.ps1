# Общие функции для сборки паков Napoleon TW (PFH0, без сжатия). Подключать: . "$PSScriptRoot\packlib.ps1"

$Latin1 = [Text.Encoding]::GetEncoding(28591)   # байт-в-байт, XML эффектов чисто ASCII

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

