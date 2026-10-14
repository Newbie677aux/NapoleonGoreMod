# Сборка NapoleonGoreMod: умеренная тёмно-красная кровь поверх эффектов DarthMod.
# Берёт effects\landbattle.xml и форму капли из DMN_Darth_Effects_Napoleon.pack (сам пак не меняет)
# и собирает отдельный movie-пак zz_NapoleonGoreMod.pack. Префикс zz_ нужен, чтобы пак грузился
# после DMN_* и перекрывал их (проверено в игре тестом с синей/зелёной кровью).
# Запуск:   powershell -ExecutionPolicy Bypass -File tools\build_pack.ps1
# Удаление: powershell -ExecutionPolicy Bypass -File tools\build_pack.ps1 -Uninstall

param(
    [string]$GameDir = 'E:\Steam\steamapps\common\Napoleon Total War',
    [switch]$NoInstall,
    [switch]$NoSounds,     # собрать только кровь, без своих звуков попаданий
    [switch]$NoVoices,     # без стонов в звуках попадания
    [int]$VoiceEvery = 0,  # стон в каждом N-м варианте звука попадания (0 = нет: крики теперь родные, см. ниже)
    [switch]$NoSmoke,      # не трогать пороховой дым DarthMod
    [switch]$NoPerf,       # без оптимизаций FPS (дальность/потолки дыма, дрожание воздуха)
    [switch]$KeepDistortion, # оптимизировать, но оставить дрожание воздуха
    [switch]$Uninstall
)

$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\packlib.ps1"
. "$PSScriptRoot\soundevents.ps1"

$Data     = Join-Path $GameDir 'data'
$Source   = Join-Path $Data 'DMN_Darth_Effects_Napoleon.pack'
$OutDir   = Join-Path $PSScriptRoot '..\build'
$PackName = 'zz_NapoleonGoreMod.pack'
$TestPacks = @('zz_gore_test.pack', '!gore_test_blue.pack', 'zz_gore_test_green.pack', 'zz_gore_test_ui.pack', 'zz_gore_test_ui2.pack')

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

if (-not $NoSmoke) {
    # Пороховой дым DarthMod: живёт долго (мушкет ~33 с, пушки 80-120 с), но тает уже с 40% жизни
    # (fadeout = доля жизни на затухание в конце, как fadein — в начале) и рисуется вплотную к камере
    # (min_lod 0.5-1 м; в ванили 10-90 м — так CA не давали облаку заливать весь экран слоями).
    # 1) min_lod — ближняя граница: облако ближе к камере не рисуется, FPS не падает при нырке в дым.
    #    У мушкетного дыма у линии 12 м, у больших облаков 25 м.
    # 2) Тает только последние 35% жизни — дым дольше держится плотным, после залпов висит пелена.
    # 3) Основной мушкетный клуб: 2 частицы вместо 3, чтобы плотный дым не стоил дороже прежнего.
    foreach ($e in 'musket_1', 'musket_3') {
        $xml = Edit-Effect $xml $e @{ min_lod_range = 'variance(12.000000,0.000000)'; fadeout_range_life_unary = 'variance(0.350000,0.000000)' }
    }
    $xml = Edit-Effect $xml 'musket_1' @{ num_particles_per_point = '2' }
    foreach ($e in 'musket_2', 'landgun_med_1') {
        $xml = Edit-Effect $xml $e @{ min_lod_range = 'variance(25.000000,0.000000)'; fadeout_range_life_unary = 'variance(0.350000,0.000000)' }
    }
    foreach ($e in 'landgun_med_3', 'landgun_med_2_whispy') {
        $xml = Edit-Effect $xml $e @{ min_lod_range = 'variance(25.000000,0.000000)' }
    }
    $xml = Edit-Effect $xml 'Uber_smoke_white' @{ min_lod_range = 'variance(25.000000,0.000000)'; life_range = 'variance(60.000000,5.000000)' }
}

if (-not $NoPerf) {
    # FPS: у DarthMod дым рисуется до 10 км (ваниль 1 км) и держит в 10-20 раз больше частиц, чем ваниль.
    # 1) Дальность 2 км: дальше дым — пара пикселей у горизонта, а считается целиком.
    # 2) Потолок частиц вдвое ниже DarthMod (всё ещё в 5-10 раз выше ванили) — срезает только самые
    #    тяжёлые моменты огромных сражений.
    $far = 'Uber_smoke_white', 'flash_dir_tiny', 'landgun_fastsmoke', 'landgun_med_1', 'landgun_med_2', 'landgun_med_2_whispy',
           'landgun_med_3', 'musket_1', 'musket_2', 'musket_3', 'small_bloodspray2'
    foreach ($e in $far) { $xml = Edit-Effect $xml $e @{ max_lod_range = 'variance(2000.000000,0.000000)' } }
    foreach ($e in 'Uber_smoke_white', 'landgun_fastsmoke', 'landgun_med_1', 'landgun_med_2', 'landgun_med_2_whispy', 'landgun_med_3') {
        $xml = Edit-Effect $xml $e @{ max_num_quads = '5000' }
    }
    foreach ($e in 'musket_1', 'musket_2', 'musket_3') { $xml = Edit-Effect $xml $e @{ max_num_quads = '10000' } }

    # 3) Дрожание воздуха (RENDER_METHOD_DISTORTION): любой такой эффект на экране — лишний проход
    #    по всей картинке. Убираем из групп (выстрелы, попадания ядер, марево жары); -KeepDistortion оставляет.
    if (-not $KeepDistortion) {
        $dist = [regex]::Matches($xml, "<SCRIPTED_EFFECT_INFO name='([^']+)'(?:(?!</SCRIPTED_EFFECT_INFO>)[\s\S])*?render_method='RENDER_METHOD_DISTORTION'") |
            ForEach-Object { $_.Groups[1].Value } | Select-Object -Unique |
            Where-Object { $_ -notlike '*heathaze*' }   # марево жары — единственный эффект своей группы; пустую группу не оставляем
        foreach ($e in $dist) { $xml = Remove-GroupEntries $xml $e }
        Write-Host "Эффектов дрожания воздуха убрано из групп: $(@($dist).Count)"
    }
}

$doc = New-Object Xml.XmlDocument; $doc.LoadXml($xml)   # проверка, что XML не сломан

$files = @{
    'effects\landbattle.xml' = $Latin1.GetBytes($xml)
    $TexPath                 = $texBytes
}
if (-not $NoSounds) {
    if (-not $NoVoices -and $VoiceEvery -gt 0) {
        Write-Host '== Голоса для стонов ==' -ForegroundColor Cyan
        & powershell -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot\build_voices.ps1" -GameDir $GameDir | Out-Null
        if ($LASTEXITCODE) { throw 'build_voices.ps1 завершился с ошибкой' }
    }
    Write-Host '== Звуки попаданий ==' -ForegroundColor Cyan
    & powershell -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot\build_sounds.ps1" -VoiceEvery $(if ($NoVoices) { 0 } else { $VoiceEvery }) | Out-Null
    if ($LASTEXITCODE) { throw 'build_sounds.ps1 завершился с ошибкой' }
    foreach ($f in Get-ChildItem (Join-Path $OutDir 'sfx') -Filter *.wav) {
        $files[($f.Name -replace '__', '\')] = [IO.File]::ReadAllBytes($f.FullName)
    }
    Write-Host "Звуков в паке: $(@($files.Keys | Where-Object { $_ -like 'sfx\*' }).Count)"

    # Громкость и дальность звуков. Игра читает скомпилированную таблицу sounds_packed\sound_events
    # из sound.pack, а не sounds\events\*.csv (это исходники — правки в них ни на что не влияли,
    # проверено в игре). Что именно меняется — $GoreSoundChanges в soundevents.ps1.
    $soundPack = Join-Path $Data 'sound.pack'
    $g = Get-GoreSoundEvents (Read-PackFile $soundPack 'sounds_packed\sound_events') $soundPack
    $files['sounds_packed\sound_events'] = $g.Bytes
    Write-Host "Звуковых событий изменено: $($g.Events.Count)"
    foreach ($i in ($g.Events.Keys | Sort-Object)) { Write-Host "        $i  $($g.Events[$i])" }
}

$packPath = Join-Path $OutDir $PackName
Write-Pack $packPath 4 $files                             # 4 = movie, грузится без user.script
Write-Host "Собран: $packPath" -ForegroundColor Green

if (-not $NoInstall) {
    Remove-FromData $TestPacks
    Copy-Item -LiteralPath $packPath -Destination (Join-Path $Data $PackName) -Force
    Write-Host "Установлен: $(Join-Path $Data $PackName)" -ForegroundColor Green
}
