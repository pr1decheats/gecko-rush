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
