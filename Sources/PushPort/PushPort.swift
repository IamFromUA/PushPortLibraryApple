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
    public static let version = "0.0.2"
    /// Called on the main actor; registering a callback does not replace the host notification delegate.
    public var onStatusChange: ((Status) -> Void)?
    public var onNotificationOpened: ((PushPortNotification) -> Void)?
    public private(set) var status: Status?
    public private(set) var registrationError: String?
    public private(set) var user: PushPortUser?
    private var consentRequired: Bool?
    private var consentGiven: Bool?
    private var groupDirectory: URL?
    private var notificationInbox: NotificationInbox?
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
        engine = try InstallationEngine(configuration: config, store: store, consentRequired: consentRequired, consentGiven: consentGiven)
        configuration = config
        if let group = Bundle.main.object(forInfoDictionaryKey: "PushPortAppGroup") as? String,
           let directory = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) {
            groupDirectory = directory; notificationInbox = try NotificationInbox(directory: directory)
        }
        if manageNotificationDelegate {
            let center = UNUserNotificationCenter.current()
            let delegate = NotificationDelegate(owner: self, forwarding: center.delegate)
            notificationDelegate = delegate; center.delegate = delegate
        }
        for name in [UIApplication.didBecomeActiveNotification, NSLocale.currentLocaleDidChangeNotification,
                     NSNotification.Name.NSSystemTimeZoneDidChange] {
            observerTokens.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    if name == UIApplication.didBecomeActiveNotification, let engine = self?.engine { try? await engine.foreground() }
                    self?.sync()
                }
            })
        }
        observerTokens.append(NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in if let engine = self?.engine { try? await engine.background(); self?.sync() } }
        })
        let monitor = NWPathMonitor()
        monitor.pathUpdateHandler = { [weak self] path in
            if path.status == .satisfied { Task { @MainActor in self?.sync() } }
        }
        monitor.start(queue: DispatchQueue(label: "dev.pushport.connectivity")); self.monitor = monitor
        Task { @MainActor in if let engine = self.engine, await engine.collectionAllowed() { UIApplication.shared.registerForRemoteNotifications() } }
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
        guard let engine else { throw PushPortFailure.notInitialized }
        guard await engine.collectionAllowed() else { throw PushPortFailure.invalidConfiguration }
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
        PushPortNotification(userInfo: notification.request.content.userInfo)?.appId == configuration?.appId
    }

    func presented(_ notification: UNNotification, options: UNNotificationPresentationOptions) {
        guard let value = PushPortNotification(userInfo: notification.request.content.userInfo), value.appId == configuration?.appId, let engine else { return }
        Task { try? await engine.record(NotificationEvent(type: "received", messageId: value.messageId))
            try? await engine.record(NotificationEvent(type: options.isEmpty ? "not_displayed" : "posted", messageId: value.messageId, reason: options.isEmpty ? "foreground_suppressed" : nil)); await synchronize() }
    }

    /// Consent controls can be set before initialization. Revocation stops collection and clears unsent data.
    public func setConsentRequired(_ value: Bool) async throws { consentRequired = value; if let engine { try await engine.consent(required: value); if await engine.collectionAllowed() { UIApplication.shared.registerForRemoteNotifications() }; await synchronize() } }
    public func setConsentGiven(_ value: Bool) async throws { consentGiven = value; if let engine { try await engine.consent(given: value); if value { UIApplication.shared.registerForRemoteNotifications(); if UIApplication.shared.applicationState == .active { try await engine.foreground() } }; await synchronize() } }
    public func setTags(_ tags: [String: String?]) async throws { var operation = UserOperation(kind: "tags"); operation.tags = tags; try await mutate(operation) }
    public func login(externalId: String, identityToken: String) async throws { var operation = UserOperation(kind: "login"); operation.externalId = externalId; operation.identityToken = identityToken; try await mutate(operation) }
    public func logout() async throws { try await mutate(UserOperation(kind: "logout")) }
    public func setEmail(_ email: String?) async throws { var operation = UserOperation(kind: "email"); operation.email = email; try await mutate(operation) }
    public func setPhoneNumber(_ number: String?) async throws { var operation = UserOperation(kind: "phone"); operation.phoneNumber = number; try await mutate(operation) }
    public func setLocation(latitude: Double?, longitude: Double?) async throws { var operation = UserOperation(kind: "location"); operation.latitude = latitude; operation.longitude = longitude; try await mutate(operation) }
    public func trackEvent(_ name: String, properties: [String: String] = [:]) async throws { var operation = UserOperation(kind: "event"); operation.eventName = name; operation.eventProperties = properties; try await mutate(operation) }
    func mutate(_ operation: UserOperation) async throws { guard let engine else { throw PushPortFailure.notInitialized }; try await engine.enqueue(operation); await synchronize() }

    private func synchronize() async {
        guard let engine else { return }
        let allowed = await engine.collectionAllowed()
        if let directory = groupDirectory, let config = configuration {
            struct Consent: Encodable { let appId: String; let allowed: Bool }
            try? JSONEncoder().encode(Consent(appId: config.appId, allowed: allowed)).write(to: directory.appendingPathComponent("PushPortNotificationConsent.json"), options: .atomic)
        }
        if let inbox = notificationInbox, let config = configuration, let events = try? inbox.read(appId: config.appId) {
            for (file, event) in events { do { if allowed { try await engine.record(event) }; try inbox.remove(file) } catch { break } }
        }
        guard allowed else { await refreshStatus(); return }
        if UIApplication.shared.applicationState == .active { try? await engine.foreground() }
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
        user = await engine.user()
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
