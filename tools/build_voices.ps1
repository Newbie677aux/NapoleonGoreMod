# Голоса для NapoleonGoreMod:
#  1) все родные предсмертные крики (death_cry_fall_scream_*.mp3 всех наций и актёров) громче —
#     build\voices\<путь>.mp3, кладутся в мод по тем же путям и перекрывают sound.pack;
#  2) набор стонов/вскриков разных актёров — build\voice_pool\*.wav, его вклеивает build_sounds.ps1
#     в часть звуков попадания.
# Исходник: data\sound.pack (сам пак не меняется). Медленно (сотни перекодирований), поэтому кэш:
# уже готовые файлы пропускаются; -Force пересобирает всё.

param(
    [string]$GameDir = 'E:\Steam\steamapps\common\Napoleon Total War',
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\packlib.ps1"
Add-Type -Path "$PSScriptRoot\sfxlib.cs"

$Build = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path + '\build'
$Raw   = "$Build\voices_raw";  $Out = "$Build\voices";  $Pool = "$Build\voice_pool"
New-Item -ItemType Directory -Force $Raw, $Out, $Pool | Out-Null

# Громче без перегруза: пик к 1.0, мягкое сжатие, запас 0.97
function Louder([float[]]$x) { [Sfx]::Normalize([Sfx]::SoftClip([Sfx]::Normalize($x, 1.0), 2.0), 0.97) }

Write-Host '== Чтение криков из sound.pack ==' -ForegroundColor Cyan
$cries = Read-PackFiles (Join-Path $GameDir 'data\sound.pack') 'death_cry_fall_scream[^\\]*\.mp3$|\\actor_1\\individuals_grunt_[123]\.mp3$'
Write-Host "Файлов: $($cries.Count)"

$done = 0
foreach ($path in $cries.Keys | Sort-Object) {
    $flat = $path -replace '\\', '__'
    $mp3Src = "$Raw\$flat"; $wav = $mp3Src -replace '\.mp3$', '.wav'
    if ($Force -or -not (Test-Path -LiteralPath $wav)) {
        [IO.File]::WriteAllBytes($mp3Src, $cries[$path])
        & "$PSScriptRoot\audioconv.ps1" -In $mp3Src -Out $wav | Out-Null
    }
    $loud = Louder ([Sfx]::Load($wav))

    if ($path -match 'death_cry') {
        $mp3Out = "$Out\$flat"
        if ($Force -or -not (Test-Path -LiteralPath $mp3Out)) {
            $tmp = $wav -replace '\.wav$', '.loud.wav'      # свой файл на крик: Windows держит его после перекодирования
            [Sfx]::Save($tmp, $loud)
            & "$PSScriptRoot\audioconv.ps1" -In $tmp -Out $mp3Out | Out-Null
        }
    }
    # Набор для звуков попадания: актёр 1 шести наций, крики и кряхтение
    if ($path -match '^(uk|fr|ge|ru|sp|it)\\actor_1\\') { [Sfx]::Save("$Pool\$($flat -replace '\.mp3$', '.wav')", $loud) }

    $done++
    if ($done % 25 -eq 0) { Write-Host "  $done / $($cries.Count)" }
}
Write-Host "Криков громче: $(@(Get-ChildItem $Out -Filter *.mp3).Count), стонов в наборе: $(@(Get-ChildItem $Pool -Filter *.wav).Count)" -ForegroundColor Green
