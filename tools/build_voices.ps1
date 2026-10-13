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

# Кодировщик Windows пишет в начало ID3v2-тег и нули, в конце бывает ID3v1. Оригинальные крики игры —
# голые MPEG-кадры, поэтому срезаем всё до первого кадра (проверяем, что за ним идёт второй) и хвостовой тег.
function Get-FrameLength([byte[]]$b, [int]$i) {
    if ($i + 4 -gt $b.Length -or $b[$i] -ne 0xFF -or ($b[$i + 1] -band 0xFE) -ne 0xFA) { return 0 }   # MPEG-1 Layer III
    $rates = 0, 32, 40, 48, 56, 64, 80, 96, 112, 128, 160, 192, 224, 256, 320, 0
    $br = $rates[$b[$i + 2] -shr 4]; $srIdx = ($b[$i + 2] -shr 2) -band 3
    if (-not $br -or $srIdx -eq 3) { return 0 }
    $sr = (44100, 48000, 32000)[$srIdx]
    [int][math]::Floor(144000 * $br / $sr) + (($b[$i + 2] -shr 1) -band 1)
}
function Strip-Mp3([byte[]]$b) {
    $start = -1
    for ($i = 0; $i -lt $b.Length - 4; $i++) {
        $len = Get-FrameLength $b $i
        if ($len -and ($i + $len -ge $b.Length -or (Get-FrameLength $b ($i + $len)))) { $start = $i; break }
    }
    if ($start -lt 0) { throw 'В MP3 не найдено ни одного кадра' }
    $end = $b.Length
    if ($end -ge 128 -and [Text.Encoding]::ASCII.GetString($b, $end - 128, 3) -eq 'TAG') { $end -= 128 }
    $out = New-Object byte[] ($end - $start); [Array]::Copy($b, $start, $out, 0, $out.Length); $out
}

# Громче без перегруза: пик к 1.0 (но усиление не больше x3 — у тихих записей иначе лезет шум),
# мягкое сжатие, запас 0.97. Меняешь формулу — меняй $Recipe, иначе MP3 возьмутся из кэша.
$Recipe = 'louder-v2-cap3'
function Louder([float[]]$x) {
    $peak = [math]::Min(1.0, [Sfx]::Peak($x) * 3.0)
    [Sfx]::Normalize([Sfx]::SoftClip([Sfx]::Normalize($x, $peak), 2.0), 0.97 * $peak)
}
$stamp = "$Out\.recipe"
if (-not (Test-Path $stamp) -or (Get-Content $stamp -Raw).Trim() -ne $Recipe) { $Force = $true; Write-Host "Рецепт громкости изменился — пересобираю все крики" }

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
        $bytes = [IO.File]::ReadAllBytes($mp3Out); $clean = Strip-Mp3 $bytes
        if ($clean.Length -ne $bytes.Length) { [IO.File]::WriteAllBytes($mp3Out, $clean) }
    }
    # Набор для звуков попадания: актёр 1 шести наций, крики и кряхтение
    if ($path -match '^(uk|fr|ge|ru|sp|it)\\actor_1\\') { [Sfx]::Save("$Pool\$($flat -replace '\.mp3$', '.wav')", $loud) }

    $done++
    if ($done % 25 -eq 0) { Write-Host "  $done / $($cries.Count)" }
}
Set-Content -LiteralPath $stamp -Value $Recipe
Write-Host "Криков громче: $(@(Get-ChildItem $Out -Filter *.mp3).Count), стонов в наборе: $(@(Get-ChildItem $Pool -Filter *.wav).Count)" -ForegroundColor Green
