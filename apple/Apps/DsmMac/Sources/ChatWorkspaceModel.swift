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
    private(set) var isLoadingEarlierMessages = false
    private(set) var isRefreshingMessages = false
    private(set) var hasMoreMessagesBefore = false
    private(set) var newMessageCount = 0
    private(set) var isPerformingAction = false
    private(set) var statusMessage: String?
    private(set) var statusIsError = false
    private(set) var activeToast: ToastMessage?
    private(set) var uploadProgressByMessageID: [String: Double] = [:]

    @ObservationIgnored private let repository: any ChatRepository
    @ObservationIgnored private let currentAccountName: String?
    @ObservationIgnored private var hasLoaded = false
    @ObservationIgnored private var previousMessageCursor: String?
    @ObservationIgnored private var toastDismissTask: Task<Void, Never>?
    @ObservationIgnored private var sendTasksByMessageID: [String: Task<ChatMessage, Error>] = [:]
    private var draftsByConversationID: [String: String] = [:]
    private var failedMessageErrorsByID: [String: String] = [:]
    private var localOutgoingMessagesByConversationID: [String: [ChatMessage]] = [:]
    private var draftsByLocalMessageID: [String: ChatMessageDraft] = [:]

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

    var canCreatePoll: Bool {
        canUseMessaging && availability.supportedFeatures.contains(.poll)
    }

    var canDeleteOwnMessages: Bool {
        canUseMessaging && availability.supportedFeatures.contains(.deleteOwnMessage)
    }

    var canCloseConversations: Bool {
        canUseMessaging && availability.supportedFeatures.contains(.closeConversation)
    }

    func canDelete(_ message: ChatMessage) -> Bool {
        canDeleteOwnMessages && message.deliveryState == .sent && isCurrentUser(message)
    }

    func draftText(for conversationID: String) -> String {
        draftsByConversationID[conversationID] ?? ""
    }

    func updateDraft(_ text: String, for conversationID: String) {
        if text.isEmpty {
            draftsByConversationID[conversationID] = nil
        } else {
            draftsByConversationID[conversationID] = text
        }
    }

    func sendFailureMessage(for messageID: String) -> String? {
        failedMessageErrorsByID[messageID]
    }

    func uploadProgress(for messageID: String) -> Double? {
        uploadProgressByMessageID[messageID]
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
            previousMessageCursor = nil
            hasMoreMessagesBefore = false
            newMessageCount = 0
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
            messages = Self.mergedMessages(
                page.messages,
                localOutgoingMessagesByConversationID[id] ?? []
            )
            previousMessageCursor = page.previousCursor
            hasMoreMessagesBefore = page.hasMoreBefore
            newMessageCount = 0
        } catch {
            guard selectedConversationID == id else { return }
            messages = []
            previousMessageCursor = nil
            hasMoreMessagesBefore = false
            newMessageCount = 0
            show(error)
        }
    }

    /// 读取更早的消息并插入列表顶部。返回分页前的首条消息 ID，供界面保持滚动位置。
    func loadEarlierMessages() async -> String? {
        guard canUseMessaging, !isLoadingEarlierMessages, hasMoreMessagesBefore,
              let conversationID = selectedConversationID,
              let cursor = previousMessageCursor else { return nil }
        let anchorID = messages.first?.id
        isLoadingEarlierMessages = true
        defer { isLoadingEarlierMessages = false }
        do {
            let page = try await repository.listMessages(
                conversationID: conversationID,
                before: cursor,
                limit: 50
            )
            guard selectedConversationID == conversationID else { return nil }
            messages = Self.mergedMessages(page.messages, messages)
            previousMessageCursor = page.previousCursor
            hasMoreMessagesBefore = page.hasMoreBefore
            return anchorID
        } catch {
            guard selectedConversationID == conversationID else { return nil }
            show(error)
            return nil
        }
    }

    /// 前台轻量刷新当前会话，只合并最新消息，不清空历史和本地发送状态。
    func refreshCurrentConversation() async {
        guard canUseMessaging, !isRefreshingMessages, !isLoadingMessages,
              let conversationID = selectedConversationID else { return }
        isRefreshingMessages = true
        defer { isRefreshingMessages = false }
        do {
            let page = try await repository.listMessages(
                conversationID: conversationID,
                before: nil,
                limit: 50
            )
            guard selectedConversationID == conversationID else { return }
            let existingIDs = Set(messages.map(\.id))
            let added = page.messages.filter { !existingIDs.contains($0.id) }
            let localMessages = messages.filter { $0.deliveryState != .sent }
            messages = Self.mergedMessages(messages.filter { $0.deliveryState == .sent }, page.messages)
            messages = Self.mergedMessages(messages, localMessages)
            newMessageCount += added.filter { !isCurrentUser($0) }.count
            if previousMessageCursor == nil {
                previousMessageCursor = page.previousCursor
                hasMoreMessagesBefore = page.hasMoreBefore
            }
        } catch {
            // 定时刷新失败不打断阅读；用户主动刷新时仍会获得完整错误提示。
        }
    }

    func clearNewMessageIndicator() {
        newMessageCount = 0
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

    func createPoll(
        question: String,
        options: [String],
        allowsMultipleSelection: Bool,
        isAnonymous: Bool
    ) async -> Bool {
        guard canCreatePoll, !isPerformingAction,
              let conversationID = selectedConversationID else { return false }
        isPerformingAction = true
        defer { isPerformingAction = false }
        do {
            let draft = try ChatPollDraft(
                conversationID: conversationID,
                question: question,
                options: options,
                allowsMultipleSelection: allowsMultipleSelection,
                isAnonymous: isAnonymous
            )
            let message = try await repository.createPoll(draft)
            guard selectedConversationID == conversationID else { return true }
            messages.removeAll { $0.id == message.id }
            messages.append(message)
            messages.sort(by: Self.messageSort)
            showToast("投票已发送", icon: "chart.bar.fill")
            return true
        } catch {
            show(error)
            return false
        }
    }

    func send(text: String?, attachmentURLs: [URL] = []) async -> Bool {
        guard let selectedConversationID, !isPerformingAction else { return false }
        guard canSendText || (!attachmentURLs.isEmpty && canSendAttachments) else { return false }
        let draft: ChatMessageDraft
        do {
            draft = try ChatMessageDraft(
                conversationID: selectedConversationID,
                text: text,
                localAttachmentURLs: attachmentURLs
            )
        } catch {
            show(error)
            return false
        }

        let localMessage = ChatMessage(
            id: "local-\(draft.clientRequestID.uuidString)",
            clientRequestID: draft.clientRequestID,
            conversationID: selectedConversationID,
            senderID: currentUserID ?? "current",
            senderDisplayName: currentAccountName,
            isFromCurrentUser: true,
            sentAt: Date(),
            text: draft.text,
            attachments: draft.localAttachmentURLs.map(Self.localAttachment),
            deliveryState: .sending
        )
        messages.append(localMessage)
        messages.sort { $0.sentAt < $1.sentAt }
        localOutgoingMessagesByConversationID[selectedConversationID, default: []].append(localMessage)
        draftsByLocalMessageID[localMessage.id] = draft
        draftsByConversationID[selectedConversationID] = nil
        isPerformingAction = true
        defer {
            isPerformingAction = false
            sendTasksByMessageID[localMessage.id] = nil
        }
        let sendTask = Task {
            try await repository.sendMessage(draft) { [weak self] completed, total in
                guard let total, total > 0 else { return }
                Task { @MainActor [weak self] in
                    self?.uploadProgressByMessageID[localMessage.id] = min(
                        max(Double(completed) / Double(total), 0),
                        1
                    )
                }
            }
        }
        sendTasksByMessageID[localMessage.id] = sendTask
        do {
            let message = try await sendTask.value
            replaceLocalMessage(localID: localMessage.id, with: message)
            return true
        } catch is CancellationError {
            removeLocalMessage(id: localMessage.id, conversationID: selectedConversationID)
            showToast("已取消发送。")
            return false
        } catch {
            markMessageFailed(localMessage, error: error)
            return false
        }
    }

    func retryMessage(id: String) async {
        guard !isPerformingAction,
              let message = messages.first(where: { $0.id == id }),
              message.deliveryState == .failed,
              let clientRequestID = message.clientRequestID else { return }
        let draft: ChatMessageDraft
        if let preservedDraft = draftsByLocalMessageID[id] {
            draft = preservedDraft
        } else {
            do {
                draft = try ChatMessageDraft(
                    clientRequestID: clientRequestID,
                    conversationID: message.conversationID,
                    text: message.text
                )
            } catch {
                show(error)
                return
            }
        }
        isPerformingAction = true
        defer { isPerformingAction = false }
        // 网络中断时原请求可能已经被 NAS 接收。重试前先回读近期消息，
        // 找到同一账号、相同正文且时间接近的消息时直接确认，避免重复发送。
        if let page = try? await repository.listMessages(
            conversationID: message.conversationID,
            before: nil,
            limit: 50
        ), let confirmed = matchingServerMessage(for: message, in: page.messages) {
            replaceLocalMessage(localID: id, with: confirmed)
            return
        }
        replaceDeliveryState(for: id, with: .sending)
        failedMessageErrorsByID[id] = nil
        let sendTask = Task {
            try await repository.sendMessage(draft) { [weak self] completed, total in
                guard let total, total > 0 else { return }
                Task { @MainActor [weak self] in
                    self?.uploadProgressByMessageID[id] = min(max(Double(completed) / Double(total), 0), 1)
                }
            }
        }
        sendTasksByMessageID[id] = sendTask
        defer { sendTasksByMessageID[id] = nil }
        do {
            let sent = try await sendTask.value
            replaceLocalMessage(localID: id, with: sent)
        } catch is CancellationError {
            removeLocalMessage(id: id, conversationID: message.conversationID)
            showToast("已取消发送。")
        } catch {
            guard let current = messages.first(where: { $0.id == id }) else { return }
            markMessageFailed(current, error: error)
        }
    }

    func removeFailedMessage(id: String) {
        guard let message = messages.first(where: { $0.id == id }),
              message.deliveryState == .failed else { return }
        messages.removeAll { $0.id == id }
        localOutgoingMessagesByConversationID[message.conversationID]?.removeAll { $0.id == id }
        failedMessageErrorsByID[id] = nil
        draftsByLocalMessageID[id] = nil
        uploadProgressByMessageID[id] = nil
    }

    func cancelMessageSend(id: String) {
        sendTasksByMessageID[id]?.cancel()
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
            statusMessage = nil
            statusIsError = false
            showToast(
                deletedCount == 1 ? "消息已删除" : "已删除 \(deletedCount) 条消息",
                icon: "trash.fill"
            )
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
            for id in closedIDs {
                draftsByConversationID[id] = nil
                localOutgoingMessagesByConversationID[id] = nil
            }
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
            statusMessage = nil
            statusIsError = false
            showToast(
                closedCount == 1 ? "会话已删除并进入归档" : "已删除 \(closedCount) 个会话并进入归档",
                icon: "archivebox.fill"
            )
        }
        return closedCount
    }

    func showToast(
        _ text: String,
        icon: String = "checkmark.circle.fill",
        style: ToastMessage.Style = .success
    ) {
        toastDismissTask?.cancel()
        activeToast = ToastMessage(text: text, icon: icon, style: style)
        toastDismissTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            self?.activeToast = nil
        }
    }

    func showAttachmentUnavailable() {
        showToast(
            "这台 NAS 尚未开放附件发送",
            icon: "paperclip",
            style: .info
        )
    }

    func dismissToast() {
        toastDismissTask?.cancel()
        activeToast = nil
    }

    func clearStatus() {
        statusMessage = nil
        statusIsError = false
    }

    private func replaceLocalMessage(localID: String, with message: ChatMessage) {
        localOutgoingMessagesByConversationID[message.conversationID]?.removeAll { $0.id == localID }
        failedMessageErrorsByID[localID] = nil
        draftsByLocalMessageID[localID] = nil
        uploadProgressByMessageID[localID] = nil
        guard selectedConversationID == message.conversationID else { return }
        if let index = messages.firstIndex(where: { $0.id == localID }) {
            messages[index] = message
        } else if !messages.contains(where: { $0.id == message.id }) {
            messages.append(message)
        }
        messages.sort(by: Self.messageSort)
    }

    private func removeLocalMessage(id: String, conversationID: String) {
        localOutgoingMessagesByConversationID[conversationID]?.removeAll { $0.id == id }
        if selectedConversationID == conversationID {
            messages.removeAll { $0.id == id }
        }
        failedMessageErrorsByID[id] = nil
        draftsByLocalMessageID[id] = nil
        uploadProgressByMessageID[id] = nil
    }

    private func markMessageFailed(_ message: ChatMessage, error: Error) {
        guard selectedConversationID == message.conversationID else { return }
        replaceDeliveryState(for: message.id, with: .failed)
        failedMessageErrorsByID[message.id] = Self.safeMessage(for: error)
    }

    private func replaceDeliveryState(for id: String, with state: ChatMessageDeliveryState) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        let message = messages[index]
        messages[index] = ChatMessage(
            id: message.id,
            clientRequestID: message.clientRequestID,
            conversationID: message.conversationID,
            senderID: message.senderID,
            senderDisplayName: message.senderDisplayName,
            isFromCurrentUser: message.isFromCurrentUser,
            sentAt: message.sentAt,
            text: message.text,
            attachments: message.attachments,
            poll: message.poll,
            deliveryState: state,
            encryptionState: message.encryptionState
        )
        if let localIndex = localOutgoingMessagesByConversationID[message.conversationID]?
            .firstIndex(where: { $0.id == id }) {
            localOutgoingMessagesByConversationID[message.conversationID]?[localIndex] = messages[index]
        }
    }

    private static func mergedMessages(_ first: [ChatMessage], _ second: [ChatMessage]) -> [ChatMessage] {
        var messagesByID: [String: ChatMessage] = [:]
        for message in first { messagesByID[message.id] = message }
        for message in second { messagesByID[message.id] = message }
        return messagesByID.values.sorted(by: messageSort)
    }

    private static func messageSort(_ lhs: ChatMessage, _ rhs: ChatMessage) -> Bool {
        if lhs.sentAt != rhs.sentAt { return lhs.sentAt < rhs.sentAt }
        return lhs.id.localizedStandardCompare(rhs.id) == .orderedAscending
    }

    private static func safeMessage(for error: Error) -> String {
        if let appError = error as? AppError { return appError.safeUserMessage }
        if let localizedError = error as? LocalizedError,
           let description = localizedError.errorDescription {
            return description
        }
        return "消息没有发送，请检查连接后重试。"
    }

    private func matchingServerMessage(
        for localMessage: ChatMessage,
        in serverMessages: [ChatMessage]
    ) -> ChatMessage? {
        let localFileNames = localMessage.attachments.map(\.fileName)
        return serverMessages
            .filter {
                $0.conversationID == localMessage.conversationID
                    && $0.text == localMessage.text
                    && (localFileNames.isEmpty || $0.attachments.map(\.fileName) == localFileNames)
                    && isCurrentUser($0)
                    && abs($0.sentAt.timeIntervalSince(localMessage.sentAt)) <= 180
            }
            .min {
                abs($0.sentAt.timeIntervalSince(localMessage.sentAt))
                    < abs($1.sentAt.timeIntervalSince(localMessage.sentAt))
            }
    }

    private static func localAttachment(from url: URL) -> ChatAttachment {
        let ext = url.pathExtension.lowercased()
        let kind: ChatAttachmentKind
        if ["jpg", "jpeg", "png", "gif", "heic", "heif", "webp", "tif", "tiff"].contains(ext) {
            kind = .image
        } else if ["mov", "mp4", "m4v", "avi", "mkv", "3gp", "webm"].contains(ext) {
            kind = .video
        } else {
            kind = .file
        }
        let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize.map(Int64.init)
        return ChatAttachment(
            id: "local-attachment-\(UUID().uuidString)",
            kind: kind,
            fileName: url.lastPathComponent,
            sizeBytes: size ?? nil,
            thumbnailAvailable: false
        )
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
