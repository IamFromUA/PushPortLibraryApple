// SPDX-FileCopyrightText: 2026 Oleh Yurkov
// SPDX-License-Identifier: Apache-2.0
import Foundation

public enum APNsEnvironment: String, Codable, Sendable { case sandbox, production }

public enum PushPortFailure: Error, Equatable, LocalizedError, Sendable {
    case invalidConfiguration, configurationConflict, notInitialized, invalidLocale, storageUnavailable
    case invalidResponse, network, http(Int)
    public var errorDescription: String? {
        switch self {
        case .invalidConfiguration: return "Use a canonical PushPort App ID, bundle ID and HTTPS server URL."
        case .configurationConflict: return "This installation is already bound to another PushPort configuration."
        case .notInitialized: return "Initialize PushPort first."
        case .invalidLocale: return "Use a BCP-47 locale such as de-DE."
        case .storageUnavailable: return "PushPort could not access persistent installation storage."
        case .invalidResponse: return "PushPort returned an invalid response."
        case .network: return "PushPort is unreachable. Pending changes will be retried."
        case .http(let status): return "PushPort request failed (\(status))."
        }
    }
    public var retryable: Bool {
        switch self { case .network: return true; case .http(let code): return code == 409 || code == 429 || code >= 500; default: return false }
    }
}

public struct Configuration: Codable, Equatable, Sendable {
    public let appId: String
    public let serverURL: URL
    public let bundleId: String
    public let environment: APNsEnvironment

    public init(appId: String, serverURL: URL = URL(string: "https://pushport.dev")!, bundleId: String,
                environment: APNsEnvironment = .production, allowInsecureLocalhost: Bool = false) throws {
        let local = ["localhost", "127.0.0.1", "::1", "[::1]"].contains(serverURL.host ?? "")
        guard Self.isUUID(appId), !bundleId.isEmpty, bundleId.count <= 200,
              serverURL.host != nil, serverURL.user == nil, serverURL.password == nil,
              serverURL.query == nil, serverURL.fragment == nil,
              serverURL.scheme == "https" || (allowInsecureLocalhost && local && serverURL.scheme == "http") else {
            throw PushPortFailure.invalidConfiguration
        }
        self.appId = appId
        self.serverURL = serverURL
        self.bundleId = bundleId
        self.environment = environment
    }

    public static func isUUID(_ value: String) -> Bool { UUID(uuidString: value)?.uuidString.lowercased() == value }
    public static func locale(_ value: String) throws -> String {
        guard value.count <= 100, value.range(of: "^[A-Za-z]{2,8}(-[A-Za-z0-9]{1,8})*$", options: .regularExpression) != nil,
              value.lowercased() != "und" else { throw PushPortFailure.invalidLocale }
        // Foundation uses underscores in some identifiers; the wire format is always BCP-47.
        return Locale.canonicalIdentifier(from: value).replacingOccurrences(of: "_", with: "-")
    }
}

public struct DeviceMetadata: Codable, Equatable, Sendable {
    public var locale: String
    public var appLocales: [String]
    public var systemLocales: [String]
    public var timezone: String
    public var notificationsEnabled: Bool
    public var appVersion: String
    public var osVersion: String
    public var model: String
    public init(locale: String, appLocales: [String], systemLocales: [String], timezone: String,
                notificationsEnabled: Bool, appVersion: String, osVersion: String, model: String) {
        self.locale = locale; self.appLocales = appLocales; self.systemLocales = systemLocales
        self.timezone = timezone; self.notificationsEnabled = notificationsEnabled
        self.appVersion = appVersion; self.osVersion = osVersion; self.model = model
    }
}

public struct DeviceSnapshot: Codable, Equatable, Sendable {
    public var revision: Int64
    public let platform: String
    public let applicationIdentifier: String
    public let apnsEnvironment: APNsEnvironment
    public let pushToken: String?
    public let language: String
    public let locale: String
    public let appLocales: [String]
    public let systemLocales: [String]
    public let timezone: String
    public let notificationsEnabled: Bool
    public let pushSubscribed: Bool
    public let sdkVersion: String
    public let appVersion: String
    public let osVersion: String
    public let model: String
}

public struct Status: Codable, Equatable, Sendable {
    public let configured: Bool
    public let installationId: String
    public let subscribed: Bool
    public let hasToken: Bool
    public let notificationsEnabled: Bool
    public let locale: String?
    public let lastSyncedAt: Int64?
    public let syncError: String?
}

public struct PersistentState: Codable, Sendable, CustomStringConvertible {
    public let schema: Int
    public let configuration: Configuration
    public let installationId: String
    public let secret: String
    public var token: String?
    public var subscribed: Bool
    public var localeOverride: String?
    public var revision: Int64
    public var acknowledgedRevision: Int64
    public var snapshot: DeviceSnapshot?
    public var pendingEvents: [String]
    public var lastSyncedAt: Int64?
    public var syncError: String?

    public var description: String { "PersistentState(installationId=\(installationId), revision=\(revision), credentials=<redacted>)" }

    public static func create(_ configuration: Configuration) -> PersistentState {
        let bytes = (0..<32).map { _ in UInt8.random(in: .min ... .max) }
        let secret = Data(bytes).base64EncodedString().replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        return PersistentState(schema: 1, configuration: configuration, installationId: UUID().uuidString.lowercased(),
                               secret: secret, token: nil, subscribed: true, localeOverride: nil, revision: 0,
                               acknowledgedRevision: 0, snapshot: nil, pendingEvents: [], lastSyncedAt: nil, syncError: nil)
    }

    public var status: Status {
        Status(configured: true, installationId: installationId, subscribed: subscribed, hasToken: token != nil,
               notificationsEnabled: snapshot?.notificationsEnabled ?? false, locale: snapshot?.locale,
               lastSyncedAt: lastSyncedAt, syncError: syncError)
    }

    public func makeSnapshot(_ metadata: DeviceMetadata) -> DeviceSnapshot {
        let locale = localeOverride ?? metadata.locale
        return DeviceSnapshot(revision: revision + 1, platform: "IOS", applicationIdentifier: configuration.bundleId,
                              apnsEnvironment: configuration.environment, pushToken: token,
                              language: String(locale.split(separator: "-").first ?? "en").lowercased(), locale: locale,
                              appLocales: localeOverride.map { [$0] } ?? metadata.appLocales, systemLocales: metadata.systemLocales,
                              timezone: metadata.timezone, notificationsEnabled: metadata.notificationsEnabled,
                              pushSubscribed: subscribed, sdkVersion: "0.0.1", appVersion: metadata.appVersion,
                              osVersion: metadata.osVersion, model: metadata.model)
    }
}
