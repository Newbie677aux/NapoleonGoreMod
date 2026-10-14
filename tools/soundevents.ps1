# Скомпилированная таблица звуков sounds_packed\sound_events (из sound.pack). Игра читает ЕЁ, а не
# sounds\events\*.csv (это исходники, правки в них ни на что не влияют). Подключать после packlib.ps1.
#
# Формат (всё little-endian, строки = u16 длина + UTF-16LE):
#   f32 ?; u32 nc; nc × (строка категории, f32 громкость категории)
#   u32 k; k × u32                       (неизвестно, переносится как есть)
#   u32 np; np × 35 f32                  (наборы параметров = колонки 2..36 csv, общие для многих событий)
#   u32 ne; ne × (u32 категория, [строка-имя — только у некоторых], u32 индекс набора, u32 n, n × строка wav)
#   хвост (музыкальные плейлисты nap_*.csv) — переносится как есть
# Имён событий нет: банки ссылаются на события по номеру.

$SoundParamCount = 35

function Read-SoundEvents([byte[]]$b) {
    $r = New-Object IO.BinaryReader(New-Object IO.MemoryStream(, $b))
    $str = { $l = $r.ReadUInt16(); [Text.Encoding]::Unicode.GetString($r.ReadBytes(2 * $l)) }
    $head0 = $r.ReadBytes(4)
    $nc = $r.ReadUInt32()
    $cats = New-Object Collections.Generic.List[object]
    for ($i = 0; $i -lt $nc; $i++) { $cats.Add(@((& $str), $r.ReadSingle())) }
    $k = $r.ReadUInt32(); $mid = New-Object Collections.Generic.List[uint32]
    for ($i = 0; $i -lt $k; $i++) { $mid.Add($r.ReadUInt32()) }
    $np = $r.ReadUInt32()
    $params = New-Object Collections.Generic.List[float[]]
    for ($i = 0; $i -lt $np; $i++) {
        $f = New-Object float[] $SoundParamCount
        for ($j = 0; $j -lt $SoundParamCount; $j++) { $f[$j] = $r.ReadSingle() }
        $params.Add($f)
    }
    $ne = $r.ReadUInt32()
    $events = New-Object Collections.Generic.List[object]
    for ($i = 0; $i -lt $ne; $i++) {
        $cat = $r.ReadUInt32(); $name = $null
        # индекс набора всегда < np; строка же даёт u32 = длина | (первый символ << 16) — заведомо больше
        $pos = $r.BaseStream.Position
        if ($r.ReadUInt32() -ge $np) { $r.BaseStream.Position = $pos; $name = & $str } else { $r.BaseStream.Position = $pos }
        $p = $r.ReadUInt32(); $n = $r.ReadUInt32()
        $w = New-Object string[] $n
        for ($j = 0; $j -lt $n; $j++) { $w[$j] = & $str }
        $events.Add([pscustomobject]@{ Index = $i; Category = $cat; Name = $name; Param = $p; Waves = $w })
    }
    $tail = $r.ReadBytes($b.Length - [int]$r.BaseStream.Position)
    [pscustomobject]@{ Head0 = $head0; Categories = $cats; Mid = $mid; Params = $params; Events = $events; Tail = $tail }
}

function Write-SoundEvents($se) {
    $ms = New-Object IO.MemoryStream; $w = New-Object IO.BinaryWriter($ms)
    $str = { param($s) $w.Write([uint16]$s.Length); $w.Write([Text.Encoding]::Unicode.GetBytes($s)) }
    $w.Write([byte[]]$se.Head0)
    $w.Write([uint32]$se.Categories.Count)
    foreach ($c in $se.Categories) { & $str $c[0]; $w.Write([single]$c[1]) }
    $w.Write([uint32]$se.Mid.Count); foreach ($m in $se.Mid) { $w.Write([uint32]$m) }
    $w.Write([uint32]$se.Params.Count)
    foreach ($f in $se.Params) { foreach ($x in $f) { $w.Write([single]$x) } }
    $w.Write([uint32]$se.Events.Count)
    foreach ($e in $se.Events) {
        $w.Write([uint32]$e.Category)
        if ($null -ne $e.Name) { & $str $e.Name }
        $w.Write([uint32]$e.Param); $w.Write([uint32]$e.Waves.Count)
        foreach ($x in $e.Waves) { & $str $x }
    }
    $w.Write([byte[]]$se.Tail); $w.Flush()
    $ms.ToArray()
}

# Даёт событию собственный набор параметров (копия общего) и меняет в нём поля.
# $cols — @{ колонка csv = значение }, колонки как в sounds\events\*.csv: 2 громкость, 5 min_dist,
# 6 max_dist, 13 вероятность, 35 сколько одновременно. В бинарнике поле = колонка - 2.
function Set-SoundEventParams($se, [int]$event, [hashtable]$cols) {
    $e = $se.Events[$event]
    $f = [float[]]$se.Params[[int]$e.Param].Clone()
    foreach ($c in $cols.Keys) {
        $j = [int]$c - 2
        if ($j -lt 0 -or $j -ge $SoundParamCount) { throw "Колонка $c не числовой параметр" }
        $f[$j] = [float]$cols[$c]
    }
    $se.Params.Add($f); $e.Param = $se.Params.Count - 1
}

# Номера событий, соответствующих строке csv $name: тот же список wav (без учёта регистра) и те же
# основные числовые параметры (текстовые колонки вроде playback в бинарнике — номера).
# Одинаковых событий бывает несколько (одна строка на разные анимации) — возвращаются все.
function Find-SoundEventsByCsv($se, [string]$csv, [string]$name) {
    $m = [regex]::Matches($csv, '(?m)^("?)' + [regex]::Escape($name) + '\1,[^\r\n]*')
    if ($m.Count -ne 1) { throw "Строка $name в csv: найдено $($m.Count)" }
    $f = $m[0].Value -split ','
    $key = (@($f[37..($f.Count - 1)] | ForEach-Object { $_.Trim('"').ToLowerInvariant() } | Where-Object { $_ }) -join '|')
    $inv = [Globalization.CultureInfo]::InvariantCulture
    $found = @(foreach ($e in $se.Events) {
        if ((($e.Waves | ForEach-Object { $_.ToLowerInvariant() }) -join '|') -ne $key) { continue }
        $p = $se.Params[[int]$e.Param]; $same = $true
        foreach ($c in 2, 3, 4, 5, 6, 7, 8, 9, 13, 35, 36) {   # не все колонки 1:1 (например -1 в 26-й хранится как 0)
            $v = 0.0
            if ([double]::TryParse($f[$c].Trim('"'), [Globalization.NumberStyles]::Float, $inv, [ref]$v) -and [math]::Abs($v - $p[$c - 2]) -gt 1e-4) { $same = $false; break }
        }
        if ($same) { $e.Index }
    })
    if (-not $found.Count) { throw "Событие $name не найдено в sounds_packed\sound_events" }
    $found
}

# Что меняет мод: csv-файл, имя строки, @{ колонка = значение }. Используют build_pack и verify_pack.
# Ваниль глушит всё «мясное»: пуля в тело — 0.3 и слышно до 3 м от камеры, ядро 0.1,
# рукопашная 0.1 с затуханием от 10 см, предсмертный крик 0.1 с 16 см и только в трети смертей.
$GoreMelee = @{ 2 = 0.45; 5 = 3; 6 = 45; 35 = 16 }
$GoreSoundChanges = @(
    @('voices_land', 'Unit_Voices_Death_Gen', @{ 2 = 0.7; 5 = 6; 6 = 70; 13 = 0.7; 35 = 24 }),
    @('weapons', 'PROJECTILE_BulletImpactFlesh', @{ 2 = 0.5; 5 = 2.5; 6 = 40; 35 = 16 }),
    @('weapons', 'PROJECTILE_CannonballImpactFlesh', @{ 2 = 0.6; 5 = 6; 6 = 120; 35 = 8 })
) + @('axe_hit_flesh', 'bayonet_hit_flesh', 'bayonet_impact_flesh', 'club_hit_flesh', 'lance_spear_hit_flesh',
      'longsword_hit_flesh', 'pike_hit_flesh', 'sabre_hit_flesh', 'musket_impact_body' | ForEach-Object { , @('animations', $_, $GoreMelee) })

# Применяет $GoreSoundChanges к исходным байтам sound_events. Возвращает @{ Bytes; Events = номер → имя }.
function Get-GoreSoundEvents([byte[]]$src, [string]$soundPack) {
    $csvs = Read-PackFiles $soundPack '^sounds\\events\\sound_events_(voices_land|weapons|animations)\.csv$'
    $se = Read-SoundEvents $src
    # сначала ищем все (поиск сравнивает параметры), потом меняем
    $hits = @(foreach ($ch in $GoreSoundChanges) {
        $csv = [Text.Encoding]::ASCII.GetString($csvs["sounds\events\sound_events_$($ch[0]).csv"])
        foreach ($i in (Find-SoundEventsByCsv $se $csv $ch[1])) { , @($i, $ch[1], $ch[2]) }
    })
    $done = @{}
    foreach ($h in $hits) {
        if ($done.ContainsKey($h[0])) { $done[$h[0]] += ", $($h[1])"; continue }   # одно событие на две строки csv
        Set-SoundEventParams $se $h[0] $h[2]; $done[$h[0]] = $h[1]
    }
    @{ Bytes = (Write-SoundEvents $se); Events = $done }
}
