# Неподписанная iPhone IPA 2.3 через GitHub Actions

Текущий запуск **2.3.0 (5)**: [GitHub Actions 43397179970](https://github.com/pr1decheats/gecko-rush/actions/runs/43397179970), source commit `f6f8983890746740a9a2200f83150fb7e2492246`. **CI завершён успешно; скачанный IPA независимо проверен и опубликован.** Это нативное приложение для физического iPhone arm64, iOS 14+, без подписи Apple.

```text
Size: 27 233 132
SHA-256: 410e30c73dd83fb7173865ef433a0cdb7da7d0929aa946ea066bac34ebc9e155
```

Проверенные файлы опубликованы по постоянным адресам: [GeckoRush-2.3-unsigned.ipa](https://github.com/pr1decheats/gecko-rush/releases/download/v2.3.0/GeckoRush-2.3-unsigned.ipa) и [GeckoRush-2.3.apk](https://github.com/pr1decheats/gecko-rush/releases/download/v2.3.0/GeckoRush-2.3.apk). Точный статус и параметры обоих файлов — [builds.md](builds.md).

## Что делает workflow

[`.github/workflows/ios.yml`](../.github/workflows/ios.yml) запускается вручную через `workflow_dispatch` на стандартном `macos-15-intel`. Проверка публичности репозитория стоит до выделения Mac. Job ограничен 30 минутами; исходный checkout не получает ключей Apple. В job разрешён `contents: write`, чтобы создать **черновик GitHub Release**; workflow не публикует его автоматически и отказывается перезаписывать существующий релиз или тег.

1. Восстанавливает заранее подписанный Android APK из частей и проверяет размер и SHA-256 всего файла и каждой части. CI не пересобирает и не переподписывает APK.
2. Загружает официальные Godot **4.6.3 stable macOS universal** и экспортные шаблоны с зафиксированными SHA-256. Из шаблонов извлекается `ios.zip`.
3. Создаёт из текущего commit временную копию исходников. [Helper](../scripts/ci/export_ios.gd) меняет только её пресет и экспортирует проект `GeckoRush.xcodeproj` для `iphoneos`.
4. Собирает Xcode Release для физического iPhone: `CODE_SIGNING_ALLOWED=NO`, `CODE_SIGNING_REQUIRED=NO`, без provisioning. Team ID `0000000000` — только требуемый экспортёром placeholder во временном пресете; при сборке `DEVELOPMENT_TEAM` очищается.
5. Проверяет метаданные, bundle identifier `org.geckorush.game`, версию **2.3.0 (5)**, iPhoneOS, исполняемый **Mach-O arm64 MH_EXECUTE**, наличие PCK и целостность ZIP. Упаковывает настоящий `.app` в `Payload/` и создаёт IPA.
6. [Проверяет оба мобильных пакета](../.github/verify_mobile.py), включая контрольные суммы PCK и побайтовое совпадение всех **12 скомпилированных игровых `.gdc`** Android/iPhone до загрузки в черновик выпуска.
7. Сохраняет `GeckoRush-unsigned-ipa` и лог Xcode как Actions artifacts на семь дней; создаёт черновик `v2.3.0` с APK, IPA, `SHA256SUMS`, `build-info.txt` и инструкцией Sideloadly. Независимое скачивание, сверка и публикация выполняются после успешного CI.

Apple ID, сертификаты Apple, provisioning profile и Android keystore для этой сборки не требуются и не включаются в репозиторий. Пресет iOS в исходниках не получает данные пользовательской подписи. Добавление нативных GDExtension или iOS-плагинов потребует отдельной проверки процесса.

## Повторная сборка и проверка

Для полного workflow используйте Git-клон репозитория: архив исходников Godot не включает замороженные бинарные части APK из `.github/release-assets`.

Опубликованный тег `v2.3.0` защищён от перезаписи. Для нового полного выпуска задайте неиспользованные версию, номер сборки и тег в пресетах и workflow. Повтор с прежним тегом сохранит артефакт IPA, но остановится перед созданием черновика.

Откройте Actions → **Build unsigned iOS IPA (manual)** → **Run workflow** для нужного commit. Успех экспорта Xcode сам по себе не подтверждает готовый IPA: дождитесь упаковки и проверки обоих пакетов. Скачайте артефакт `GeckoRush-unsigned-ipa`, распакуйте внешнюю ZIP-обёртку GitHub и проверьте IPA вместе с `build-info.txt`; в черновике релиза также проверьте `SHA256SUMS` и совпадение с подписанным APK. Не публикуйте черновик до независимой сверки скачанных файлов.

Установка, сенсор, звук, safe area и реальные 60/120 FPS на физическом iPhone 2.3 **не проверены**. Признак `CADisableMinimumFrameDurationOnPhone` разрешает высокий лимит кадров на подходящем устройстве, но не подтверждает производительность. Сборка для симулятора не заменяет `iphoneos`.

## Установка с Windows через Sideloadly

Скачайте unsigned IPA на компьютер и откройте её в [Sideloadly](https://sideloadly.io/). Подключите разблокированный iPhone по USB, подтвердите доверие компьютеру, выберите телефон в программе, перетащите IPA, укажите Apple ID локально и нажмите **Start**. При запросе iOS подтвердите профиль в **Настройки → Основные → VPN и управление устройством**; для iOS 16+ может потребоваться **Режим разработчика**.

Unsigned IPA перед установкой должна получить подпись. Бесплатные личные профили обычно действуют семь дней; затем повторите подпись и установку с тем же Apple ID, не удаляя игру. Компьютер нужен для установки и продления подписи, сама игра работает на iPhone отдельно. Apple ID, пароль и коды подтверждения вводятся только в локальный инструмент/интерфейс Apple. Этот процесс не создаёт релиз App Store или TestFlight.

## Архив: проверенная IPA 2.2.0 (4)

[Запуск 43295517584](https://github.com/pr1decheats/gecko-rush/actions/runs/43295517584) успешно собрал IPA 12 ноября 2026 года на `macos-15-intel`, source commit `0fa8ddcdb156725c6d959d31ba59c58539d67061`. `GeckoRush-2.2-unsigned.ipa`: **27 202 757 байт**.

```text
SHA-256: 4345bb56c97123ee659adf9ae7bfd5404bfa96b34e8f7393d1fd705468f2e96d
```

Скачанный архив 2.2 проверен независимо: ZIP CRC, `org.geckorush.game`, 2.2.0 (4), arm64 Mach-O MH_EXECUTE для iOS device, минимум iOS 14, отсутствие подписи/профиля Apple. PCK Godot 4.6.3 содержал 39 записей с корректными MD5; все 12 игровых `.gdc` побайтно совпали с замороженным Android 2.2. В `Info.plist` были портретная ориентация и `CADisableMinimumFrameDurationOnPhone`. Подпись, установка и запуск на устройстве не выполнялись.

Для рецепта 2.2 также прошли проверка YAML, `bash -n`, компиляция встроенного Python, синтаксис helper через Godot `--check-only` и smoke-тест изменения только временного пресета с неизменным SHA-256 исходного `export_presets.cfg`. Эти исторические результаты подтверждают файл и рецепт 2.2; результат 2.3 проверяется отдельно.

Официальные источники: [Godot 4.6.3 assets](https://github.com/godotengine/godot-builds/releases/tag/4.6.3-stable), [экспортёр Apple Embedded](https://github.com/godotengine/godot/blob/4.6.3-stable/editor/export/editor_export_platform_apple_embedded.cpp), [штатная Xcode scheme](https://github.com/godotengine/godot/blob/4.6.3-stable/misc/dist/apple_embedded_xcode/godot_apple_embedded.xcodeproj/xcshareddata/xcschemes/godot_apple_embedded.xcscheme), [GitHub runner images](https://github.com/actions/runner-images#available-images), [Apple о подписи приложений](https://support.apple.com/guide/security/app-code-signing-process-sec7c917bf14/web).
