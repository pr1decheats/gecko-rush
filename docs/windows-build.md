# Windows 2.7

Параметры: **2.7.0 (9)**, AMD64 / PE32+ / Windows GUI, FileVersion **2.7.0.9**, ProductVersion **2.7.0.0**, встроенный PCK и прежняя новая иконка приложения. Пакет — `GeckoRush-2.7-Windows.zip`.

Пакетный verifier сравнивает 13 compiled scripts и 8 ресурсов иконки/Triada с APK и требует отсутствие старых атласов. SHA сравниваемого APK Windows workflow получает из замороженного манифеста, без захардкоженной суммы прежнего выпуска. Нативный CI запускает точный release EXE на 360 headless-кадров; внешний диагностический скрипт выполняется отдельно редактором против экспортированного PCK, поскольку официальные release templates запрещают path overrides.

Распакуйте ZIP в новую папку и запустите `GeckoRush.exe`. Пользовательскую папку сохранений не удаляйте. Лимит 240 FPS остаётся в настройках ПК; производительность физического GPU/монитора требует отдельного измерения.

---

## Архив: версия 2.6 и более ранние выпуски

# Windows 2.6 — готовая сборка x64

`GeckoRush-2.6-Windows.zip`: **50,671,515 байт**, SHA-256 `449e0eaa286742f1f4ad8badab9cd3c7d1707877a78a383cbf4069d90779be34`. EXE **119,376,384 байт**, SHA-256 `366a1e95060ed61cdc697b25551ddfee8022644b95cf857881d94f8a780644ed`. [Загрузить ZIP](https://github.com/pr1decheats/gecko-rush/releases/download/v2.6.0/GeckoRush-2.6-Windows.zip).

PE64 AMD64 / Windows GUI. FileVersion **2.6.0.8**, ProductVersion **2.6.0.0**, ProductName/FileDescription **Gecko Rush**, встроенная новая полноцветная иконка. PCK: **75 корректных MD5**, все **13 compiled scripts и 25 ресурсов подробных гекконов совпали с Android**. Пакетный verifier прошёл **17 положительных и отрицательных проб**, включая отсутствие каталога, шейдера, настоящего imported atlas и устаревшую иконку.

[Нативный CI43596560822](https://github.com/pr1decheats/gecko-rush/actions/runs/43596560822), source `bd05095f86fe9ad7e3cbde7216ab3cf85cc0e4a3`, результат **PASS**. Точный замороженный EXE запущен на **Microsoft Windows NT 10.0.26100.0**: **360 headless-кадров / 6 секунд симуляции**, exit0, без ERROR/SCRIPT ERROR. Отдельные **67 проверок** 21 образа / 42 поз и лимита240FPS выполнены редакторным Godot на Linux против PCK именно этого EXE; это не нативный Windows GPU-тест.

Официальные release templates Godot4.6.3 собраны без path overrides: внешний `--script` игнорируется, `--main-pack` отклоняется. Поэтому CI запускает штатную игру, а внешний диагностический скрипт выполняется отдельно редактором. Первоначальная расширенная CLI-проверка была исправлена с учётом этого ограничения; игровые файлы остались теми же.

Для игры распакуйте ZIP и запустите `GeckoRush.exe`. Обновление не требует удаления `%APPDATA%\Godot\app_userdata\Gecko Rush`. Настройки графики предлагают60/120/240FPS, физика120Гц. Реальная частота зависит от монитора и ПК. Windows GPU и фактические240FPS не измерялись. Цифровой подписи издателя у EXE нет.

---

## Архив: предыдущие Windows-сборки

# Windows Gecko Rush 2.5 — опубликован и проверен

**GeckoRush-2.5-Windows.zip** опубликован, статически проверен, нативно запущен в Windows CI и независимо скачан по публичному адресу. Игровые код/ресурсы — **2.5.0 (7)**; все 25 замороженных runtime/config/asset-файлов и опубликованные APK/IPA не изменялись.

[Скачать GeckoRush-2.5-Windows.zip](https://github.com/pr1decheats/gecko-rush/releases/download/v2.5.0/GeckoRush-2.5-Windows.zip). Распакуйте ZIP и запустите автономный **GeckoRush.exe**; редактор Godot не нужен.

```text
ZIP size: 37 207 919
ZIP SHA-256: a3168bed43a06abb4a1b36232f9dd70dbf83378a1bb7e52f7782364757f5ae89
EXE size: 105 894 032
EXE SHA-256: 02ece870b6246b1600dd31dad5c1f04e63849ef085df866ac85e5c6c5bd2901b
Windows run: https://github.com/pr1decheats/gecko-rush/actions/runs/43499155704
Build source commit: 00138a6a2335f96d72b3841fea341e9a9b086e41
Native verification JSON SHA-256: 530f2ede9b85f91c1e054ec00b8bcf9d2ae4b509d73a6faab7e222a1dce618c1
```

## Статическая проверка

- **PE64 AMD64 GUI**, корректная игровая иконка, FileVersion **2.5.0.7**, ProductVersion **2.5.0.0**, ProductName/FileDescription **Gecko Rush**. EXE без цифровой подписи.
- Встроенный PCK: **49 записей с корректными MD5**; все **13 игровых `.gdc`**, включая `boot.gdc`, побайтно совпали с Android 2.5 и соответствующим iPhone-пакетом.
- Windows verifier прошёл **13 положительных/отрицательных проб**, без ошибок. Эти проверки учитываются отдельно от нативного запуска.
- [Export helper](../scripts/ci/export_windows.gd) требует изолированный `GECKO_WINDOWS_STAGING_DIR` и меняет только Windows-пресет этой копии. `application/modify_resources=true` использует встроенный **Godot TemplateModifier**; RCEdit и Wine не нужны. Мобильные пресеты не изменялись.

## Нативный запуск и публичная загрузка

[Workflow](../.github/workflows/windows.yml), запуск **43499155704**, успешно выполнил **точный замороженный release EXE** на **Microsoft Windows NT 10.0.26100.0** (`windows-latest`): **360 headless-кадров / 6 секунд симуляции**, **exit 0**, без `ERROR` в журнале. Это фактический Windows-executable на Windows runner, а не Linux-замена или статический разбор.

CI добавил в существующий выпуск **v2.5.0** три файла:

- [GeckoRush-2.5-Windows.zip](https://github.com/pr1decheats/gecko-rush/releases/download/v2.5.0/GeckoRush-2.5-Windows.zip).
- [Windows-SHA256SUMS.txt](https://github.com/pr1decheats/gecko-rush/releases/download/v2.5.0/Windows-SHA256SUMS.txt).
- [windows-native-verification.json](https://github.com/pr1decheats/gecko-rush/releases/download/v2.5.0/windows-native-verification.json).

Публичный ZIP независимо скачан: **37 207 919 байт**, ожидаемый SHA-256, ZIP CRC и хеш встроенного EXE совпали. Native JSON также скачан и проверен по SHA-256 выше. Публичные APK/IPA сохранили прежние размеры/хеши; игровые данные 2.5 не менялись.

Headless CI не измеряет физический GPU, FPS или поведение на пользовательской Windows-машине. Исторические Windows 2.2 и более ранние файлы сохранены в [архиве сборок](builds.md). [Текущая валидация](validation.md).
