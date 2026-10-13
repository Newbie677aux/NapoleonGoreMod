# Тест порядка загрузки: два movie-пака с кровью разного цвета.
#   !gore_test_blue.pack     (по алфавиту ДО паков DMN_*)    -> синяя кровь
#   zz_gore_test_green.pack  (по алфавиту ПОСЛЕ паков DMN_*) -> зелёная кровь
# Какой цвет виден в игре, тот пак и перекрывает DarthMod. Обычная красная кровь значит,
# что DarthMod перекрывает оба пака.
# Берёт effects\landbattle.xml и текстуру крови из DMN_Darth_Effects_Napoleon.pack (сам пак не меняет).
# Запуск:  powershell -ExecutionPolicy Bypass -File tools\build_test_pack.ps1
# Удаление: powershell -ExecutionPolicy Bypass -File tools\build_test_pack.ps1 -Uninstall

param(
    [string]$GameDir = 'E:\Steam\steamapps\common\Napoleon Total War',
    [switch]$NoInstall,
    [switch]$Uninstall
)

$ErrorActionPreference = 'Stop'
$Data    = Join-Path $GameDir 'data'
$Source  = Join-Path $Data 'DMN_Darth_Effects_Napoleon.pack'
$OutDir  = Join-Path $PSScriptRoot '..\build'
New-Item -ItemType Directory -Force $OutDir | Out-Null

$Variants = @(
    @{ Pack = '!gore_test_blue.pack';    Tex = 'gore_test_blue';  R = 0;  G = 80;  B = 255 },
    @{ Pack = 'zz_gore_test_green.pack'; Tex = 'gore_test_green'; R = 0;  G = 255; B = 0 }
)
$Obsolete = @('zz_gore_test.pack')   # первая тестовая сборка

if ($Uninstall) {
    foreach ($n in @($Variants | ForEach-Object { $_.Pack }) + $Obsolete) {
        $f = Join-Path $Data $n
        if (Test-Path -LiteralPath $f) { Remove-Item -LiteralPath $f; Write-Host "Удалён: $f" }
    }
    return
}

. "$PSScriptRoot\packlib.ps1"

Write-Host '== Чтение landbattle.xml и текстуры крови из DarthMod ==' -ForegroundColor Cyan
$baseXml = $Latin1.GetString((Read-PackFile $Source 'effects\landbattle.xml'))
$baseTex = Read-PackFile $Source 'effects\textures\emp_humanhit_diffuse2.tga'

foreach ($v in $Variants) {
    $texPath = "effects\textures\$($v.Tex).tga"
    $xml = $baseXml
    # Белый множитель цвета: цвет задаёт текстура, освещение не затемняет
    $look = @{
        start_colour_range_r = 'variance(255,0)'; start_colour_range_g = 'variance(255,0)'; start_colour_range_b = 'variance(255,0)'
        end_colour_range_r   = 'variance(255,0)'; end_colour_range_g   = 'variance(255,0)'; end_colour_range_b   = 'variance(255,0)'
        colour_range_a       = 'variance(255,0)'
        lighting             = 'variance(0.000000,0.000000)'
        texture_1            = $texPath
    }
    foreach ($e in 'small_bloodspray1', 'small_bloodspray2', 'small_bloodspray3', 'blood_mist') {
        $xml = Edit-Effect $xml $e $look
    }
    $xml = Edit-Effect $xml 'small_bloodspray1' @{
        initial_scale_range_metres = 'vector(variance(0.500000,0.300000),variance(0.050000,0.100000))'
    }
    # Пули: к одиночной струйке добавляем более заметный bloodspray2
    $xml = Add-GroupEntry $xml 'Musket_impact_human' 'small_bloodspray2'

    $doc = New-Object Xml.XmlDocument; $doc.LoadXml($xml)   # проверка, что XML не сломан

    $packPath = Join-Path $OutDir $v.Pack
    Write-Pack $packPath 4 @{                                 # 4 = movie, грузится без user.script
        'effects\landbattle.xml' = $Latin1.GetBytes($xml)
        $texPath                 = New-TintedTga $baseTex $v.R $v.G $v.B
    }
    Write-Host "Собран: $packPath" -ForegroundColor Green
}

if (-not $NoInstall) {
    foreach ($n in $Obsolete) {
        $f = Join-Path $Data $n
        if (Test-Path -LiteralPath $f) { Remove-Item -LiteralPath $f; Write-Host "Удалён старый тест: $f" }
    }
    foreach ($v in $Variants) {
        Copy-Item -LiteralPath (Join-Path $OutDir $v.Pack) -Destination (Join-Path $Data $v.Pack) -Force
        Write-Host "Установлен: $(Join-Path $Data $v.Pack)" -ForegroundColor Green
    }
}
