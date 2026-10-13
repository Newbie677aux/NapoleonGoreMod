# NapoleonGoreMod

Мод крови/расчленёнки для Napoleon: Total War (поверх DarthMod), отдельным `.pack`.
Оригинальные паки игры и файлы DarthMod не изменяются.

## Шаги 1–2: бэкап и разведка

`tools/step1_backup_and_recon.ps1` — только копирует и читает, в игре ничего не меняет:

1. Копирует `save_games` и `scripts\user.script.txt` в
   `%APPDATA%\The Creative Assembly\Napoleon\_backup_2026-10-13` и сверяет хэши.
2. Читает индексы всех `data\*.pack` (без распаковки), ищет файлы DarthMod,
   переопределения между паками, эффекты/декали/variantmesh/звуки.
3. Складывает отчёт в `_backup_2026-10-13\recon\` и `recon.zip`.

Запуск (PowerShell):

```
powershell -ExecutionPolicy Bypass -File tools\step1_backup_and_recon.ps1
```

## Шаг 3: что реально сделать

Отчёт: [docs/step3_report.md](docs/step3_report.md). Кратко:

- **Да:** кровь от пуль и ядер (правка `effects\landbattle.xml`, взятого из DarthMod), звуки попаданий (WAV по путям USM).
- **Частично:** пятна на земле (плоские частицы с жизнью 15–20 с).
- **Нет:** отлетающие головы и дыры в телах (в движке нет расчленения).

## Сборка и установка

```
powershell -ExecutionPolicy Bypass -File tools\build_pack.ps1             # собрать и положить в data\
powershell -ExecutionPolicy Bypass -File tools\build_pack.ps1 -Uninstall  # убрать мод
```

Результат: `data\zz_NapoleonGoreMod.pack` (movie-пак, `user.script.txt` не трогается).
Префикс `zz_` обязателен: так пак грузится после `DMN_*` и перекрывает их `landbattle.xml`.
Это проверено в игре через `tools\build_test_pack.ps1`, где у паков разные цвета крови.

Сейчас в моде:
- тёмно-красная кровь (своя текстура `gore_blood_diffuse.tga` той же формы, что у DarthMod);
- пули: струйка чуть крупнее плюс короткий веер мелких брызг;
- ядра: крупный выброс плюс облачко брызг (`blood_mist`);
- жёсткие лимиты частиц (40–200 эффектов на тип, капли живут 1,5–2 с) под слабые видеокарты;
- звуки попаданий: пуля в тело (8 вариантов) и ядро по людям (8 вариантов). Собраны
  `tools\build_sounds.ps1` из CC0-записей в `sounds\src` (см. `sounds\src\SOURCES.md`), лежат по путям
  Ultimate Sound Mod и перекрывают его звуки.

Без звуков: `tools\build_pack.ps1 -NoSounds`.

Пятен крови на земле нет и не будет: воронки от ядер движок рисует из кода, а частицы
не умеют ложиться на рельеф.
