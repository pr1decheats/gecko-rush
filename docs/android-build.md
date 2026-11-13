# Android 2.5.0 (7) — опубликованная сборка

**GeckoRush-2.5.apk опубликован и независимо проверен.** Прямая загрузка: [GitHub Release v2.5.0](https://github.com/pr1decheats/gecko-rush/releases/download/v2.5.0/GeckoRush-2.5.apk).

| Параметр | Проверенное значение |
|---|---|
| versionName / versionCode | `2.5.0` / `7` |
| Размер | `52 919 978` |
| SHA-256 | `27ff8128bf9d86dd92e7b52a599e3c154354870dadf215b70e562586efcdbb1d` |
| Подпись | v2/v3, прежний сертификат |
| ABI / API | `armeabi-v7a`, `arm64-v8a` / min 24, target 36 |
| CRC / alignment / отладка | PASS / 16 KB ZIP+ELF / `debuggable=false` |
| Разрешения | Нет запрошенных разрешений |

Готовый APK 2.5 отдельно прошёл все проверки таблицы; прежний сертификат допускает совместимое обновление с сохранением данных. Результат подтверждён новым `v25-release/android-verification.json`. Закрытый ключ и пароли остаются вне репозитория.

Реализована компактная заставка Triada Games: **55% ширины экрана**, fade-in **0,7 с**, удержание до **2,0 с** и fade-out до **2,5 с**. Только символ вращается со скоростью **6°/с**; `TRIADA` над `GAMES` остаются неподвижными. Пропуск разрешён после **0,3 с**. Нативная заставка движка и пресет iOS используют новый `assets/triada-games-launch.png` **1080×1920**: компактный первый кадр с **18% непрозрачности**, вписанный с сохранением пропорций; минимальный показ движка — **100 мс**. Исходный `triada-games.png` не изменён. Сосульки уже увеличены до 30,24×110 px и отдельно проверены. Boot-тест (21) и нативная регрессия брендинга (29) прошли без ошибок; в APK подтверждены **13 игровых `.gdc`**, включая `boot.gdc`. Декодированные пиксели compact launch PNG совпали с источником 1080×1920; исходный логотип хранится как импортированный CTEX, его байты совпали с frozen export source. Отдельный raw original PNG в пакете не требуется. `project.binary` выбирает `boot.tscn` и compact launch PNG; 25 исходных файлов остались неизменны.

[Текущие поля сборок](builds.md), [отчёт о проверках](validation.md), [экспорт](mobile-export.md). Android 2.5 на физическом устройстве не проверен.

## Архив: Android 2.4

Далее сохранены параметры проверенных прежних APK. Они не являются проверкой нового файла 2.5.

### Android 2.4.0 (6) — текущая сборка

**GeckoRush-2.4.apk** собран и проверен. Опубликованный прямой адрес: [GitHub Release v2.4.0](https://github.com/pr1decheats/gecko-rush/releases/download/v2.4.0/GeckoRush-2.4.apk).

| Параметр | Значение |
|---|---|
| Package | `org.geckorush.game` |
| versionName / versionCode | `2.4.0` / `6` |
| Минимальный / целевой API | `24` / `36` |
| Архитектуры | `armeabi-v7a`, `arm64-v8a` |
| Движок | Godot `4.6.3 stable`, Release, Compatibility |
| Размер | `53 517 342` байт |
| Разрешения / отладка | Нет запрошенных разрешений; `debuggable=false` |

```text
SHA-256: 1d1ee9a359c3082a5d1afda365271504c61cd9734d6caf92d41375717d5e456c
```

Подписи **v2/v3**, прежний сертификат, ZIP CRC, `zipalign -c -P 16` и 16 KB alignment нативных ELF проверены. Совместимое обновление сохраняет данные; удалять прежнюю игру не требуется. Закрытый ключ и пароли остаются вне исходников. AAB и публикация Google Play не выполнялись.

Логотип **Triada Games** — предоставленный PNG 1170×1075, SHA-256 `59f25a432ae2f364524569d1afa703e01fd1632e1684c6d8d3cb52eb55063e84`. Проверены декодированные пиксели PNG внутри APK и настройка boot-ресурса. Физический Android 2.4 ещё не проверен; эти проверки не измеряют FPS, сенсор, звук или safe area.

[Текущая валидация](validation.md), [APK и проверенная IPA](builds.md), [экспорт](mobile-export.md).

#### Архив: Android 2.3

Далее сохранены сведения о прежних APK; их размеры и хеши относятся только к указанной версии.

##### Android 2.3.0 (5)

APK **GeckoRush-2.3.apk** собран и проверен. Проверенная [загрузка APK из GitHub Release](https://github.com/pr1decheats/gecko-rush/releases/download/v2.3.0/GeckoRush-2.3.apk) доступна без сайта игры.

| Параметр | Значение |
|---|---|
| Package | `org.geckorush.game` |
| versionName / versionCode | `2.3.0` / `5` |
| Минимальный / целевой API | `24` / `36` |
| Архитектуры | `armeabi-v7a`, `arm64-v8a` |
| Движок | Godot `4.6.3 stable`, Release, Compatibility |
| Размер | `52 075 268` байт |
| Разрешения / отладка | Нет запрошенных разрешений; `debuggable=false` |

```text
SHA-256: 0c1cf65b31644b5eada9a6861faf9dedc94b26b2b4a10ba66315810f5d532f77
```

`apksigner verify`, ZIP CRC, `zipalign -c -P 16` и проверка 16 KB alignment нативных ELF прошли. Сертификат совпадает с прежними APK, совместимое обновление сохраняет локальный прогресс. Это установочная тестовая подпись; AAB и публикация Google Play не выполнялись. APK 2.3 на физическом Android и эмуляторе ещё не запускался.

[Игровая валидация](validation.md), [все файлы и статус IPA](builds.md), [экспорт](mobile-export.md), [историческая подпись и требования магазина](android-2.1.md).

##### Архив: Android 2.2.0

Исторический APK GeckoRush-2.2.apk на [странице скачивания](https://gecko-rush-godot-6e42.honedgrackle2.chatgpt.site). org.geckorush.game, versionCode4, API24+/target36, ARM32/64. Release engine Godot4.6.3 и прежний тестовый ключ для обновления2.1 с сохранением данных.

Подпись/требования магазина: [android-2.1.md](android-2.1.md). Игровые проверки: [validation.md](validation.md). Фактический размер иSHA256 — [builds.md](builds.md).
