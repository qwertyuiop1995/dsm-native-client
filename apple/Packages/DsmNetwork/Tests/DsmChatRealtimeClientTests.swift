import DsmCore
import Foundation
import XCTest
@testable import DsmNetwork

final class DsmChatRealtimeClientTests: XCTestCase {
    func test解析EngineIO与SocketIO控制帧() {
        XCTAssertEqual(
            DsmSocketIOPacketParser.actions(
                in: #"0{"sid":"sanitized","pingInterval":25000,"pingTimeout":20000}"#
            ),
            [.engineOpened]
        )
        XCTAssertEqual(DsmSocketIOPacketParser.actions(in: "40"), [.namespaceConnected])
        XCTAssertEqual(DsmSocketIOPacketParser.actions(in: "2"), [.replyPong])
        XCTAssertEqual(DsmSocketIOPacketParser.actions(in: "41"), [.disconnected])
    }

    func test消息事件只上报内容变化且支持复合帧() {
        let frame = #"42["post_create",{"message":"不应进入业务层"}]"#
            + "\u{001E}"
            + #"42["channel_update",{"id":"sanitized"}]"#

        XCTAssertEqual(
            DsmSocketIOPacketParser.actions(in: frame),
            [.contentChanged, .contentChanged]
        )
        XCTAssertEqual(
            DsmSocketIOPacketParser.actions(in: #"43["ack"]"#),
            [.ignored]
        )
    }

    func test握手请求不在地址中暴露会话凭据() throws {
        let request = try DsmChatSocketRequestBuilder.make(
            baseURL: try XCTUnwrap(URL(string: "https://nas.example.test:5001/base/")),
            credential: DsmSessionCredential(
                sid: "SANITIZED-SID",
                synoToken: "SANITIZED-TOKEN"
            ),
            engineVersion: 4
        )
        let url = try XCTUnwrap(request.url)
        let components = try XCTUnwrap(
            URLComponents(url: url, resolvingAgainstBaseURL: false)
        )

        XCTAssertEqual(components.scheme, "wss")
        XCTAssertEqual(components.path, "/base/sc/socket.io/")
        XCTAssertEqual(
            Set(components.queryItems ?? []),
            Set([
                URLQueryItem(name: "EIO", value: "4"),
                URLQueryItem(name: "transport", value: "websocket")
            ])
        )
        XCTAssertFalse(url.absoluteString.contains("SANITIZED-SID"))
        XCTAssertFalse(url.absoluteString.contains("SANITIZED-TOKEN"))
        XCTAssertEqual(request.value(forHTTPHeaderField: "Cookie"), "id=SANITIZED-SID")
        XCTAssertEqual(
            request.value(forHTTPHeaderField: "X-SYNO-TOKEN"),
            "SANITIZED-TOKEN"
        )
        XCTAssertEqual(
            request.value(forHTTPHeaderField: "Origin"),
            "https://nas.example.test:5001"
        )
    }
}
