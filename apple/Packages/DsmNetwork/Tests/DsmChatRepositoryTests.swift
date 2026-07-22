import DsmCore
import Foundation
import XCTest
@testable import DsmNetwork

final class DsmChatRepositoryTests: XCTestCase {
    func test能力齐全时启用已接入功能() async throws {
        let repository = try makeRepository(transport: MockHTTPTransport(responses: []))

        let availability = await repository.availability()

        XCTAssertEqual(availability.status, .available)
        XCTAssertTrue(availability.supportedFeatures.contains(.directConversation))
        XCTAssertTrue(availability.supportedFeatures.contains(.groupConversation))
        XCTAssertTrue(availability.supportedFeatures.contains(.textMessage))
        XCTAssertTrue(availability.supportedFeatures.contains(.reminder))
        XCTAssertTrue(availability.supportedFeatures.contains(.deleteOwnMessage))
        XCTAssertTrue(availability.supportedFeatures.contains(.closeConversation))
        XCTAssertFalse(availability.supportedFeatures.contains(.fileAttachment))
    }

    func test解析用户与会话并兼容数字和字符串标识() async throws {
        let users = response(#"{"success":true,"data":{"users":[{"user_id":2,"nickname":"林青"},{"user_id":"3","username":"周明"}]}}"#)
        let channels = response(#"{"success":true,"data":{"channels":[{"channel_id":27,"name":"","members":[1,2],"unread":3,"last_post":{"message":"下午见","create_at":"1774166400000"}},{"channel_id":"42","name":"项目组","members":[1,"2","3"],"type":"private"}]}}"#)
        let repository = try makeRepository(
            transport: MockHTTPTransport(responses: [users, channels])
        )

        let conversations = try await repository.listConversations()

        XCTAssertEqual(conversations.count, 2)
        let direct = try XCTUnwrap(conversations.first(where: { $0.id == "27" }))
        XCTAssertEqual(direct.kind, .direct)
        XCTAssertTrue(direct.title.contains("林青"))
        XCTAssertEqual(direct.unreadCount, 3)
        let group = try XCTUnwrap(conversations.first(where: { $0.id == "42" }))
        XCTAssertEqual(group.kind, .group)
        XCTAssertEqual(group.title, "项目组")
    }

    func test用户列表兼容根数组和空用户名() async throws {
        let repository = try makeRepository(transport: MockHTTPTransport(responses: [
            response(#"{"success":true,"data":[{"uid":1,"displayname":" "},{"uid":2,"user_name":"林青","is_avatar_exist":false}]}"#)
        ]))

        let users = try await repository.listUsers()

        XCTAssertEqual(users.map(\.id), ["2", "1"])
        XCTAssertEqual(users.first(where: { $0.id == "1" })?.displayName, "用户 1")
        XCTAssertEqual(users.first(where: { $0.id == "2" })?.displayName, "林青")
    }

    func test用户列表读取已声明头像() async throws {
        let pngPrefix = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        let transport = MockHTTPTransport(responses: [
            response(#"{"success":true,"data":{"users":[{"user_id":"2","nickname":"林青","has_avatar":true}]}}"#),
            DsmHTTPResponse(
                data: pngPrefix,
                statusCode: 200,
                headers: ["Content-Type": "image/png"]
            )
        ])
        let repository = try makeRepository(
            transport: transport,
            includesAvatarCapability: true
        )

        let users = try await repository.listUsers()

        XCTAssertEqual(users.first?.avatarData, pngPrefix)
        XCTAssertEqual(users.first?.avatarAvailable, true)
        let requests = await transport.recordedRequests()
        let avatarRequest = try XCTUnwrap(requests.last)
        XCTAssertEqual(avatarRequest.httpMethod, "GET")
        XCTAssertNil(URLComponents(url: try XCTUnwrap(avatarRequest.url), resolvingAgainstBaseURL: false)?
            .queryItems?.first(where: { $0.name == "_sid" }))
    }

    func test解析当前用户和对象成员并从私聊标题排除自己() async throws {
        let users = response(#"{"success":true,"data":{"current_user_id":"1","users":[{"user_id":"1","nickname":"测试账号"},{"user_id":"2","nickname":"林青"}]}}"#)
        let channels = response(#"{"success":true,"data":{"channels":[{"channel_id":"27","name":"","type":"anonymous","members":[{"user_id":"1"},{"user_id":"2"}],"member_count":2}]}}"#)
        let repository = try makeRepository(
            transport: MockHTTPTransport(responses: [users, channels])
        )

        let conversations = try await repository.listConversations()

        let direct = try XCTUnwrap(conversations.first)
        XCTAssertEqual(direct.title, "林青")
        XCTAssertEqual(direct.memberIDs, ["1", "2"])
        XCTAssertEqual(direct.memberCount, 2)
    }

    func test解析嵌套发送者并标记当前用户消息() async throws {
        let transport = MockHTTPTransport(responses: [
            response(#"{"success":true,"data":{"posts":[{"post_id":"9001","channel_id":"27","create_at":"1774166400000","message":"收到","creator":{"user_id":"2","nickname":"林青","is_current_user":false}},{"post_id":"9002","channel_id":"27","create_at":"1774166401000","message":"好的","creator":{"user_id":"1","nickname":"测试账号","is_current_user":true}}]}}"#)
        ])
        let repository = try makeRepository(transport: transport)

        let page = try await repository.listMessages(conversationID: "27", before: nil, limit: 20)

        XCTAssertEqual(page.messages.first?.senderID, "2")
        XCTAssertEqual(page.messages.first?.senderDisplayName, "林青")
        XCTAssertEqual(page.messages.first?.isFromCurrentUser, false)
        XCTAssertEqual(page.messages.last?.isFromCurrentUser, true)
    }

    func test空发送者名称不会覆盖用户目录名称() async throws {
        let users = response(#"{"success":true,"data":{"users":[{"user_id":"2","nickname":"林青"}]}}"#)
        let channels = response(#"{"success":true,"data":{"channels":[]}}"#)
        let posts = response(#"{"success":true,"data":{"posts":[{"post_id":"9001","channel_id":"27","creator_id":"2","creator_name":" ","create_at":1774166400000,"message":"收到"}]}}"#)
        let repository = try makeRepository(
            transport: MockHTTPTransport(responses: [users, channels, posts])
        )

        _ = try await repository.listConversations()
        let page = try await repository.listMessages(conversationID: "27", before: nil, limit: 20)

        XCTAssertEqual(page.messages.first?.senderDisplayName, "林青")
    }

    func test读取历史消息使用正文传递会话和分页() async throws {
        let transport = MockHTTPTransport(responses: [
            response(#"{"success":true,"data":{"posts":[{"post_id":"9001","channel_id":27,"creator_id":2,"create_at":1774166400000,"message":"收到"}],"total":2}}"#)
        ])
        let repository = try makeRepository(transport: transport)

        let page = try await repository.listMessages(
            conversationID: "27",
            before: nil,
            limit: 1
        )

        XCTAssertEqual(page.messages.first?.text, "收到")
        XCTAssertEqual(page.previousCursor, "1")
        let requests = await transport.recordedRequests()
        let request = try XCTUnwrap(requests.first)
        let fields = try decodeForm(request.httpBody)
        XCTAssertEqual(fields["api"], DsmAPIName.chatPost)
        XCTAssertEqual(fields["method"], "list")
        XCTAssertEqual(fields["channel_id"], "27")
        XCTAssertNil(URLComponents(url: try XCTUnwrap(request.url), resolvingAgainstBaseURL: false)?.query)
    }

    func test相同请求标识只发送一次文字消息() async throws {
        let transport = MockHTTPTransport(responses: [
            response(#"{"success":true,"data":{"post_id":"9002","channel_id":"27","creator_id":"1","create_at":"1774166400000","message":"你好"}}"#)
        ])
        let repository = try makeRepository(transport: transport)
        let requestID = UUID()
        let draft = try ChatMessageDraft(
            clientRequestID: requestID,
            conversationID: "27",
            text: "你好"
        )

        let first = try await repository.sendMessage(draft)
        let second = try await repository.sendMessage(draft)

        XCTAssertEqual(first, second)
        let requests = await transport.recordedRequests()
        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(first.clientRequestID, requestID)
    }

    func test删除自己的消息并复查结果且重复请求只执行一次() async throws {
        let ownPost = #"{"success":true,"data":{"posts":[{"post_id":"9001","channel_id":"27","creator_id":"1","creator_name":"testaccount","create_at":1774166400000,"message":"待删除"}]}}"#
        let transport = MockHTTPTransport(responses: [
            response(ownPost),
            response(#"{"success":true}"#),
            response(#"{"success":true,"data":{"posts":[]}}"#)
        ])
        let repository = try makeRepository(transport: transport)
        let requestID = UUID()

        try await repository.deleteMessage(
            conversationID: "27",
            messageID: "9001",
            clientRequestID: requestID
        )
        try await repository.deleteMessage(
            conversationID: "27",
            messageID: "9001",
            clientRequestID: requestID
        )

        let requests = await transport.recordedRequests()
        XCTAssertEqual(requests.count, 3)
        let deleteFields = try decodeForm(requests[1].httpBody)
        XCTAssertEqual(deleteFields["api"], DsmAPIName.chatPost)
        XCTAssertEqual(deleteFields["method"], "delete")
        XCTAssertEqual(deleteFields["post_id"], "9001")
    }

    func test拒绝删除其他成员发送的消息且不发送写请求() async throws {
        let transport = MockHTTPTransport(responses: [
            response(#"{"success":true,"data":{"posts":[{"post_id":"9001","channel_id":"27","creator_id":"2","creator_name":"other","create_at":1774166400000,"message":"其他成员消息"}]}}"#)
        ])
        let repository = try makeRepository(transport: transport)

        do {
            try await repository.deleteMessage(
                conversationID: "27",
                messageID: "9001",
                clientRequestID: UUID()
            )
            XCTFail("应拒绝删除其他成员的消息")
        } catch let error as AppError {
            XCTAssertEqual(error.category, .permissionDenied)
        }

        let requests = await transport.recordedRequests()
        XCTAssertEqual(requests.count, 1)
    }

    func test关闭会话后复查会话已移除() async throws {
        let users = response(#"{"success":true,"data":{"current_user_id":"1","users":[{"user_id":"1","nickname":"testaccount"},{"user_id":"2","nickname":"other"}]}}"#)
        let existingChannels = response(#"{"success":true,"data":{"channels":[{"channel_id":"27","type":"anonymous","members":["1","2"]}]}}"#)
        let emptyChannels = response(#"{"success":true,"data":{"channels":[]}}"#)
        let transport = MockHTTPTransport(responses: [
            users,
            existingChannels,
            response(#"{"success":true}"#),
            users,
            emptyChannels
        ])
        let repository = try makeRepository(transport: transport)
        let requestID = UUID()

        try await repository.closeConversation(
            conversationID: "27",
            clientRequestID: requestID
        )
        try await repository.closeConversation(
            conversationID: "27",
            clientRequestID: requestID
        )

        let requests = await transport.recordedRequests()
        XCTAssertEqual(requests.count, 5)
        let closeFields = try decodeForm(requests[2].httpBody)
        XCTAssertEqual(closeFields["api"], DsmAPIName.chatChannel)
        XCTAssertEqual(closeFields["method"], "close")
        XCTAssertEqual(closeFields["channel_id"], "27")
    }

    private func makeRepository(
        transport: MockHTTPTransport,
        includesAvatarCapability: Bool = false
    ) throws -> DsmChatRepository {
        var names = [
            DsmAPIName.chatChannel: 5,
            DsmAPIName.chatChannelNamed: 1,
            DsmAPIName.chatUser: 3,
            DsmAPIName.chatPost: 8,
            DsmAPIName.chatPostReminder: 1
        ]
        if includesAvatarCapability {
            names[DsmAPIName.chatUserAvatar] = 1
        }
        let capabilities = CapabilitySet(Dictionary(uniqueKeysWithValues: names.map { name, version in
            (name, ApiCapability(
                name: name,
                path: "entry.cgi",
                minVersion: 1,
                maxVersion: version,
                requestFormat: .form,
                selectedVersion: version
            ))
        }))
        return try DsmChatRepository(
            profile: NasProfile(
                displayName: "测试设备",
                host: "nas.example.invalid",
                port: 5_001,
                usernameHint: "testaccount"
            ),
            capabilities: capabilities,
            session: AuthSession(
                sid: "SANITIZED_TEST_SID",
                synoToken: "SANITIZED_TEST_TOKEN",
                did: nil,
                isPortalPort: false
            ),
            transport: transport
        )
    }

    private func response(_ json: String) -> DsmHTTPResponse {
        DsmHTTPResponse(data: Data(json.utf8), statusCode: 200)
    }

    private func decodeForm(_ data: Data?) throws -> [String: String] {
        let body = try XCTUnwrap(data.flatMap { String(data: $0, encoding: .utf8) })
        let components = try XCTUnwrap(URLComponents(string: "?\(body)"))
        return Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map {
            ($0.name, $0.value ?? "")
        })
    }
}
