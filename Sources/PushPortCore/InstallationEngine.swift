import Foundation

/// Actor serializes persistence. A snapshot is committed before any HTTP request.
public actor InstallationEngine {
    private var state: PersistentState
    private let store: any StateStore
    private let transport: any Transport
    private let sharedDirectory: URL?
    private var metadata: DeviceMetadata?
    private var flushing = false
    private var validated = false
    private var configuredAt: Date?
    private var foregroundAt: TimeInterval?

    public init(configuration: Configuration, store: any StateStore, transport: any Transport = HTTPTransport(), consentRequired: Bool? = nil, consentGiven: Bool? = nil, sharedDirectory: URL? = nil) throws {
        self.store = store; self.transport = transport
        self.sharedDirectory = sharedDirectory
        if let saved = try store.load() {
            guard saved.schema == 1, saved.configuration == configuration else { throw PushPortFailure.configurationConflict }
            state = saved
        } else { state = .create(configuration) }
        try Self.persistConsent(&state, required: consentRequired, given: consentGiven, store: store, directory: sharedDirectory)
    }
    public func status() -> Status {
        var result = state.status
        result.profileChecked = validated || !collectionAllowed()
        return result
    }
    public func user() -> PushPortUser? { state.supplemental?.user }
    public func collectionAllowed() -> Bool { state.supplemental?.collectionAllowed ?? true }
    public func imageLimitBytes() -> Int { state.supplemental?.imageLimitBytes ?? 5 * 1024 * 1024 }
    public func consent(required: Bool? = nil, given: Bool? = nil) throws {
        try Self.persistConsent(&state, required: required, given: given, store: store, directory: sharedDirectory)
        if !collectionAllowed() { foregroundAt = nil; validated = false }
    }

    private static func persistConsent(_ state: inout PersistentState, required: Bool?, given: Bool?, store: any StateStore, directory: URL?) throws {
        var next = state
        var extra = next.supplemental ?? SupplementalState()
        if let required { extra.consentRequired = required }
        if let given { extra.consentGiven = given }
        let consent = NotificationConsent(appId: state.configuration.appId, allowed: extra.collectionAllowed)
        if !consent.allowed {
            extra.appProfile = nil
            extra.events.removeAll()
            extra.userOperations.removeAll()
            next.pendingEvents.removeAll()
        }
        next.supplemental = extra
        if !consent.allowed {
            state = next
            do {
                if let directory { try consent.save(in: directory) }
            } catch {
                try store.save(next)
                throw error
            }
        }
        try store.save(next)
        state = next
        if consent.allowed, let directory { try consent.save(in: directory) }
    }
    public func enqueue(_ operation: UserOperation) throws {
        try operation.validate()
        guard collectionAllowed() else { throw PushPortFailure.invalidConfiguration }
        var extra = state.supplemental ?? SupplementalState()
        if operation.kind == "login", let first = extra.userOperations.first,
           first.kind == "login", first.externalId == operation.externalId {
            extra.userOperations[0].identityToken = operation.identityToken
            state.supplemental = extra
            try store.save(state)
            return
        }
        if ["login", "logout"].contains(operation.kind) { extra.userOperations = []; extra.user = nil }
        guard extra.userOperations.count < 100 else { throw PushPortFailure.storageUnavailable }
        extra.userRevision = max(extra.userRevision, extra.user?.revision ?? 0) + 1
        var operation = operation; operation.revision = extra.userRevision; extra.userOperations.append(operation)
        state.supplemental = extra; try store.save(state)
    }
    public func record(_ event: NotificationEvent) throws {
        guard collectionAllowed(), Configuration.isUUID(event.id), event.messageId.map(Configuration.isUUID) ?? true else { return }
        var extra = state.supplemental ?? SupplementalState()
        if extra.events.contains(where: { $0.id == event.id }) { return }
        if event.type == "received", let messageId = event.messageId {
            if extra.receivedMessages.contains(messageId) { return }
            extra.receivedMessages = Array((extra.receivedMessages + [messageId]).suffix(200)); extra.lastReceived = event
        }
        if event.type == "clicked" { extra.lastClicked = event }
        extra.events.append(event)
        if extra.events.count > 1000 { extra.dropped += Int64(extra.events.count - 1000); extra.events = Array(extra.events.suffix(1000)) }
        state.supplemental = extra; try store.save(state)
    }
    public func foreground(wallMillis: Int64 = Int64(Date().timeIntervalSince1970 * 1000), uptime: TimeInterval = ProcessInfo.processInfo.systemUptime) throws {
        guard foregroundAt == nil, collectionAllowed() else { return }; foregroundAt = uptime
        var extra = state.supplemental ?? SupplementalState()
        let fresh = extra.usage.sessionCount == 0 || wallMillis - extra.lastActivityAt >= 30000 || wallMillis < extra.lastActivityAt
        if fresh {
            extra.usage.firstSessionAt = extra.usage.firstSessionAt ?? wallMillis; extra.usage.lastSessionAt = max(wallMillis, extra.usage.lastSessionAt ?? wallMillis); extra.usage.sessionCount += 1
        }
        extra.lastActivityAt = wallMillis; state.supplemental = extra
        if fresh {
            let direct = extra.lastClicked.map { (0...60000).contains(wallMillis - $0.occurredAt) } ?? false
            let influenced = extra.lastReceived.map { $0.messageId != extra.lastClicked?.messageId && (0...3600000).contains(wallMillis - $0.occurredAt) } ?? false
            try record(NotificationEvent(type: "session_started", messageId: direct ? extra.lastClicked?.messageId : influenced ? extra.lastReceived?.messageId : nil, reason: direct ? "direct" : influenced ? "influenced" : "organic"))
        } else { try store.save(state) }
    }
    public func background(wallMillis: Int64 = Int64(Date().timeIntervalSince1970 * 1000), uptime: TimeInterval = ProcessInfo.processInfo.systemUptime) throws {
        guard let started = foregroundAt else { return }; foregroundAt = nil
        guard collectionAllowed() else { return }
        let duration = Int64(min(604800000, max(0, (uptime - started) * 1000)))
        state.supplemental?.usage.totalUsageMillis += duration; state.supplemental?.lastActivityAt = wallMillis
        try record(NotificationEvent(type: "session_ended", durationMillis: duration)); try commitSnapshot()
    }

    public func capture(_ metadata: DeviceMetadata) throws {
        guard collectionAllowed() else { return }
        self.metadata = metadata
        try commitSnapshot()
    }
    public func setToken(_ token: Data) throws {
        guard collectionAllowed() else { return }
        guard !token.isEmpty, token.count <= 256 else { throw PushPortFailure.invalidConfiguration }
        state.token = token.map { String(format: "%02x", $0) }.joined()
        try commitSnapshot()
    }
    public func setSubscribed(_ value: Bool) throws { state.subscribed = value; try commitSnapshot() }
    public func setLocale(_ value: String?) throws {
        state.localeOverride = try value.map(Configuration.locale)
        try commitSnapshot()
    }
    public func opened(appId: String, messageId: String) throws {
        guard collectionAllowed(), appId == state.configuration.appId, Configuration.isUUID(messageId) else { return }
        if !state.pendingEvents.contains(messageId) {
            state.pendingEvents.append(messageId)
            state.pendingEvents = Array(state.pendingEvents.suffix(100))
            try store.save(state)
            try record(NotificationEvent(type: "clicked", messageId: messageId))
        }
    }
    private func commitSnapshot() throws {
        if let metadata {
            let snapshot = state.makeSnapshot(metadata)
            state.snapshot = snapshot; state.revision = snapshot.revision
        } else if var snapshot = state.snapshot, snapshot.telemetryVersion != state.supplemental?.telemetryVersion {
            state.revision += 1; snapshot.revision = state.revision
            snapshot.telemetryVersion = state.supplemental?.telemetryVersion
            snapshot.usage = state.supplemental?.usage; state.snapshot = snapshot
        }
        try store.save(state)
    }

    private func flushUsers() async throws {
        if collectionAllowed(), state.supplemental?.userProfileVersion == 1 {
            while let operation = state.supplemental?.userOperations.first {
                guard collectionAllowed() else { break }
                if operation.kind == "login", operation.identityToken == nil { throw PushPortFailure.identityTokenRequired }
                let profile: PushPortUser
                do { profile = try await transport.user(state, operation: operation) }
                catch PushPortFailure.http(401) where operation.kind == "login" {
                    guard let first = state.supplemental?.userOperations.first,
                          first.revision == operation.revision, first.identityToken == operation.identityToken else { continue }
                    state.supplemental?.userOperations[0].identityToken = nil
                    try store.save(state)
                    throw PushPortFailure.identityTokenRequired
                }
                guard collectionAllowed(), state.supplemental?.userOperations.first?.revision == operation.revision else { continue }
                state.supplemental?.userOperations.removeAll { $0.revision == operation.revision }
                if state.supplemental?.userOperations.contains(where: { ["login", "logout"].contains($0.kind) }) != true { state.supplemental?.user = profile }
                try store.save(state)
            }
            if state.supplemental?.user == nil, collectionAllowed() {
                let profile = try await transport.user(state, operation: nil)
                if collectionAllowed(), state.supplemental?.userOperations.isEmpty == true { state.supplemental?.user = profile; try store.save(state) }
            }
        }
    }

    private func flushTelemetry() async throws {
        for _ in 0..<10 {
            guard collectionAllowed(), state.supplemental?.telemetryVersion == 1, let events = state.supplemental?.events, !events.isEmpty else { break }
            let batch = Array(events.prefix(100)); let sent = Set(batch.map(\.id))
            let accepted: Set<String>
            do { accepted = Set(try await transport.telemetry(state, events: batch, dropped: state.supplemental?.dropped ?? 0)).intersection(sent) }
            catch PushPortFailure.http(let status) where status == 404 || status == 405 { state.supplemental?.telemetryVersion = 0; try store.save(state); break }
            if accepted.isEmpty { break }
            state.supplemental?.events.removeAll { accepted.contains($0.id) }; try store.save(state)
        }
    }

    /// Concurrent calls coalesce. New revisions arriving during HTTP are sent before the loop exits.
    public func flush(onConfiguration: (@Sendable () async -> Void)? = nil) async throws {
        guard !flushing, collectionAllowed() else { return }
        flushing = true
        defer { flushing = false }
        do {
            if !validated || configuredAt.map({ Date().timeIntervalSince($0) > 60 }) == true {
                let remote = try await transport.remoteConfiguration(state.configuration)
                guard collectionAllowed() else { return }
                state.supplemental?.appProfile = remote.appProfile
                state.supplemental?.telemetryVersion = remote.telemetryVersion
                state.supplemental?.userProfileVersion = remote.userProfileVersion
                state.supplemental?.imageLimitBytes = remote.imageLimitBytes
                try commitSnapshot()
                validated = true; configuredAt = Date()
                await onConfiguration?()
            }
            while true {
                guard collectionAllowed() else { break }
                if let snapshot = state.snapshot, snapshot.revision > state.acknowledgedRevision {
                    let sent = state
                    try await transport.register(sent, snapshot: snapshot)
                    state.acknowledgedRevision = max(state.acknowledgedRevision, snapshot.revision)
                    state.lastSyncedAt = Int64(Date().timeIntervalSince1970 * 1000)
                    state.syncError = nil
                    try store.save(state)
                    continue
                }
                guard let messageId = state.pendingEvents.first else { break }
                do { try await transport.opened(state, messageId: messageId) }
                catch PushPortFailure.http(404) { /* Deleted message; don't hold the entire outbox. */ }
                state.pendingEvents.removeAll { $0 == messageId }
                try store.save(state)
            }
            var telemetryError: Error?
            do { try await flushTelemetry() } catch { telemetryError = error }
            do { try await flushUsers() }
            catch PushPortFailure.identityTokenRequired {
                // Transient telemetry failures still need their normal retry.
                throw telemetryError ?? PushPortFailure.identityTokenRequired
            }
            if let telemetryError { throw telemetryError }
            state.syncError = nil; try store.save(state)
        } catch {
            let safe = (error as? PushPortFailure) ?? .storageUnavailable
            state.syncError = safe.localizedDescription
            let reason: String
            let status: Int?
            switch safe { case .network: reason = "network_error"; status = nil
                case .http(let value): reason = "http_error"; status = value
                case .invalidResponse: reason = "invalid_response"; status = nil
                default: reason = "storage_unavailable"; status = nil }
            if safe != .identityTokenRequired { try? record(NotificationEvent(type: "sync_failed", reason: reason, httpStatus: status)) }
            try? store.save(state)
            throw safe
        }
    }
}
