import XCTest
@testable import PushPortCore

final class MemoryStore: StateStore, @unchecked Sendable {
    private let lock = NSLock()
    private var value: PersistentState?
    func load() -> PersistentState? { lock.lock(); defer { lock.unlock() }; return value }
    func save(_ state: PersistentState) { lock.lock(); defer { lock.unlock() }; value = state }
}

actor FakeTransport: Transport {
    var snapshots: [DeviceSnapshot] = []
    var events: [String] = []
    var failure: PushPortFailure?
    var delay: UInt64 = 0
    var diagnostics: [[NotificationEvent]] = []
    var supportsDiagnostics = false
    func remoteConfiguration(_ configuration: Configuration) async throws -> RemoteConfiguration {
        try await configure(configuration); return RemoteConfiguration(telemetryVersion: supportsDiagnostics ? 1 : 0)
    }
    func telemetry(_ state: PersistentState, events: [NotificationEvent], dropped: Int64) async throws -> [String] {
        if let failure { throw failure }; diagnostics.append(events); return events.map(\.id)
    }
    func enableDiagnostics() { supportsDiagnostics = true }
    func configure(_ configuration: Configuration) async throws { if let failure { throw failure } }
    func register(_ state: PersistentState, snapshot: DeviceSnapshot) async throws {
        if delay > 0 { try await Task.sleep(nanoseconds: delay) }
        if let failure { throw failure }
        snapshots.append(snapshot)
    }
    func opened(_ state: PersistentState, messageId: String) async throws {
        if let failure { throw failure }; events.append(messageId)
    }
    func fail(_ value: PushPortFailure?) { failure = value }
    func setDelay(_ value: UInt64) { delay = value }
}

final class EngineTests: XCTestCase {
    func testImageSettingsRespectAppleCeilingAndRejectUnsafeURLsAndPixelBombs() throws {
        XCTAssertEqual(NotificationImagePolicy.downloadLimit(20 * 1024 * 1024), 10 * 1024 * 1024)
        XCTAssertEqual(NotificationImagePolicy.downloadLimit(1), 5 * 1024 * 1024)
        XCTAssertTrue(NotificationImagePolicy.allows(URL(string: "https://images.example.test/image.png")!))
        for address in ["http://example.test/image", "https://user:pass@example.test/image", "https://127.0.0.1/image", "https://172.20.0.1/image", "https://example.test:8443/image"] { XCTAssertFalse(NotificationImagePolicy.allows(URL(string: address)!)) }
        XCTAssertFalse(NotificationImagePolicy.allowsPixels(width: 4096, height: 4096))
        XCTAssertTrue(NotificationImagePolicy.allowsPixels(width: 2000, height: 1000))
    }
    func testLegacyStorageUpgradePreservesIdentityAndPendingClick() async throws {
        let state = PersistentState.create(try config()); let data = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(PersistentState.self, from: data)
        XCTAssertEqual(decoded.installationId, state.installationId); XCTAssertNil(decoded.supplemental)
        let store = MemoryStore(); store.save(decoded)
        let engine = try InstallationEngine(configuration: config(), store: store, transport: FakeTransport())
        let status = await engine.status(); XCTAssertEqual(status.installationId, state.installationId)
        XCTAssertNotNil(store.load()?.supplemental)
    }
    func testDiagnosticsSurviveRestartAndAcknowledgeStableIdsInBatches() async throws {
        let store = MemoryStore(); let transport = FakeTransport(); await transport.enableDiagnostics()
        let engine = try InstallationEngine(configuration: config(), store: store, transport: transport)
        try await engine.capture(metadata)
        for _ in 0..<105 { try await engine.record(NotificationEvent(type: "session_started", reason: "organic")) }
        let ids = store.load()!.supplemental!.events.map(\.id)
        await transport.fail(.network); do { try await engine.flush(); XCTFail() } catch {}
        XCTAssertEqual(store.load()?.supplemental?.events.map(\.id), ids)
        let restarted = try InstallationEngine(configuration: config(), store: store, transport: transport)
        await transport.fail(nil); try await restarted.flush()
        let batches = await transport.diagnostics
        XCTAssertEqual(batches.map(\.count), [100, 5]); XCTAssertEqual(batches.flatMap { $0.map(\.id) }, ids)
        XCTAssertEqual(store.load()?.supplemental?.events.count, 0)
        XCTAssertEqual(store.load()?.snapshot?.telemetryVersion, 1)
    }
    func testConsentStopsCollectionAndDurableOperationsValidateBeforeQueueing() async throws {
        let store = MemoryStore(); let transport = FakeTransport()
        let engine = try InstallationEngine(configuration: config(), store: store, transport: transport, consentRequired: true)
        try await engine.capture(metadata); try await engine.foreground(); try await engine.flush()
        XCTAssertNil(store.load()?.snapshot); XCTAssertEqual(store.load()?.supplemental?.events.count, 0)
        try await engine.consent(given: true); try await engine.capture(metadata)
        var tags = UserOperation(kind: "tags"); tags.tags = ["buyer": "team1", "removed": nil]
        try await engine.enqueue(tags)
        var bad = UserOperation(kind: "login"); bad.externalId = "victim"
        do { try await engine.enqueue(bad); XCTFail() } catch {}
        XCTAssertEqual(store.load()?.supplemental?.userOperations.count, 1)
        XCTAssertEqual(store.load()?.supplemental?.userOperations.first?.revision, 1)
        try await engine.consent(given: false)
        XCTAssertEqual(store.load()?.supplemental?.userOperations.count, 0)
    }
    func testSessionsDeduplicateShortForegroundTransitionsAndUseMonotonicDuration() async throws {
        let store = MemoryStore(); let engine = try InstallationEngine(configuration: config(), store: store, transport: FakeTransport())
        try await engine.foreground(wallMillis: 100000, uptime: 10); try await engine.foreground(wallMillis: 100000, uptime: 11)
        try await engine.background(wallMillis: 90000, uptime: 12)
        XCTAssertEqual(store.load()?.supplemental?.usage.totalUsageMillis, 2000)
        try await engine.foreground(wallMillis: 90010, uptime: 13)
        XCTAssertEqual(store.load()?.supplemental?.usage.sessionCount, 1)
        try await engine.background(wallMillis: 100000, uptime: 14)
        try await engine.foreground(wallMillis: 140000, uptime: 15)
        XCTAssertEqual(store.load()?.supplemental?.usage.sessionCount, 2)
    }
    func testNotificationInboxIsAppScopedAndDoesNotStoreCredentials() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let inbox = try NotificationInbox(directory: directory)
        let event = NotificationEvent(type: "image_failed", messageId: UUID().uuidString.lowercased(), reason: "too_large")
        try inbox.append(appId: appId, event: event); let values = try inbox.read(appId: appId)
        XCTAssertEqual(values.count, 1); XCTAssertEqual(values[0].1, event)
        XCTAssertEqual(try inbox.read(appId: UUID().uuidString.lowercased()).count, 0)
        try inbox.remove(values[0].0); XCTAssertEqual(try inbox.read(appId: appId).count, 0)
    }
    let appId = "00000000-0000-4000-8000-000000000001"
    var metadata: DeviceMetadata {
        DeviceMetadata(locale: "en-US", appLocales: ["en-US"], systemLocales: ["de-DE", "en-US"], timezone: "Europe/Berlin",
                       notificationsEnabled: true, appVersion: "1.0", osVersion: "18", model: "iPhone")
    }
    func config() throws -> Configuration { try Configuration(appId: appId, bundleId: "dev.pushport.example", environment: .sandbox) }

    func testIdentitySurvivesRestartAndRejectsRebinding() async throws {
        let store = MemoryStore()
        let first = try InstallationEngine(configuration: config(), store: store, transport: FakeTransport())
        let firstStatus = await first.status()
        let second = try InstallationEngine(configuration: config(), store: store, transport: FakeTransport())
        let secondStatus = await second.status()
        XCTAssertEqual(firstStatus.installationId, secondStatus.installationId)
        XCTAssertEqual(store.load()?.secret.count, 43)
        XCTAssertThrowsError(try InstallationEngine(configuration: Configuration(appId: UUID().uuidString.lowercased(), bundleId: "dev.pushport.other"), store: store))
    }
    func testFailedSyncIsDurableAndNewTokenDoesNotResetOptOut() async throws {
        let store = MemoryStore(); let transport = FakeTransport()
        let engine = try InstallationEngine(configuration: config(), store: store, transport: transport)
        try await engine.capture(metadata)
        try await engine.setToken(Data([0, 1, 255]))
        try await engine.setSubscribed(false)
        await transport.fail(.network)
        do { try await engine.flush(); XCTFail("Expected offline failure") } catch {}
        XCTAssertEqual(store.load()?.snapshot?.pushToken, "0001ff")
        XCTAssertEqual(store.load()?.acknowledgedRevision, 0)
        let restarted = try InstallationEngine(configuration: config(), store: store, transport: transport)
        await transport.fail(nil)
        try await restarted.capture(metadata)
        try await restarted.setToken(Data([2, 3]))
        try await restarted.flush()
        let sent = await transport.snapshots
        XCTAssertEqual(sent.last?.pushSubscribed, false)
        XCTAssertEqual(sent.last?.pushToken, "0203")
        XCTAssertEqual(sent.last?.platform, "IOS")
        XCTAssertEqual(sent.last?.apnsEnvironment, .sandbox)
        XCTAssertNil(store.load()?.syncError)
    }
    func testNewRevisionDuringNetworkIsEventuallyAcknowledged() async throws {
        let store = MemoryStore(); let transport = FakeTransport()
        let engine = try InstallationEngine(configuration: config(), store: store, transport: transport)
        try await engine.capture(metadata)
        await transport.setDelay(30_000_000)
        let flush = Task { try await engine.flush() }
        try await Task.sleep(nanoseconds: 5_000_000)
        try await engine.setLocale("uk-UA")
        try await engine.setSubscribed(false)
        try await flush.value
        let snapshots = await transport.snapshots
        XCTAssertEqual(snapshots.last?.locale, "uk-UA")
        XCTAssertEqual(snapshots.last?.pushSubscribed, false)
        XCTAssertEqual(store.load()?.acknowledgedRevision, store.load()?.revision)
    }
    func testEventsAreAppScopedDeduplicatedAndRetried() async throws {
        let store = MemoryStore(); let transport = FakeTransport()
        let engine = try InstallationEngine(configuration: config(), store: store, transport: transport)
        let message = UUID().uuidString.lowercased()
        try await engine.opened(appId: "wrong", messageId: message)
        try await engine.opened(appId: appId, messageId: "bad")
        XCTAssertEqual(store.load()?.pendingEvents, [])
        try await engine.opened(appId: appId, messageId: message)
        try await engine.opened(appId: appId, messageId: message)
        XCTAssertEqual(store.load()?.pendingEvents, [message])
        await transport.fail(.http(503))
        do { try await engine.flush(); XCTFail("Expected 503") } catch {}
        await transport.fail(nil)
        try await engine.flush()
        let sent = await transport.events
        XCTAssertEqual(sent, [message])
        XCTAssertEqual(store.load()?.pendingEvents, [])
    }
    func testConfigurationAndLocaleValidation() throws {
        XCTAssertThrowsError(try Configuration(appId: appId, serverURL: URL(string: "https://user:password@example.com")!, bundleId: "app"))
        XCTAssertThrowsError(try Configuration(appId: appId, serverURL: URL(string: "http://example.com")!, bundleId: "app", allowInsecureLocalhost: true))
        XCTAssertNoThrow(try Configuration(appId: appId, serverURL: URL(string: "http://localhost:15793")!, bundleId: "app", allowInsecureLocalhost: true))
        XCTAssertThrowsError(try Configuration.locale("und"))
        XCTAssertThrowsError(try Configuration.locale("../../private"))
        XCTAssertEqual(try Configuration.locale("de-DE"), "de-DE")
    }
    func testFileStoreRoundTripAndCorruptionDoesNotSilentlyResetIdentity() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = try FileStateStore(directory: directory)
        XCTAssertNil(try store.load())
        let state = PersistentState.create(try config())
        try store.save(state)
        XCTAssertEqual(try store.load()?.installationId, state.installationId)
        try Data("broken".utf8).write(to: directory.appendingPathComponent("installation-v1.json"))
        XCTAssertThrowsError(try store.load())
    }
}
