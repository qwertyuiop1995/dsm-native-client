import DsmCore
import DsmNetwork
import Foundation
import XCTest
@testable import DsmMacExecutable

@MainActor
final class ChatWorkspaceModelTests: XCTestCase {
    func test未验证服务保持关闭且不展示空会话误导用户() async {
        let model = ChatWorkspaceModel(repository: UnverifiedDsmChatRepository())

        await model.loadIfNeeded()

        XCTAssertEqual(model.availability.status, .requiresValidation)
        XCTAssertFalse(model.canUseMessaging)
        XCTAssertTrue(model.conversations.isEmpty)
        XCTAssertTrue(model.messages.isEmpty)
        XCTAssertTrue(model.statusMessage?.contains("安全连接") == true)
    }

    func test可用服务按最近活动排序并载入第一段会话() async throws {
        let recentDate = Date(timeIntervalSince1970: 2_000)
        let oldDate = Date(timeIntervalSince1970: 1_000)
        let recent = conversation(id: "recent", title: "最近聊天", activity: recentDate)
        let old = conversation(id: "old", title: "较早聊天", activity: oldDate)
        let repository = ChatRepositoryStub(
            conversations: [old, recent],
            messagesByConversation: [
                "recent": [message(id: "message-1", conversationID: "recent", date: recentDate)]
            ]
        )
        let model = ChatWorkspaceModel(repository: repository)

        await model.loadIfNeeded()

        XCTAssertEqual(model.conversations.map(\.id), ["recent", "old"])
        XCTAssertEqual(model.selectedConversationID, "recent")
        XCTAssertEqual(model.messages.map(\.id), ["message-1"])
        XCTAssertTrue(model.canSendText)
    }

    func test发送成功后加入当前会话且清理文字空白() async throws {
        let activeConversation = conversation(
            id: "conversation-1",
            title: "测试聊天",
            activity: Date(timeIntervalSince1970: 1_000)
        )
        let repository = ChatRepositoryStub(conversations: [activeConversation])
        let model = ChatWorkspaceModel(repository: repository)
        await model.loadIfNeeded()

        let succeeded = await model.send(text: "  你好 👋  ")
        let sentTexts = await repository.sentTexts()

        XCTAssertTrue(succeeded)
        XCTAssertEqual(model.messages.last?.text, "你好 👋")
        XCTAssertEqual(sentTexts, ["你好 👋"])
    }

    func test使用登录账号识别当前用户并将其消息标记为自己() async {
        let repository = ChatRepositoryStub(
            conversations: [conversation(
                id: "conversation-1",
                title: "测试聊天",
                activity: Date(timeIntervalSince1970: 1_000)
            )],
            users: [ChatUser(id: "user-1", displayName: "YuangY")]
        )
        let model = ChatWorkspaceModel(
            repository: repository,
            currentAccountName: " yuangy "
        )
        await model.loadIfNeeded()
        let ownMessage = ChatMessage(
            id: "message-1",
            conversationID: "conversation-1",
            senderID: "user-1",
            isFromCurrentUser: false,
            sentAt: Date(),
            text: "这是我发送的消息"
        )

        XCTAssertEqual(model.currentUserID, "user-1")
        XCTAssertTrue(model.isCurrentUser(ownMessage))
    }

    func test登录账号不会把其他成员的消息标记为自己() async {
        let repository = ChatRepositoryStub(
            conversations: [conversation(
                id: "conversation-1",
                title: "测试聊天",
                activity: Date(timeIntervalSince1970: 1_000)
            )],
            users: [
                ChatUser(id: "current-user", displayName: "yuangy"),
                ChatUser(id: "other-user", displayName: "chenwh")
            ]
        )
        let model = ChatWorkspaceModel(
            repository: repository,
            currentAccountName: "yuangy"
        )
        await model.loadIfNeeded()
        let otherMessage = ChatMessage(
            id: "message-2",
            conversationID: "conversation-1",
            senderID: "other-user",
            senderDisplayName: "chenwh",
            sentAt: Date(),
            text: "这是其他成员的消息"
        )

        XCTAssertFalse(model.isCurrentUser(otherMessage))
    }

    func test批量删除自己的消息后直接同步当前会话() async {
        let activeConversation = conversation(
            id: "conversation-1",
            title: "测试聊天",
            activity: Date(timeIntervalSince1970: 1_000)
        )
        let ownMessages = ["message-1", "message-2"].map { id in
            ChatMessage(
                id: id,
                conversationID: activeConversation.id,
                senderID: "current-user",
                isFromCurrentUser: true,
                sentAt: Date(),
                text: "待删除消息"
            )
        }
        let repository = ChatRepositoryStub(
            conversations: [activeConversation],
            messagesByConversation: [activeConversation.id: ownMessages]
        )
        let model = ChatWorkspaceModel(repository: repository)
        await model.loadIfNeeded()

        let deletedCount = await model.deleteMessages(ids: Set(ownMessages.map(\.id)))

        XCTAssertEqual(deletedCount, 2)
        XCTAssertTrue(model.messages.isEmpty)
        XCTAssertEqual(model.statusMessage, "已删除 2 条消息。")
    }

    func test不能删除其他成员发送的消息() async {
        let activeConversation = conversation(
            id: "conversation-1",
            title: "测试聊天",
            activity: Date(timeIntervalSince1970: 1_000)
        )
        let otherMessage = ChatMessage(
            id: "message-1",
            conversationID: activeConversation.id,
            senderID: "other-user",
            isFromCurrentUser: false,
            sentAt: Date(),
            text: "其他成员消息"
        )
        let repository = ChatRepositoryStub(
            conversations: [activeConversation],
            messagesByConversation: [activeConversation.id: [otherMessage]]
        )
        let model = ChatWorkspaceModel(repository: repository)
        await model.loadIfNeeded()

        let deletedCount = await model.deleteMessages(ids: [otherMessage.id])

        XCTAssertEqual(deletedCount, 0)
        XCTAssertEqual(model.messages.map(\.id), [otherMessage.id])
        XCTAssertEqual(model.statusMessage, "只能删除自己发送的消息。")
    }

    func test批量关闭会话后直接同步会话列表() async {
        let first = conversation(id: "conversation-1", title: "聊天一", activity: Date())
        let second = conversation(id: "conversation-2", title: "聊天二", activity: Date())
        let repository = ChatRepositoryStub(conversations: [first, second])
        let model = ChatWorkspaceModel(repository: repository)
        await model.loadIfNeeded()

        let closedCount = await model.closeConversations(ids: [first.id, second.id])

        XCTAssertEqual(closedCount, 2)
        XCTAssertTrue(model.conversations.isEmpty)
        XCTAssertNil(model.selectedConversationID)
        XCTAssertEqual(model.statusMessage, "已删除 2 个会话，消息已进入群晖 Chat 归档。")
    }

    private func conversation(
        id: String,
        title: String,
        activity: Date
    ) -> ChatConversation {
        ChatConversation(
            id: id,
            kind: .direct,
            title: title,
            memberIDs: ["user-1"],
            lastMessageSummary: "上一条消息",
            lastActivityAt: activity
        )
    }

    private func message(id: String, conversationID: String, date: Date) -> ChatMessage {
        ChatMessage(
            id: id,
            conversationID: conversationID,
            senderID: "user-1",
            sentAt: date,
            text: "测试消息"
        )
    }
}

private actor ChatRepositoryStub: ChatRepository {
    private let availableFeatures: Set<ChatFeature>
    private var storedConversations: [ChatConversation]
    private let users: [ChatUser]
    private var messagesByConversation: [String: [ChatMessage]]
    private var recordedSentTexts: [String] = []

    init(
        conversations: [ChatConversation],
        users: [ChatUser] = [ChatUser(id: "user-1", displayName: "测试用户")],
        messagesByConversation: [String: [ChatMessage]] = [:],
        availableFeatures: Set<ChatFeature> = [
            .directConversation,
            .groupConversation,
            .textMessage,
            .emoji,
            .imageAttachment,
            .videoAttachment,
            .fileAttachment,
            .deleteOwnMessage,
            .closeConversation
        ]
    ) {
        self.storedConversations = conversations
        self.users = users
        self.messagesByConversation = messagesByConversation
        self.availableFeatures = availableFeatures
    }

    func availability() async -> ChatAvailability {
        ChatAvailability(status: .available, supportedFeatures: availableFeatures)
    }

    func listUsers() async throws -> [ChatUser] {
        users
    }

    func listConversations() async throws -> [ChatConversation] {
        storedConversations
    }

    func listMessages(
        conversationID: String,
        before cursor: String?,
        limit: Int
    ) async throws -> ChatMessagePage {
        ChatMessagePage(
            messages: Array((messagesByConversation[conversationID] ?? []).suffix(limit)),
            previousCursor: nil,
            hasMoreBefore: false
        )
    }

    func openDirectConversation(
        userID: String,
        clientRequestID: UUID
    ) async throws -> ChatConversation {
        let opened = ChatConversation(
            id: "direct-\(userID)",
            kind: .direct,
            title: users.first(where: { $0.id == userID })?.displayName ?? "聊天",
            memberIDs: [userID]
        )
        storedConversations.append(opened)
        return opened
    }

    func createGroup(_ draft: ChatGroupDraft) async throws -> ChatConversation {
        let created = ChatConversation(
            id: "group-1",
            kind: .group,
            title: draft.title,
            memberIDs: draft.memberIDs,
            isEncrypted: draft.isEncrypted
        )
        storedConversations.append(created)
        return created
    }

    func sendMessage(_ draft: ChatMessageDraft) async throws -> ChatMessage {
        recordedSentTexts.append(draft.text ?? "")
        let sent = ChatMessage(
            id: "sent-\(recordedSentTexts.count)",
            clientRequestID: draft.clientRequestID,
            conversationID: draft.conversationID,
            senderID: "current-user",
            sentAt: Date(timeIntervalSince1970: 3_000 + Double(recordedSentTexts.count)),
            text: draft.text
        )
        messagesByConversation[draft.conversationID, default: []].append(sent)
        return sent
    }

    func deleteMessage(
        conversationID: String,
        messageID: String,
        clientRequestID: UUID
    ) async throws {
        messagesByConversation[conversationID, default: []].removeAll { $0.id == messageID }
    }

    func closeConversation(
        conversationID: String,
        clientRequestID: UUID
    ) async throws {
        storedConversations.removeAll { $0.id == conversationID }
        messagesByConversation[conversationID] = nil
    }

    func setReminder(
        messageID: String,
        remindAt: Date,
        clientRequestID: UUID
    ) async throws -> ChatReminder {
        ChatReminder(id: "reminder-1", messageID: messageID, remindAt: remindAt)
    }

    func createPoll(_ draft: ChatPollDraft) async throws -> ChatMessage {
        ChatMessage(
            id: "poll-1",
            clientRequestID: draft.clientRequestID,
            conversationID: draft.conversationID,
            senderID: "current-user",
            sentAt: Date(timeIntervalSince1970: 4_000),
            poll: ChatPoll(
                id: "poll-1",
                question: draft.question,
                allowsMultipleSelection: draft.allowsMultipleSelection,
                isAnonymous: draft.isAnonymous,
                closesAt: draft.closesAt,
                options: draft.options.enumerated().map { index, text in
                    ChatPollOption(id: "option-\(index)", text: text)
                }
            )
        )
    }

    func sentTexts() -> [String] {
        recordedSentTexts
    }
}
