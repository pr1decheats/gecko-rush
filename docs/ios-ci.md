# Неподписанная iPhone IPA 2.5 — опубликована и проверена

Версия **2.5.0 (7)** собрана в успешном [Mac CI 43495568383](https://github.com/pr1decheats/gecko-rush/actions/runs/43495568383), build source commit `590dfdb3c39e6c0716a91c9144cd619c19c14e70`, независимо скачана и проверена. Выпуск [v2.5.0](https://github.com/pr1decheats/gecko-rush/releases/tag/v2.5.0) опубликован **13 ноября 2026 года в 19:52:27 UTC** после независимой сверки файлов черновика; постоянные адреса подтверждены через GitHub API. После публикации оба файла повторно скачаны по постоянным адресам; размеры и SHA-256 точно совпали с независимо проверенными пакетами.

```text
Run: https://github.com/pr1decheats/gecko-rush/actions/runs/43495568383
Build source commit: 590dfdb3c39e6c0716a91c9144cd619c19c14e70
Size: 28 229 654
SHA-256: cf8d9be660e72faf3a814bfb14cf723b2d1375856202e269a949616a10f770a2
Android size: 52 919 978
Android SHA-256: 27ff8128bf9d86dd92e7b52a599e3c154354870dadf215b70e562586efcdbb1d
```

Опубликованная прямая загрузка: [GeckoRush-2.5-unsigned.ipa](https://github.com/pr1decheats/gecko-rush/releases/download/v2.5.0/GeckoRush-2.5-unsigned.ipa), Android-пара — [GeckoRush-2.5.apk](https://github.com/pr1decheats/gecko-rush/releases/download/v2.5.0/GeckoRush-2.5.apk). [Статус файлов](builds.md).

## Выполненная сборка и проверка 2.5

Реализована компактная заставка Triada Games: **55% ширины экрана**, fade-in **0,7 с**, удержание до **2,0 с** и fade-out до **2,5 с**. Только символ вращается со скоростью **6°/с**; `TRIADA` над `GAMES` остаются неподвижными. Пропуск разрешён после **0,3 с**. Нативная заставка движка и пресет iOS используют новый `assets/triada-games-launch.png` **1080×1920**: компактный первый кадр с **18% непрозрачности**, вписанный с сохранением пропорций; минимальный показ движка — **100 мс**. Исходный `triada-games.png` не изменён. Boot-тест (21) и нативная регрессия брендинга (29) прошли без ошибок; повторно просмотрены пять чистых кадров. Локальный четырёхаргументный helper подтвердил original + compact launch + две PNG-копии. Настоящий Mac-экспорт, XML `Launch Screen` и compact PNG прошли checker в успешном CI 2.5.

Ручной публичный CI на стандартном `macos-15-intel` восстановил и проверил замороженный подписанный APK, затем Xcode собрал настоящий unsigned arm64 `iphoneos` без Apple ID/ключей Apple. Независимый portable verifier подтвердил **2.5.0 (7)**, iOS 14 / SDK 18.5, отсутствие подписи Apple, **49 записей PCK с корректными MD5**, лицензии и **все 13 игровых `.gdc` побайтно совпадающие с APK**, включая `boot.gdc`. Внешний Actions ZIP отдельно прошёл SHA-256, CRC и проверку списка файлов; APK/IPA/build-info черновика совпали по размерам и хешам. Совместимость verifier с фактическими файлами 2.4 сохранена и проверена.

Actions artifacts остаются `GeckoRush-unsigned-ipa` и `GeckoRush-ios-build-log`. Выпуск `v2.5.0` сначала был создан как черновик, затем опубликован после независимого скачивания, сверки размеров/SHA и проверки нового launch branding. Run/build source commit выше относятся к фактически собранному коду; Size/SHA — к независимо скачанной IPA.

Локальная установка unsigned IPA выполняется через Sideloadly на своём Windows/Mac; Apple ID вводится только локально. Физический iPhone 2.5 не проверен. Локальные тесты, Mac CI и независимая проверка IPA завершены. Windows ZIP, Android APK и iPhone IPA 2.5 опубликованы и независимо проверены; страница скачивания содержит три платформы 2.5.

## Архив: CI и IPA 2.4

Ниже сохранены реальные run, commit, размеры и проверки опубликованных прежних файлов. Они не являются результатом CI 2.5.

### Неподписанная iPhone IPA 2.4 через GitHub Actions

**Версия 2.4.0 (6) собрана, независимо скачана и проверена. Выпуск [v2.4.0](https://github.com/pr1decheats/gecko-rush/releases/tag/v2.4.0) опубликован 13 ноября 2026 года в 14:36:46 UTC.** Mac CI успешно выполнил нативную сборку, проверку пакета и Triada Games launch branding; постоянные адреса подтверждены через GitHub API. Публичные APK и IPA повторно скачаны по этим адресам; размеры и SHA-256 совпали.

```text
Run: https://github.com/pr1decheats/gecko-rush/actions/runs/43442922509
Build source commit: 46bd604382b9e7518c2c4b13a4b6c42830198629
Size: 30 200 857
SHA-256: 6705629fe3d4f45690f15fbf1b22dd2eba36a6fdbb171e93516f4956f9f68c2e
```

Опубликована прямая загрузка [GeckoRush-2.4-unsigned.ipa](https://github.com/pr1decheats/gecko-rush/releases/download/v2.4.0/GeckoRush-2.4-unsigned.ipa); Android-пара — [GeckoRush-2.4.apk](https://github.com/pr1decheats/gecko-rush/releases/download/v2.4.0/GeckoRush-2.4.apk). [Общий статус файлов](builds.md).

#### Текущий процесс 2.4

[Workflow](../.github/workflows/ios.yml) остаётся ручным, только для публичного репозитория, на стандартном **`macos-15-intel`**: без платного увеличенного runner, Apple ID и ключей Apple. `contents: write` нужен для создания **черновика** `v2.4.0`; публикация выполняется после независимой проверки, существующий тег/выпуск не перезаписывается.

1. Из `.github/release-assets/android/manifest.json` и частей восстанавливается замороженный подписанный APK 2.4. Проверяются размер и SHA-256 каждой части и целого файла. CI не строит и не переподписывает Android.
2. Официальные Godot 4.6.3 и экспортные шаблоны проверяются по фиксированным SHA-256. `git archive` создаёт изолированную копию исходников без бинарных частей APK; helper меняет только временный iOS-пресет.
3. **До `xcodebuild`** проверяются `Launch Screen.storyboard` как XML, `launchScreen=YES`, ровно один `SplashImage` с `scaleAspectFit`, выбранный `UILaunchStoryboardName`, каталоги @2x/@3x и отсутствие незаменённых placeholder. Отдельная Godot-проверка сравнивает пиксели обоих экспортированных PNG с предоставленным логотипом **Triada Games**.
4. Xcode собирает настоящий Release `iphoneos`, arm64, минимум iOS 14, с `CODE_SIGNING_ALLOWED=NO`, `CODE_SIGNING_REQUIRED=NO` и очищенными данными подписи. Team ID `0000000000` остаётся только placeholder экспортёра во временном пресете.
5. Настоящий `.app` упаковывается в IPA. [Portable verifier](../.github/verify_mobile.py) проверяет ZIP, метаданные **2.4.0 (6)**, unsigned Mach-O arm64/iOS 14, PCK/MD5, лицензии и побайтовое совпадение всех **12 игровых `.gdc`** с замороженным APK.
6. Сохраняются стабильные Actions artifacts `GeckoRush-unsigned-ipa` и `GeckoRush-ios-build-log`; черновик содержит versioned IPA/APK, `SHA256SUMS`, `build-info.txt` и инструкцию Sideloadly. Только затем выполняются независимое скачивание, проверка и публикация.

Исходный логотип `assets/triada-games.png`: **1170×1075**, SHA-256 `59f25a432ae2f364524569d1afa703e01fd1632e1684c6d8d3cb52eb55063e84`. Предпросмотр ресурса выполнен; первый Linux boot-кадр не захвачен из-за ещё не отображённого окна Xorg. Проверки XML/пикселей успешно выполнены в CI 43442922509.

#### Независимая проверка и публикация

После скачивания проверены SHA-256/CRC и список файлов внешнего Actions-архива, затем [portable verifier](../.github/verify_mobile.py) с `--version 2.4.0 --build 6` дал **PASS**. IPA: `org.geckorush.game`, iPhoneOS/arm64, минимум iOS 14, native Mach-O без подписи Apple; **42 записи PCK с корректными MD5**, лицензии и все **12 игровых `.gdc` побайтно совпадают с APK**. В нативном `Info.plist` подтверждён `Launch Screen`. Размеры и SHA-256 APK/IPA/build-info черновика совпали, после чего выпуск опубликован. Run и build source commit выше относятся к фактически собранному мобильному коду; Size и SHA-256 — к независимо скачанной IPA.

Для установки unsigned IPA нужна локальная подпись через бесплатный Sideloadly на своём Windows/Mac. Apple ID вводится только локально, личный профиль обычно действует семь дней; продлевайте его с тем же Apple ID без удаления игры. Подробная последовательность сохранена ниже. **Физический iPhone 2.4 не проверен**; CI не подтверждает мобильные FPS, звук, safe area или установку.

#### Архив: CI и IPA 2.3

Последующие run, commit, размеры и контрольные суммы относятся к историческим выпускам 2.3/2.2.

##### Неподписанная iPhone IPA 2.3 через GitHub Actions

Текущий запуск **2.3.0 (5)**: [GitHub Actions 43397179970](https://github.com/pr1decheats/gecko-rush/actions/runs/43397179970), source commit `f6f8983890746740a9a2200f83150fb7e2492246`. **CI завершён успешно; скачанный IPA независимо проверен и опубликован.** Это нативное приложение для физического iPhone arm64, iOS 14+, без подписи Apple.

```text
Size: 27 233 132
SHA-256: 410e30c73dd83fb7173865ef433a0cdb7da7d0929aa946ea066bac34ebc9e155
```

Проверенные файлы опубликованы по постоянным адресам: [GeckoRush-2.3-unsigned.ipa](https://github.com/pr1decheats/gecko-rush/releases/download/v2.3.0/GeckoRush-2.3-unsigned.ipa) и [GeckoRush-2.3.apk](https://github.com/pr1decheats/gecko-rush/releases/download/v2.3.0/GeckoRush-2.3.apk). Точный статус и параметры обоих файлов — [builds.md](builds.md).

###### Что делает workflow

[`.github/workflows/ios.yml`](../.github/workflows/ios.yml) запускается вручную через `workflow_dispatch` на стандартном `macos-15-intel`. Проверка публичности репозитория стоит до выделения Mac. Job ограничен 30 минутами; исходный checkout не получает ключей Apple. В job разрешён `contents: write`, чтобы создать **черновик GitHub Release**; workflow не публикует его автоматически и отказывается перезаписывать существующий релиз или тег.

1. Восстанавливает заранее подписанный Android APK из частей и проверяет размер и SHA-256 всего файла и каждой части. CI не пересобирает и не переподписывает APK.
2. Загружает официальные Godot **4.6.3 stable macOS universal** и экспортные шаблоны с зафиксированными SHA-256. Из шаблонов извлекается `ios.zip`.
3. Создаёт из текущего commit временную копию исходников. [Helper](../scripts/ci/export_ios.gd) меняет только её пресет и экспортирует проект `GeckoRush.xcodeproj` для `iphoneos`.
4. Собирает Xcode Release для физического iPhone: `CODE_SIGNING_ALLOWED=NO`, `CODE_SIGNING_REQUIRED=NO`, без provisioning. Team ID `0000000000` — только требуемый экспортёром placeholder во временном пресете; при сборке `DEVELOPMENT_TEAM` очищается.
5. Проверяет метаданные, bundle identifier `org.geckorush.game`, версию **2.3.0 (5)**, iPhoneOS, исполняемый **Mach-O arm64 MH_EXECUTE**, наличие PCK и целостность ZIP. Упаковывает настоящий `.app` в `Payload/` и создаёт IPA.
6. [Проверяет оба мобильных пакета](../.github/verify_mobile.py), включая контрольные суммы PCK и побайтовое совпадение всех **12 скомпилированных игровых `.gdc`** Android/iPhone до загрузки в черновик выпуска.
7. Сохраняет `GeckoRush-unsigned-ipa` и лог Xcode как Actions artifacts на семь дней; создаёт черновик `v2.3.0` с APK, IPA, `SHA256SUMS`, `build-info.txt` и инструкцией Sideloadly. Независимое скачивание, сверка и публикация выполняются после успешного CI.

Apple ID, сертификаты Apple, provisioning profile и Android keystore для этой сборки не требуются и не включаются в репозиторий. Пресет iOS в исходниках не получает данные пользовательской подписи. Добавление нативных GDExtension или iOS-плагинов потребует отдельной проверки процесса.

###### Повторная сборка и проверка

Для полного workflow используйте Git-клон репозитория: архив исходников Godot не включает замороженные бинарные части APK из `.github/release-assets`.

Опубликованный тег `v2.3.0` защищён от перезаписи. Для нового полного выпуска задайте неиспользованные версию, номер сборки и тег в пресетах и workflow. Повтор с прежним тегом сохранит артефакт IPA, но остановится перед созданием черновика.

Откройте Actions → **Build unsigned iOS IPA (manual)** → **Run workflow** для нужного commit. Успех экспорта Xcode сам по себе не подтверждает готовый IPA: дождитесь упаковки и проверки обоих пакетов. Скачайте артефакт `GeckoRush-unsigned-ipa`, распакуйте внешнюю ZIP-обёртку GitHub и проверьте IPA вместе с `build-info.txt`; в черновике релиза также проверьте `SHA256SUMS` и совпадение с подписанным APK. Не публикуйте черновик до независимой сверки скачанных файлов.

Установка, сенсор, звук, safe area и реальные 60/120 FPS на физическом iPhone 2.3 **не проверены**. Признак `CADisableMinimumFrameDurationOnPhone` разрешает высокий лимит кадров на подходящем устройстве, но не подтверждает производительность. Сборка для симулятора не заменяет `iphoneos`.

###### Установка с Windows через Sideloadly

Скачайте unsigned IPA на компьютер и откройте её в [Sideloadly](https://sideloadly.io/). Подключите разблокированный iPhone по USB, подтвердите доверие компьютеру, выберите телефон в программе, перетащите IPA, укажите Apple ID локально и нажмите **Start**. При запросе iOS подтвердите профиль в **Настройки → Основные → VPN и управление устройством**; для iOS 16+ может потребоваться **Режим разработчика**.

Unsigned IPA перед установкой должна получить подпись. Бесплатные личные профили обычно действуют семь дней; затем повторите подпись и установку с тем же Apple ID, не удаляя игру. Компьютер нужен для установки и продления подписи, сама игра работает на iPhone отдельно. Apple ID, пароль и коды подтверждения вводятся только в локальный инструмент/интерфейс Apple. Этот процесс не создаёт релиз App Store или TestFlight.

###### Архив: проверенная IPA 2.2.0 (4)

[Запуск 43295517584](https://github.com/pr1decheats/gecko-rush/actions/runs/43295517584) успешно собрал IPA 12 ноября 2026 года на `macos-15-intel`, source commit `0fa8ddcdb156725c6d959d31ba59c58539d67061`. `GeckoRush-2.2-unsigned.ipa`: **27 202 757 байт**.

```text
SHA-256: 4345bb56c97123ee659adf9ae7bfd5404bfa96b34e8f7393d1fd705468f2e96d
```

Скачанный архив 2.2 проверен независимо: ZIP CRC, `org.geckorush.game`, 2.2.0 (4), arm64 Mach-O MH_EXECUTE для iOS device, минимум iOS 14, отсутствие подписи/профиля Apple. PCK Godot 4.6.3 содержал 39 записей с корректными MD5; все 12 игровых `.gdc` побайтно совпали с замороженным Android 2.2. В `Info.plist` были портретная ориентация и `CADisableMinimumFrameDurationOnPhone`. Подпись, установка и запуск на устройстве не выполнялись.

Для рецепта 2.2 также прошли проверка YAML, `bash -n`, компиляция встроенного Python, синтаксис helper через Godot `--check-only` и smoke-тест изменения только временного пресета с неизменным SHA-256 исходного `export_presets.cfg`. Эти исторические результаты подтверждают файл и рецепт 2.2; результат 2.3 проверяется отдельно.

Официальные источники: [Godot 4.6.3 assets](https://github.com/godotengine/godot-builds/releases/tag/4.6.3-stable), [экспортёр Apple Embedded](https://github.com/godotengine/godot/blob/4.6.3-stable/editor/export/editor_export_platform_apple_embedded.cpp), [штатная Xcode scheme](https://github.com/godotengine/godot/blob/4.6.3-stable/misc/dist/apple_embedded_xcode/godot_apple_embedded.xcodeproj/xcshareddata/xcschemes/godot_apple_embedded.xcscheme), [GitHub runner images](https://github.com/actions/runner-images#available-images), [Apple о подписи приложений](https://support.apple.com/guide/security/app-code-signing-process-sec7c917bf14/web).
