# Публикация PushPort Apple SDK, версия 0.0.1

Библиотека распространяется через **GitHub + Swift Package Manager**. Пользователь добавляет URL репозитория в Xcode. Публиковать саму библиотеку в App Store не требуется. Одна публикация подходит всем клиентам PushPort; их App ID и ключи APNs в библиотеку не включаются.

## 1. Создать репозиторий

Создай пустой публичный репозиторий, например `PushPortLibraryApple`, в нужном GitHub-аккаунте. Не добавляй README, лицензию или gitignore через GitHub: они уже есть в этой папке. Пришли URL — подключение репозитория, коммит и push будем выполнять по отдельной команде.

## 2. Перенести подготовленный пакет в Git

Корень репозитория должен содержать `Package.swift`, `Sources`, `Tests`, `Examples`, документацию и `.github/workflows/verify.yml`. Не добавляй родительскую папку `D:\PushPort` целиком. Секретов и `.p8` в пакете быть не должно. Версия API и bridge — `0.0.1`.

В репозитории включи GitHub Actions. Проверочный workflow не публикует пакет, не использует серверные ключи и не требует Apple Developer account.

## 3. Проверить на macOS до релиза

Нужны актуальный стабильный Xcode с установленным iOS Simulator и выбранный toolchain (`xcode-select`). Workflow делает:

1. `swift test` — хранение, повторы, токены, локали, очередь событий.
2. `xcodebuild` для iOS Simulator — компиляция самого iOS SDK и Notification Service Extension.
3. Тесты iOS-файлов и Objective-C API для KMP.

Локально на Mac запусти `bash scripts/verify-ios.sh`. Здесь, на Windows, были проверены переносимый Swift-код и структура пакета; это не заменяет эту проверку. Ошибки macOS CI нужно исправить **до** тега.

После проверки добавим пакет как локальную зависимость в отдельное тестовое iOS-приложение. Пример AppDelegate и расширения уже лежит в `Examples`. Для проверки отображения можно использовать `xcrun simctl push booted YOUR_BUNDLE_ID Examples/push.apns` после замены примерного App ID. Эта команда проверяет локальное отображение, а не доставку через APNs.

## 4. Выпустить 0.0.1

После успешных проверок создаём тег `0.0.1` на проверенном коммите и GitHub Release с кратким описанием. SPM скачивает исходники по тегу; отдельный ZIP/XCFramework для этой Swift-библиотеки не нужен. Не перемещаем опубликованные теги: исправления выпускаются новой версией.

Публикацию, коммит, push и тег выполняем только после твоей команды. В этой работе ничего из перечисленного не выполнялось.

## 5. Как будет подключать клиент

1. Xcode → **File → Add Package Dependencies**.
2. URL опубликованного репозитория, правило версии **Up to Next Major**, начиная с `0.0.1` (для более строгой фиксации — Exact Version).
3. Продукт **PushPort** в основной target приложения.
4. App ID из PushPort в `initialize`, capability Push Notifications и два APNs callback из README.
5. Для картинок — отдельный Notification Service Extension с продуктом **PushPortNotificationService**.

Для **публикации библиотеки** от тебя нужен только публичный репозиторий и возможность выполнить macOS CI. Для следующего этапа **реальной доставки пушей** потребуются Apple Developer, Bundle ID, Team ID, Key ID и `.p8` нужного APNs environment. Эти секреты вводятся на серверной стороне PushPort, не в SDK/репозиторий. Ключи Apple могут иметь ограничения по environment/topic; используем параметры именно выданного ключа.

Серверные изменения этой работы добавляют регистрацию iOS/Web. APNs/Web Push sender и интерфейс его настройки ещё не введены в эксплуатацию. Текущий production не обновлялся; сначала отдельно проверяем пакет, затем подключаем и тестируем доставку.

Официальная справка: [публикация Swift-пакетов](https://developer.apple.com/documentation/xcode/publishing-a-swift-package-with-xcode), [регистрация в APNs](https://developer.apple.com/documentation/usernotifications/registering-your-app-with-apns).
