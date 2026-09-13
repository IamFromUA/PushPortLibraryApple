// SPDX-FileCopyrightText: 2026 Oleh Yurkov
// SPDX-License-Identifier: Apache-2.0
@_exported import PushPortCore
#if os(iOS)
import Foundation
import UIKit
import UserNotifications
import Network

/// Native iOS SDK. Call on the main actor, normally from application launch.
@MainActor
public final class PushPort {
    public static let shared = PushPort()
    public static let version = "0.0.1"
    /// Called on the main actor; registering a callback does not replace the host notification delegate.
    public var onStatusChange: ((Status) -> Void)?
    public var onNotificationOpened: ((PushPortNotification) -> Void)?
    public private(set) var status: Status?
    public private(set) var registrationError: String?
    private var engine: InstallationEngine?
    private var configuration: Configuration?
    private var observerTokens: [NSObjectProtocol] = []
    private var notificationDelegate: NotificationDelegate?
    private var retry: Task<Void, Never>?
    private var failures = 0
    private var monitor: NWPathMonitor?
    private init() {}

    /// Initialization saves an installation, but does not prompt for notification permission.
    /// Select the environment matching the signed app's aps-environment entitlement.
    public func initialize(appId: String, environment: APNsEnvironment = .production,
                           serverURL: URL = URL(string: "https://pushport.dev")!,
                           manageNotificationDelegate: Bool = true,
                           allowInsecureLocalhost: Bool = false) throws {
        guard let bundleId = Bundle.main.bundleIdentifier else { throw PushPortFailure.invalidConfiguration }
        #if DEBUG
        let allowLocal = allowInsecureLocalhost
        #else
        let allowLocal = false
        #endif
        let config = try Configuration(appId: appId, serverURL: serverURL, bundleId: bundleId,
                                       environment: environment, allowInsecureLocalhost: allowLocal)
        if let configuration {
            guard configuration == config else { throw PushPortFailure.configurationConflict }
            sync(); return
        }
        let support = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                  appropriateFor: nil, create: true)
        let store = try FileStateStore(directory: support.appendingPathComponent("PushPort", isDirectory: true))
        engine = try InstallationEngine(configuration: config, store: store)
        configuration = config
        if manageNotificationDelegate {
            let center = UNUserNotificationCenter.current()
            let delegate = NotificationDelegate(owner: self, forwarding: center.delegate)
            notificationDelegate = delegate; center.delegate = delegate
        }
        for name in [UIApplication.didBecomeActiveNotification, NSLocale.currentLocaleDidChangeNotification,
                     NSNotification.Name.NSSystemTimeZoneDidChange] {
            observerTokens.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.sync() }
            })
        }
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            if path.status == .satisfied { Task { @MainActor in self?.sync() } }
        }
        monitor.start(queue: DispatchQueue(label: "dev.pushport.connectivity")); self.monitor = monitor
        UIApplication.shared.registerForRemoteNotifications()
        sync()
    }

    /// Call from the host's didRegisterForRemoteNotificationsWithDeviceToken callback.
    public func didRegisterForRemoteNotifications(deviceToken: Data) {
        guard let engine else { return }
        registrationError = nil
        Task { do { try await engine.setToken(deviceToken); await synchronize() } catch { await refreshStatus() } }
    }
    /// Call from the host's didFailToRegisterForRemoteNotificationsWithError callback.
    public func didFailToRegisterForRemoteNotifications(error: Error) {
        // Never forward platform error text that could contain device-specific data.
        registrationError = "APNs registration failed. Verify network access and Push Notifications capability."
    }

    /// Request from a visible UI after explaining the benefit. Does not bypass a previous denial.
    @discardableResult
    public func requestPermission() async throws -> Bool {
        guard engine != nil else { throw PushPortFailure.notInitialized }
        let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
        UIApplication.shared.registerForRemoteNotifications()
        await synchronize()
        return granted
    }
    /// Preference is persisted locally and queued for the server. APNs alerts already in flight may still appear.
    public func setSubscribed(_ value: Bool) async throws {
        guard let engine else { throw PushPortFailure.notInitialized }
        try await engine.setSubscribed(value); await synchronize()
    }
    public func setLocale(_ languageTag: String?) async throws {
        guard let engine else { throw PushPortFailure.notInitialized }
        try await engine.setLocale(languageTag); await synchronize()
    }
    /// Schedules a metadata capture. Pending changes retry with backoff and on foreground/connectivity.
    public func sync() { guard engine != nil else { return }; Task { await synchronize() } }

    /// For hosts that own their notification delegate. Returns false for notifications from another app/provider.
    @discardableResult
    public func handleNotificationResponse(_ response: UNNotificationResponse) -> Bool {
        guard let config = configuration, let notification = PushPortNotification(userInfo: response.notification.request.content.userInfo),
              notification.appId == config.appId else { return false }
        // Dismissals are not opens. Custom actions are user interactions and count as opens.
        guard response.actionIdentifier != UNNotificationDismissActionIdentifier else { return true }
        if let engine {
            Task { try? await engine.opened(appId: notification.appId, messageId: notification.messageId); await synchronize() }
        }
        onNotificationOpened?(notification)
        return true
    }

    func recognizes(_ notification: UNNotification) -> Bool {
        (notification.request.content.userInfo["pushport_app_id"] as? String) == configuration?.appId
    }

    private func synchronize() async {
        guard let engine else { return }
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        let authorized = [.authorized, .provisional, .ephemeral].contains(settings.authorizationStatus)
        let system = Locale.preferredLanguages.compactMap { try? Configuration.locale($0) }
        let app = Bundle.main.preferredLocalizations.compactMap { try? Configuration.locale($0) }
        let locale = app.first ?? system.first ?? "en"
        let metadata = DeviceMetadata(locale: locale, appLocales: Array((app.isEmpty ? [locale] : app).prefix(30)),
                                      systemLocales: Array((system.isEmpty ? [locale] : system).prefix(30)),
                                      timezone: TimeZone.current.identifier, notificationsEnabled: authorized,
                                      appVersion: String((Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "").prefix(100)),
                                      osVersion: UIDevice.current.systemVersion, model: UIDevice.current.model)
        do {
            try await engine.capture(metadata)
            await refreshStatus()
            try await engine.flush()
            failures = 0; retry?.cancel(); retry = nil
        } catch {
            if let failure = error as? PushPortFailure, failure.retryable, failures < 6 {
                let delay = min(60.0, pow(2, Double(failures))) + Double.random(in: 0...0.5)
                failures += 1; retry?.cancel()
                retry = Task { [weak self] in
                    do { try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000)) }
                    catch { return }
                    await self?.synchronize()
                }
            }
        }
        await refreshStatus()
    }
    private func refreshStatus() async {
        guard let engine else { return }
        let updated = await engine.status()
        if status != updated { status = updated; onStatusChange?(updated) }
    }
}

/// Validated PushPort notification. Custom URL navigation is controlled by the host.
public struct PushPortNotification: Sendable {
    public let appId: String
    public let messageId: String
    public let clickURL: URL?
    init?(userInfo: [AnyHashable: Any]) {
        guard let appId = userInfo["pushport_app_id"] as? String, Configuration.isUUID(appId),
              let messageId = userInfo["pushport_message_id"] as? String, Configuration.isUUID(messageId) else { return nil }
        self.appId = appId; self.messageId = messageId
        if let value = userInfo["click_url"] as? String, let url = URL(string: value), url.scheme == "https",
           url.host != nil, url.user == nil, url.password == nil { clickURL = url } else { clickURL = nil }
    }
}
#endif
