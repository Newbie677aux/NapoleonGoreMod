# Сборка NapoleonGoreMod: умеренная тёмно-красная кровь поверх эффектов DarthMod.
# Берёт effects\landbattle.xml и форму капли из DMN_Darth_Effects_Napoleon.pack (сам пак не меняет)
# и собирает отдельный movie-пак zz_NapoleonGoreMod.pack. Префикс zz_ нужен, чтобы пак грузился
# после DMN_* и перекрывал их (проверено в игре тестом с синей/зелёной кровью).
# Запуск:   powershell -ExecutionPolicy Bypass -File tools\build_pack.ps1
# Удаление: powershell -ExecutionPolicy Bypass -File tools\build_pack.ps1 -Uninstall

param(
    [string]$GameDir = 'E:\Steam\steamapps\common\Napoleon Total War',
    [switch]$NoInstall,
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
# Пули: чуть крупнее одиночная струйка + короткий веер мелких брызг.
$xml = Edit-Effect $xml 'small_bloodspray1' @{
    initial_scale_range_metres = 'vector(variance(0.550000,0.250000),variance(0.040000,0.100000))'
    life_range = 'variance(1.500000,0.300000)'; max_effects = '200'; max_num_quads = '400'
}
$xml = Edit-Effect $xml 'small_bloodspray3' @{
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
    life_range = 'variance(1.000000,0.200000)'; max_effects = '40'; max_num_quads = '300'
}
$xml = Add-GroupEntry $xml 'blood_spray' 'blood_mist'

$doc = New-Object Xml.XmlDocument; $doc.LoadXml($xml)   # проверка, что XML не сломан

$packPath = Join-Path $OutDir $PackName
Write-Pack $packPath 4 @{                                 # 4 = movie, грузится без user.script
    'effects\landbattle.xml' = $Latin1.GetBytes($xml)
    $TexPath                 = $texBytes
}
Write-Host "Собран: $packPath" -ForegroundColor Green

if (-not $NoInstall) {
    Remove-FromData $TestPacks
    Copy-Item -LiteralPath $packPath -Destination (Join-Path $Data $PackName) -Force
    Write-Host "Установлен: $(Join-Path $Data $PackName)" -ForegroundColor Green
}
