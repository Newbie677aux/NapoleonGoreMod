# Звуки попаданий для NapoleonGoreMod из CC0-исходников в sounds\src.
# Результат: build\sfx\<путь внутри пака>.wav, mono 44.1 kHz 16-bit, как у Ultimate Sound Mod.
# Пути совпадают с файлами USM, поэтому игра берёт наши звуки вместо них (наш пак грузится позже).
# Вызывается из build_pack.ps1; отдельно: powershell -ExecutionPolicy Bypass -File tools\build_sounds.ps1

param(
    [int]$VoiceEvery = 2   # стон в каждом N-м варианте: 1 = во всех (проверочная сборка), 2 = в половине, 0 = без стонов
)

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
    if (-not (Test-Path $wav)) { & "$PSScriptRoot\audioconv.ps1" -In $f.FullName -Out $wav | Out-Null }
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

# Стоны/вскрики из build\voice_pool (готовит build_voices.ps1). Ставятся почти вплотную к удару и громко:
# игра, похоже, обрезает и глушит звуки попаданий в залпе, поздний тихий стон до уха не доходил.
$PoolDir = Join-Path $PSScriptRoot '..\build\voice_pool'
function Get-Voices([string]$like) {
    # List, а не конвейер: PowerShell разворачивает float[] из конвейера в одну ленту сэмплов
    $list = New-Object System.Collections.Generic.List[float[]]
    if (-not (Test-Path $PoolDir)) { return ,$list }
    foreach ($f in Get-ChildItem $PoolDir -Filter $like | Sort-Object Name) {
        $x = [Sfx]::Load($f.FullName); $on = [Sfx]::Onsets($x, 0.10, 0.2)
        $list.Add([Sfx]::Slice($x, $(if ($on.Count) { $on[0] } else { 0 }), 0.8, 0.30))
    }
    ,$list
}
$grunts = Get-Voices '*individuals_grunt*.wav'
$screams = Get-Voices '*death_cry*.wav'
Write-Host "Голосов: кряхтение $($grunts.Count), крики $($screams.Count); стон в каждом $VoiceEvery-м варианте"
# Голос для варианта i оружия с номером kind (разные голоса у разных видов оружия), или $null
function Get-VoiceFor([int]$i, [int]$kind, $pool) {
    if ($VoiceEvery -le 0 -or $i % $VoiceEvery -ne 0 -or -not $pool.Count) { return $null }
    ,$pool[($i * 5 + $kind * 7) % $pool.Count]
}
function Add-Voice([float[]]$w, $voice, [double]$offset) {
    if ($null -eq $voice) { return ,$w }
    $w = [Sfx]::Mix($w, $voice, $offset, 0.95)
    if ([Sfx]::Peak($w) -gt 0.98) { $w = [Sfx]::Normalize($w, 0.98) }
    ,$w
}

# Пуля в тело: короткий удар по мясу (разная высота) + громкий мокрый слой. ~0.35 с.
$bulletSpeed = 1.00, 1.12, 0.92, 1.06, 0.97, 1.18, 0.88, 1.03
for ($i = 0; $i -lt 8; $i++) {
    $hit = [Sfx]::Slice([Sfx]::Speed($meat[$i % 2], $bulletSpeed[$i]), 0, 0.30, 0.15)
    $wet = [Sfx]::Slice($splats[8 + $i].Wave, 0, 0.32, 0.20)          # средние по силе шлепки
    $w = [Sfx]::Normalize([Sfx]::Mix($hit, $wet, 0.005, 0.9), 1.0)    # мокрый слой громко: середину ухо слышит лучше баса
    $w = [Sfx]::Normalize([Sfx]::SoftClip($w, 4.0), 0.98)          # плотно: в бою тонет в залпах, поэтому громче USM
    $w = Add-Voice $w (Get-VoiceFor $i 0 $grunts) 0.03
    $result.Add((Save-Sfx ("sfx\weapons\bullet_impacts\emp_hyb_bullet_hitbody_{0:D2}_v1.00_gme.wav" -f ($i + 1)) $w))
}

# Ядро по людям: низкий глухой удар + два крупных хлюпа. ~0.8 с, сжато для громкости.
$cannonSpeed = 0.70, 0.62, 0.75, 0.66, 0.72, 0.60, 0.68, 0.78
for ($i = 0; $i -lt 8; $i++) {
    $thud = [Sfx]::LowPass([Sfx]::Speed($meat[$i % 2], $cannonSpeed[$i]), 1800)
    $w = [Sfx]::Mix($thud, [Sfx]::Speed($splats[$i].Wave, 0.85), 0.02, 0.9)       # самые сильные шлепки
    $w = [Sfx]::Mix($w, $splats[16 + $i].Wave, 0.12 + 0.02 * ($i % 3), 0.6)
    $w = [Sfx]::Normalize([Sfx]::Slice($w, 0, 0.85, 0.35), 1.0)
    $w = [Sfx]::Normalize([Sfx]::SoftClip($w, 3.0), 0.98)
    $w = Add-Voice $w (Get-VoiceFor $i 1 $screams) 0.04
    $result.Add((Save-Sfx ("sfx\weapons\cannonballhitflesh\emp_hyb_cannonball_hitflesh_{0:D2}_v1.00_gme.wav" -f ($i + 1)) $w))
}

# Сабля по телу: свист клинка -> резкий (ускоренный) удар по мясу + мокрый шлепок. ~0.5 с.
$sabreSpeed = 1.25, 1.15, 1.35, 1.20, 1.30, 1.10, 1.40, 1.22
for ($i = 0; $i -lt 8; $i++) {
    $swishLen = 0.16 + 0.02 * ($i % 4)
    $swish = [Sfx]::Swish($swishLen, 700 + 60 * $i, 3200 + 150 * $i, 100 + $i)
    $hit = [Sfx]::Slice([Sfx]::Speed($meat[$i % 2], $sabreSpeed[$i]), 0, 0.25, 0.12)
    $wet = [Sfx]::Slice($splats[$i + 4].Wave, 0, 0.28, 0.18)
    $w = [Sfx]::Mix([Sfx]::Normalize($swish, 0.45), $hit, $swishLen * 0.85, 1.0)
    $w = [Sfx]::Mix($w, $wet, $swishLen * 0.85 + 0.01, 0.8)
    $w = [Sfx]::Normalize([Sfx]::SoftClip([Sfx]::Normalize($w, 1.0), 3.0), 0.98)
    $w = Add-Voice $w (Get-VoiceFor $i 2 $grunts) ($swishLen * 0.85 + 0.03)
    $result.Add((Save-Sfx ("sfx\weapons\sabre\emp_lib_sabre_slashflesh_{0:D2}_v1.00_gme.wav" -f ($i + 1)) $w))
}

# Штык в тело: короткий глухой выпад -> низкий удар + тягучий хлюп (замедленный шлепок). ~0.55 с.
$stabSpeed = 0.90, 0.85, 0.95, 0.88, 0.92, 0.82, 0.97, 0.86
for ($i = 0; $i -lt 8; $i++) {
    $thrust = [Sfx]::Normalize([Sfx]::Swish(0.07, 300, 1100, 200 + $i), 0.35)
    $hit = [Sfx]::LowPass([Sfx]::Slice([Sfx]::Speed($meat[($i + 1) % 2], $stabSpeed[$i]), 0, 0.30, 0.15), 3000)
    $squelch = [Sfx]::Slice([Sfx]::Speed($splats[$i + 12].Wave, 0.72 + 0.03 * ($i % 3)), 0, 0.45, 0.25)
    $w = [Sfx]::Mix($thrust, $hit, 0.06, 1.0)
    $w = [Sfx]::Mix($w, $squelch, 0.075, 0.9)
    $w = [Sfx]::Normalize([Sfx]::SoftClip([Sfx]::Normalize($w, 1.0), 3.0), 0.98)
    $w = Add-Voice $w (Get-VoiceFor $i 3 $screams) 0.08
    $result.Add((Save-Sfx ("sfx\weapons\bayonet\emp_hyb_bayonet_stabflesh_{0:D2}_v1.00_gme.wav" -f ($i + 1)) $w))
}

Write-Host "Звуков собрано: $($result.Count) -> $Out" -ForegroundColor Green
$result
