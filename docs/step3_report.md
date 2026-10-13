# NapoleonGoreMod — шаги 1–3 (2026-10-13)

## Шаг 1: бэкап — готово
`C:\Users\Niki\AppData\Roaming\The Creative Assembly\Napoleon\_backup_2026-10-13\`
- `save_games\` — 17 файлов, 126 928 811 байт (совпадает с оригиналом)
- `scripts\user.script.txt`

Сейчас в `user.script.txt`: `mod DMN_DarthMod_Napoleon.pack;` и `campaign_unit_multiplier 2;`.

Проверено скриптом `tools\step1_backup_and_recon.ps1`: 18 файлов, хэши совпадают.

## Шаг 2: разведка

### Порядок загрузки паков (тип из заголовка PFH0)
| Тип | Паки |
|---|---|
| boot | DMN_Boot |
| release | data, sound, variantmodels*, rigidmodels, buildings, battleterrain, local_ru |
| patch | local_ru_patch, DMN_UltimateSoundMod_V3, DMN_Brigadiers_Drum_roll_cadence_v5 |
| mod (через user.script) | DMN_DarthMod_Napoleon (таблицы db, groupformations) |
| movie (грузятся всегда) | DMN_Darth_Effects_Napoleon, DMN_PDGuru_All_Units, DMN_MOD_*, DMN_maum*, DMN_aum*, DMNtranslate, media … |

### Что уже есть про кровь
В движке NTW кровь есть, но её мало.
- `effects\landbattle.xml`: в ванили 283 эффекта. DarthMod заменяет файл целиком
  (`DMN_Darth_Effects_Napoleon.pack`, 290 эффектов, плюс `small_bloodspray2/3`).
- Эффекты крови: `blood_mist`, `small_bloodspray1` (пули), `small_bloodspray2`, `small_bloodspray3`.
  Текстура: `effects\textures\emp_humanhit_diffuse2.tga` (её добавил DarthMod).
- Группы: `Musket_impact_human` (в ней только bloodspray1), `blood_spray` (bloodspray2+3), `blood_gen`.
- Таблица `projectile_impacts`: DarthMod ссылается на `Musket_impact_human` и `blood_spray` (ядра).
- Земля: воронки от ядер через `effects\textures\impact_decal_cannonball_finish_*.dds`.

### Звуки
- Ultimate Sound Mod V3 (patch) уже подменяет WAV попаданий по тем же путям:
  `sfx\weapons\bullet_impacts\emp_hyb_bullet_hitbody_0[1-8]`,
  `sfx\weapons\cannonballhitflesh\..._hitflesh_0[1-8]`, `sfx\weapons\bayonet\..._stabflesh_0[1-8]`,
  а также sabre, spear, club, longsword.
- Значит, звуки можно заменить без правки таблиц: положить свои WAV по тем же путям.

### Модели
- Головы — это отдельные variant-части (`variantmodels\unitparts\...\heads\`), 58 шт.
  DMN_PDGuru_All_Units и паки фракций переопределяют сотни файлов юнитов.
- Анимаций смерти: 421 (в том числе от ядер). Системы расчленения в движке нет.

## Шаг 3: что реально сделать

| Хотелка | Реально? | Как | Нагрузка на GT 740M |
|---|---|---|---|
| Кровь от пуль | **Да** | Добавить в `Musket_impact_human` лёгкий bloodspray2, цвет темнее (≈110,0,0), жизнь 0.8–1.2 с | Низкая при `max_num_quads` ≤ 300 |
| Кровь от ядер | **Да** | Усилить группу `blood_spray`, добавить `blood_mist`, срезать `max_effects` с 500 до ~80 | Низкая или средняя |
| Кровь в рукопашной | **Частично** | Отдельного хука на удар штыком/саблей нет. Только через `anim_sound_event`, и то вряд ли. Пока не делать | — |
| Звуки | **Да** | Свои WAV (CC0, моно, 22 кГц) по путям USM: hitbody, hitflesh, stabflesh, sabre. Наш пак должен грузиться после USM | Нулевая |
| Пятна на земле | **Частично** | Настоящей декали «под трупом» нет. Вместо неё плоская частица (`LOCAL_Y_AXIS`), которая живёт 15–20 с с затуханием и спавнится вместе с `blood_spray`. Без долгих луж | Низкая, если лимит ~60 штук |
| Отлетающие головы | **Нет** | Движок не умеет менять меш при смерти, новых анимаций не сделать. Максимум — более сильный всплеск на уровне головы при попадании ядра | — |
| Дыры от ядер в телах | **Нет** | Аналогично. Воронки в земле уже есть, текстуру можно сделать темнее (опционально) | — |
| Кровь на мундирах | **Не рекомендую** | Пришлось бы переписать текстуры юнитов, а это конфликт с PDGuru (254 файла) | — |

### План мода (отдельный .pack, оригиналы не трогаются)
1. Взять `landbattle.xml` **из DarthMod**, а не из ванили, чтобы не потерять его эффекты дыма и выстрелов,
   и внести правки только в блоки крови и групп.
2. Свою текстуру крови назвать новым именем (`effects\textures\gore_blood_diffuse.dds`), DarthMod-овскую не трогать.
3. `projectile_impacts`: оставить таблицу DarthMod, если пятна поедут через ту же группу `blood_spray`.
4. Звуки: 8+8+8 WAV.
5. Пак типа **movie**. Наш `effects\landbattle.xml` должен перебить файл из DMN_Darth_Effects (тоже movie).
   Как движок упорядочивает movie-паки между собой, нужно проверить в игре:
   тестовая сборка с явно красной кровью → смотрим, что победило.
6. Сборка: простой упаковщик PFH0 без сжатия на PowerShell (читалка уже есть в `tools\`) или RPFM.

### Риски
- Любая обновлённая версия `landbattle.xml` в другом паке перекроет наш файл целиком.
- Если частиц больше примерно 1000 квадов в кадре, на 740M будут просадки в больших сражениях.
  Поэтому все лимиты задаём жёстко.

## Утилиты
- `tools\packindex.ps1 -Pack <файл> [-OutFile <txt>]`: тип пака и список файлов (только чтение).
- `tools\packextract.ps1 <пак> <regex> <папка>`: извлечь файлы по regex (только чтение, PFH0 без сжатия).

