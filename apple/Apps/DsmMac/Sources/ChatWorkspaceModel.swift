import DsmCore
import Foundation
import Observation

@MainActor
@Observable
final class ChatWorkspaceModel {
    private(set) var availability = ChatAvailability(status: .requiresValidation)
    private(set) var conversations: [ChatConversation] = []
    private(set) var users: [ChatUser] = []
    private(set) var messages: [ChatMessage] = []
    private(set) var selectedConversationID: String?
    private(set) var isLoading = false
    private(set) var isLoadingMessages = false
    private(set) var isPerformingAction = false
    private(set) var statusMessage: String?
    private(set) var statusIsError = false

    @ObservationIgnored private let repository: any ChatRepository
    @ObservationIgnored private let currentAccountName: String?
    @ObservationIgnored private var hasLoaded = false

    init(
        repository: any ChatRepository,
        currentAccountName: String? = nil
    ) {
        self.repository = repository
        self.currentAccountName = Self.normalizedIdentityName(currentAccountName)
    }

    var selectedConversation: ChatConversation? {
        guard let selectedConversationID else { return nil }
        return conversations.first { $0.id == selectedConversationID }
    }

    var currentUserID: String? {
        if let explicitUserID = users.first(where: { $0.isCurrentUser == true })?.id {
            return explicitUserID
        }
        guard let currentAccountName else { return nil }
        return users.first {
            Self.normalizedIdentityName($0.displayName) == currentAccountName
        }?.id
    }

    func displayName(for userID: String) -> String? {
        users.first(where: { $0.id == userID })?.displayName
    }

    func isCurrentUser(_ message: ChatMessage) -> Bool {
        if message.isFromCurrentUser == true { return true }
        if message.clientRequestID != nil { return true }
        if currentUserID == message.senderID { return true }
        if let currentAccountName {
            let senderName = message.senderDisplayName
                ?? users.first(where: { $0.id == message.senderID })?.displayName
            if Self.normalizedIdentityName(senderName) == currentAccountName {
                return true
            }
        }
        return false
    }

    private static func normalizedIdentityName(_ value: String?) -> String? {
        let normalized = value?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return normalized?.isEmpty == false ? normalized : nil
    }

    func memberSummary(for conversation: ChatConversation) -> String {
        guard conversation.kind == .group else { return "一对一聊天" }
        let names = conversation.memberIDs.compactMap(displayName(for:))
        let count = conversation.memberCount ?? conversation.memberIDs.count
        if !names.isEmpty {
            let prefix = count > 0 ? "\(count) 位成员 · " : ""
            return prefix + names.prefix(4).joined(separator: "、")
                + (names.count > 4 ? " 等" : "")
        }
        return count > 0 ? "\(count) 位成员" : "群聊"
    }

    var canUseMessaging: Bool {
        availability.status == .available
    }

    var canCreateDirectConversation: Bool {
        canUseMessaging && availability.supportedFeatures.contains(.directConversation)
    }

    var canCreateGroupConversation: Bool {
        canUseMessaging && availability.supportedFeatures.contains(.groupConversation)
    }

    var canSendText: Bool {
        canUseMessaging && availability.supportedFeatures.contains(.textMessage)
    }

    var canSendAttachments: Bool {
        let features = availability.supportedFeatures
        return canUseMessaging && (
            features.contains(.imageAttachment)
                || features.contains(.videoAttachment)
                || features.contains(.fileAttachment)
        )
    }

    var canDeleteOwnMessages: Bool {
        canUseMessaging && availability.supportedFeatures.contains(.deleteOwnMessage)
    }

    var canCloseConversations: Bool {
        canUseMessaging && availability.supportedFeatures.contains(.closeConversation)
    }

    func canDelete(_ message: ChatMessage) -> Bool {
        canDeleteOwnMessages && isCurrentUser(message)
    }

    func loadIfNeeded() async {
        guard !hasLoaded else { return }
        await reload()
    }

    func reload() async {
        guard !isLoading else { return }
        isLoading = true
        statusMessage = nil
        statusIsError = false
        defer {
            isLoading = false
            hasLoaded = true
        }

        let discoveredAvailability = await repository.availability()
        availability = discoveredAvailability
        guard discoveredAvailability.status == .available else {
            conversations = []
            users = []
            messages = []
            selectedConversationID = nil
            statusMessage = availabilityMessage(for: discoveredAvailability.status)
            return
        }

        do {
            async let loadedConversations = repository.listConversations()
            async let loadedUsers = repository.listUsers()
            conversations = try await loadedConversations.sorted(by: Self.conversationSort)
            users = try await loadedUsers
                .filter { !$0.isDisabled }
                .sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }

            if let selectedConversationID,
               conversations.contains(where: { $0.id == selectedConversationID }) {
                await selectConversation(id: selectedConversationID)
            } else if let first = conversations.first {
                await selectConversation(id: first.id)
            } else {
                selectedConversationID = nil
                messages = []
            }
        } catch {
            show(error)
        }
    }

    func selectConversation(id: String?) async {
        guard canUseMessaging else { return }
        guard let id else {
            selectedConversationID = nil
            messages = []
            return
        }
        guard conversations.contains(where: { $0.id == id }) else { return }
        selectedConversationID = id
        isLoadingMessages = true
        statusMessage = nil
        statusIsError = false
        defer { isLoadingMessages = false }
        do {
            let page = try await repository.listMessages(
                conversationID: id,
                before: nil,
                limit: 50
            )
            guard selectedConversationID == id else { return }
            messages = page.messages.sorted { $0.sentAt < $1.sentAt }
        } catch {
            guard selectedConversationID == id else { return }
            messages = []
            show(error)
        }
    }

    func openDirectConversation(userID: String) async -> Bool {
        guard canCreateDirectConversation, !isPerformingAction else { return false }
        isPerformingAction = true
        defer { isPerformingAction = false }
        do {
            let conversation = try await repository.openDirectConversation(
                userID: userID,
                clientRequestID: UUID()
            )
            merge(conversation)
            await selectConversation(id: conversation.id)
            return true
        } catch {
            show(error)
            return false
        }
    }

    func createGroup(title: String, memberIDs: [String], isEncrypted: Bool) async -> Bool {
        guard canCreateGroupConversation, !isPerformingAction else { return false }
        isPerformingAction = true
        defer { isPerformingAction = false }
        do {
            let draft = try ChatGroupDraft(
                title: title,
                memberIDs: memberIDs,
                isEncrypted: isEncrypted
            )
            let conversation = try await repository.createGroup(draft)
            merge(conversation)
            await selectConversation(id: conversation.id)
            return true
        } catch {
            show(error)
            return false
        }
    }

    func send(text: String?, attachmentURLs: [URL] = []) async -> Bool {
        guard let selectedConversationID, !isPerformingAction else { return false }
        guard canSendText || (!attachmentURLs.isEmpty && canSendAttachments) else { return false }
        isPerformingAction = true
        defer { isPerformingAction = false }
        do {
            let draft = try ChatMessageDraft(
                conversationID: selectedConversationID,
                text: text,
                localAttachmentURLs: attachmentURLs
            )
            let message = try await repository.sendMessage(draft)
            guard self.selectedConversationID == selectedConversationID else { return true }
            if let index = messages.firstIndex(where: { $0.id == message.id }) {
                messages[index] = message
            } else {
                messages.append(message)
            }
            messages.sort { $0.sentAt < $1.sentAt }
            return true
        } catch {
            show(error)
            return false
        }
    }

    @discardableResult
    func deleteMessages(ids: Set<String>) async -> Int {
        guard canDeleteOwnMessages, !isPerformingAction, !ids.isEmpty,
              let conversationID = selectedConversationID else { return 0 }
        let targets = messages.filter { ids.contains($0.id) }
        guard targets.count == ids.count, targets.allSatisfy(canDelete) else {
            statusIsError = true
            statusMessage = "只能删除自己发送的消息。"
            return 0
        }

        isPerformingAction = true
        statusMessage = nil
        statusIsError = false
        var deletedCount = 0
        var deletedIDs: Set<String> = []
        var lastError: Error?
        for message in targets {
            do {
                try await repository.deleteMessage(
                    conversationID: conversationID,
                    messageID: message.id,
                    clientRequestID: UUID()
                )
                deletedCount += 1
                deletedIDs.insert(message.id)
            } catch {
                lastError = error
            }
        }
        // Repository 已经完成服务端回读校验，直接同步本地列表，避免再次刷新失败
        // 覆盖“删除成功”的结果，也减少一次不必要的历史消息请求。
        if selectedConversationID == conversationID, !deletedIDs.isEmpty {
            messages.removeAll { deletedIDs.contains($0.id) }
        }
        isPerformingAction = false
        if let lastError {
            showBatchFailure(
                completedCount: deletedCount,
                failedCount: targets.count - deletedCount,
                noun: "条消息",
                lastError: lastError
            )
        } else {
            statusMessage = deletedCount == 1 ? "消息已删除。" : "已删除 \(deletedCount) 条消息。"
            statusIsError = false
        }
        return deletedCount
    }

    @discardableResult
    func closeConversations(ids: Set<String>) async -> Int {
        guard canCloseConversations, !isPerformingAction, !ids.isEmpty else { return 0 }
        let targets = conversations.filter { ids.contains($0.id) }
        guard targets.count == ids.count else { return 0 }

        isPerformingAction = true
        statusMessage = nil
        statusIsError = false
        var closedCount = 0
        var closedIDs: Set<String> = []
        var lastError: Error?
        for conversation in targets {
            do {
                try await repository.closeConversation(
                    conversationID: conversation.id,
                    clientRequestID: UUID()
                )
                closedCount += 1
                closedIDs.insert(conversation.id)
            } catch {
                lastError = error
            }
        }
        // 关闭接口内部已经复查会话列表。这里直接更新本地状态，避免额外的全量刷新
        // 将已经成功的关闭操作错误显示成失败。
        if !closedIDs.isEmpty {
            conversations.removeAll { closedIDs.contains($0.id) }
            if let selectedConversationID, closedIDs.contains(selectedConversationID) {
                self.selectedConversationID = nil
                messages = []
            }
        }
        isPerformingAction = false
        if let lastError {
            showBatchFailure(
                completedCount: closedCount,
                failedCount: targets.count - closedCount,
                noun: "个会话",
                lastError: lastError
            )
        } else {
            statusMessage = closedCount == 1 ? "会话已删除，消息已进入群晖 Chat 归档。" : "已删除 \(closedCount) 个会话，消息已进入群晖 Chat 归档。"
            statusIsError = false
        }
        return closedCount
    }

    func clearStatus() {
        statusMessage = nil
        statusIsError = false
    }

    private func merge(_ conversation: ChatConversation) {
        conversations.removeAll { $0.id == conversation.id }
        conversations.append(conversation)
        conversations.sort(by: Self.conversationSort)
    }

    private func show(_ error: Error) {
        statusIsError = true
        if let appError = error as? AppError {
            statusMessage = appError.safeUserMessage
        } else if let localizedError = error as? LocalizedError,
                  let description = localizedError.errorDescription {
            statusMessage = description
        } else {
            statusMessage = "消息暂时没有完成，请稍后重试。"
        }
    }

    private func showBatchFailure(
        completedCount: Int,
        failedCount: Int,
        noun: String,
        lastError: Error
    ) {
        statusIsError = true
        let detail: String
        if let appError = lastError as? AppError {
            detail = appError.safeUserMessage
        } else if let localizedError = lastError as? LocalizedError,
                  let description = localizedError.errorDescription {
            detail = description
        } else {
            detail = "请刷新后重试。"
        }
        if completedCount > 0 {
            statusMessage = "已处理 \(completedCount) \(noun)，另有 \(failedCount) \(noun)未完成。\(detail)"
        } else {
            statusMessage = detail
        }
    }

    private func availabilityMessage(for status: ChatAvailabilityStatus) -> String {
        switch status {
        case .available:
            "消息服务已就绪。"
        case .requiresValidation:
            "岚仓暂时还不能安全连接这台 NAS 的消息服务。准备完成前不会尝试发送消息，你仍可以继续使用文件和照片功能。"
        case .unavailable:
            "这台 NAS 当前没有可用的消息服务。请确认已安装并启用 Synology Chat Server，且当前账号具有使用权限。"
        }
    }

    private static func conversationSort(_ lhs: ChatConversation, _ rhs: ChatConversation) -> Bool {
        switch (lhs.lastActivityAt, rhs.lastActivityAt) {
        case let (left?, right?) where left != right:
            left > right
        case (nil, _?):
            false
        case (_?, nil):
            true
        default:
            lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
        }
    }
}
