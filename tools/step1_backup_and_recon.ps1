# Шаг 1 (бэкап) + Шаг 2 (разведка) для мода крови в Napoleon: Total War.
# Ничего в игре и DarthMod НЕ меняет: только копирует сейвы и читает файлы.
# Запуск:  powershell -ExecutionPolicy Bypass -File step1_backup_and_recon.ps1

param(
    [string]$GameDir   = 'E:\Steam\steamapps\common\Napoleon Total War',
    [string]$UserDir   = "$env:APPDATA\The Creative Assembly\Napoleon",
    [string]$BackupDir = "$env:APPDATA\The Creative Assembly\Napoleon\_backup_2026-10-13"
)

$ErrorActionPreference = 'Stop'
$ReconDir = Join-Path $BackupDir 'recon'

# ---------- Шаг 1: бэкап ----------
Write-Host '== Шаг 1: бэкап ==' -ForegroundColor Cyan
if (-not (Test-Path $UserDir)) { throw "Не найдена папка $UserDir" }
if (Test-Path (Join-Path $BackupDir 'save_games')) {
    Write-Host "Бэкап уже есть в $BackupDir - пропускаю копирование (ничего не перезаписываю)." -ForegroundColor Yellow
} else {
    New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null
    $saves = Join-Path $UserDir 'save_games'
    if (Test-Path $saves) {
        Copy-Item -Path $saves -Destination $BackupDir -Recurse
    } else { Write-Host "Нет папки save_games в $UserDir" -ForegroundColor Yellow }
    $us = Join-Path $UserDir 'scripts\user.script.txt'
    if (Test-Path $us) {
        New-Item -ItemType Directory -Force -Path (Join-Path $BackupDir 'scripts') | Out-Null
        Copy-Item -Path $us -Destination (Join-Path $BackupDir 'scripts\user.script.txt')
    } else { Write-Host "Нет файла $us" -ForegroundColor Yellow }
}
# Проверка: сравниваем хэши оригинала и копии
$bad = 0; $ok = 0
foreach ($pair in @(@('save_games','save_games'), @('scripts\user.script.txt','scripts\user.script.txt'))) {
    $src = Join-Path $UserDir $pair[0]; $dst = Join-Path $BackupDir $pair[1]
    if (-not (Test-Path $src)) { continue }
    $srcFiles = if ((Get-Item $src).PSIsContainer) { Get-ChildItem $src -Recurse -File } else { @(Get-Item $src) }
    foreach ($f in $srcFiles) {
        $rel = $f.FullName.Substring($src.Length).TrimStart('\')
        $copy = if ($rel) { Join-Path $dst $rel } else { $dst }
        if ((Test-Path $copy) -and ((Get-FileHash $f.FullName).Hash -eq (Get-FileHash $copy).Hash)) { $ok++ } else { $bad++; Write-Host "НЕ совпадает/нет копии: $rel" -ForegroundColor Red }
    }
}
Write-Host "Проверено файлов: $ok OK, $bad проблем." -ForegroundColor ($(if ($bad) {'Red'} else {'Green'}))

# ---------- Шаг 2: разведка (только чтение) ----------
Write-Host '== Шаг 2: разведка ==' -ForegroundColor Cyan
New-Item -ItemType Directory -Force -Path $ReconDir | Out-Null
$summary = Join-Path $ReconDir 'summary.txt'
$out = New-Object System.Collections.Generic.List[string]
$out.Add("Recon $(Get-Date -Format s)"); $out.Add("GameDir: $GameDir"); $out.Add('')

# Верхний уровень папки игры (лаунчер DarthMod, exe и т.п.)
$out.Add('### Папка игры (верхний уровень)')
Get-ChildItem $GameDir | Sort-Object Name | ForEach-Object {
    $out.Add(('{0,-45} {1,12} {2:yyyy-MM-dd HH:mm}' -f $_.Name, $(if ($_.PSIsContainer) {'<DIR>'} else {$_.Length}), $_.LastWriteTime))
}
$out.Add('')

# Всё, что похоже на DarthMod (папки/файлы), в игре и в AppData
$out.Add('### Файлы/папки с "darth" в имени')
foreach ($root in @($GameDir, $UserDir)) {
    Get-ChildItem $root -Recurse -ErrorAction SilentlyContinue | Where-Object { $_.Name -match 'darth' -and $_.FullName -notlike "$BackupDir*" } |
        Select-Object -First 300 | ForEach-Object { $out.Add($_.FullName) }
}
$out.Add('')

# user.script.txt и прочие скрипты
$out.Add('### scripts\ в AppData')
$scriptsDir = Join-Path $UserDir 'scripts'
if (Test-Path $scriptsDir) {
    Get-ChildItem $scriptsDir -File | ForEach-Object { $out.Add(('{0,-40} {1,10} {2:yyyy-MM-dd HH:mm}' -f $_.Name, $_.Length, $_.LastWriteTime)) }
    $us = Join-Path $scriptsDir 'user.script.txt'
    if (Test-Path $us) { $out.Add(''); $out.Add('--- user.script.txt ---'); Get-Content $us | ForEach-Object { $out.Add($_) }; $out.Add('--- end ---') }
}
$out.Add('')

# Чтение индекса .pack (PFH0/PFH2/PFH3) без распаковки
function Read-PackIndex([string]$path) {
    $fs = [System.IO.File]::OpenRead($path)
    try {
        $br = New-Object System.IO.BinaryReader($fs)
        $magic = [System.Text.Encoding]::ASCII.GetString($br.ReadBytes(4))
        $type = $br.ReadUInt32(); $nDeps = $br.ReadUInt32(); $depsSize = $br.ReadUInt32()
        $nFiles = $br.ReadUInt32(); $idxSize = $br.ReadUInt32()
        if ($magic -eq 'PFH2' -or $magic -eq 'PFH3') { [void]$br.ReadBytes(8) }   # timestamp в заголовке
        elseif ($magic -ne 'PFH0') { return [pscustomobject]@{Magic=$magic; Type=$type; Deps=@(); Files=@()} }
        $deps = @(); if ($depsSize) { $deps = [System.Text.Encoding]::ASCII.GetString($br.ReadBytes($depsSize)).Split([char]0) | Where-Object { $_ } }
        $idx = $br.ReadBytes($idxSize)
        $files = New-Object System.Collections.Generic.List[object]
        $p = 0
        for ($i = 0; $i -lt $nFiles -and $p -lt $idx.Length; $i++) {
            $size = [BitConverter]::ToUInt32($idx, $p); $p += 4
            if ($magic -eq 'PFH2' -or $magic -eq 'PFH3') { $p += 4 }          # timestamp файла
            $start = $p; while ($p -lt $idx.Length -and $idx[$p] -ne 0) { $p++ }
            $files.Add([pscustomobject]@{Name=[System.Text.Encoding]::ASCII.GetString($idx, $start, $p - $start); Size=$size}); $p++
        }
        [pscustomobject]@{Magic=$magic; Type=$type; Deps=$deps; Files=$files}
    } finally { $fs.Close() }
}
function Get-Folder([string]$name) { $s = $name -split '\\'; if ($s.Count -gt 2) { $s[0] + '\' + $s[1] } else { $s[0] } }
$typeNames = @{0='boot';1='release';2='patch';3='mod';4='movie'}
$interesting = 'blood|gore|decal|particle|effect|vfx|death|die|dying|hit|impact|wound|splat|gib|head|variantmesh|variant_mesh|battle_entit|projectile|cannon|musket|bayonet|melee|sound|\.(sfx|wav|ogg|mp3)$|unit_variants|kv_rules|battle_settings'

$out.Add('### .pack в data')
$packs = Get-ChildItem (Join-Path $GameDir 'data') -Filter *.pack | Sort-Object Name
foreach ($pk in $packs) {
    try {
        $info = Read-PackIndex $pk.FullName
        $t = $info.Type -band 0xFF; $tn = if ($typeNames.ContainsKey([int]$t)) { $typeNames[[int]$t] } else { "?$t" }
        $out.Add(('{0,-40} {1,12:N0} B  {2:yyyy-MM-dd}  {3} type={4}(0x{5:X}) files={6} deps=[{7}]' -f $pk.Name, $pk.Length, $pk.LastWriteTime, $info.Magic, $tn, $info.Type, $info.Files.Count, ($info.Deps -join ',')))
        # Полный список файлов пака + сводка по папкам
        $info.Files | ForEach-Object { "{0}`t{1}" -f $_.Size, $_.Name } | Set-Content -Encoding UTF8 (Join-Path $ReconDir ("pack_" + $pk.BaseName + '.txt'))
        $info.Files | Group-Object { Get-Folder $_.Name } |
            Sort-Object Count -Descending | Select-Object -First 15 | ForEach-Object { $out.Add(('      {0,7}  {1}' -f $_.Count, $_.Name)) }
        $hits = @($info.Files | Where-Object { $_.Name -match $interesting })
        if ($hits.Count) {
            $hits | ForEach-Object { "{0}`t{1}" -f $_.Size, $_.Name } | Set-Content -Encoding UTF8 (Join-Path $ReconDir ("interesting_" + $pk.BaseName + '.txt'))
            $out.Add("      интересных файлов: $($hits.Count) -> interesting_$($pk.BaseName).txt")
        }
    } catch { $out.Add("$($pk.Name): ошибка чтения: $($_.Exception.Message)") }
}
$out.Add('')

# Какие пути переопределяются несколькими паками (так видно, что меняет DarthMod поверх ванили)
$out.Add('### Файлы, которые есть в нескольких паках (переопределения)')
$owner = @{}
foreach ($pk in $packs) {
    $lst = Join-Path $ReconDir ("pack_" + $pk.BaseName + '.txt')
    if (-not (Test-Path $lst)) { continue }
    foreach ($line in [System.IO.File]::ReadLines($lst)) {
        $n = ($line -split "`t", 2)[1]; if (-not $n) { continue }
        if ($owner.ContainsKey($n)) { $owner[$n] += ",$($pk.Name)" } else { $owner[$n] = $pk.Name }
    }
}
$multi = $owner.GetEnumerator() | Where-Object { $_.Value -like '*,*' } | Sort-Object Name
$multi | ForEach-Object { "$($_.Name)`t$($_.Value)" } | Set-Content -Encoding UTF8 (Join-Path $ReconDir 'overrides.txt')
$out.Add("Всего переопределённых путей: $(@($multi).Count) -> overrides.txt")
$multi | Group-Object { Get-Folder $_.Name } | Sort-Object Count -Descending | Select-Object -First 30 |
    ForEach-Object { $out.Add(('      {0,7}  {1}' -f $_.Count, $_.Name)) }
$out.Add('')

# Железо (для подбора бюджета эффектов)
$out.Add('### Система')
try { Get-CimInstance Win32_VideoController | ForEach-Object { $out.Add("GPU: $($_.Name) driver $($_.DriverVersion)") } } catch {}
try { $out.Add("RAM: {0:N1} GB" -f ((Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory / 1GB)) } catch {}

$out | Set-Content -Encoding UTF8 $summary
$zip = Join-Path $BackupDir 'recon.zip'
if (Test-Path $zip) { Remove-Item $zip }
Compress-Archive -Path (Join-Path $ReconDir '*') -DestinationPath $zip
Write-Host "Готово. Сводка: $summary" -ForegroundColor Green
Write-Host "Архив для отправки: $zip" -ForegroundColor Green
