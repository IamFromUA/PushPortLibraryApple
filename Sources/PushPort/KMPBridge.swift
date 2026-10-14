#if os(iOS)
import Foundation

/// Stable Objective-C selectors consumed by the independently published KMP SDK.
/// Apple hosts link the PushPort SPM product once. No second installation/network engine is created.
@objc(PPPushPortBridge)
@MainActor public final class PushPortKMPBridge: NSObject {
    @objc public override init() { super.init() }
    @objc(initializeWithAppId:serverURL:environment:completion:)
    public func initialize(appId: String, serverURL: String, environment: String, completion: @escaping (String?) -> Void) {
        do {
            guard let url = URL(string: serverURL), let environment = APNsEnvironment(rawValue: environment) else { throw PushPortFailure.invalidConfiguration }
            try PushPort.shared.initialize(appId: appId, environment: environment, serverURL: url)
            completion(nil)
        } catch { completion((error as? PushPortFailure)?.localizedDescription ?? "PushPort initialization failed") }
    }
    @objc(statusJSON) public func statusJSON() -> String {
        guard let status = PushPort.shared.status, let data = try? JSONEncoder().encode(status), let json = String(data: data, encoding: .utf8) else {
            return "{\"configured\":false,\"subscribed\":true,\"hasToken\":false,\"notificationsEnabled\":false}"
        }
        return json
    }
    @objc(sync) public func sync() { PushPort.shared.sync() }
    @objc(userJSON) public func userJSON() -> String? {
        guard let user = PushPort.shared.user, let data = try? JSONEncoder().encode(user) else { return nil }
        return String(data: data, encoding: .utf8)
    }
    @objc(updateUserJSON:completion:)
    public func updateUserJSON(_ json: String, completion: @escaping (String?) -> Void) {
        Task { do {
            guard let bytes = json.data(using: .utf8), bytes.count <= 32768 else { throw PushPortFailure.invalidConfiguration }
            let operation = try JSONDecoder().decode(UserOperation.self, from: bytes)
            try await PushPort.shared.mutate(operation); completion(nil)
        } catch { completion((error as? PushPortFailure)?.localizedDescription ?? "Invalid user operation") } }
    }
    @objc(setConsentRequired:completion:)
    public func setConsentRequired(_ value: Bool, completion: @escaping (String?) -> Void) {
        Task { do { try await PushPort.shared.setConsentRequired(value); completion(nil) } catch { completion("Consent update failed") } }
    }
    @objc(setConsentGiven:completion:)
    public func setConsentGiven(_ value: Bool, completion: @escaping (String?) -> Void) {
        Task { do { try await PushPort.shared.setConsentGiven(value); completion(nil) } catch { completion("Consent update failed") } }
    }
    @objc(setSubscribed:completion:)
    public func setSubscribed(_ value: Bool, completion: @escaping (String?) -> Void) {
        Task { do { try await PushPort.shared.setSubscribed(value); completion(nil) } catch { completion(error.localizedDescription) } }
    }
    @objc(setLocale:completion:)
    public func setLocale(_ value: String?, completion: @escaping (String?) -> Void) {
        Task { do { try await PushPort.shared.setLocale(value); completion(nil) } catch { completion(error.localizedDescription) } }
    }
    @objc(requestPermissionWithCompletion:)
    public func requestPermission(completion: @escaping (String?) -> Void) {
        Task { do { _ = try await PushPort.shared.requestPermission(); completion(nil) } catch { completion(error.localizedDescription) } }
    }
}
#endif
