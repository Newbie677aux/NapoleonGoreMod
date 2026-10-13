# Проверка установленного мода без запуска игры: структура пака, XML эффектов, текстура, WAV, MP3,
# события анимаций, что все пути перекрывают реальные файлы игры и что чужие паки не тронуты.
# Запуск: powershell -ExecutionPolicy Bypass -File tools\verify_pack.ps1

param([string]$GameDir = 'E:\Steam\steamapps\common\Napoleon Total War')

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\packlib.ps1"
$Data = Join-Path $GameDir 'data'
$Pack = Join-Path $Data 'zz_NapoleonGoreMod.pack'
$fail = 0; $warn = 0
function Ok([string]$m)   { Write-Host "  OK    $m" -ForegroundColor Green }
function Bad([string]$m)  { Write-Host "  FAIL  $m" -ForegroundColor Red; $script:fail++ }
function Warn([string]$m) { Write-Host "  WARN  $m" -ForegroundColor Yellow; $script:warn++ }

# Индекс пака: имена и размеры, без чтения данных
function Get-PackIndex([string]$path) {
    $fs = [IO.File]::OpenRead($path); $br = New-Object IO.BinaryReader($fs)
    try {
        $h = [pscustomobject]@{ Magic = [Text.Encoding]::ASCII.GetString($br.ReadBytes(4)); Type = $br.ReadUInt32()
            Deps = $br.ReadUInt32(); DepSize = $br.ReadUInt32(); Count = $br.ReadUInt32(); IdxSize = $br.ReadUInt32(); Files = @{}; Length = $fs.Length }
        $null = $br.ReadBytes($h.DepSize); $idx = $br.ReadBytes($h.IdxSize); $p = 0; $sum = [int64]0
        for ($i = 0; $i -lt $h.Count; $i++) {
            $size = [BitConverter]::ToUInt32($idx, $p); $p += 4
            $e = [Array]::IndexOf($idx, [byte]0, $p)
            $h.Files[[Text.Encoding]::ASCII.GetString($idx, $p, $e - $p)] = $size; $p = $e + 1; $sum += $size
        }
        $h | Add-Member DataSum $sum; $h | Add-Member IdxEnd $p
        $h
    } finally { $br.Close() }
}

Write-Host '== 1. Установка ==' -ForegroundColor Cyan
if (Test-Path -LiteralPath $Pack) { Ok "есть $Pack" } else { Bad "нет $Pack"; exit 1 }
$left = @(Get-ChildItem -LiteralPath $Data -Filter *.pack | Where-Object { $_.Name -match 'gore' -and $_.Name -ne 'zz_NapoleonGoreMod.pack' })
if ($left.Count) { Bad "лишние тестовые паки: $($left.Name -join ', ')" } else { Ok 'тестовых паков нет' }
$us = Get-Content "$env:APPDATA\The Creative Assembly\Napoleon\scripts\user.script.txt" -Raw
if ($us -match 'gore') { Bad 'user.script.txt ссылается на мод' } else { Ok 'user.script.txt не тронут модом' }

Write-Host '== 2. Структура пака ==' -ForegroundColor Cyan
$ix = Get-PackIndex $Pack
if ($ix.Magic -eq 'PFH0' -and $ix.Type -eq 4 -and $ix.Deps -eq 0) { Ok 'PFH0, тип movie, без зависимостей' } else { Bad "заголовок: $($ix.Magic) type=$($ix.Type) deps=$($ix.Deps)" }
if ($ix.IdxEnd -eq $ix.IdxSize) { Ok "индекс: $($ix.Count) файлов" } else { Bad "индекс разобран не до конца ($($ix.IdxEnd) из $($ix.IdxSize))" }
$expect = 24 + $ix.DepSize + $ix.IdxSize + $ix.DataSum
if ($expect -eq $ix.Length) { Ok "размер файла сходится ($([math]::Round($ix.Length/1MB,1)) МБ)" } else { Bad "размер $($ix.Length), ожидалось $expect" }
$badNames = @($ix.Files.Keys | Where-Object { $_ -match '/' -or $_ -match '[^\x20-\x7E]' -or $_ -match '__' })
if ($badNames.Count) { Bad "странные пути: $($badNames -join ', ')" } else { Ok 'пути ASCII, разделитель \' }

Write-Host '== 3. Каждый путь перекрывает настоящий файл игры ==' -ForegroundColor Cyan
$orig = @{}
foreach ($p in Get-ChildItem -LiteralPath $Data -Filter *.pack | Where-Object Name -ne 'zz_NapoleonGoreMod.pack') {
    foreach ($k in (Get-PackIndex $p.FullName).Files.Keys) { $orig[$k.ToLower()] = $p.Name }
}
$ours = 'effects\textures\gore_blood_diffuse.tga'
$stray = @($ix.Files.Keys | Where-Object { $_ -ne $ours -and -not $orig.ContainsKey($_.ToLower()) })
if ($stray.Count) { Bad "пути, которых нет в игре (не сработают): $($stray[0..([math]::Min(9,$stray.Count-1))] -join ', ')" } else { Ok "все $($ix.Count - 1) путей есть в паках игры (+ своя текстура)" }
$groups = $ix.Files.Keys | Group-Object { if ($_ -like 'animations*') { 'события анимаций' } elseif ($_ -like '*death_cry*') { 'крики MP3' } elseif ($_ -like 'sfx*') { 'звуки попаданий' } else { 'эффекты' } }
$groups | ForEach-Object { Write-Host "        $($_.Count) — $($_.Name)" }

Write-Host '== 4. Эффекты ==' -ForegroundColor Cyan
$xml = $Latin1.GetString((Read-PackFile $Pack 'effects\landbattle.xml'))
try { $doc = New-Object Xml.XmlDocument; $doc.LoadXml($xml); Ok 'landbattle.xml — валидный XML' } catch { Bad "XML: $($_.Exception.Message)" }
$effects = @{}; foreach ($n in $doc.SelectNodes('//SCRIPTED_EFFECT_INFO')) { $effects[$n.name] = $n }
$missing = @($doc.SelectNodes('//SCRIPTED_EFFECT_GROUP_ENTRY') | Where-Object { -not $effects.ContainsKey($_.effect) } | ForEach-Object { $_.effect } | Select-Object -Unique)
if ($missing.Count) { Bad "группы ссылаются на несуществующие эффекты: $($missing -join ', ')" } else { Ok "все записи групп ссылаются на существующие эффекты ($($effects.Count))" }
$tex = @($doc.SelectNodes('//SCRIPTED_EFFECT_RENDERING_VARS') | ForEach-Object { $_.texture_1; $_.texture_2 } | Select-Object -Unique)
$noTex = @($tex | Where-Object { $_ -and $_.TrimStart('\').ToLower() -ne $ours -and -not $orig.ContainsKey($_.TrimStart('\').ToLower()) })   # ведущий \ есть ещё в ванили
if ($noTex.Count) { Warn "текстуры не найдены в паках: $($noTex -join ', ')" } else { Ok 'все текстуры эффектов на месте' }
foreach ($g in 'Musket_impact_human', 'blood_spray') {
    $e = @($doc.SelectNodes("//SCRIPTED_EFFECT_GROUP[@name='$g']/SCRIPTED_EFFECT_GROUP_ENTRY") | ForEach-Object effect)
    Write-Host "        $g : $($e -join ', ')"
}
$quads = 0
foreach ($n in 'small_bloodspray1', 'small_bloodspray2', 'small_bloodspray3', 'blood_mist') {
    $r = $effects[$n].SCRIPTED_EFFECT_RENDERING_VARS
    if ($r.texture_1 -ne $ours) { Bad "$n не использует нашу текстуру" }
    $quads += [int]$r.max_num_quads
    Write-Host ("        {0,-18} max_effects={1,4} max_num_quads={2,4} частиц/точку={3}" -f $n, $r.max_effects, $r.max_num_quads, $effects[$n].num_particles_per_point)
}
if ($quads -le 2500) { Ok "потолок частиц крови: $quads квадов на все эффекты крови" } else { Warn "потолок частиц крови высокий: $quads" }

Write-Host '== 5. Текстура ==' -ForegroundColor Cyan
$t = Read-PackFile $Pack $ours
$w = [BitConverter]::ToUInt16($t, 12); $h = [BitConverter]::ToUInt16($t, 14)
if ($t[2] -eq 2 -and $t[16] -eq 32 -and $t.Length -eq 18 + $w * $h * 4) { Ok "TGA ${w}x$h 32 bpp, размер сходится" } else { Bad "TGA: type=$($t[2]) bpp=$($t[16]) len=$($t.Length)" }

Write-Host '== 6. Звуки попаданий (WAV) ==' -ForegroundColor Cyan
$wavs = Read-PackFiles $Pack '\.wav$'; $wb = 0
foreach ($k in $wavs.Keys) {
    $b = $wavs[$k]
    $okHdr = [Text.Encoding]::ASCII.GetString($b, 0, 4) -eq 'RIFF' -and [BitConverter]::ToUInt16($b, 20) -eq 1 -and
        [BitConverter]::ToUInt16($b, 22) -eq 1 -and [BitConverter]::ToUInt32($b, 24) -eq 44100 -and [BitConverter]::ToUInt16($b, 34) -eq 16 -and
        [BitConverter]::ToUInt32($b, 40) -eq $b.Length - 44 -and [BitConverter]::ToUInt32($b, 4) -eq $b.Length - 8
    if (-not $okHdr) { Bad "WAV заголовок: $k"; $wb++ }
}
if (-not $wb) { Ok "$($wavs.Count) WAV: PCM mono 44.1 kHz 16-bit, размеры сходятся" }

Write-Host '== 7. Крики (MP3) ==' -ForegroundColor Cyan
$mp3 = Read-PackFiles $Pack '\.mp3$'; $mb = 0
foreach ($k in $mp3.Keys) {
    $b = $mp3[$k]; $i = 0
    # Как у оригиналов игры: файл начинается прямо с кадра MPEG-1 Layer III, без ID3, и за ним идёт ещё кадр
    if ($b.Length -lt 8 -or $b[0] -ne 0xFF -or ($b[1] -band 0xFE) -ne 0xFA) { Bad "MP3 не начинается с кадра: $k"; $mb++; continue }
    $rates = 0, 32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320, 0
    $flen = [int][math]::Floor(144000 * $rates[$b[2] -shr 4] / 44100) + (($b[2] -shr 1) -band 1)
    if ($flen -lt 4 -or $flen + 2 -gt $b.Length -or $b[$flen] -ne 0xFF -or ($b[$flen + 1] -band 0xFE) -ne 0xFA) { Bad "MP3 второй кадр не на месте: $k"; $mb++; continue }
    $ver = ($b[$i + 1] -shr 3) -band 3; $sr = ($b[$i + 2] -shr 2) -band 3; $ch = $b[$i + 3] -shr 6
    if ($ver -ne 3 -or $sr -ne 0 -or $ch -ne 3) { Bad "MP3 не MPEG1/44.1k/mono: $k"; $mb++ }
    if ($b.Length -lt 4000) { Bad "MP3 подозрительно мал ($($b.Length) Б): $k"; $mb++ }
}
if (-not $mb) { Ok "$($mp3.Count) MP3: MPEG-1, 44.1 kHz, mono" }

Write-Host '== 8. События анимаций смерти ==' -ForegroundColor Cyan
$ev = Read-PackFiles $Pack '\.anim_sound_event$'; $eb = 0; $with = 0
$known = @{}; foreach ($id in 21,22,23,24,25,29,30,60,61,66,74,85,90,102,103,104,105,109) { $known[$id] = 1 }
foreach ($k in $ev.Keys) {
    $b = $ev[$k]; $n = [BitConverter]::ToUInt32($b, 4)
    if ([BitConverter]::ToUInt32($b, 0) -ne 1 -or $b.Length -ne 8 + 8 * $n) { Bad "формат: $k"; $eb++; continue }
    $prev = -1.0; $has = $false
    for ($i = 0; $i -lt $n; $i++) {
        $tm = [BitConverter]::ToSingle($b, 8 + 8 * $i); $id = [BitConverter]::ToUInt32($b, 12 + 8 * $i)
        if ($tm -lt $prev -or $tm -lt 0 -or $tm -gt 30) { Bad "время не по порядку: $k"; $eb++; break }
        if (-not $known.ContainsKey([int]$id)) { Bad "неизвестный код $id в $k"; $eb++; break }
        if ($id -eq 102) { $has = $true }; $prev = $tm
    }
    if ($has) { $with++ }
}
if (-not $eb) { Ok "$($ev.Count) файлов событий: формат и порядок времени в норме, код 102 в $with" }

Write-Host '== 9. Чужие паки не тронуты ==' -ForegroundColor Cyan
# Точка отсчёта — бэкап шага 1 (сделан до мода); без него — начало сегодняшнего дня
$backup = Get-ChildItem "$env:APPDATA\The Creative Assembly\Napoleon" -Directory -Filter '_backup_*' -ErrorAction SilentlyContinue | Sort-Object CreationTime | Select-Object -First 1
$since = if ($backup) { $backup.CreationTime } else { (Get-Date).Date }
$recent = @(Get-ChildItem -LiteralPath $Data -Filter *.pack | Where-Object { $_.Name -ne 'zz_NapoleonGoreMod.pack' -and $_.LastWriteTime -gt $since })
if ($recent.Count) { Bad "менялись после $($since.ToString('dd.MM.yyyy HH:mm')): $($recent.Name -join ', ')" } else { Ok "ни один пак игры/DarthMod не менялся после $($since.ToString('dd.MM.yyyy HH:mm'))" }

Write-Host ''
if ($fail) { Write-Host "ИТОГ: $fail ошибок, $warn предупреждений" -ForegroundColor Red; exit 1 }
Write-Host "ИТОГ: всё в порядке ($warn предупреждений)" -ForegroundColor Green
