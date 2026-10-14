import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public protocol Transport: Sendable {
    func configure(_ configuration: Configuration) async throws
    func register(_ state: PersistentState, snapshot: DeviceSnapshot) async throws
    func opened(_ state: PersistentState, messageId: String) async throws
    func remoteConfiguration(_ configuration: Configuration) async throws -> RemoteConfiguration
    func telemetry(_ state: PersistentState, events: [NotificationEvent], dropped: Int64) async throws -> [String]
    func user(_ state: PersistentState, operation: UserOperation?) async throws -> PushPortUser
}

public extension Transport {
    func remoteConfiguration(_ configuration: Configuration) async throws -> RemoteConfiguration { try await configure(configuration); return RemoteConfiguration() }
    func telemetry(_ state: PersistentState, events: [NotificationEvent], dropped: Int64) async throws -> [String] { [] }
    func user(_ state: PersistentState, operation: UserOperation?) async throws -> PushPortUser { throw PushPortFailure.http(404) }
}

private final class NoRedirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

public final class HTTPTransport: Transport, @unchecked Sendable {
    private let session: URLSession
    public init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15
        configuration.timeoutIntervalForResource = 20
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        configuration.httpCookieStorage = nil
        configuration.urlCredentialStorage = nil
        session = URLSession(configuration: configuration, delegate: NoRedirects(), delegateQueue: nil)
    }
    deinit { session.invalidateAndCancel() }

    public func configure(_ configuration: Configuration) async throws {
        _ = try await remoteConfiguration(configuration)
    }
    public func remoteConfiguration(_ configuration: Configuration) async throws -> RemoteConfiguration {
        var query = URLComponents(); query.queryItems = [URLQueryItem(name: "bundleId", value: configuration.bundleId)]
        let data = try await send(configuration, path: "config?\(query.percentEncodedQuery ?? "")", method: "GET")
        struct Config: Decodable { let appId: String; let platform: String; let protocolVersion: Int; let telemetryVersion: Int?; let userProfileVersion: Int?; let imageLimitBytes: Int? }
        guard let result = try? JSONDecoder().decode(Config.self, from: data), result.appId == configuration.appId,
              result.platform == "IOS", result.protocolVersion == 1 else { throw PushPortFailure.invalidResponse }
        return RemoteConfiguration(telemetryVersion: result.telemetryVersion ?? 0, userProfileVersion: result.userProfileVersion ?? 0, imageLimitBytes: result.imageLimitBytes ?? 5 * 1024 * 1024)
    }
    public func telemetry(_ state: PersistentState, events: [NotificationEvent], dropped: Int64) async throws -> [String] {
        struct Batch: Encodable { let events: [NotificationEvent]; let dropped: Int64 }
        struct Ack: Decodable { let acceptedIds: [String] }
        let data = try await send(state.configuration, path: "installations/\(state.installationId)/telemetry", method: "POST", secret: state.secret, body: JSONEncoder().encode(Batch(events: events, dropped: dropped)))
        return try JSONDecoder().decode(Ack.self, from: data).acceptedIds
    }
    public func user(_ state: PersistentState, operation: UserOperation?) async throws -> PushPortUser {
        let data = try await send(state.configuration, path: "installations/\(state.installationId)/user", method: operation == nil ? "GET" : "PUT", secret: state.secret, body: try operation.map { try JSONEncoder().encode($0) })
        return try JSONDecoder().decode(PushPortUser.self, from: data)
    }
    public func register(_ state: PersistentState, snapshot: DeviceSnapshot) async throws {
        _ = try await send(state.configuration, path: "installations/\(state.installationId)", method: "PUT",
                           secret: state.secret, body: JSONEncoder().encode(snapshot))
    }
    public func opened(_ state: PersistentState, messageId: String) async throws {
        _ = try await send(state.configuration, path: "installations/\(state.installationId)/events", method: "POST",
                           secret: state.secret, body: JSONEncoder().encode(["messageId": messageId, "type": "opened"]))
    }
    private func send(_ configuration: Configuration, path: String, method: String, secret: String? = nil,
                      body: Data? = nil) async throws -> Data {
        let base = configuration.serverURL.absoluteString.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard let url = URL(string: "\(base)/api/v1/sdk/apps/\(configuration.appId)/platforms/ios/\(path)") else {
            throw PushPortFailure.invalidConfiguration
        }
        var request = URLRequest(url: url)
        request.httpMethod = method; request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        if let secret { request.setValue("Bearer \(secret)", forHTTPHeaderField: "Authorization") }
        do {
            let (data, response) = try await session.data(for: request)
            guard let response = response as? HTTPURLResponse else { throw PushPortFailure.invalidResponse }
            guard (200...299).contains(response.statusCode) else { throw PushPortFailure.http(response.statusCode) }
            guard data.count <= 65536 else { throw PushPortFailure.invalidResponse }
            return data
        } catch let error as PushPortFailure { throw error }
        catch { throw PushPortFailure.network }
    }
}
