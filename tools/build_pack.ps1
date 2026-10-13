# Сборка NapoleonGoreMod: умеренная тёмно-красная кровь поверх эффектов DarthMod.
# Берёт effects\landbattle.xml и форму капли из DMN_Darth_Effects_Napoleon.pack (сам пак не меняет)
# и собирает отдельный movie-пак zz_NapoleonGoreMod.pack. Префикс zz_ нужен, чтобы пак грузился
# после DMN_* и перекрывал их (проверено в игре тестом с синей/зелёной кровью).
# Запуск:   powershell -ExecutionPolicy Bypass -File tools\build_pack.ps1
# Удаление: powershell -ExecutionPolicy Bypass -File tools\build_pack.ps1 -Uninstall

param(
    [string]$GameDir = 'E:\Steam\steamapps\common\Napoleon Total War',
    [switch]$NoInstall,
    [switch]$NoSounds,     # собрать только кровь, без своих звуков попаданий и криков
    [switch]$NoVoices,     # без криков: родные крики не громче, в попаданиях нет стонов
    [switch]$Uninstall
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\packlib.ps1"

$Data     = Join-Path $GameDir 'data'
$Source   = Join-Path $Data 'DMN_Darth_Effects_Napoleon.pack'
$OutDir   = Join-Path $PSScriptRoot '..\build'
$PackName = 'zz_NapoleonGoreMod.pack'
$TestPacks = @('zz_gore_test.pack', '!gore_test_blue.pack', 'zz_gore_test_green.pack')

function Remove-FromData([string[]]$names) {
    foreach ($n in $names) {
        $f = Join-Path $Data $n
        if (Test-Path -LiteralPath $f) { Remove-Item -LiteralPath $f; Write-Host "Удалён: $f" }
    }
}

if ($Uninstall) { Remove-FromData (@($PackName) + $TestPacks); return }

New-Item -ItemType Directory -Force $OutDir | Out-Null
Write-Host '== Чтение landbattle.xml и текстуры крови из DarthMod ==' -ForegroundColor Cyan
$xml = $Latin1.GetString((Read-PackFile $Source 'effects\landbattle.xml'))
$tex = Read-PackFile $Source 'effects\textures\emp_humanhit_diffuse2.tga'

# Своя текстура: та же форма брызг, цвет тёмной крови. Цвет задаёт текстура, множитель белый.
$TexPath = 'effects\textures\gore_blood_diffuse.tga'
$texBytes = New-TintedTga $tex 150 10 10
$look = @{
    start_colour_range_r = 'variance(255,0)'; start_colour_range_g = 'variance(255,0)'; start_colour_range_b = 'variance(255,0)'
    end_colour_range_r   = 'variance(255,0)'; end_colour_range_g   = 'variance(255,0)'; end_colour_range_b   = 'variance(255,0)'
    colour_range_a       = 'variance(255,0)'
    lighting             = 'variance(0.000000,0.000000)'
    texture_1            = $TexPath
}
foreach ($e in 'small_bloodspray1', 'small_bloodspray2', 'small_bloodspray3', 'blood_mist') {
    $xml = Edit-Effect $xml $e $look
}

# Бюджет под слабую видеокарту: капли живут ~1.5-2 с, жёсткие лимиты на число эффектов и квадов.
# Пули: струйка + веер брызг (по 2 капли на точку выпуска) + красное облачко, видное издалека.
$xml = Edit-Effect $xml 'small_bloodspray1' @{
    num_particles_per_point = '2'; emission_time_range_seconds = 'variance(0.060000,0.000000)'
    initial_scale_range_metres = 'vector(variance(0.550000,0.250000),variance(0.040000,0.100000))'
    life_range = 'variance(1.500000,0.300000)'; max_effects = '200'; max_num_quads = '400'
}
$xml = Edit-Effect $xml 'small_bloodspray3' @{
    num_particles_per_point = '2'
    initial_scale_range_metres = 'vector(variance(0.400000,0.250000),variance(0.030000,0.080000))'
    life_range = 'variance(1.500000,0.300000)'; max_effects = '150'; max_num_quads = '500'
}
$xml = Add-GroupEntry $xml 'Musket_impact_human' 'small_bloodspray3'

# Ядра: крупный выброс + облачко брызг. У DarthMod здесь было до 500 эффектов, режем.
$xml = Edit-Effect $xml 'small_bloodspray2' @{
    initial_scale_range_metres = 'vector(variance(1.600000,0.400000),variance(0.450000,0.100000))'
    life_range = 'variance(1.800000,0.400000)'; max_effects = '60'; max_num_quads = '500'
}
$xml = Edit-Effect $xml 'blood_mist' @{
    life_range = 'variance(1.000000,0.200000)'; max_effects = '120'; max_num_quads = '600'
}
$xml = Add-GroupEntry $xml 'blood_spray' 'blood_mist'
$xml = Add-GroupEntry $xml 'Musket_impact_human' 'blood_mist'

$doc = New-Object Xml.XmlDocument; $doc.LoadXml($xml)   # проверка, что XML не сломан

$files = @{
    'effects\landbattle.xml' = $Latin1.GetBytes($xml)
    $TexPath                 = $texBytes
}
if (-not $NoSounds) {
    $pool = Join-Path $OutDir 'voice_pool'
    if ($NoVoices) {
        if (Test-Path $pool) { Remove-Item -Recurse $pool }   # build_sounds без набора стонов = чистые удары
    } else {
        Write-Host '== Крики (долго при первой сборке) ==' -ForegroundColor Cyan
        & powershell -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot\build_voices.ps1" -GameDir $GameDir | Out-Null
        if ($LASTEXITCODE) { throw 'build_voices.ps1 завершился с ошибкой' }
        foreach ($f in Get-ChildItem (Join-Path $OutDir 'voices') -Filter *.mp3) {
            $files[($f.Name -replace '__', '\')] = [IO.File]::ReadAllBytes($f.FullName)
        }
        Write-Host "Криков в паке: $(@($files.Keys | Where-Object { $_ -like '*death_cry*' }).Count)"

        # Крик в каждой смерти. anim_sound_event: u32 версия=1, u32 N, затем N x (float время, u32 код).
        # Коды 102-105 встречаются только в анимациях смерти (~25% из них) — считаем их вызовом крика.
        # Где крика нет, добавляем 102 в начало падения.
        $events = Read-PackFiles (Join-Path $Data 'sound.pack') '^animations\\men\\.*(death|die)[^\\]*\.anim_sound_event$'
        $added = 0
        foreach ($path in $events.Keys) {
            $b = $events[$path]
            if ($b.Length -lt 8 -or [BitConverter]::ToUInt32($b, 0) -ne 1) { continue }
            $n = [BitConverter]::ToUInt32($b, 4)
            if ($b.Length -ne 8 + 8 * $n) { continue }
            $list = for ($i = 0; $i -lt $n; $i++) { [pscustomobject]@{ T = [BitConverter]::ToSingle($b, 8 + 8 * $i); Id = [BitConverter]::ToUInt32($b, 12 + 8 * $i) } }
            if (@($list | Where-Object { $_.Id -ge 102 -and $_.Id -le 105 }).Count) { continue }
            $list = @(@($list) + [pscustomobject]@{ T = [single]0.12; Id = [uint32]102 } | Sort-Object T)
            $ms = New-Object IO.MemoryStream; $bw = New-Object IO.BinaryWriter($ms)
            $bw.Write([uint32]1); $bw.Write([uint32]$list.Count)
            foreach ($e in $list) { $bw.Write([single]$e.T); $bw.Write([uint32]$e.Id) }
            $files[$path] = $ms.ToArray(); $added++
        }
        Write-Host "Смертей с добавленным криком: $added из $($events.Count)"
    }
    Write-Host '== Звуки попаданий ==' -ForegroundColor Cyan
    & powershell -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot\build_sounds.ps1" | Out-Null
    if ($LASTEXITCODE) { throw 'build_sounds.ps1 завершился с ошибкой' }
    foreach ($f in Get-ChildItem (Join-Path $OutDir 'sfx') -Filter *.wav) {
        $files[($f.Name -replace '__', '\')] = [IO.File]::ReadAllBytes($f.FullName)
    }
    Write-Host "Звуков в паке: $(@($files.Keys | Where-Object { $_ -like 'sfx\*' }).Count)"
}

$packPath = Join-Path $OutDir $PackName
Write-Pack $packPath 4 $files                             # 4 = movie, грузится без user.script
Write-Host "Собран: $packPath" -ForegroundColor Green

if (-not $NoInstall) {
    Remove-FromData $TestPacks
    Copy-Item -LiteralPath $packPath -Destination (Join-Path $Data $PackName) -Force
    Write-Host "Установлен: $(Join-Path $Data $PackName)" -ForegroundColor Green
}
