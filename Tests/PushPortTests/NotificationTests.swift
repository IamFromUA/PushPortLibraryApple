import XCTest
@testable import PushPort
#if os(iOS)
final class NotificationTests: XCTestCase {
    func testOnlyCanonicalMessagesAndSafeClickURLsAreExposed() {
        let appId = "6d632180-a023-4101-a4b1-9068404346f8"
        let messageId = UUID().uuidString.lowercased()
        XCTAssertNil(PushPortNotification(userInfo: ["pushport_app_id": appId]))
        let valid = PushPortNotification(userInfo: ["pushport_app_id": appId, "pushport_message_id": messageId, "click_url": "https://pushport.dev/docs"])
        XCTAssertEqual(valid?.clickURL?.host, "pushport.dev")
        let unsafe = PushPortNotification(userInfo: ["pushport_app_id": appId, "pushport_message_id": messageId, "click_url": "javascript:alert(1)"])
        XCTAssertNotNil(unsafe)
        XCTAssertNil(unsafe?.clickURL)
    }
    @MainActor func testKMPBridgeHasStableSelectors() {
        let bridge = PushPortKMPBridge()
        for name in ["statusJSON", "sync", "initializeWithAppId:serverURL:environment:completion:",
                     "setSubscribed:completion:", "setLocale:completion:", "requestPermissionWithCompletion:"] {
            XCTAssertTrue(bridge.responds(to: NSSelectorFromString(name)), name)
        }
    }
}
#endif
