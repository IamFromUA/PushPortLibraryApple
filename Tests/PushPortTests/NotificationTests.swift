import XCTest
@testable import PushPort
#if os(iOS)
final class NotificationTests: XCTestCase {
    func testOnlyCanonicalMessagesAndSafeClickURLsAreExposed() {
        let appId = "00000000-0000-4000-8000-000000000001"
        let messageId = UUID().uuidString.lowercased()
        XCTAssertNil(PushPortNotification(userInfo: ["pushport_app_id": appId]))
        let valid = PushPortNotification(userInfo: ["pushport_app_id": appId, "pushport_message_id": messageId, "click_url": "https://pushport.dev/docs"])
        XCTAssertEqual(valid?.clickURL?.host, "pushport.dev")
        let unsafe = PushPortNotification(userInfo: ["pushport_app_id": appId, "pushport_message_id": messageId, "click_url": "javascript:alert(1)"])
        XCTAssertNotNil(unsafe)
        XCTAssertNil(unsafe?.clickURL)
        for link in ["https://127.0.0.1/page", "https://demo.internal/page", "https://pushport.dev:81/"] {
            let payload = ["pushport_app_id": appId, "pushport_message_id": messageId, "click_url": link]
            XCTAssertNil(PushPortNotification(userInfo: payload)?.clickURL)
        }
    }
    @MainActor func testTapRoutesExactlyOnceAndCustomActionsStayWithTheHost() throws {
        let id = UUID().uuidString.lowercased()
        let message = try XCTUnwrap(PushPortNotification(userInfo: [
            "pushport_app_id": id, "pushport_message_id": id, "click_url": "https://pushport.dev/ru/"
        ]))
        var destinations = [URL]()
        var interactions = [String]()
        message.route(defaultTap: true, hostHandler: nil) { destinations.append($0) }
        message.route(defaultTap: true, hostHandler: { interactions.append($0.messageId) }) { destinations.append($0) }
        message.route(defaultTap: false, hostHandler: nil) { destinations.append($0) }
        XCTAssertEqual(destinations.map(\.absoluteString), ["https://pushport.dev/ru/"])
        XCTAssertEqual(interactions, [id])
    }

    @MainActor func testKMPBridgeHasStableSelectors() {
        let bridge = PushPortKMPBridge()
        for name in ["statusJSON", "sync", "initializeWithAppId:serverURL:environment:completion:",
                     "setSubscribed:completion:", "setLocale:completion:", "requestPermissionWithCompletion:",
                     "userJSON", "updateUserJSON:completion:", "setConsentRequired:completion:", "setConsentGiven:completion:"] {
            XCTAssertTrue(bridge.responds(to: NSSelectorFromString(name)), name)
        }
    }
}
#endif
