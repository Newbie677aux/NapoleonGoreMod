# Проверка установленного мода без запуска игры: структура пака, XML эффектов, текстура, WAV, MP3,
# события анимаций, что все пути перекрывают реальные файлы игры и что чужие паки не тронуты.
# Запуск: powershell -ExecutionPolicy Bypass -File tools\verify_pack.ps1

param([string]$GameDir = 'E:\Steam\steamapps\common\Napoleon Total War')

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\packlib.ps1"
. "$PSScriptRoot\soundevents.ps1"
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
$emptyG = @($doc.SelectNodes('//SCRIPTED_EFFECT_GROUP') | Where-Object { -not $_.SelectNodes('SCRIPTED_EFFECT_GROUP_ENTRY').Count } | ForEach-Object name)
if ($emptyG.Count) { Bad "пустые группы эффектов: $($emptyG -join ', ')" } else { Ok 'пустых групп эффектов нет' }
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

Write-Host '== 7. Нет криков MP3 и правок анимаций смерти ==' -ForegroundColor Cyan
# Громкие death_cry и событие 102 в анимациях смерти были ошибочной гипотезой (в игре криков не стало) — убраны
$extra = @($ix.Files.Keys | Where-Object { $_ -like '*.mp3' -or $_ -like '*.anim_sound_event' })
if ($extra.Count) { Bad "в паке остались убранные файлы: $($extra.Count) (например $($extra[0]))" } else { Ok 'MP3 криков и событий анимаций в паке нет' }
Write-Host '== 7a. Таблица звуков sounds_packed\sound_events: изменено только нужное ==' -ForegroundColor Cyan
$csvLeft = @($ix.Files.Keys | Where-Object { $_ -like 'sounds\events\*' })
if ($csvLeft.Count) { Bad "в паке csv-таблицы, которые игра не читает: $($csvLeft -join ', ')" }
$sp = Join-Path $Data 'sound.pack'
$origB = Read-PackFile $sp 'sounds_packed\sound_events'
$a = Read-SoundEvents $origB; $b = Read-SoundEvents (Read-PackFile $Pack 'sounds_packed\sound_events')
$expect = (Get-GoreSoundEvents $origB $sp)
if ([Linq.Enumerable]::SequenceEqual([byte[]](Write-SoundEvents $b), [byte[]](Read-PackFile $Pack 'sounds_packed\sound_events'))) { Ok 'файл разбирается и собирается обратно байт-в-байт' } else { Bad 'файл не собирается обратно байт-в-байт' }
if ($a.Events.Count -ne $b.Events.Count -or $a.Categories.Count -ne $b.Categories.Count) { Bad "число событий/категорий изменилось" }
else {
    $same = $true
    for ($i = 0; $i -lt $a.Params.Count; $i++) { if (-not [Linq.Enumerable]::SequenceEqual($a.Params[$i], $b.Params[$i])) { $same = $false } }
    if ($same) { Ok "старые $($a.Params.Count) наборов параметров не тронуты, добавлено $($b.Params.Count - $a.Params.Count)" } else { Bad 'изменены общие наборы параметров (заденет чужие звуки)' }
    $changed = @(); $badF = @(); $wfix = 0; $wadd = 0; $wcopy = 0; $names = Get-PackNames $sp
    for ($i = 0; $i -lt $a.Events.Count; $i++) {
        $x = $a.Events[$i]; $y = $b.Events[$i]
        $extraOk = $y.Waves.Count -gt $x.Waves.Count -and $expect.Events.ContainsKey($i) -and
            @($y.Waves[$x.Waves.Count..($y.Waves.Count - 1)] | Where-Object { -not $names.Contains($_.ToLowerInvariant()) }).Count -eq 0
        if ($extraOk) { $wadd += $y.Waves.Count - $x.Waves.Count }
        if ($expect.Copies.ContainsKey($i)) {
            if (($y.Waves -join '|') -ne ($a.Events[$expect.Copies[$i][1]].Waves -join '|')) { $badF += "событие ${i}: файлы не как у $($expect.Copies[$i][1])" } else { $wcopy++ }
            continue
        }
        if ($x.Category -ne $y.Category -or $x.Name -ne $y.Name -or ($x.Waves.Count -ne $y.Waves.Count -and -not $extraOk)) { $badF += "событие ${i}: категория/число файлов" }
        else { for ($j = 0; $j -lt $x.Waves.Count; $j++) { if ($x.Waves[$j] -ne $y.Waves[$j]) {
            # допустима только починка пути к несуществующему файлу (опечатка actor9 -> actor_9)
            if ($names.Contains($x.Waves[$j].ToLowerInvariant()) -or -not $names.Contains($y.Waves[$j].ToLowerInvariant())) { $badF += "событие ${i}: файл $($y.Waves[$j])" } else { $wfix++ }
        } } }
        if ($x.Param -ne $y.Param) {
            $changed += $i
            $pa = $a.Params[[int]$x.Param]; $pb = $b.Params[[int]$y.Param]
            for ($j = 0; $j -lt $pa.Count; $j++) { if ($pa[$j] -ne $pb[$j] -and @(0, 3, 4, 5, 11, 33) -notcontains $j) { $badF += "событие ${i}: колонка $($j + 2)" } }
        }
    }
    if ($badF.Count) { Bad "лишние изменения: $($badF[0..([math]::Min(4, $badF.Count - 1))] -join '; ')" } else { Ok "менялись только громкость/дальность/затухание/вероятность/лимит (+ исправлено путей: $wfix, добавлено вариантов из файлов игры: $wadd, событий с файлами линейной пехоты: $wcopy)" }
    $missing = @(foreach ($i in $expect.Events.Keys) { $b.Events[$i].Waves | Where-Object { -not $names.Contains($_.ToLowerInvariant()) -and -not $ix.Files.ContainsKey($_) } })
    # недостающие файлы, которые были и в ванильном событии (разработчики не записали фразу) — не наша ошибка
    $vanillaMiss = @{}; foreach ($i in $expect.Events.Keys) { foreach ($w in $a.Events[$i].Waves) { $vanillaMiss[$w] = 1 } }
    $ourMiss = @($missing | Where-Object { -not $vanillaMiss.ContainsKey($_) })
    if ($ourMiss.Count) { Bad "мод ссылается на несуществующие файлы: $($ourMiss -join ', ')" }
    else { Ok "все файлы, которые вносит мод, существуют$(if ($missing.Count) { " (в ванили не хватает $($missing.Count) фраз — по одной из ~128 у отдельных отрядов, не трогаем)" })" }
    if ([Linq.Enumerable]::SequenceEqual([byte[]]$expect.Bytes, [byte[]](Read-PackFile $Pack 'sounds_packed\sound_events'))) { Ok 'совпадает со свежей сборкой из sound.pack байт-в-байт' } else { Bad 'отличается от свежей сборки — пак устарел, пересоберите' }
    if (@(Compare-Object @($changed) @($expect.Events.Keys)).Count) { Bad "изменены события $($changed -join ','), ожидались $(($expect.Events.Keys | Sort-Object) -join ',')" }
    else { Ok "изменено $($changed.Count) событий: $((($changed | ForEach-Object { $expect.Events[$_] }) -join '; '))" }
    $d = $b.Params[[int]$b.Events[($expect.Events.Keys | Where-Object { $expect.Events[$_] -eq 'Unit_Voices_Death_Gen' })].Param]
    Write-Host ("        предсмертный крик: громкость {0}, без затухания до {1} ед., затухание {2}, слышно до {3} ед. (1 ед. ≈ 14 м), вероятность {4}, вариантов {5}" -f $d[0], $d[3], $d[5], $d[4], $d[11], $b.Events[($expect.Events.Keys | Where-Object { $expect.Events[$_] -eq 'Unit_Voices_Death_Gen' })].Waves.Count)
    $db0 = Read-PackFile $sp 'sounds_packed\sound_bank_database'; $db = Read-PackFile $Pack 'sounds_packed\sound_bank_database'
    $diff = @(for ($k = 0; $k -lt $db0.Length; $k++) { if ($db0[$k] -ne $db[$k]) { $k } })
    if ($db.Length -ne $db0.Length -or @($diff | Where-Object { $_ -lt $GoreBankTimersOffset -or $_ -ge $GoreBankTimersOffset + 24 }).Count) { Bad 'sound_bank_database изменён не только в таймерах голосов' }
    elseif (-not [Linq.Enumerable]::SequenceEqual([byte[]](Get-GoreBankDatabase $db0), [byte[]]$db)) { Bad 'sound_bank_database отличается от свежей сборки' }
    else { Ok ("sound_bank_database: изменены только таймеры голосов (реплики {0}–{1} с, рукопашная {2}–{3} с)" -f $GoreBankTimers[0], $GoreBankTimers[1], $GoreBankTimers[2], $GoreBankTimers[3]) }
}
Write-Host '== 8. Чужие паки не тронуты ==' -ForegroundColor Cyan
# Точка отсчёта — бэкап шага 1 (сделан до мода); без него — начало сегодняшнего дня
$backup = Get-ChildItem "$env:APPDATA\The Creative Assembly\Napoleon" -Directory -Filter '_backup_*' -ErrorAction SilentlyContinue | Sort-Object CreationTime | Select-Object -First 1
$since = if ($backup) { $backup.CreationTime } else { (Get-Date).Date }
$recent = @(Get-ChildItem -LiteralPath $Data -Filter *.pack | Where-Object { $_.Name -ne 'zz_NapoleonGoreMod.pack' -and $_.LastWriteTime -gt $since })
if ($recent.Count) { Bad "менялись после $($since.ToString('dd.MM.yyyy HH:mm')): $($recent.Name -join ', ')" } else { Ok "ни один пак игры/DarthMod не менялся после $($since.ToString('dd.MM.yyyy HH:mm'))" }

Write-Host ''
if ($fail) { Write-Host "ИТОГ: $fail ошибок, $warn предупреждений" -ForegroundColor Red; exit 1 }
Write-Host "ИТОГ: всё в порядке ($warn предупреждений)" -ForegroundColor Green
