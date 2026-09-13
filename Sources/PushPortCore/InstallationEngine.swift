import Foundation

/// Actor serializes persistence. A snapshot is committed before any HTTP request.
public actor InstallationEngine {
    private var state: PersistentState
    private let store: any StateStore
    private let transport: any Transport
    private var metadata: DeviceMetadata?
    private var flushing = false
    private var validated = false

    public init(configuration: Configuration, store: any StateStore, transport: any Transport = HTTPTransport()) throws {
        self.store = store; self.transport = transport
        if let saved = try store.load() {
            guard saved.schema == 1, saved.configuration == configuration else { throw PushPortFailure.configurationConflict }
            state = saved
        } else { state = .create(configuration); try store.save(state) }
    }
    public func status() -> Status { state.status }

    public func capture(_ metadata: DeviceMetadata) throws {
        self.metadata = metadata
        try commitSnapshot()
    }
    public func setToken(_ token: Data) throws {
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
        guard appId == state.configuration.appId, Configuration.isUUID(messageId) else { return }
        if !state.pendingEvents.contains(messageId) {
            state.pendingEvents.append(messageId)
            state.pendingEvents = Array(state.pendingEvents.suffix(100))
            try store.save(state)
        }
    }
    private func commitSnapshot() throws {
        if let metadata {
            let snapshot = state.makeSnapshot(metadata)
            state.snapshot = snapshot; state.revision = snapshot.revision
        }
        try store.save(state)
    }

    /// Concurrent calls coalesce. New revisions arriving during HTTP are sent before the loop exits.
    public func flush() async throws {
        guard !flushing else { return }
        flushing = true
        defer { flushing = false }
        do {
            if !validated { try await transport.configure(state.configuration); validated = true }
            while true {
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
            state.syncError = nil; try store.save(state)
        } catch {
            let safe = (error as? PushPortFailure) ?? .storageUnavailable
            state.syncError = safe.localizedDescription
            try? store.save(state)
            throw safe
        }
    }
}
