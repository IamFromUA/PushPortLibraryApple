#if os(iOS)
import Foundation
import UserNotifications
import PushPortCore
import ImageIO

/// Subclass this from the host's Notification Service Extension target to attach HTTPS images.
/// Add mutable-content: 1 to the APNs aps payload. Expiry always returns the original text.
open class PushPortNotificationService: UNNotificationServiceExtension {
    private let lock = NSLock()
    private var completion: ((UNNotificationContent) -> Void)?
    private var content: UNMutableNotificationContent?
    private var downloader: ImageDownloader?
    private var appId: String?
    private var messageId: String?
    private var inbox: NotificationInbox?

    open override func didReceive(_ request: UNNotificationRequest, withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {
        guard let mutable = request.content.mutableCopy() as? UNMutableNotificationContent else { contentHandler(request.content); return }
        lock.lock(); completion = contentHandler; content = mutable; lock.unlock()
        guard let app = request.content.userInfo["pushport_app_id"] as? String, Configuration.isUUID(app),
              let message = request.content.userInfo["pushport_message_id"] as? String, Configuration.isUUID(message) else { finish(); return }
        appId = app; messageId = message
        if let group = Bundle.main.object(forInfoDictionaryKey: "PushPortAppGroup") as? String,
           let directory = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) {
            struct Consent: Decodable { let appId: String; let allowed: Bool }
            if let bytes = try? Data(contentsOf: directory.appendingPathComponent("PushPortNotificationConsent.json")),
               let consent = try? JSONDecoder().decode(Consent.self, from: bytes), consent.appId == app, consent.allowed {
                inbox = try? NotificationInbox(directory: directory)
            }
        }
        report("received")
        guard let raw = request.content.userInfo["image_url"] as? String else { finish(); return }
        guard raw.count <= 1000,
              let url = URL(string: raw), url.scheme == "https", url.host != nil, url.user == nil, url.password == nil else {
            report("image_failed", reason: "invalid_url"); finish(); return
        }
        let requested = request.content.userInfo["image_limit_bytes"] as? Int ?? 5 * 1024 * 1024
        let limit = NotificationImagePolicy.downloadLimit(requested)
        let downloader = ImageDownloader(limit: limit)
        self.downloader = downloader
        downloader.start(url) { [weak self] attachment, reason, bytes, duration, status in
            guard let self else { return }
            self.lock.lock()
            let active = self.completion != nil
            if active, let attachment { self.content?.attachments = [attachment] }
            self.lock.unlock()
            if let attachment, active {
                _ = attachment
                self.report("image_downloaded", bytes: bytes, duration: duration, status: status)
                self.report("image_attached")
            } else { self.report(active ? "image_failed" : "image_skipped", reason: active ? reason ?? "decode_failed" : "extension_expired", bytes: bytes, duration: duration, status: status) }
            self.finish()
        }
    }
    open override func serviceExtensionTimeWillExpire() { downloader?.cancel(); finish() }
    private func finish() {
        lock.lock(); let handler = completion; let result = content; completion = nil; lock.unlock()
        if let handler, let result { handler(result) }
    }
    private func report(_ type: String, reason: String? = nil, bytes: Int64? = nil, duration: Int64? = nil, status: Int? = nil) {
        guard let appId, let messageId else { return }
        try? inbox?.append(appId: appId, event: NotificationEvent(type: type, messageId: messageId, reason: reason, durationMillis: duration, sizeBytes: bytes, httpStatus: status))
    }
}

final class ImageDownloader: NSObject, URLSessionDataDelegate {
    private var session: URLSession?
    private var data = Data()
    private var suffix: String?
    private var done: ((UNNotificationAttachment?, String?, Int64, Int64, Int?) -> Void)?
    private let limit: Int
    private var failure: String?
    private var status: Int?
    private var started = ProcessInfo.processInfo.systemUptime
    private let suppliedConfiguration: URLSessionConfiguration?
    init(limit: Int, configuration: URLSessionConfiguration? = nil) { self.limit = limit; suppliedConfiguration = configuration }
    func start(_ url: URL, completion: @escaping (UNNotificationAttachment?, String?, Int64, Int64, Int?) -> Void) {
        done = completion
        if !NotificationImagePolicy.allows(url) {
            done = nil; completion(nil, "invalid_url", 0, 0, nil); return
        }
        let configuration = suppliedConfiguration ?? URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 5; configuration.timeoutIntervalForResource = 10
        configuration.httpShouldSetCookies = false
        configuration.httpCookieStorage = nil; configuration.urlCredentialStorage = nil; configuration.urlCache = nil
        let queue = OperationQueue(); queue.maxConcurrentOperationCount = 1
        session = URLSession(configuration: configuration, delegate: self, delegateQueue: queue)
        session?.dataTask(with: url).resume()
    }
    func cancel() { session?.invalidateAndCancel() }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        failure = "redirect"; completionHandler(nil)
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        let types = ["image/jpeg": "jpg", "image/png": "png", "image/gif": "gif", "image/webp": "webp"]
        suffix = types[response.mimeType ?? ""]
        status = (response as? HTTPURLResponse)?.statusCode
        guard status == 200 else { failure = "http_error"; completionHandler(.cancel); return }
        guard suffix != nil else { failure = "unsupported_content_type"; completionHandler(.cancel); return }
        guard response.expectedContentLength <= Int64(limit) else { failure = "too_large"; completionHandler(.cancel); return }
        completionHandler(.allow)
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard self.data.count + data.count <= limit else { failure = "too_large"; dataTask.cancel(); return }
        self.data.append(data)
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        var attachment: UNNotificationAttachment?
        if error == nil, let suffix, !data.isEmpty {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                guard let source = CGImageSourceCreateWithData(data as CFData, [kCGImageSourceShouldCache: false] as CFDictionary),
                      let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
                      let width = properties[kCGImagePropertyPixelWidth] as? Int, let height = properties[kCGImagePropertyPixelHeight] as? Int,
                      NotificationImagePolicy.allowsPixels(width: width, height: height) else {
                    failure = "pixel_limit"; throw PushPortFailure.invalidResponse
                }
                var output = data; var extensionName = suffix
                if suffix == "webp" || width > 2000 || height > 2000 {
                    guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceThumbnailMaxPixelSize: 2000, kCGImageSourceCreateThumbnailWithTransform: true] as CFDictionary) else { throw PushPortFailure.invalidResponse }
                    let encoded = NSMutableData()
                    guard let destination = CGImageDestinationCreateWithData(encoded, "public.png" as CFString, 1, nil) else { throw PushPortFailure.invalidResponse }
                    CGImageDestinationAddImage(destination, image, nil); guard CGImageDestinationFinalize(destination) else { throw PushPortFailure.invalidResponse }
                    output = encoded as Data; extensionName = "png"
                }
                let file = directory.appendingPathComponent("image.\(extensionName)")
                try output.write(to: file, options: .atomic)
                attachment = try UNNotificationAttachment(identifier: "pushport-image", url: file, options: nil)
                try? FileManager.default.removeItem(at: directory)
            } catch { attachment = nil }
        }
        let callback = done; done = nil
        let errorCode = (error as? URLError)?.code
        callback?(attachment, failure ?? (errorCode == .timedOut ? "timeout" : error != nil ? "network_error" : attachment == nil ? "decode_failed" : nil), Int64(data.count), Int64(min(10000, max(0, (ProcessInfo.processInfo.systemUptime - started) * 1000))), status)
        session.finishTasksAndInvalidate()
    }
}
#endif
