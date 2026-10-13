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
