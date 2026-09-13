#if os(iOS)
import Foundation
import UserNotifications

/// Subclass this from the host's Notification Service Extension target to attach HTTPS images.
/// Add mutable-content: 1 to the APNs aps payload. Expiry always returns the original text.
open class PushPortNotificationService: UNNotificationServiceExtension {
    private let lock = NSLock()
    private var completion: ((UNNotificationContent) -> Void)?
    private var content: UNMutableNotificationContent?
    private var downloader: ImageDownloader?

    open override func didReceive(_ request: UNNotificationRequest, withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {
        guard let mutable = request.content.mutableCopy() as? UNMutableNotificationContent else { contentHandler(request.content); return }
        lock.lock(); completion = contentHandler; content = mutable; lock.unlock()
        guard request.content.userInfo["pushport_app_id"] is String,
              let raw = request.content.userInfo["image_url"] as? String,
              let url = URL(string: raw), url.scheme == "https", url.host != nil, url.user == nil, url.password == nil else {
            finish(); return
        }
        let downloader = ImageDownloader()
        self.downloader = downloader
        downloader.start(url) { [weak self] attachment in
            guard let self else { return }
            self.lock.lock()
            if let attachment { self.content?.attachments = [attachment] }
            self.lock.unlock()
            self.finish()
        }
    }
    open override func serviceExtensionTimeWillExpire() { downloader?.cancel(); finish() }
    private func finish() {
        lock.lock(); let handler = completion; let result = content; completion = nil; lock.unlock()
        if let handler, let result { handler(result) }
    }
}

private final class ImageDownloader: NSObject, URLSessionDataDelegate {
    private var session: URLSession?
    private var data = Data()
    private var suffix: String?
    private var done: ((UNNotificationAttachment?) -> Void)?
    private let limit = 5 * 1024 * 1024
    func start(_ url: URL, completion: @escaping (UNNotificationAttachment?) -> Void) {
        done = completion
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 15; configuration.timeoutIntervalForResource = 20
        configuration.httpCookieStorage = nil; configuration.urlCredentialStorage = nil; configuration.urlCache = nil
        let queue = OperationQueue(); queue.maxConcurrentOperationCount = 1
        session = URLSession(configuration: configuration, delegate: self, delegateQueue: queue)
        session?.dataTask(with: url).resume()
    }
    func cancel() { session?.invalidateAndCancel() }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        guard let url = request.url, url.scheme == "https", url.user == nil, url.password == nil else { completionHandler(nil); return }
        completionHandler(request)
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive response: URLResponse,
                    completionHandler: @escaping (URLSession.ResponseDisposition) -> Void) {
        let types = ["image/jpeg": "jpg", "image/png": "png", "image/gif": "gif"]
        suffix = types[response.mimeType ?? ""]
        guard (response as? HTTPURLResponse)?.statusCode == 200, suffix != nil,
              response.expectedContentLength <= Int64(limit) else { completionHandler(.cancel); return }
        completionHandler(.allow)
    }
    func urlSession(_ session: URLSession, dataTask: URLSessionDataTask, didReceive data: Data) {
        guard self.data.count + data.count <= limit else { dataTask.cancel(); return }
        self.data.append(data)
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        var attachment: UNNotificationAttachment?
        if error == nil, let suffix, !data.isEmpty {
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
            do {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let file = directory.appendingPathComponent("image.\(suffix)")
                try data.write(to: file, options: .atomic)
                attachment = try UNNotificationAttachment(identifier: "pushport-image", url: file, options: nil)
                try? FileManager.default.removeItem(at: directory)
            } catch { attachment = nil }
        }
        let callback = done; done = nil; callback?(attachment)
        session.finishTasksAndInvalidate()
    }
}
#endif
