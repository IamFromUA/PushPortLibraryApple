import Foundation

public struct NotificationEvent: Codable, Equatable, Sendable {
    public var id: String = UUID().uuidString.lowercased()
    public var type: String
    public var occurredAt: Int64 = Int64(Date().timeIntervalSince1970 * 1000)
    public var messageId: String?
    public var reason: String?
    public var durationMillis: Int64?
    public var sizeBytes: Int64?
    public var httpStatus: Int?
    public init(type: String, messageId: String? = nil, reason: String? = nil, durationMillis: Int64? = nil,
                sizeBytes: Int64? = nil, httpStatus: Int? = nil) {
        self.type = type; self.messageId = messageId; self.reason = reason; self.durationMillis = durationMillis
        self.sizeBytes = sizeBytes; self.httpStatus = httpStatus
    }
}
public struct UsageSnapshot: Codable, Equatable, Sendable {
    public var firstSessionAt: Int64?
    public var lastSessionAt: Int64?
    public var sessionCount: Int64 = 0
    public var totalUsageMillis: Int64 = 0
    public init() {}
}
public struct RemoteConfiguration: Sendable {
    public var telemetryVersion: Int
    public var userProfileVersion: Int
    public var imageLimitBytes: Int
    public init(telemetryVersion: Int = 0, userProfileVersion: Int = 0, imageLimitBytes: Int = 5 * 1024 * 1024) {
        self.telemetryVersion = telemetryVersion == 1 ? 1 : 0; self.userProfileVersion = userProfileVersion == 1 ? 1 : 0
        self.imageLimitBytes = (1024 * 1024...20 * 1024 * 1024).contains(imageLimitBytes) ? imageLimitBytes : 5 * 1024 * 1024
    }
}
public enum NotificationImagePolicy {
    public static func downloadLimit(_ requested: Int) -> Int { (1024 * 1024...20 * 1024 * 1024).contains(requested) ? min(requested, 10 * 1024 * 1024) : 5 * 1024 * 1024 }
    public static func allows(_ url: URL) -> Bool {
        guard url.scheme == "https", let host = url.host?.lowercased(), url.user == nil, url.password == nil,
              url.absoluteString.count <= 1000, url.port == nil || url.port == 443 else { return false }
        if ["localhost", "::1", "[::1]", "0.0.0.0"].contains(host) || host.hasPrefix("127.") || host.hasPrefix("10.") || host.hasPrefix("192.168.") || host.hasPrefix("169.254.") || host.hasPrefix("[fc") || host.hasPrefix("[fd") || host.hasPrefix("[fe80:") { return false }
        let parts = host.split(separator: ".").compactMap { Int($0) }
        if parts.count == 4 && (parts[0] == 0 || parts[0] >= 224 || (parts[0] == 172 && (16...31).contains(parts[1])) || (parts[0] == 100 && (64...127).contains(parts[1]))) { return false }
        return true
    }
    public static func allowsPixels(width: Int, height: Int) -> Bool { width > 0 && height > 0 && width <= 4096 && height <= 4096 && width * height <= 8000000 }
}
public struct UserProperties: Codable, Equatable, Sendable, CustomStringConvertible {
    public var description: String { "UserProperties(<redacted>)" }
    public var tags: [String: String]
    public var email: String?
    public var phoneNumber: String?
    public var latitude: Double?
    public var longitude: Double?
}
public struct PushPortUser: Codable, Equatable, Sendable, CustomStringConvertible {
    public var description: String { "PushPortUser(userId=\(userId), revision=\(revision), properties=<redacted>)" }
    public var userId: String
    public var externalId: String?
    public var properties: UserProperties
    public var revision: Int64
}
public struct UserOperation: Codable, Sendable, CustomStringConvertible {
    public var description: String { "UserOperation(revision=\(revision), kind=\(kind), data=<redacted>)" }
    public var revision: Int64 = 0
    public var kind: String
    public var externalId: String?
    public var identityToken: String?
    public var tags: [String: String?] = [:]
    public var email: String?
    public var phoneNumber: String?
    public var latitude: Double?
    public var longitude: Double?
    public var eventName: String?
    public var eventProperties: [String: String] = [:]
    public init(kind: String) { self.kind = kind }
    private enum CodingKeys: String, CodingKey { case revision, kind, externalId, identityToken, tags, email, phoneNumber, latitude, longitude, eventName, eventProperties }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        revision = try values.decodeIfPresent(Int64.self, forKey: .revision) ?? 0
        kind = try values.decode(String.self, forKey: .kind)
        externalId = try values.decodeIfPresent(String.self, forKey: .externalId); identityToken = try values.decodeIfPresent(String.self, forKey: .identityToken)
        tags = try values.decodeIfPresent([String: String?].self, forKey: .tags) ?? [:]
        email = try values.decodeIfPresent(String.self, forKey: .email); phoneNumber = try values.decodeIfPresent(String.self, forKey: .phoneNumber)
        latitude = try values.decodeIfPresent(Double.self, forKey: .latitude); longitude = try values.decodeIfPresent(Double.self, forKey: .longitude)
        eventName = try values.decodeIfPresent(String.self, forKey: .eventName); eventProperties = try values.decodeIfPresent([String: String].self, forKey: .eventProperties) ?? [:]
    }
    public func validate() throws {
        func valid(_ value: String, _ pattern: String) -> Bool { value.range(of: pattern, options: .regularExpression) != nil }
        guard ["login", "logout", "tags", "email", "phone", "location", "event"].contains(kind),
              tags.count <= 50, tags.allSatisfy({ !$0.key.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.key.count <= 64 && !$0.key.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) && ($0.value?.count ?? 0) <= 256 }) else { throw PushPortFailure.invalidConfiguration }
        if kind == "login" {
            guard let externalId, !externalId.isEmpty, externalId.count <= 128,
                  externalId == externalId.trimmingCharacters(in: .whitespacesAndNewlines),
                  !externalId.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains),
                  let identityToken, valid(identityToken, "^[A-Za-z0-9_-]{43}$") else { throw PushPortFailure.invalidConfiguration }
        }
        if let email, email.count > 254 || !valid(email, "^[^\\s@]+@[^\\s@]+\\.[^\\s@]+$") { throw PushPortFailure.invalidConfiguration }
        if let phoneNumber, !valid(phoneNumber, "^\\+[1-9][0-9]{6,14}$") { throw PushPortFailure.invalidConfiguration }
        if (latitude == nil) != (longitude == nil) { throw PushPortFailure.invalidConfiguration }
        if let latitude, !latitude.isFinite || !(-90...90).contains(latitude) { throw PushPortFailure.invalidConfiguration }
        if let longitude, !longitude.isFinite || !(-180...180).contains(longitude) { throw PushPortFailure.invalidConfiguration }
        if kind == "event" {
            guard let eventName, valid(eventName, "^[A-Za-z][A-Za-z0-9_.-]{0,63}$"), eventProperties.count <= 20,
                  eventProperties.allSatisfy({ !$0.key.isEmpty && $0.key.count <= 64 && $0.value.count <= 256 && !$0.key.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) }) else { throw PushPortFailure.invalidConfiguration }
        }
    }
}
public struct SupplementalState: Codable, Sendable {
    public var consentRequired = false
    public var consentGiven = false
    public var telemetryVersion = 0
    public var userProfileVersion = 0
    public var imageLimitBytes = 5 * 1024 * 1024
    public var events: [NotificationEvent] = []
    public var dropped: Int64 = 0
    public var receivedMessages: [String] = []
    public var lastReceived: NotificationEvent?
    public var lastClicked: NotificationEvent?
    public var usage = UsageSnapshot()
    public var lastActivityAt: Int64 = 0
    public var user: PushPortUser?
    public var userRevision: Int64 = 0
    public var userOperations: [UserOperation] = []
    public init() {}
    public var collectionAllowed: Bool { !consentRequired || consentGiven }
}

/// A separate, bounded spool per event avoids cross-process updates to installation credentials.
/// The host drains it on foreground. Both targets must share the same App Group entitlement.
public struct NotificationInbox: Sendable {
    private let directory: URL
    public init(directory: URL) throws {
        self.directory = directory.appendingPathComponent("PushPortNotificationEvents", isDirectory: true)
        try FileManager.default.createDirectory(at: self.directory, withIntermediateDirectories: true)
    }
    public func append(appId: String, event: NotificationEvent) throws {
        guard Configuration.isUUID(appId), Configuration.isUUID(event.id) else { return }
        struct Envelope: Codable { let appId: String; let event: NotificationEvent }
        let files = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).filter { $0.pathExtension == "json" }
        // Bounded extension storage. Overflow is counted by the host when its own outbox fills.
        guard files.count < 1000 else { return }
        try JSONEncoder().encode(Envelope(appId: appId, event: event)).write(to: directory.appendingPathComponent(event.id + ".json"), options: .atomic)
    }
    public func read(appId: String) throws -> [(URL, NotificationEvent)] {
        struct Envelope: Decodable { let appId: String; let event: NotificationEvent }
        return try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).filter { $0.pathExtension == "json" }.prefix(1000).compactMap { file in
            guard let value = try? JSONDecoder().decode(Envelope.self, from: Data(contentsOf: file)), value.appId == appId else { return nil }
            return (file, value.event)
        }
    }
    public func remove(_ file: URL) throws { guard file.deletingLastPathComponent().standardizedFileURL == directory.standardizedFileURL else { return }; try FileManager.default.removeItem(at: file) }
}
