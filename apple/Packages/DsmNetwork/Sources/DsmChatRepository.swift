import DsmCore
import Foundation

/// 通过 DSM 登录会话访问 Synology Chat 套件的适配器。
///
/// `SYNO.Chat.*` 普通用户聊天接口没有公开契约，因此所有调用都必须先通过
/// `SYNO.API.Info` 能力发现，并集中在本文件内，避免内部协议扩散到界面和业务层。
public actor DsmChatRepository: ChatRepository {
    private let capabilities: CapabilitySet
    private let credential: DsmSessionCredential
    private let client: DsmAPIClient
    private let baseURL: URL
    private let transport: any DsmHTTPTransport
    private var completedMessages: [UUID: ChatMessage] = [:]
    private var completedGroups: [UUID: ChatConversation] = [:]
    private var completedReminders: [UUID: ChatReminder] = [:]
    private var completedMessageDeletions: Set<UUID> = []
    private var completedConversationClosures: Set<UUID> = []
    private var knownUsersByID: [String: ChatUser] = [:]
    private var cachedCurrentUserID: String?
    private let currentAccountName: String?
    private var avatarCache: [String: Data] = [:]
    private var unavailableAvatarUserIDs: Set<String> = []

    public init(
        profile: NasProfile,
        capabilities: CapabilitySet,
        session: AuthSession,
        transport: (any DsmHTTPTransport)? = nil
    ) throws {
        let resolvedTransport = transport ?? URLSessionTransport(
            expectedHost: profile.host,
            pinnedCertificateSHA256: profile.pinnedCertificateSHA256,
            requiresSystemCertificateTrust: DsmQuickConnectResolver.isTrustedRelayHost(profile.host)
        )
        let resolvedBaseURL = try DsmEndpoint.baseURL(for: profile)
        self.capabilities = capabilities
        self.baseURL = resolvedBaseURL
        self.transport = resolvedTransport
        currentAccountName = Self.normalizedIdentityName(profile.usernameHint)
        credential = DsmSessionCredential(sid: session.sid, synoToken: session.synoToken)
        client = DsmAPIClient(
            baseURL: resolvedBaseURL,
            transport: resolvedTransport
        )
    }

    public func availability() async -> ChatAvailability {
        guard hasCapability(DsmAPIName.chatChannel),
              hasCapability(DsmAPIName.chatUser),
              hasCapability(DsmAPIName.chatPost) else {
            return ChatAvailability(status: .unavailable)
        }
        var features: Set<ChatFeature> = [
            .directConversation,
            .textMessage,
            .emoji,
            .deleteOwnMessage,
            .closeConversation
        ]
        if hasCapability(DsmAPIName.chatChannelNamed) {
            features.insert(.groupConversation)
        }
        if hasCapability(DsmAPIName.chatPostReminder) {
            features.insert(.reminder)
        }
        if supportsAttachmentUpload {
            features.formUnion([.imageAttachment, .videoAttachment, .fileAttachment])
        }
        return ChatAvailability(status: .available, supportedFeatures: features)
    }

    public func listUsers() async throws -> [ChatUser] {
        let payload = try await call(
            DsmAPIName.chatUser,
            method: "list",
            parameters: [:]
        )
        let currentUserID = currentUserID(from: payload)
        cachedCurrentUserID = currentUserID ?? cachedCurrentUserID
        let parsedUsers = userValues(from: payload).compactMap {
            makeUser(from: $0, currentUserID: currentUserID)
        }
        let users = await usersByLoadingAvatars(parsedUsers)
            .sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
        for user in users { knownUsersByID[user.id] = user }
        return users
    }

    public func listConversations() async throws -> [ChatConversation] {
        let users = try await call(DsmAPIName.chatUser, method: "list", parameters: [:])
        let channels = try await call(DsmAPIName.chatChannel, method: "list", parameters: [:])
        let currentUserID = currentUserID(from: users)
        cachedCurrentUserID = currentUserID ?? cachedCurrentUserID
        let names = userValues(from: users).reduce(into: [String: String]()) { result, value in
            guard let user = makeUser(from: value, currentUserID: currentUserID) else { return }
            result[user.id] = user.displayName
            knownUsersByID[user.id] = user
        }
        return channels.array(for: "channels").compactMap {
            makeConversation(from: $0, userNames: names, currentUserID: currentUserID)
        }
        .sorted {
            ($0.lastActivityAt ?? .distantPast) > ($1.lastActivityAt ?? .distantPast)
        }
    }

    public func listMessages(
        conversationID: String,
        before cursor: String?,
        limit: Int
    ) async throws -> ChatMessagePage {
        let safeLimit = min(max(limit, 1), 100)
        let offset = max(Int(cursor ?? "0") ?? 0, 0)
        let payload = try await call(
            DsmAPIName.chatPost,
            method: "list",
            parameters: [
                "channel_id": .string(conversationID),
                "limit": .integer(safeLimit),
                "offset": .integer(offset)
            ]
        )
        let messages = payload.array(for: "posts").compactMap {
            makeMessage(from: $0, fallbackConversationID: conversationID)
        }
        .sorted { $0.sentAt < $1.sentAt }
        let total = payload.objectValue?.firstInt(for: ["total"])
        let hasMore = total.map { offset + messages.count < $0 } ?? (messages.count == safeLimit)
        return ChatMessagePage(
            messages: messages,
            previousCursor: hasMore ? String(offset + messages.count) : nil,
            hasMoreBefore: hasMore
        )
    }

    public func openDirectConversation(
        userID: String,
        clientRequestID: UUID
    ) async throws -> ChatConversation {
        let normalizedID = userID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedID.isEmpty else { throw ChatContractError.emptyUserID }
        let conversations = try await listConversations()
        if let existing = conversations.first(where: {
            $0.kind == .direct && $0.memberIDs.contains(normalizedID)
        }) {
            return existing
        }
        // Chat Server 没有暴露创建一对一匿名会话的方法；不能用建群接口伪造私聊。
        throw AppError(
            category: .apiUnavailable,
            isRetryable: false,
            safeUserMessage: "还没有与这位用户的聊天。请先在群晖 Chat 中向对方发送一条消息，再回到岚仓继续。"
        )
    }

    public func createGroup(_ draft: ChatGroupDraft) async throws -> ChatConversation {
        if let completed = completedGroups[draft.clientRequestID] { return completed }
        guard !draft.isEncrypted else {
            throw unsupported("当前版本还不能安全创建加密群聊，请先创建普通群聊。")
        }
        let named = try requireCapability(DsmAPIName.chatChannelNamed)
        let existing = try await listConversations().first {
            $0.kind == .group && $0.title == draft.title
                && Set(draft.memberIDs).isSubset(of: Set($0.memberIDs))
        }
        if let existing {
            completedGroups[draft.clientRequestID] = existing
            return existing
        }

        do {
            let created = try await client.call(
                path: named.path,
                api: named.name,
                version: try selectedVersion(named),
                method: "create",
                requestFormat: named.requestFormat,
                parameters: ["name": .string(draft.title), "type": .string("private")],
                credential: credential,
                as: ChatJSON.self
            )
            guard let channelID = created.objectValue?.firstString(for: ["channel_id", "id"]) else {
                throw invalidChatResponse()
            }
            do {
                try await client.callVoid(
                    path: named.path,
                    api: named.name,
                    version: try selectedVersion(named),
                    method: "join",
                    requestFormat: named.requestFormat,
                    parameters: ["channel_id": .string(channelID)],
                    credential: credential
                )
            } catch let error as DsmNetworkError {
                if case .api(let code, _) = error, code == 117 {
                    // 117 表示创建者已经在群聊中，可继续邀请成员。
                } else {
                    throw error
                }
            }
            try await client.callVoid(
                path: named.path,
                api: named.name,
                version: try selectedVersion(named),
                method: "invite",
                requestFormat: named.requestFormat,
                parameters: [
                    "channel_id": .string(channelID),
                    "user_ids": .stringArray(draft.memberIDs),
                    "channel_key_encs": .string("[]")
                ],
                credential: credential
            )
            guard let verified = try await listConversations().first(where: { $0.id == channelID }),
                  Set(draft.memberIDs).isSubset(of: Set(verified.memberIDs)) else {
                throw AppError(
                    category: .partialFailure,
                    isRetryable: false,
                    safeUserMessage: "群聊已创建，但部分成员可能还没有加入。请在群晖 Chat 中检查成员列表。"
                )
            }
            completedGroups[draft.clientRequestID] = verified
            return verified
        } catch let error as AppError {
            throw error
        } catch let error as DsmNetworkError {
            throw mapChatError(error)
        }
    }

    public func sendMessage(
        _ draft: ChatMessageDraft,
        progress: @escaping FileTransferProgress
    ) async throws -> ChatMessage {
        if let completed = completedMessages[draft.clientRequestID] { return completed }
        guard draft.localAttachmentURLs.count <= 1 else {
            throw unsupported("请一次发送一个附件。当前文件发送完成后，可以继续选择下一个文件。")
        }
        if let localURL = draft.localAttachmentURLs.first {
            let uploaded = try await uploadAttachment(
                localURL: localURL,
                draft: draft,
                progress: progress
            )
            completedMessages[draft.clientRequestID] = uploaded
            return uploaded
        }
        guard let text = draft.text else { throw ChatContractError.emptyMessage }
        let payload = try await call(
            DsmAPIName.chatPost,
            method: "create",
            parameters: [
                "channel_id": .string(draft.conversationID),
                "message": .string(text)
            ]
        )
        let message: ChatMessage
        if let parsed = makeMessage(from: payload, fallbackConversationID: draft.conversationID) {
            message = parsed
        } else {
            guard let id = payload.objectValue?.firstString(for: ["post_id", "id"]) else {
                throw invalidChatResponse()
            }
            message = ChatMessage(
                id: id,
                clientRequestID: draft.clientRequestID,
                conversationID: draft.conversationID,
                senderID: "current",
                sentAt: Date(),
                text: text
            )
        }
        let result = ChatMessage(
            id: message.id,
            clientRequestID: draft.clientRequestID,
            conversationID: message.conversationID,
            senderID: message.senderID,
            senderDisplayName: message.senderDisplayName,
            isFromCurrentUser: true,
            sentAt: message.sentAt,
            text: message.text ?? text,
            attachments: message.attachments,
            poll: message.poll,
            deliveryState: .sent,
            encryptionState: message.encryptionState
        )
        completedMessages[draft.clientRequestID] = result
        return result
    }

    /// 使用 Chat Server 2.4.1-22111 官方网页客户端当前采用的内部上传契约。
    /// `SYNO.Chat.Post/create` v5 与 multipart 的 `file` 字段均不是群晖公开 API，
    /// 因此仅在运行时能力范围明确包含 v5 时启用，并保持关闭型兼容策略。
    private func uploadAttachment(
        localURL: URL,
        draft: ChatMessageDraft,
        progress: @escaping FileTransferProgress
    ) async throws -> ChatMessage {
        guard supportsAttachmentUpload else {
            throw unsupported("这台 NAS 当前不能发送附件。请更新 Chat Server 后重试。")
        }
        guard localURL.isFileURL else {
            throw AppError(
                category: .permissionDenied,
                isRetryable: false,
                safeUserMessage: "只能发送保存在这台 Mac 上的文件。"
            )
        }
        let securityScoped = localURL.startAccessingSecurityScopedResource()
        defer {
            if securityScoped { localURL.stopAccessingSecurityScopedResource() }
        }
        let values: URLResourceValues
        do {
            values = try localURL.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        } catch {
            throw AppError(
                category: .permissionDenied,
                isRetryable: false,
                safeUserMessage: "无法读取所选文件。请重新选择文件，并确认岚仓有访问权限。"
            )
        }
        guard values.isRegularFile == true else {
            throw AppError(
                category: .permissionDenied,
                isRetryable: false,
                safeUserMessage: "请选择一个文件，不要选择文件夹。"
            )
        }

        let capability = try requireCapability(DsmAPIName.chatPost)
        let boundary = "LanStash-Chat-\(UUID().uuidString)"
        let fields = [
            "api": capability.name,
            "version": "5",
            "method": "create",
            "channel_id": draft.conversationID,
            "type": "file",
            "message": draft.text ?? "",
            "is_thread": "false",
            "_sid": credential.sid,
            "SynoToken": credential.synoToken ?? "",
            "synotoken": credential.synoToken ?? ""
        ]
        let bodyURL: URL
        do {
            bodyURL = try createChatMultipartBody(
                localURL: localURL,
                boundary: boundary,
                fields: fields
            )
        } catch let error as AppError {
            throw error
        } catch {
            throw AppError(
                category: .localStorageFull,
                isRetryable: false,
                safeUserMessage: "准备附件时空间不足。请释放这台 Mac 的存储空间后重试。"
            )
        }
        defer { try? FileManager.default.removeItem(at: bodyURL) }

        guard let binaryTransport = transport as? any DsmBinaryHTTPTransport else {
            throw unsupported("当前连接方式不能发送附件，请重新连接后重试。")
        }
        var uploadURL = apiURL(path: capability.path)
        if var components = URLComponents(url: uploadURL, resolvingAgainstBaseURL: false) {
            let queryItems = [
                URLQueryItem(name: "api", value: capability.name),
                URLQueryItem(name: "version", value: "5"),
                URLQueryItem(name: "method", value: "create")
            ]
            components.queryItems = queryItems
            uploadURL = components.url ?? uploadURL
        }
        var request = URLRequest(url: uploadURL)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let bodySize = try? bodyURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
            request.setValue(String(bodySize), forHTTPHeaderField: "Content-Length")
        }
        if let cookie = credential.cookieHeaderValue {
            request.setValue(cookie, forHTTPHeaderField: "Cookie")
        }
        if let token = credential.synoToken, !token.isEmpty {
            request.setValue(token, forHTTPHeaderField: "X-SYNO-TOKEN")
        }

        let response: DsmHTTPResponse
        do {
            response = try await binaryTransport.upload(request, from: bodyURL, progress: progress)
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as DsmCertificateTrustError {
            throw error
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch let error as URLError {
            throw DsmErrorMapper.map(.transport(code: error.errorCode, requestID: UUID()))
        }
        guard (200..<300).contains(response.statusCode) else {
            throw mapChatError(.httpStatus(code: response.statusCode, requestID: UUID()))
        }
        let envelope: ChatUploadEnvelope
        do {
            envelope = try JSONDecoder().decode(ChatUploadEnvelope.self, from: response.data)
        } catch {
            throw invalidChatResponse()
        }
        if let code = envelope.error?.code {
            throw mapChatError(.api(code: code, requestID: UUID()))
        }
        guard envelope.success else { throw invalidChatResponse() }

        let fallbackAttachment = makeLocalAttachment(
            localURL: localURL,
            fileSize: values.fileSize.map(Int64.init)
        )
        var parsed = envelope.data.flatMap {
            makeMessage(from: $0, fallbackConversationID: draft.conversationID)
        }
        if parsed == nil,
           let page = try? await listMessages(
               conversationID: draft.conversationID,
               before: nil,
               limit: 50
           ) {
            parsed = page.messages.first {
                $0.text == draft.text
                    && $0.attachments.contains(where: { $0.fileName == localURL.lastPathComponent })
                    && isOwnedByCurrentUser($0)
                    && abs($0.sentAt.timeIntervalSinceNow) <= 180
            }
        }
        guard let parsed else {
            throw AppError(
                category: .partialFailure,
                isRetryable: false,
                safeUserMessage: "NAS 已接收附件，但暂时无法确认发送结果。请刷新会话确认后，再决定是否重试。"
            )
        }
        return ChatMessage(
            id: parsed.id,
            clientRequestID: draft.clientRequestID,
            conversationID: parsed.conversationID,
            senderID: parsed.senderID,
            senderDisplayName: parsed.senderDisplayName,
            isFromCurrentUser: true,
            sentAt: parsed.sentAt,
            text: parsed.text ?? draft.text,
            attachments: parsed.attachments.isEmpty ? [fallbackAttachment] : parsed.attachments,
            deliveryState: .sent,
            encryptionState: parsed.encryptionState
        )
    }

    public func deleteMessage(
        conversationID: String,
        messageID: String,
        clientRequestID: UUID
    ) async throws {
        if completedMessageDeletions.contains(clientRequestID) { return }
        let normalizedConversationID = conversationID.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedMessageID = messageID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedConversationID.isEmpty else { throw ChatContractError.emptyConversationID }
        guard !normalizedMessageID.isEmpty else {
            throw AppError(
                category: .notFound,
                isRetryable: false,
                safeUserMessage: "没有找到要删除的消息，请刷新后重试。"
            )
        }

        let currentPage = try await listMessages(
            conversationID: normalizedConversationID,
            before: nil,
            limit: 100
        )
        guard let message = currentPage.messages.first(where: { $0.id == normalizedMessageID }) else {
            completedMessageDeletions.insert(clientRequestID)
            return
        }
        guard isOwnedByCurrentUser(message) else {
            throw AppError(
                category: .permissionDenied,
                isRetryable: false,
                safeUserMessage: "只能删除自己发送的消息。"
            )
        }

        // 内部 API：SYNO.Chat.Post/delete 尚无公开开发者契约，必须由能力发现和实机复查共同保护。
        try await callVoid(
            DsmAPIName.chatPost,
            method: "delete",
            parameters: ["post_id": .string(normalizedMessageID)]
        )
        let verifiedPage = try await listMessages(
            conversationID: normalizedConversationID,
            before: nil,
            limit: 100
        )
        guard !verifiedPage.messages.contains(where: { $0.id == normalizedMessageID }) else {
            throw AppError(
                category: .partialFailure,
                isRetryable: true,
                safeUserMessage: "消息没有从会话中移除，请确认管理员允许删除消息后重试。"
            )
        }
        completedMessageDeletions.insert(clientRequestID)
    }

    public func closeConversation(
        conversationID: String,
        clientRequestID: UUID
    ) async throws {
        if completedConversationClosures.contains(clientRequestID) { return }
        let normalizedID = conversationID.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedID.isEmpty else { throw ChatContractError.emptyConversationID }
        let currentConversations = try await listConversations()
        guard currentConversations.contains(where: { $0.id == normalizedID }) else {
            completedConversationClosures.insert(clientRequestID)
            return
        }

        // 内部 API：群晖客户端称此操作为“关闭会话”；消息会进入 Chat 归档而不是本地直接抹除。
        try await callVoid(
            DsmAPIName.chatChannel,
            method: "close",
            parameters: ["channel_id": .string(normalizedID)]
        )
        let verifiedConversations = try await listConversations()
        guard !verifiedConversations.contains(where: { $0.id == normalizedID }) else {
            throw AppError(
                category: .partialFailure,
                isRetryable: true,
                safeUserMessage: "会话仍然存在，可能没有关闭权限。请刷新后重试。"
            )
        }
        completedConversationClosures.insert(clientRequestID)
    }

    public func setReminder(
        messageID: String,
        remindAt: Date,
        clientRequestID: UUID
    ) async throws -> ChatReminder {
        if let completed = completedReminders[clientRequestID] { return completed }
        _ = try await call(
            DsmAPIName.chatPostReminder,
            method: "set",
            parameters: [
                "post_id": .string(messageID),
                "remind_at": .string(String(Int64(remindAt.timeIntervalSince1970 * 1_000)))
            ]
        )
        let reminder = ChatReminder(id: messageID, messageID: messageID, remindAt: remindAt)
        completedReminders[clientRequestID] = reminder
        return reminder
    }

    public func createPoll(_ draft: ChatPollDraft) async throws -> ChatMessage {
        throw unsupported("投票协议仍需在实机确认，当前版本不会发送未经验证的投票请求。")
    }

    private func call(
        _ name: String,
        method: String,
        parameters: [String: DsmParameterValue]
    ) async throws -> ChatJSON {
        let capability = try requireCapability(name)
        do {
            return try await client.call(
                path: capability.path,
                api: capability.name,
                version: try selectedVersion(capability),
                method: method,
                requestFormat: capability.requestFormat,
                parameters: parameters,
                credential: credential,
                as: ChatJSON.self
            )
        } catch let error as DsmNetworkError {
            throw mapChatError(error)
        }
    }

    /// 调用只返回成功状态、不携带 `data` 的 Chat 写操作。
    ///
    /// Chat Server 的删除消息、关闭会话等内部接口在成功时通常只返回
    /// `{ "success": true }`。若按读取接口强制解析 `data`，会在写入已经
    /// 生效后错误地向用户报告失败。
    private func callVoid(
        _ name: String,
        method: String,
        parameters: [String: DsmParameterValue]
    ) async throws {
        let capability = try requireCapability(name)
        do {
            try await client.callVoid(
                path: capability.path,
                api: capability.name,
                version: try selectedVersion(capability),
                method: method,
                requestFormat: capability.requestFormat,
                parameters: parameters,
                credential: credential
            )
        } catch let error as DsmNetworkError {
            throw mapChatError(error)
        }
    }

    private func makeConversation(
        from value: ChatJSON,
        userNames: [String: String],
        currentUserID: String?
    ) -> ChatConversation? {
        guard let object = value.objectValue,
              let id = object.firstString(for: ["channel_id", "id"]) else { return nil }
        let rawMembers = object.array(for: "members").isEmpty
            ? object.array(for: "member_ids")
            : object.array(for: "members")
        let memberIDs = rawMembers.compactMap { member in
            member.stringValue
                ?? member.objectValue?.firstString(for: ["user_id", "member_id", "id"])
        }
        let rawName = object.firstString(for: ["name", "channel_name"])?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let type = object.firstString(for: ["type", "channel_type"]) ?? ""
        let declaredMemberCount = object.firstInt(for: ["member_count", "members_count", "total_members"])
        let resolvedMemberCount = declaredMemberCount ?? memberIDs.count
        let normalizedType = type.lowercased()
        let isDirect = normalizedType == "direct"
            || normalizedType == "anonymous"
            || (rawName.isEmpty && resolvedMemberCount <= 2 && normalizedType != "chatbot")
        let title: String
        if !isDirect, !rawName.isEmpty {
            title = rawName
        } else {
            let otherMemberIDs = memberIDs.filter { $0 != currentUserID }
            let visibleMemberIDs = otherMemberIDs.isEmpty ? memberIDs : otherMemberIDs
            title = visibleMemberIDs.compactMap { userNames[$0] }.joined(separator: "、")
        }
        let lastPost = object["last_post"]?.objectValue
        return ChatConversation(
            id: id,
            kind: isDirect ? .direct : .group,
            title: title.isEmpty ? "聊天" : title,
            memberIDs: memberIDs,
            memberCount: declaredMemberCount ?? (memberIDs.isEmpty ? nil : memberIDs.count),
            lastMessageSummary: lastPost?.firstString(for: ["message", "text", "content"])
                ?? object.firstString(for: ["last_message", "last_message_summary", "last_post_message"]),
            lastActivityAt: Self.date(from: lastPost?.firstDouble(for: ["create_at", "created_at"])
                ?? object.firstDouble(for: ["update_at", "last_activity_at"])),
            unreadCount: object.firstInt(for: ["unread", "unread_count"]) ?? 0,
            isEncrypted: object.firstBool(for: ["encrypted", "is_encrypted"]) ?? false
        )
    }

    private func makeMessage(
        from value: ChatJSON,
        fallbackConversationID: String
    ) -> ChatMessage? {
        guard let object = value.objectValue,
              let id = object.firstString(for: ["post_id", "id"]) else { return nil }
        let conversationID = object.firstString(for: ["channel_id", "conversation_id"])
            ?? fallbackConversationID
        let creator = object["creator"]?.objectValue
            ?? object["user"]?.objectValue
            ?? object["sender"]?.objectValue
            ?? object["author"]?.objectValue
            ?? object["creator_info"]?.objectValue
        let senderID = object.firstNonEmptyString(for: ["creator_id", "user_id", "sender_id", "author_id", "owner_id"])
            ?? object["creator"]?.stringValue
            ?? object["user"]?.stringValue
            ?? object["sender"]?.stringValue
            ?? object["author"]?.stringValue
            ?? creator?.firstNonEmptyString(for: ["user_id", "creator_id", "sender_id", "author_id", "uid", "id"])
            ?? "unknown"
        let senderName = object.firstNonEmptyString(
            for: ["creator_name", "creator_nickname", "sender_name", "author_name", "nickname", "username", "user_name"]
        )
            ?? creator?.firstNonEmptyString(
                for: ["nickname", "display_name", "displayname", "name", "username", "user_name", "account"]
            )
            ?? knownUsersByID[senderID]?.displayName
        let isCurrentUser = object.firstBool(for: ["is_my_post", "is_mine", "is_current_user"])
            ?? creator?.firstBool(for: ["is_login", "is_current", "is_current_user", "is_self", "is_me"])
            ?? cachedCurrentUserID.map { $0 == senderID }
        let attachments = makeAttachments(from: object, messageID: id)
        return ChatMessage(
            id: id,
            conversationID: conversationID,
            senderID: senderID,
            senderDisplayName: senderName,
            isFromCurrentUser: isCurrentUser,
            sentAt: Self.date(from: object.firstDouble(for: ["create_at", "created_at", "timestamp"])) ?? Date(),
            text: object.firstString(for: ["message", "text", "content"]),
            attachments: attachments,
            encryptionState: (object.firstBool(for: ["encrypted", "is_encrypted"]) ?? false)
                ? .locked : .notEncrypted
        )
    }

    private func makeAttachments(
        from object: [String: ChatJSON],
        messageID: String
    ) -> [ChatAttachment] {
        var values = object.array(for: "files")
        if values.isEmpty { values = object.array(for: "attachments") }
        if values.isEmpty, let file = object["file_props"] {
            if let encoded = file.stringValue,
               let data = encoded.data(using: .utf8),
               let decoded = try? JSONDecoder().decode(ChatJSON.self, from: data) {
                values = [decoded]
            } else {
                values = [file]
            }
        }
        if values.isEmpty,
           let type = object.firstString(for: ["type", "post_type"])?.lowercased(),
           type == "file" || type == "image" || type == "video" {
            values = [.object(object)]
        }
        return values.enumerated().compactMap { index, value in
            let fileObject = value.objectValue ?? [:]
            let name = fileObject.firstNonEmptyString(
                for: ["name", "file_name", "filename", "title"]
            ) ?? object.firstNonEmptyString(for: ["file_name", "filename"])
            guard let name else { return nil }
            let mediaType = fileObject.firstNonEmptyString(
                for: ["content_type", "mime_type", "media_type"]
            )
            let extensionName = fileObject.firstNonEmptyString(for: ["type", "extension"])
                ?? URL(fileURLWithPath: name).pathExtension
            let kind = Self.attachmentKind(fileName: name, mediaType: mediaType, extensionName: extensionName)
            return ChatAttachment(
                id: fileObject.firstString(for: ["file_id", "id", "uuid"])
                    ?? "\(messageID)-attachment-\(index)",
                kind: kind,
                fileName: name,
                mediaType: mediaType,
                sizeBytes: fileObject.firstDouble(for: ["size", "file_size", "bytes"]).map(Int64.init),
                durationMilliseconds: fileObject.firstDouble(for: ["duration", "duration_ms"]).map(Int64.init),
                thumbnailAvailable: fileObject.firstBool(for: ["has_thumbnail", "thumbnail_available"])
            )
        }
    }

    private func makeLocalAttachment(localURL: URL, fileSize: Int64?) -> ChatAttachment {
        let name = localURL.lastPathComponent
        return ChatAttachment(
            id: "local-file-\(UUID().uuidString)",
            kind: Self.attachmentKind(
                fileName: name,
                mediaType: nil,
                extensionName: localURL.pathExtension
            ),
            fileName: name,
            sizeBytes: fileSize,
            thumbnailAvailable: false
        )
    }

    private static func attachmentKind(
        fileName: String,
        mediaType: String?,
        extensionName: String?
    ) -> ChatAttachmentKind {
        let media = mediaType?.lowercased() ?? ""
        let ext = (extensionName?.isEmpty == false ? extensionName : URL(fileURLWithPath: fileName).pathExtension)?
            .lowercased() ?? ""
        if media.hasPrefix("image/") || ["jpg", "jpeg", "png", "gif", "heic", "heif", "webp", "tif", "tiff"].contains(ext) {
            return .image
        }
        if media.hasPrefix("video/") || ["mov", "mp4", "m4v", "avi", "mkv", "3gp", "webm"].contains(ext) {
            return .video
        }
        return .file
    }

    private static func date(from raw: Double?) -> Date? {
        guard let raw else { return nil }
        return Date(timeIntervalSince1970: raw > 10_000_000_000 ? raw / 1_000 : raw)
    }

    private func isOwnedByCurrentUser(_ message: ChatMessage) -> Bool {
        if message.isFromCurrentUser == true { return true }
        if cachedCurrentUserID == message.senderID { return true }
        guard let currentAccountName else { return false }
        return Self.normalizedIdentityName(message.senderDisplayName) == currentAccountName
            || Self.normalizedIdentityName(knownUsersByID[message.senderID]?.displayName) == currentAccountName
    }

    private static func normalizedIdentityName(_ value: String?) -> String? {
        let normalized = value?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return normalized?.isEmpty == false ? normalized : nil
    }

    private func makeUser(from value: ChatJSON, currentUserID: String?) -> ChatUser? {
        guard let object = value.objectValue,
              let id = object.firstNonEmptyString(
                  for: ["user_id", "member_id", "uid", "account_id", "id"]
              ) else { return nil }
        let profile = object["profile"]?.objectValue
        let name = object.firstNonEmptyString(
            for: ["nickname", "display_name", "displayname", "name", "username", "user_name", "account", "login_name"]
        )
            ?? profile?.firstNonEmptyString(
                for: ["nickname", "display_name", "displayname", "name", "username", "user_name", "account"]
            )
            ?? "用户 \(id)"
        let explicitCurrent = object.firstBool(
            for: ["is_login", "is_current", "is_current_user", "is_self", "is_me"]
        )
        let avatarAvailable = object.firstBool(
            for: ["has_avatar", "avatar_available", "is_avatar_exist"]
        ) ?? (object.firstNonEmptyString(for: ["avatar", "avatar_url", "avatar_path"]) != nil ? true : nil)
        return ChatUser(
            id: id,
            displayName: name,
            avatarAvailable: avatarAvailable,
            isDisabled: object.firstBool(for: ["disabled", "is_disabled"]) ?? false,
            isCurrentUser: explicitCurrent ?? currentUserID.map { $0 == id }
        )
    }

    private func currentUserID(from payload: ChatJSON) -> String? {
        if let object = payload.objectValue,
           let id = object.firstString(
               for: ["current_user_id", "login_user_id", "my_user_id", "self_user_id"]
           ) {
            return id
        }
        if let object = payload.objectValue {
            let currentUser = object["current_user"]?.objectValue
                ?? object["login_user"]?.objectValue
                ?? object["me"]?.objectValue
            if let id = currentUser?.firstString(for: ["user_id", "id"]) {
                return id
            }
        }
        for user in userValues(from: payload) {
            guard let object = user.objectValue,
                  object.firstBool(
                      for: ["is_login", "is_current", "is_current_user", "is_self", "is_me"]
                  ) == true else { continue }
            return object.firstString(for: ["user_id", "member_id", "id"])
        }
        return nil
    }

    private func userValues(from payload: ChatJSON) -> [ChatJSON] {
        if let values = payload.arrayValue { return values }
        guard let object = payload.objectValue else { return [] }
        for key in ["users", "user", "user_list", "list", "members", "items", "results"] {
            if let values = object[key]?.arrayValue { return values }
            if let values = object[key]?.objectValue?.values { return Array(values) }
        }
        let values = object.values.filter { value in
            guard let candidate = value.objectValue else { return false }
            return candidate.firstNonEmptyString(
                for: ["user_id", "member_id", "uid", "account_id", "id"]
            ) != nil
        }
        return values
    }

    private func usersByLoadingAvatars(_ users: [ChatUser]) async -> [ChatUser] {
        guard let capability = capabilities[DsmAPIName.chatUserAvatar],
              capability.selectedVersion != nil else { return users }

        var resolved: [ChatUser] = []
        resolved.reserveCapacity(users.count)
        for user in users {
            let avatarData: Data?
            if let cached = avatarCache[user.id] {
                avatarData = cached
            } else if unavailableAvatarUserIDs.contains(user.id) || user.avatarAvailable != true {
                avatarData = nil
            } else {
                avatarData = await loadAvatar(userID: user.id, capability: capability)
                if let avatarData {
                    avatarCache[user.id] = avatarData
                } else {
                    unavailableAvatarUserIDs.insert(user.id)
                }
            }
            resolved.append(ChatUser(
                id: user.id,
                displayName: user.displayName,
                avatarAvailable: avatarData != nil ? true : user.avatarAvailable,
                avatarData: avatarData,
                isDisabled: user.isDisabled,
                isCurrentUser: user.isCurrentUser
            ))
        }
        return resolved
    }

    private func loadAvatar(userID: String, capability: ApiCapability) async -> Data? {
        guard let version = capability.selectedVersion,
              let request = try? DsmRequestBuilder.build(
                  baseURL: baseURL,
                  path: capability.path,
                  api: capability.name,
                  version: version,
                  method: "get",
                  requestFormat: capability.requestFormat,
                  parameters: ["user_id": .string(userID)],
                  credential: nil,
                  httpMethod: "GET"
              ) else { return nil }
        var imageRequest = request
        imageRequest.setValue("image/*", forHTTPHeaderField: "Accept")
        if let cookie = credential.cookieHeaderValue {
            imageRequest.setValue(cookie, forHTTPHeaderField: "Cookie")
        }
        if let synoToken = credential.synoToken, !synoToken.isEmpty {
            imageRequest.setValue(synoToken, forHTTPHeaderField: "X-SYNO-TOKEN")
        }
        guard let response = try? await transport.send(imageRequest),
              (200..<300).contains(response.statusCode),
              !response.data.isEmpty,
              response.data.count <= 2 * 1_024 * 1_024 else { return nil }
        let contentType = response.headers.first {
            $0.key.caseInsensitiveCompare("Content-Type") == .orderedSame
        }?.value.lowercased()
        guard contentType?.hasPrefix("image/") == true || Self.hasKnownImageSignature(response.data) else {
            return nil
        }
        return response.data
    }

    private static func hasKnownImageSignature(_ data: Data) -> Bool {
        let bytes = [UInt8](data.prefix(12))
        if bytes.starts(with: [0x89, 0x50, 0x4E, 0x47]) { return true }
        if bytes.starts(with: [0xFF, 0xD8, 0xFF]) { return true }
        if bytes.starts(with: [0x47, 0x49, 0x46, 0x38]) { return true }
        return bytes.count >= 12
            && Array(bytes[0..<4]) == [0x52, 0x49, 0x46, 0x46]
            && Array(bytes[8..<12]) == [0x57, 0x45, 0x42, 0x50]
    }

    private func hasCapability(_ name: String) -> Bool {
        capabilities[name]?.selectedVersion != nil
    }

    private var supportsAttachmentUpload: Bool {
        guard let capability = capabilities[DsmAPIName.chatPost] else { return false }
        return capability.minVersion <= 5 && capability.maxVersion >= 5
    }

    private func apiURL(path: String) -> URL {
        var url = baseURL.appendingPathComponent("webapi", isDirectory: true)
        for segment in path.split(separator: "/") {
            url.appendPathComponent(String(segment), isDirectory: false)
        }
        return url
    }

    private func createChatMultipartBody(
        localURL: URL,
        boundary: String,
        fields: [String: String]
    ) throws -> URL {
        let bodyURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("LanStashChatUpload-\(UUID().uuidString).multipart")
        guard FileManager.default.createFile(atPath: bodyURL.path, contents: nil) else {
            throw AppError(
                category: .localStorageFull,
                isRetryable: false,
                safeUserMessage: "无法准备附件，请检查这台 Mac 的可用空间。"
            )
        }
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: bodyURL.path)
        do {
            let output = try FileHandle(forWritingTo: bodyURL)
            defer { try? output.close() }
            func write(_ string: String) throws {
                guard let data = string.data(using: .utf8) else {
                    throw DsmRequestError.parameterEncodingFailed
                }
                try output.write(contentsOf: data)
            }
            for (name, value) in fields.sorted(by: { $0.key < $1.key }) where !value.isEmpty {
                try write("--\(boundary)\r\n")
                try write("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
                try write("\(value)\r\n")
            }
            let safeFilename = localURL.lastPathComponent
                .replacingOccurrences(of: "\r", with: "")
                .replacingOccurrences(of: "\n", with: "")
                .replacingOccurrences(of: "\"", with: "'")
            try write("--\(boundary)\r\n")
            try write("Content-Disposition: form-data; name=\"file\"; filename=\"\(safeFilename)\"\r\n")
            try write("Content-Type: application/octet-stream\r\n\r\n")
            let input = try FileHandle(forReadingFrom: localURL)
            defer { try? input.close() }
            while let chunk = try input.read(upToCount: 1_048_576), !chunk.isEmpty {
                try Task.checkCancellation()
                try output.write(contentsOf: chunk)
            }
            try write("\r\n--\(boundary)--\r\n")
            return bodyURL
        } catch {
            try? FileManager.default.removeItem(at: bodyURL)
            throw error
        }
    }

    private func requireCapability(_ name: String) throws -> ApiCapability {
        guard let capability = capabilities[name], capability.selectedVersion != nil else {
            throw unsupported("这台 NAS 没有启用所需的消息功能，请检查 Chat Server 和当前用户的应用权限。")
        }
        return capability
    }

    private func selectedVersion(_ capability: ApiCapability) throws -> Int {
        guard let version = capability.selectedVersion else {
            throw unsupported("这台 NAS 的消息服务版本暂不受支持。")
        }
        return version
    }

    private func mapChatError(_ error: DsmNetworkError) -> AppError {
        if case .api(let code, let requestID) = error, code == 119 {
            return AppError(
                category: .permissionDenied,
                isRetryable: false,
                safeUserMessage: "当前用户没有使用群晖 Chat 的权限，请让管理员在 DSM 中开启应用权限。",
                dsmCode: code,
                requestID: requestID
            )
        }
        return DsmErrorMapper.map(error)
    }

    private func unsupported(_ message: String) -> AppError {
        AppError(category: .apiUnavailable, isRetryable: false, safeUserMessage: message)
    }

    private func invalidChatResponse() -> AppError {
        AppError(
            category: .invalidResponse,
            isRetryable: false,
            safeUserMessage: "消息内容暂时无法读取。请退出后重新连接；如果仍然出现，请反馈发生问题的操作步骤。"
        )
    }
}

/// 用于兼容 Chat Server 不同版本返回字段的最小动态 JSON 类型。
private indirect enum ChatJSON: Decodable, Sendable {
    case object([String: ChatJSON])
    case array([ChatJSON])
    case string(String)
    case number(Double)
    case boolean(Bool)
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode([String: ChatJSON].self) { self = .object(value) }
        else if let value = try? container.decode([ChatJSON].self) { self = .array(value) }
        else if let value = try? container.decode(Bool.self) { self = .boolean(value) }
        else if let value = try? container.decode(Double.self) { self = .number(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else { throw DecodingError.dataCorruptedError(in: container, debugDescription: "无法解析 Chat 返回值。") }
    }

    var objectValue: [String: ChatJSON]? {
        guard case .object(let value) = self else { return nil }
        return value
    }

    var arrayValue: [ChatJSON]? {
        guard case .array(let value) = self else { return nil }
        return value
    }

    var stringValue: String? {
        switch self {
        case .string(let value): value
        case .number(let value): value.rounded() == value ? String(Int64(value)) : String(value)
        case .boolean(let value): value ? "true" : "false"
        default: nil
        }
    }

    var doubleValue: Double? {
        switch self {
        case .number(let value): value
        case .string(let value): Double(value)
        default: nil
        }
    }

    var boolValue: Bool? {
        switch self {
        case .boolean(let value): value
        case .number(let value): value != 0
        case .string(let value): ["true", "1", "yes"].contains(value.lowercased())
        default: nil
        }
    }

    func array(for key: String) -> [ChatJSON] {
        objectValue?.array(for: key) ?? []
    }
}

private struct ChatUploadEnvelope: Decodable, Sendable {
    let success: Bool
    let data: ChatJSON?
    let error: ChatUploadError?
}

private struct ChatUploadError: Decodable, Sendable {
    let code: Int
}

private extension Dictionary where Key == String, Value == ChatJSON {
    func array(for key: String) -> [ChatJSON] {
        guard case .array(let value)? = self[key] else { return [] }
        return value
    }

    func firstString(for keys: [String]) -> String? {
        keys.lazy.compactMap { self[$0]?.stringValue }.first
    }

    func firstNonEmptyString(for keys: [String]) -> String? {
        keys.lazy.compactMap { key in
            guard let value = self[key]?.stringValue?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                  !value.isEmpty else { return nil }
            return value
        }.first
    }

    func firstDouble(for keys: [String]) -> Double? {
        keys.lazy.compactMap { self[$0]?.doubleValue }.first
    }

    func firstInt(for keys: [String]) -> Int? {
        firstDouble(for: keys).map(Int.init)
    }

    func firstBool(for keys: [String]) -> Bool? {
        keys.lazy.compactMap { self[$0]?.boolValue }.first
    }
}
