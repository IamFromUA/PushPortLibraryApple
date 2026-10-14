import XCTest
@testable import PushPortNotificationService
#if os(iOS)
import UserNotifications

final class ImageURLProtocol: URLProtocol {
    static var status = 200
    static var mime = "image/png"
    static var bytes = Data(base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jgfsAAAAASUVORK5CYII=")!
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let response = HTTPURLResponse(url: request.url!, statusCode: Self.status, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": Self.mime, "Content-Length": String(Self.bytes.count)])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.bytes); client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
final class ImageTests: XCTestCase {
    override func setUp() { ImageURLProtocol.status = 200; ImageURLProtocol.mime = "image/png" }
    func testValidImageAttachesAndReportsBytes() async {
        let configuration = URLSessionConfiguration.ephemeral; configuration.protocolClasses = [ImageURLProtocol.self]
        let downloader = ImageDownloader(limit: 5 * 1024 * 1024, configuration: configuration)
        let completed = expectation(description: "attachment")
        downloader.start(URL(string: "https://images.example.test/image.png")!) { attachment, reason, bytes, _, status in
            XCTAssertNotNil(attachment); XCTAssertNil(reason); XCTAssertGreaterThan(bytes, 0); XCTAssertEqual(status, 200); completed.fulfill()
        }
        await fulfillment(of: [completed], timeout: 5)
    }
    func testHTTPAndMimeFailuresReturnNoAttachment() async {
        for (status, mime, reason) in [(503, "image/png", "http_error"), (200, "text/html", "unsupported_content_type")] {
            ImageURLProtocol.status = status; ImageURLProtocol.mime = mime
            let configuration = URLSessionConfiguration.ephemeral; configuration.protocolClasses = [ImageURLProtocol.self]
            let downloader = ImageDownloader(limit: 5 * 1024 * 1024, configuration: configuration)
            let completed = expectation(description: reason)
            downloader.start(URL(string: "https://images.example.test/image.png")!) { attachment, code, _, _, _ in
                XCTAssertNil(attachment); XCTAssertEqual(code, reason); completed.fulfill()
            }
            await fulfillment(of: [completed], timeout: 5)
        }
    }
    func testInvalidImageURLPreservesOriginalText() async {
        let content = UNMutableNotificationContent(); content.title = "Text remains"; content.body = "Fallback"
        content.userInfo = ["pushport_app_id": "00000000-0000-4000-8000-000000000001", "pushport_message_id": UUID().uuidString.lowercased(), "image_url": "http://unsafe.example.test/image.png"]
        let service = PushPortNotificationService(); let completed = expectation(description: "fallback")
        service.didReceive(UNNotificationRequest(identifier: "test", content: content, trigger: nil)) { result in
            XCTAssertEqual(result.title, "Text remains"); XCTAssertEqual(result.body, "Fallback"); XCTAssertTrue(result.attachments.isEmpty); completed.fulfill()
        }
        await fulfillment(of: [completed], timeout: 5)
    }
}
#endif
