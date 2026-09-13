# Публикация PushPort Apple SDK, версия 0.0.1

Библиотека распространяется через **GitHub + Swift Package Manager**. Пользователь добавляет URL репозитория в Xcode. Публиковать саму библиотеку в App Store не требуется. Одна публикация подходит всем клиентам PushPort; их App ID и ключи APNs в библиотеку не включаются.

## Репозиторий и подключение

Публичный репозиторий: [IamFromUA/PushPortLibraryApple](https://github.com/IamFromUA/PushPortLibraryApple). Для подключения нужен URL `https://github.com/IamFromUA/PushPortLibraryApple.git` и версия `0.0.1`. Полная инструкция для клиента: [getting-started.ru.md](getting-started.ru.md).

## Содержимое пакета

Корень репозитория должен содержать `Package.swift`, `Sources`, `Tests`, `Examples`, документацию и `.github/workflows/verify.yml`. Не добавляй родительскую папку `D:\PushPort` целиком. Секретов и `.p8` в пакете быть не должно. Версия API и bridge — `0.0.1`.

GitHub Actions включён. Проверочный workflow не публикует новые версии сам, не использует серверные ключи и не требует Apple Developer account. `.gitignore` исключает локальные настройки IDE, сборки и ключи. Файлы privacy manifest входят в ресурсы обоих продуктов.

## Проверки перед следующими релизами

Нужны актуальный стабильный Xcode с установленным iOS Simulator и выбранный toolchain (`xcode-select`). Workflow делает:

1. `swift test` — хранение, повторы, токены, локали, очередь событий.
2. `xcodebuild` для iOS Simulator — компиляция самого iOS SDK и Notification Service Extension.
3. Тесты iOS-файлов и Objective-C API для KMP.
4. Сборку отдельного iOS-приложения и Notification Service Extension, которые получают пакет из публичного GitHub по проверяемому коммиту. На событие тега этот же consumer получает пакет по точной опубликованной версии.

Локально на Mac запусти `bash scripts/verify-ios.sh` и `bash scripts/verify-consumer.sh` после push проверяемого коммита. Для конкретного опубликованного тега: `PUSHPORT_RELEASE_VERSION=0.0.1 bash scripts/verify-consumer.sh`. Ошибки macOS CI нужно исправить **до** тега. Фактические результаты и ограничения перечислены в [verification.md](verification.md).

Пример AppDelegate и расширения лежит в `Examples`. Для проверки отображения можно использовать `xcrun simctl push booted YOUR_BUNDLE_ID Examples/push.apns` после замены примерного App ID. Эта команда проверяет локальное отображение, а не доставку через APNs. CI-consumer проверяет подключение и линковку; он не запрашивает разрешение и не связывается с сервером PushPort.

## Выпуск версии

После успешных проверок создаём тег `0.0.1` на проверенном коммите и GitHub Release с кратким описанием. SPM скачивает исходники по тегу; отдельный ZIP/XCFramework для этой Swift-библиотеки не нужен. Не перемещаем опубликованные теги: исправления выпускаются новой версией.

Для будущих версий сначала обнови версию SDK/протокольного snapshot, CHANGELOG и примеры установки, выполни проверки, затем создай новый тег и GitHub Release. Коммиты, push и релизы выполняются по команде владельца; команда на текущую публикацию не разрешает будущие публикации автоматически.

Swift Package Index — каталог для поиска пакета и размещения DocC-документации. После первого тега подаётся заявка через [Add a Package](https://swiftpackageindex.com/add-a-package). `.spi.yml` настраивает построение документации для iOS. Индексация выполняется внешним сервисом и не требуется для подключения пакета по URL в Xcode.

## Как подключает клиент

1. Xcode → **File → Add Package Dependencies**.
2. URL опубликованного репозитория, правило **Exact Version → 0.0.1** для первой интеграции.
3. Продукт **PushPort** в основной target приложения.
4. App ID из PushPort в `initialize`, capability Push Notifications и два APNs callback из README.
5. Для картинок — отдельный Notification Service Extension с продуктом **PushPortNotificationService**.

Для **публикации библиотеки** достаточно публичного GitHub и macOS CI. Для следующего этапа **реальной доставки пушей** потребуются Apple Developer, Bundle ID, Team ID, Key ID и `.p8` нужного APNs environment. Эти секреты вводятся на серверной стороне PushPort, не в SDK/репозиторий. Ключи Apple могут иметь ограничения по environment/topic; используем параметры именно выданного ключа.

Серверные изменения этой работы добавляют регистрацию iOS/Web. APNs/Web Push sender и интерфейс его настройки ещё не введены в эксплуатацию. Текущий production не обновлялся; сначала отдельно проверяем пакет, затем подключаем и тестируем доставку.

Официальная справка: [публикация Swift-пакетов](https://developer.apple.com/documentation/xcode/publishing-a-swift-package-with-xcode), [регистрация в APNs](https://developer.apple.com/documentation/usernotifications/registering-your-app-with-apns).
