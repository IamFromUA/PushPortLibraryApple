import Foundation

/// The engine is the sole caller. Persistence must commit atomically or throw.
public protocol StateStore: Sendable {
    func load() throws -> PersistentState?
    func save(_ state: PersistentState) throws
}

/// App-container identity is removed with the application; no hardware or advertising identifier.
public struct FileStateStore: StateStore {
    private let file: URL
    public init(directory: URL) throws {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            #if canImport(Darwin)
            var directory = directory
            var values = URLResourceValues(); values.isExcludedFromBackup = true
            try directory.setResourceValues(values)
            #endif
            file = directory.appendingPathComponent("installation-v1.json")
        } catch { throw PushPortFailure.storageUnavailable }
    }
    public func load() throws -> PersistentState? {
        do { return try JSONDecoder().decode(PersistentState.self, from: Data(contentsOf: file)) }
        catch let error as CocoaError where error.code == .fileReadNoSuchFile { return nil }
        catch { throw PushPortFailure.storageUnavailable }
    }
    public func save(_ state: PersistentState) throws {
        do {
            let data = try JSONEncoder().encode(state)
            #if os(iOS)
            try data.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            #else
            try data.write(to: file, options: .atomic)
            #endif
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file.path)
        } catch { throw PushPortFailure.storageUnavailable }
    }
}
