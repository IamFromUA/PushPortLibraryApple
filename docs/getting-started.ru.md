# Подключение PushPort к iOS-приложению

## 1. Добавить библиотеку

В Xcode: **File → Add Package Dependencies** → URL:

```text
https://github.com/IamFromUA/PushPortLibraryApple.git
```

Выбери **Exact Version → 0.0.1**, затем продукт **PushPort** для основного target приложения. Минимальная версия iOS — 15.0. Исходники и зависимости скачает Swift Package Manager. Учётная запись Apple не нужна для скачивания SDK.

## 2. Подготовить приложение

Для настоящих APNs-пушей нужны платный Apple Developer account, зарегистрированный Bundle ID и capability **Push Notifications** в Xcode → Signing & Capabilities. Эти настройки относятся к приложению клиента, а не к библиотеке.

На стороне сервиса PushPort приложению должен соответствовать тот же Bundle ID и правильное окружение APNs. Версия SDK 0.0.1 подготовлена для серверного контракта из [protocol.md](protocol.md). Отправщик APNs и его настройка в рабочей админке требуют отдельного этапа; одна установка библиотеки не включает доставку.

## 3. Инициализировать SDK

Пример для SwiftUI:

```swift
import SwiftUI
import UIKit
import PushPort

@main
@MainActor
struct MyApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    var body: some Scene { WindowGroup { ContentView() } }
}

@MainActor
final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions options: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        do {
            try PushPort.shared.initialize(
                appId: "YOUR_PUSHPORT_APP_ID",
                environment: .sandbox
            )
        } catch {
            // Передай ошибку в свою диагностику, без токенов и секретов.
        }
        return true
    }

    func application(_ application: UIApplication,
                     didRegisterForRemoteNotificationsWithDeviceToken token: Data) {
        PushPort.shared.didRegisterForRemoteNotifications(deviceToken: token)
    }

    func application(_ application: UIApplication,
                     didFailToRegisterForRemoteNotificationsWithError error: Error) {
        PushPort.shared.didFailToRegisterForRemoteNotifications(error: error)
    }
}
```

В UIKit добавь эти вызовы в существующий AppDelegate. Для подписанного приложения выбирай окружение по entitlement `aps-environment`: development → `.sandbox`, production → `.production`. В TestFlight и App Store используется production. App ID, URL сервера и окружение закрепляются за установкой; SDK не меняет их незаметно при повторной инициализации.

## 4. Запросить разрешение

SDK не показывает системный диалог сам. Запроси разрешение из понятного пользователю действия:

```swift
Button("Включить уведомления") {
    Task { @MainActor in
        do {
            let granted = try await PushPort.shared.requestPermission()
            // Обнови интерфейс с учётом granted.
        } catch {
            // Покажи понятную ошибку.
        }
    }
}
```

После отказа системное разрешение меняется в Settings. Отдельно можно управлять подпиской внутри приложения: `try await PushPort.shared.setSubscribed(false)` или `true`. Подписка сохраняется и синхронизируется при восстановлении сети. Уже отправленные APNs-уведомления могут дойти после отключения подписки.

## 5. Язык, статус и нажатия

Язык приложения, системные языки, часовой пояс и разрешение собираются автоматически. `setLocale("uk-UA")` задаёт предпочтительный язык, `setLocale(nil)` возвращает автоматическое определение. Статус доступен через `status` и `onStatusChange`. Нажатия приходят в `onNotificationOpened`; переход по ссылке выполняет само приложение.

Не помещай `.p8`, Team ID/Key ID с приватным ключом или другие серверные секреты в приложение. SDK передаёт собственный случайный installation ID и APNs-токен по HTTPS. Аппаратные и рекламные идентификаторы iOS не собираются.

## 6. Картинки в уведомлениях

Создай отдельный target **Notification Service Extension** и подключи к нему продукт **PushPortNotificationService**. Используй [пример расширения](../Examples/NotificationService). В полезной нагрузке нужны `aps.mutable-content: 1`, `pushport_app_id` и HTTPS-поле `image_url`. При ошибке загрузки останется текст уведомления.

Следующий этап после установки — отдельное тестовое приложение на Mac и проверка серверной доставки. Подробный список сценариев: [testing.md](testing.md).
