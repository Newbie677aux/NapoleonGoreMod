# Набор стонов/вскриков для звуков попадания: голоса самой игры (актёр 1 шести наций — крики
# death_cry_fall_scream и кряхтение individuals_grunt) -> build\voice_pool\*.wav, громче и в формате
# звуков попадания. Их вклеивает build_sounds.ps1.
# Исходник: data\sound.pack (сам пак не меняется). Расшифровка MP3 через Windows Media Foundation
# кэшируется в build\voices_raw; -Force пересобирает.
#
# Раньше здесь же делались громкие версии всех 266 death_cry_fall_scream.mp3, а в анимации смерти
# добавлялось событие 102 как «крик». В игре криков не стало слышно вообще: death_cry, похоже, — крик
# при падении (со стены/корабля), а 102 — не крик. Обе правки убраны.

param(
    [string]$GameDir = 'E:\Steam\steamapps\common\Napoleon Total War',
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\packlib.ps1"
Add-Type -Path "$PSScriptRoot\sfxlib.cs"

$Build = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path + '\build'
$Raw = "$Build\voices_raw"; $Pool = "$Build\voice_pool"
New-Item -ItemType Directory -Force $Raw, $Pool | Out-Null

# Громче без перегруза: пик к 1.0 (усиление не больше x3 — у тихих записей иначе лезет шум),
# мягкое сжатие, запас 0.97
function Louder([float[]]$x) {
    $peak = [math]::Min(1.0, [Sfx]::Peak($x) * 3.0)
    [Sfx]::Normalize([Sfx]::SoftClip([Sfx]::Normalize($x, $peak), 2.0), 0.97 * $peak)
}

$voices = Read-PackFiles (Join-Path $GameDir 'data\sound.pack') '^(uk|fr|ge|ru|sp|it)\\actor_1\\(death_cry_fall_scream_[12]|individuals_grunt_[123])\.mp3$'
Write-Host "Голосов в sound.pack: $($voices.Count)"
foreach ($path in $voices.Keys | Sort-Object) {
    $flat = $path -replace '\\', '__'
    $mp3 = "$Raw\$flat"; $wav = $mp3 -replace '\.mp3$', '.wav'
    if ($Force -or -not (Test-Path -LiteralPath $wav)) {
        [IO.File]::WriteAllBytes($mp3, $voices[$path])
        & "$PSScriptRoot\audioconv.ps1" -In $mp3 -Out $wav | Out-Null
    }
    [Sfx]::Save("$Pool\$($flat -replace '\.mp3$', '.wav')", (Louder ([Sfx]::Load($wav))))
}
Write-Host "Стонов в наборе: $(@(Get-ChildItem $Pool -Filter *.wav).Count)" -ForegroundColor Green
