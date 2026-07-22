import Foundation

public enum ChatFeature: String, Codable, CaseIterable, Hashable, Sendable {
    case directConversation
    case groupConversation
    case textMessage
    case emoji
    case imageAttachment
    case videoAttachment
    case fileAttachment
    case voiceMessage
    case reminder
    case poll
    case encryptedConversation
    case deleteOwnMessage
    case closeConversation
}

public enum ChatAvailabilityStatus: String, Codable, Sendable {
    case unavailable
    case requiresValidation
    case available
}

public struct ChatAvailability: Codable, Equatable, Sendable {
    public let status: ChatAvailabilityStatus
    public let supportedFeatures: Set<ChatFeature>

    public init(
        status: ChatAvailabilityStatus,
        supportedFeatures: Set<ChatFeature> = []
    ) {
        self.status = status
        self.supportedFeatures = supportedFeatures
    }
}

public struct ChatUser: Identifiable, Codable, Hashable, Sendable {
    public let id: String
    public let displayName: String
    public let avatarAvailable: Bool?
    public let avatarData: Data?
    public let isDisabled: Bool
    public let isCurrentUser: Bool?

    public init(
        id: String,
        displayName: String,
        avatarAvailable: Bool? = nil,
        avatarData: Data? = nil,
        isDisabled: Bool = false,
        isCurrentUser: Bool? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.avatarAvailable = avatarAvailable
        self.avatarData = avatarData
        self.isDisabled = isDisabled
        self.isCurrentUser = isCurrentUser
    }
}

public enum ChatConversationKind: String, Codable, Sendable {
    case direct
    case group
}

public struct ChatConversation: Identifiable, Codable, Hashable, Sendable {
    public let id: String
    public let kind: ChatConversationKind
    public let title: String
    public let memberIDs: [String]
    public let memberCount: Int?
    public let lastMessageSummary: String?
    public let lastActivityAt: Date?
    public let unreadCount: Int
    public let isEncrypted: Bool

    public init(
        id: String,
        kind: ChatConversationKind,
        title: String,
        memberIDs: [String],
        memberCount: Int? = nil,
        lastMessageSummary: String? = nil,
        lastActivityAt: Date? = nil,
        unreadCount: Int = 0,
        isEncrypted: Bool = false
    ) {
        self.id = id
        self.kind = kind
        self.title = title
        self.memberIDs = memberIDs
        self.memberCount = memberCount.map { max(0, $0) }
        self.lastMessageSummary = lastMessageSummary
        self.lastActivityAt = lastActivityAt
        self.unreadCount = max(0, unreadCount)
        self.isEncrypted = isEncrypted
    }
}

public enum ChatAttachmentKind: String, Codable, Sendable {
    case image
    case video
    case file
    case voice
}

public struct ChatAttachment: Identifiable, Codable, Hashable, Sendable {
    public let id: String
    public let kind: ChatAttachmentKind
    public let fileName: String
    public let mediaType: String?
    public let sizeBytes: Int64?
    public let durationMilliseconds: Int64?
    public let thumbnailAvailable: Bool?

    public init(
        id: String,
        kind: ChatAttachmentKind,
        fileName: String,
        mediaType: String? = nil,
        sizeBytes: Int64? = nil,
        durationMilliseconds: Int64? = nil,
        thumbnailAvailable: Bool? = nil
    ) {
        self.id = id
        self.kind = kind
        self.fileName = fileName
        self.mediaType = mediaType
        self.sizeBytes = sizeBytes.map { max(0, $0) }
        self.durationMilliseconds = durationMilliseconds.map { max(0, $0) }
        self.thumbnailAvailable = thumbnailAvailable
    }
}

public enum ChatMessageDeliveryState: String, Codable, Sendable {
    case sending
    case sent
    case failed
}

public enum ChatEncryptionState: String, Codable, Sendable {
    case notEncrypted
    case locked
    case unlocked
    case recoveryRequired
    case unsupported
}

public struct ChatPollOption: Identifiable, Codable, Hashable, Sendable {
    public let id: String
    public let text: String
    public let voteCount: Int
    public let isSelectedByCurrentUser: Bool

    public init(
        id: String,
        text: String,
        voteCount: Int = 0,
        isSelectedByCurrentUser: Bool = false
    ) {
        self.id = id
        self.text = text
        self.voteCount = max(0, voteCount)
        self.isSelectedByCurrentUser = isSelectedByCurrentUser
    }
}

public struct ChatPoll: Identifiable, Codable, Hashable, Sendable {
    public let id: String
    public let question: String
    public let allowsMultipleSelection: Bool
    public let isAnonymous: Bool
    public let closesAt: Date?
    public let isClosed: Bool
    public let options: [ChatPollOption]

    public init(
        id: String,
        question: String,
        allowsMultipleSelection: Bool,
        isAnonymous: Bool,
        closesAt: Date? = nil,
        isClosed: Bool = false,
        options: [ChatPollOption]
    ) {
        self.id = id
        self.question = question
        self.allowsMultipleSelection = allowsMultipleSelection
        self.isAnonymous = isAnonymous
        self.closesAt = closesAt
        self.isClosed = isClosed
        self.options = options
    }
}

public struct ChatMessage: Identifiable, Codable, Hashable, Sendable {
    public let id: String
    public let clientRequestID: UUID?
    public let conversationID: String
    public let senderID: String
    public let senderDisplayName: String?
    public let isFromCurrentUser: Bool?
    public let sentAt: Date
    public let text: String?
    public let attachments: [ChatAttachment]
    public let poll: ChatPoll?
    public let deliveryState: ChatMessageDeliveryState
    public let encryptionState: ChatEncryptionState

    public init(
        id: String,
        clientRequestID: UUID? = nil,
        conversationID: String,
        senderID: String,
        senderDisplayName: String? = nil,
        isFromCurrentUser: Bool? = nil,
        sentAt: Date,
        text: String? = nil,
        attachments: [ChatAttachment] = [],
        poll: ChatPoll? = nil,
        deliveryState: ChatMessageDeliveryState = .sent,
        encryptionState: ChatEncryptionState = .notEncrypted
    ) {
        self.id = id
        self.clientRequestID = clientRequestID
        self.conversationID = conversationID
        self.senderID = senderID
        self.senderDisplayName = senderDisplayName
        self.isFromCurrentUser = isFromCurrentUser
        self.sentAt = sentAt
        self.text = text
        self.attachments = attachments
        self.poll = poll
        self.deliveryState = deliveryState
        self.encryptionState = encryptionState
    }
}

public struct ChatMessagePage: Codable, Equatable, Sendable {
    public let messages: [ChatMessage]
    public let previousCursor: String?
    public let hasMoreBefore: Bool

    public init(
        messages: [ChatMessage],
        previousCursor: String?,
        hasMoreBefore: Bool
    ) {
        self.messages = messages
        self.previousCursor = previousCursor
        self.hasMoreBefore = hasMoreBefore
    }
}

public struct ChatReminder: Identifiable, Codable, Hashable, Sendable {
    public let id: String
    public let messageID: String
    public let remindAt: Date

    public init(id: String, messageID: String, remindAt: Date) {
        self.id = id
        self.messageID = messageID
        self.remindAt = remindAt
    }
}

public enum ChatContractError: Error, Equatable, Sendable {
    case emptyUserID
    case emptyConversationID
    case emptyGroupTitle
    case insufficientGroupMembers
    case emptyMessage
    case emptyPollQuestion
    case insufficientPollOptions
    case duplicatePollOptions
}

extension ChatContractError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .emptyUserID:
            "请选择要聊天的用户。"
        case .emptyConversationID:
            "没有找到这段聊天，请返回会话列表后重试。"
        case .emptyGroupTitle:
            "请输入群聊名称。"
        case .insufficientGroupMembers:
            "请至少选择两位成员创建群聊。"
        case .emptyMessage:
            "请输入消息或添加附件。"
        case .emptyPollQuestion:
            "请输入投票问题。"
        case .insufficientPollOptions:
            "请至少填写两个投票选项。"
        case .duplicatePollOptions:
            "投票选项不能重复。"
        }
    }
}

public struct ChatGroupDraft: Equatable, Sendable {
    public let clientRequestID: UUID
    public let title: String
    public let memberIDs: [String]
    public let isEncrypted: Bool

    public init(
        clientRequestID: UUID = UUID(),
        title: String,
        memberIDs: [String],
        isEncrypted: Bool
    ) throws {
        let normalizedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedTitle.isEmpty else { throw ChatContractError.emptyGroupTitle }
        let normalizedMembers = memberIDs
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let uniqueMembers = Array(Set(normalizedMembers)).sorted()
        guard uniqueMembers.count >= 2 else {
            throw ChatContractError.insufficientGroupMembers
        }
        self.clientRequestID = clientRequestID
        self.title = normalizedTitle
        self.memberIDs = uniqueMembers
        self.isEncrypted = isEncrypted
    }
}

public struct ChatMessageDraft: Equatable, Sendable {
    public let clientRequestID: UUID
    public let conversationID: String
    public let text: String?
    public let localAttachmentURLs: [URL]

    public init(
        clientRequestID: UUID = UUID(),
        conversationID: String,
        text: String?,
        localAttachmentURLs: [URL] = []
    ) throws {
        let normalizedConversationID = conversationID
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedConversationID.isEmpty else {
            throw ChatContractError.emptyConversationID
        }
        let normalizedText = text?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard normalizedText?.isEmpty == false || !localAttachmentURLs.isEmpty else {
            throw ChatContractError.emptyMessage
        }
        self.clientRequestID = clientRequestID
        self.conversationID = normalizedConversationID
        self.text = normalizedText?.isEmpty == false ? normalizedText : nil
        self.localAttachmentURLs = localAttachmentURLs
    }
}

public struct ChatPollDraft: Equatable, Sendable {
    public let clientRequestID: UUID
    public let conversationID: String
    public let question: String
    public let options: [String]
    public let allowsMultipleSelection: Bool
    public let isAnonymous: Bool
    public let closesAt: Date?

    public init(
        clientRequestID: UUID = UUID(),
        conversationID: String,
        question: String,
        options: [String],
        allowsMultipleSelection: Bool,
        isAnonymous: Bool,
        closesAt: Date? = nil
    ) throws {
        let normalizedConversationID = conversationID
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedConversationID.isEmpty else {
            throw ChatContractError.emptyConversationID
        }
        let normalizedQuestion = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedQuestion.isEmpty else { throw ChatContractError.emptyPollQuestion }
        let normalizedOptions = options
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard normalizedOptions.count >= 2 else {
            throw ChatContractError.insufficientPollOptions
        }
        let canonicalOptions = normalizedOptions.map { $0.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: .current
        ) }
        guard Set(canonicalOptions).count == normalizedOptions.count else {
            throw ChatContractError.duplicatePollOptions
        }
        self.clientRequestID = clientRequestID
        self.conversationID = normalizedConversationID
        self.question = normalizedQuestion
        self.options = normalizedOptions
        self.allowsMultipleSelection = allowsMultipleSelection
        self.isAnonymous = isAnonymous
        self.closesAt = closesAt
    }
}

public protocol ChatRepository: Sendable {
    func availability() async -> ChatAvailability
    func listUsers() async throws -> [ChatUser]
    func listConversations() async throws -> [ChatConversation]
    func listMessages(
        conversationID: String,
        before cursor: String?,
        limit: Int
    ) async throws -> ChatMessagePage
    func openDirectConversation(
        userID: String,
        clientRequestID: UUID
    ) async throws -> ChatConversation
    func createGroup(_ draft: ChatGroupDraft) async throws -> ChatConversation
    func sendMessage(_ draft: ChatMessageDraft) async throws -> ChatMessage
    func deleteMessage(
        conversationID: String,
        messageID: String,
        clientRequestID: UUID
    ) async throws
    func closeConversation(
        conversationID: String,
        clientRequestID: UUID
    ) async throws
    func setReminder(
        messageID: String,
        remindAt: Date,
        clientRequestID: UUID
    ) async throws -> ChatReminder
    func createPoll(_ draft: ChatPollDraft) async throws -> ChatMessage
}
