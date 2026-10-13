# Звуки попаданий для NapoleonGoreMod из CC0-исходников в sounds\src.
# Результат: build\sfx\<путь внутри пака>.wav, mono 44.1 kHz 16-bit, как у Ultimate Sound Mod.
# Пути совпадают с файлами USM, поэтому игра берёт наши звуки вместо них (наш пак грузится позже).
# Вызывается из build_pack.ps1; отдельно: powershell -ExecutionPolicy Bypass -File tools\build_sounds.ps1

$ErrorActionPreference = 'Stop'
Add-Type -Path "$PSScriptRoot\sfxlib.cs"

$Src = Join-Path $PSScriptRoot '..\sounds\src'
$Tmp = Join-Path $PSScriptRoot '..\build\sfx_decoded'
$Out = Join-Path $PSScriptRoot '..\build\sfx'
New-Item -ItemType Directory -Force $Tmp, $Out | Out-Null
$Tmp = (Resolve-Path $Tmp).Path; $Out = (Resolve-Path $Out).Path

# FLAC -> WAV встроенными средствами Windows
foreach ($f in Get-ChildItem $Src -Filter *.flac) {
    $wav = Join-Path $Tmp ($f.BaseName + '.wav')
    if (-not (Test-Path $wav)) { & "$PSScriptRoot\flac2wav.ps1" -In $f.FullName -Out $wav | Out-Null }
}
$meat = @([Sfx]::Load("$Tmp\qubodupImpactMeat01.wav"), [Sfx]::Load("$Tmp\qubodupImpactMeat02.wav"))

# Мокрые шлепки: нарезаем удары из двух длинных записей и сортируем по силе
$splats = New-Object System.Collections.Generic.List[object]
foreach ($n in 'crack11', 'crack12') {
    $x = [Sfx]::Load("$Tmp\$n.wav")
    foreach ($o in [Sfx]::Onsets($x, 0.15, 0.12)) {
        $s = [Sfx]::Slice($x, $o, 0.45, 0.30)
        $splats.Add([pscustomobject]@{ Wave = $s; Rms = [Sfx]::Rms($s) })
    }
}
$splats = @($splats | Sort-Object Rms -Descending)
Write-Host "Шлепков найдено: $($splats.Count)"
if ($splats.Count -lt 24) { throw 'Мало шлепков для 16 вариантов' }

function Save-Sfx([string]$rel, [float[]]$wave) {
    $path = Join-Path $Out ($rel -replace '\\', '__')
    [Sfx]::Save($path, $wave)
    [pscustomobject]@{ Rel = $rel; Path = $path }
}
$result = New-Object System.Collections.Generic.List[object]

# Пуля в тело: короткий удар по мясу (разная высота) + слабый мокрый слой. ~0.35 с.
$bulletSpeed = 1.00, 1.12, 0.92, 1.06, 0.97, 1.18, 0.88, 1.03
for ($i = 0; $i -lt 8; $i++) {
    $hit = [Sfx]::Slice([Sfx]::Speed($meat[$i % 2], $bulletSpeed[$i]), 0, 0.30, 0.15)
    $wet = [Sfx]::Slice($splats[8 + $i].Wave, 0, 0.30, 0.20)          # средние по силе шлепки
    $w = [Sfx]::Normalize([Sfx]::Mix($hit, $wet, 0.01, 0.45), 1.0)
    $w = [Sfx]::Normalize([Sfx]::SoftClip($w, 2.2), 0.95)          # громкость на уровне USM (rms ~0.2)
    $result.Add((Save-Sfx ("sfx\weapons\bullet_impacts\emp_hyb_bullet_hitbody_{0:D2}_v1.00_gme.wav" -f ($i + 1)) $w))
}

# Ядро по людям: низкий глухой удар + два крупных хлюпа. ~0.8 с, пик как у USM (0.8).
$cannonSpeed = 0.70, 0.62, 0.75, 0.66, 0.72, 0.60, 0.68, 0.78
for ($i = 0; $i -lt 8; $i++) {
    $thud = [Sfx]::LowPass([Sfx]::Speed($meat[$i % 2], $cannonSpeed[$i]), 1800)
    $w = [Sfx]::Mix($thud, [Sfx]::Speed($splats[$i].Wave, 0.85), 0.02, 0.9)       # самые сильные шлепки
    $w = [Sfx]::Mix($w, $splats[16 + $i].Wave, 0.12 + 0.02 * ($i % 3), 0.6)
    $w = [Sfx]::Normalize([Sfx]::Slice($w, 0, 0.85, 0.35), 0.80)
    $result.Add((Save-Sfx ("sfx\weapons\cannonballhitflesh\emp_hyb_cannonball_hitflesh_{0:D2}_v1.00_gme.wav" -f ($i + 1)) $w))
}

Write-Host "Звуков собрано: $($result.Count) -> $Out" -ForegroundColor Green
$result
