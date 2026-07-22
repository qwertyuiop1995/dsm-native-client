import Foundation
import XCTest
@testable import DsmCore

final class ChatTests: XCTestCase {
    func test群聊草稿会清理空白并去除重复成员() throws {
        let draft = try ChatGroupDraft(
            clientRequestID: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            title: "  周末计划  ",
            memberIDs: ["user-b", "user-a", "user-b", " "],
            isEncrypted: true
        )

        XCTAssertEqual(draft.title, "周末计划")
        XCTAssertEqual(draft.memberIDs, ["user-a", "user-b"])
        XCTAssertTrue(draft.isEncrypted)
    }

    func test群聊至少需要两位成员() {
        XCTAssertThrowsError(
            try ChatGroupDraft(
                title: "项目群",
                memberIDs: ["user-a", "user-a"],
                isEncrypted: false
            )
        ) { error in
            XCTAssertEqual(error as? ChatContractError, ChatContractError.insufficientGroupMembers)
        }
    }

    func test消息必须包含文字或附件() {
        XCTAssertThrowsError(
            try ChatMessageDraft(conversationID: "conversation-1", text: "  ")
        ) { error in
            XCTAssertEqual(error as? ChatContractError, ChatContractError.emptyMessage)
        }
    }

    func test组合表情作为完整消息保留() throws {
        let emoji = "👨‍👩‍👧‍👦 👍🏽 🇨🇳"
        let draft = try ChatMessageDraft(
            conversationID: "conversation-1",
            text: emoji
        )

        XCTAssertEqual(draft.text, emoji)
        XCTAssertEqual(draft.text?.count, 5)
    }

    func test投票拒绝忽略大小写后的重复选项() {
        XCTAssertThrowsError(
            try ChatPollDraft(
                conversationID: "conversation-1",
                question: "选哪个？",
                options: ["方案 A", "方案 a"],
                allowsMultipleSelection: false,
                isAnonymous: false
            )
        ) { error in
            XCTAssertEqual(error as? ChatContractError, ChatContractError.duplicatePollOptions)
        }
    }

    func test消息模型忽略未知字段并解码加密附件() throws {
        let data = Data(
            #"""
            {
              "id":"message-1",
              "conversationID":"conversation-1",
              "senderID":"user-1",
              "sentAt":"2026-07-22T12:00:00Z",
              "text":"你好 👋",
              "attachments":[{
                "id":"attachment-1",
                "kind":"voice",
                "fileName":"voice.m4a",
                "sizeBytes":2048,
                "durationMilliseconds":3500,
                "server_only_field":"ignored"
              }],
              "deliveryState":"sent",
              "encryptionState":"unlocked",
              "server_only_field":"ignored"
            }
            """#.utf8
        )
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let message = try decoder.decode(ChatMessage.self, from: data)

        XCTAssertEqual(message.text, "你好 👋")
        XCTAssertEqual(message.attachments.first?.kind, .voice)
        XCTAssertEqual(message.attachments.first?.durationMilliseconds, 3_500)
        XCTAssertEqual(message.encryptionState, .unlocked)
    }
}
