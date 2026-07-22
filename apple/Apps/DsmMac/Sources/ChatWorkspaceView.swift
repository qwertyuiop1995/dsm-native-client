import AppKit
import DsmCore
import SwiftUI
import UniformTypeIdentifiers

struct ChatWorkspaceView: View {
    @Bindable var model: ChatWorkspaceModel
    @State private var presentsNewConversation = false
    @State private var selectedConversationIDs: Set<String> = []
    @State private var pendingConversationDeletion: Set<String> = []
    @State private var presentsConversationDeletionConfirmation = false

    var body: some View {
        VStack(spacing: 0) {
            if model.canUseMessaging, model.statusIsError, let statusMessage = model.statusMessage {
                ChatActionStatusBanner(
                    message: statusMessage,
                    isError: model.statusIsError,
                    onDismiss: model.clearStatus
                )
            }
            HSplitView {
                conversationColumn
                    .frame(minWidth: 240, idealWidth: 280, maxWidth: 360)
                conversationDetail
                    .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .overlay(alignment: .bottom) {
            if let toast = model.activeToast {
                InAppToastOverlayView(toast: toast)
                    .padding(.bottom, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(999)
                    .onTapGesture {
                        model.dismissToast()
                    }
                    .accessibilityHint("点按可关闭提示")
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.82), value: model.activeToast?.id)
        .task {
            await model.loadIfNeeded()
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    Task { await model.reload() }
                } label: {
                    Label("刷新消息", systemImage: "arrow.clockwise")
                }
                .disabled(model.isLoading)
                .help("重新检查消息服务并刷新会话")
            }
        }
        .sheet(isPresented: $presentsNewConversation) {
            NewChatSheet(model: model)
        }
        .alert(
            pendingConversationDeletion.count == 1 ? "删除这个会话？" : "删除这 \(pendingConversationDeletion.count) 个会话？",
            isPresented: $presentsConversationDeletionConfirmation
        ) {
            Button("取消", role: .cancel) {}
            Button("删除会话", role: .destructive) {
                let ids = pendingConversationDeletion
                pendingConversationDeletion = []
                Task {
                    _ = await model.closeConversations(ids: ids)
                    selectedConversationIDs.subtract(ids)
                }
            }
            .disabled(model.isPerformingAction)
        } message: {
            Text("会话会从群晖 Chat 中关闭，消息将进入归档。此操作不能在岚仓中撤销。")
        }
        .onChange(of: model.selectedConversationID) { _, selectedID in
            guard selectedConversationIDs.count <= 1 else { return }
            selectedConversationIDs = selectedID.map { [$0] } ?? []
        }
    }

    private var newConversationHelp: String {
        if model.canCreateDirectConversation || model.canCreateGroupConversation {
            return "选择用户开始聊天或创建私人群聊"
        }
        return "这台 NAS 的消息功能尚未准备好"
    }

    private var conversationColumn: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("会话")
                    .font(.headline)
                Button {
                    presentsNewConversation = true
                } label: {
                    Label("新建聊天", systemImage: "plus")
                        .labelStyle(.iconOnly)
                        .frame(width: 24, height: 24)
                }
                .buttonStyle(.borderless)
                .disabled(!model.canCreateDirectConversation && !model.canCreateGroupConversation)
                .help(newConversationHelp)
                .accessibilityLabel("新建聊天")
                Spacer()
                if model.isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("正在刷新会话")
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            if !model.canUseMessaging {
                ChatServiceStateView(
                    status: model.availability.status,
                    message: model.statusMessage,
                    isLoading: model.isLoading,
                    onRetry: { Task { await model.reload() } }
                )
            } else if model.conversations.isEmpty, !model.isLoading {
                ContentUnavailableView {
                    Label("还没有聊天", systemImage: "bubble.left.and.bubble.right")
                } description: {
                    Text("选择“新建聊天”与其他用户开始聊天。")
                } actions: {
                    Button("新建聊天") {
                        presentsNewConversation = true
                    }
                    .disabled(!model.canCreateDirectConversation && !model.canCreateGroupConversation)
                }
            } else {
                List(selection: conversationSelection) {
                    ForEach(model.conversations) { conversation in
                        ConversationRow(
                            conversation: conversation,
                            users: model.users,
                            currentUserID: model.currentUserID
                        )
                            .tag(conversation.id)
                            .contextMenu {
                                Button(role: .destructive) {
                                    requestConversationDeletion(from: conversation.id)
                                } label: {
                                    Label(conversationDeletionTitle(for: conversation.id), systemImage: "trash")
                                }
                                .disabled(!model.canCloseConversations || model.isPerformingAction)
                            }
                    }
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
                .onDeleteCommand {
                    requestConversationDeletion(ids: selectedConversationIDs)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var conversationSelection: Binding<Set<String>> {
        Binding(
            get: { selectedConversationIDs },
            set: { ids in
                selectedConversationIDs = ids
                let selectedID: String?
                if let current = model.selectedConversationID, ids.contains(current) {
                    selectedID = current
                } else {
                    selectedID = ids.first
                }
                Task { await model.selectConversation(id: selectedID) }
            }
        )
    }

    private func conversationDeletionTargets(from conversationID: String) -> Set<String> {
        selectedConversationIDs.contains(conversationID) && selectedConversationIDs.count > 1
            ? selectedConversationIDs
            : [conversationID]
    }

    private func conversationDeletionTitle(for conversationID: String) -> String {
        let count = conversationDeletionTargets(from: conversationID).count
        return count == 1 ? "删除会话" : "删除 \(count) 个会话"
    }

    private func requestConversationDeletion(from conversationID: String) {
        requestConversationDeletion(ids: conversationDeletionTargets(from: conversationID))
    }

    private func requestConversationDeletion(ids: Set<String>) {
        guard model.canCloseConversations, !model.isPerformingAction, !ids.isEmpty else { return }
        pendingConversationDeletion = ids
        presentsConversationDeletionConfirmation = true
    }

    @ViewBuilder
    private var conversationDetail: some View {
        if let conversation = model.selectedConversation {
            ChatConversationView(model: model, conversation: conversation)
        } else if model.canUseMessaging {
            ContentUnavailableView(
                "选择一个会话",
                systemImage: "bubble.left",
                description: Text("从左侧选择已有会话，或新建一段聊天。")
            )
        } else {
            ChatUnavailableDetail(status: model.availability.status)
        }
    }
}

private struct ChatActionStatusBanner: View {
    let message: String
    let isError: Bool
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: isError ? "exclamationmark.circle.fill" : "checkmark.circle.fill")
                .accessibilityHidden(true)
            Text(message)
                .font(.callout)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Button(action: onDismiss) {
                Label("关闭提示", systemImage: "xmark")
                    .labelStyle(.iconOnly)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("关闭提示")
        }
        .foregroundStyle(isError ? Color.red : Color.secondary)
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(isError ? Color.red.opacity(0.08) : Color.accentColor.opacity(0.08))
    }
}

private struct ConversationRow: View {
    let conversation: ChatConversation
    let users: [ChatUser]
    let currentUserID: String?

    private var directUser: ChatUser? {
        guard conversation.kind == .direct else { return nil }
        let otherID = conversation.memberIDs.first { $0 != currentUserID }
        return users.first { $0.id == otherID }
    }

    var body: some View {
        HStack(spacing: 10) {
            if let directUser {
                ChatAvatar(name: directUser.displayName, imageData: directUser.avatarData)
                    .frame(width: 32, height: 32)
            } else {
                Image(systemName: conversation.kind == .group ? "person.2.fill" : "person.crop.circle.fill")
                    .font(.title2)
                    .foregroundStyle(.tint)
                    .frame(width: 32, height: 32)
                    .accessibilityHidden(true)
            }

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 5) {
                    Text(conversation.title)
                        .font(.headline)
                        .lineLimit(1)
                    if conversation.isEncrypted {
                        Image(systemName: "lock.fill")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("加密会话")
                    }
                    Spacer(minLength: 4)
                    if let lastActivityAt = conversation.lastActivityAt {
                        Text(lastActivityAt, style: .relative)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                HStack(spacing: 6) {
                    Text(conversation.lastMessageSummary ?? "还没有消息")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    if conversation.unreadCount > 0 {
                        Text("\(conversation.unreadCount)")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.tint, in: Capsule())
                            .accessibilityLabel("\(conversation.unreadCount) 条未读消息")
                    }
                }
            }
        }
        .padding(.vertical, 5)
        .accessibilityElement(children: .combine)
    }
}

private struct ChatServiceStateView: View {
    let status: ChatAvailabilityStatus
    let message: String?
    let isLoading: Bool
    let onRetry: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: status == .unavailable ? "bubble.left.and.exclamationmark.bubble.right" : "checkmark.shield")
                .font(.system(size: 34))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text(status == .unavailable ? "消息服务不可用" : "消息功能正在准备")
                .font(.headline)
            Text(message ?? "暂时无法读取会话。")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                onRetry()
            } label: {
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Text("重新检查")
                }
            }
            .disabled(isLoading)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }
}

private struct ChatUnavailableDetail: View {
    let status: ChatAvailabilityStatus

    var body: some View {
        ContentUnavailableView {
            Label(
                status == .unavailable ? "无法使用消息" : "消息功能尚未开放",
                systemImage: status == .unavailable ? "exclamationmark.bubble" : "lock.shield"
            )
        } description: {
            Text(
                status == .unavailable
                    ? "请确认 NAS 已安装并启用 Synology Chat Server，且当前账号具有使用权限。"
                    : "为了保护账号和消息，在功能准备好以前不会尝试连接这台 NAS 的消息服务。"
            )
        }
    }
}

private struct ChatConversationView: View {
    @Bindable var model: ChatWorkspaceModel
    let conversation: ChatConversation
    @State private var attachmentURLs: [URL] = []
    @State private var presentsFileImporter = false
    @State private var selectedMessageIDs: Set<String> = []
    @State private var pendingMessageDeletion: Set<String> = []
    @State private var presentsMessageDeletionConfirmation = false
    @State private var scrollToLatestRequest = 0
    @FocusState private var isComposerFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            conversationHeader
            Divider()

            if model.isLoadingMessages {
                ProgressView("正在载入消息…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.messages.isEmpty {
                emptyConversationState
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            if model.hasMoreMessagesBefore {
                                Button {
                                    Task {
                                        if let anchorID = await model.loadEarlierMessages() {
                                            proxy.scrollTo(anchorID, anchor: .top)
                                        }
                                    }
                                } label: {
                                    if model.isLoadingEarlierMessages {
                                        ProgressView("正在载入更早消息…")
                                            .controlSize(.small)
                                    } else {
                                        Label("载入更早消息", systemImage: "arrow.up.circle")
                                    }
                                }
                                .buttonStyle(.borderless)
                                .disabled(model.isLoadingEarlierMessages)
                                .padding(.vertical, 6)
                            }

                            ForEach(Array(model.messages.enumerated()), id: \.element.id) { index, message in
                                if shouldShowDateSeparator(at: index) {
                                    ChatDateSeparator(date: message.sentAt)
                                        .padding(.vertical, index == 0 ? 2 : 10)
                                }
                                ChatMessageRow(
                                    message: message,
                                    users: model.users,
                                    isCurrentUser: model.isCurrentUser(message),
                                    showsSender: conversation.kind == .group,
                                    isSelected: selectedMessageIDs.contains(message.id),
                                    failureMessage: model.sendFailureMessage(for: message.id),
                                    uploadProgress: model.uploadProgress(for: message.id),
                                    onCancel: { model.cancelMessageSend(id: message.id) },
                                    onRetry: { Task { await model.retryMessage(id: message.id) } }
                                )
                                    .id(message.id)
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        selectMessage(message)
                                    }
                                    .contextMenu {
                                        if message.deliveryState == .failed {
                                            Button {
                                                Task { await model.retryMessage(id: message.id) }
                                            } label: {
                                                Label("重新发送", systemImage: "arrow.clockwise")
                                            }
                                            .disabled(model.isPerformingAction)
                                            Button(role: .destructive) {
                                                model.removeFailedMessage(id: message.id)
                                            } label: {
                                                Label("移除未发送消息", systemImage: "trash")
                                            }
                                        } else if message.deliveryState == .sending {
                                            Button(role: .destructive) {
                                                model.cancelMessageSend(id: message.id)
                                            } label: {
                                                Label("取消发送", systemImage: "xmark.circle")
                                            }
                                        } else if model.canDelete(message) {
                                            Button {
                                                toggleMessageSelection(message.id)
                                            } label: {
                                                Label(
                                                    selectedMessageIDs.contains(message.id) ? "取消选择" : "选择此消息",
                                                    systemImage: selectedMessageIDs.contains(message.id) ? "checkmark.circle.fill" : "circle"
                                                )
                                            }
                                            Divider()
                                            Button(role: .destructive) {
                                                requestMessageDeletion(from: message.id)
                                            } label: {
                                                Label(messageDeletionTitle(for: message.id), systemImage: "trash")
                                            }
                                            .disabled(model.isPerformingAction)
                                        } else {
                                            Button("只能删除自己发送的消息") {}
                                                .disabled(true)
                                        }
                                    }
                            }
                        }
                        .padding(.horizontal, 24)
                        .padding(.vertical, 16)
                        .frame(maxWidth: .infinity)
                    }
                    .background(Color(nsColor: .textBackgroundColor))
                    .task(id: conversation.id) {
                        await Task.yield()
                        if let lastID = model.messages.last?.id {
                            proxy.scrollTo(lastID, anchor: .bottom)
                        }
                    }
                    .onChange(of: model.messages.last?.id) { _, lastID in
                        guard let lastID,
                              let lastMessage = model.messages.last,
                              model.isCurrentUser(lastMessage) else { return }
                        proxy.scrollTo(lastID, anchor: .bottom)
                    }
                    .onChange(of: scrollToLatestRequest) { _, _ in
                        guard let lastID = model.messages.last?.id else { return }
                        proxy.scrollTo(lastID, anchor: .bottom)
                        model.clearNewMessageIndicator()
                    }
                }
            }

            Divider()
            composer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
        .fileImporter(
            isPresented: $presentsFileImporter,
            allowedContentTypes: [.item],
            allowsMultipleSelection: false
        ) { result in
            if case .success(let urls) = result {
                attachmentURLs = Array(urls.prefix(1))
            }
        }
        .alert(
            pendingMessageDeletion.count == 1 ? "删除这条消息？" : "删除这 \(pendingMessageDeletion.count) 条消息？",
            isPresented: $presentsMessageDeletionConfirmation
        ) {
            Button("取消", role: .cancel) {}
            Button("删除消息", role: .destructive) {
                let ids = pendingMessageDeletion
                pendingMessageDeletion = []
                Task {
                    _ = await model.deleteMessages(ids: ids)
                    selectedMessageIDs.subtract(ids)
                }
            }
            .disabled(model.isPerformingAction)
        } message: {
            Text("消息会从群晖 Chat 中删除，无法撤销。管理员可能只允许删除最近发送的消息。")
        }
        .onChange(of: conversation.id) { _, _ in
            selectedMessageIDs = []
        }
        .task(id: conversation.id) {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(15))
                guard !Task.isCancelled else { break }
                await model.refreshCurrentConversation()
            }
        }
    }

    private var conversationHeader: some View {
        HStack(spacing: 10) {
            Image(systemName: conversation.kind == .group ? "person.2.fill" : "person.crop.circle.fill")
                .foregroundStyle(.tint)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(conversation.title)
                    .font(.headline)
                Text(model.memberSummary(for: conversation))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if model.newMessageCount > 0 {
                Button {
                    scrollToLatestRequest += 1
                } label: {
                    Label("\(model.newMessageCount) 条新消息", systemImage: "arrow.down.circle.fill")
                }
                .buttonStyle(.borderless)
                .help("滚动到最新消息")
            }
            if conversation.isEncrypted {
                Label("已加密", systemImage: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var emptyConversationState: some View {
        ZStack {
            Color(nsColor: .textBackgroundColor)

            VStack(spacing: 14) {
                Image(systemName: conversation.kind == .group
                    ? "person.2.fill"
                    : "bubble.left.and.bubble.right.fill")
                    .font(.system(size: 30, weight: .medium))
                    .foregroundStyle(.tint)
                    .frame(width: 64, height: 64)
                    .background(Color.accentColor.opacity(0.10), in: Circle())
                    .accessibilityHidden(true)

                VStack(spacing: 6) {
                    Text(emptyConversationTitle)
                        .font(.title3.weight(.semibold))
                        .multilineTextAlignment(.center)
                    Text("这里还没有消息。发送第一条消息，开始这段聊天。")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if model.canSendText {
                    Button {
                        isComposerFocused = true
                    } label: {
                        Label("发送第一条消息", systemImage: "square.and.pencil")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                    .disabled(model.isPerformingAction)
                    .accessibilityHint("将焦点移到下方的消息输入框")
                }
            }
            .frame(maxWidth: 380)
            .padding(.horizontal, 32)
            .padding(.vertical, 28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .layoutPriority(1)
        .accessibilityElement(children: .contain)
    }

    private var emptyConversationTitle: String {
        switch conversation.kind {
        case .direct:
            "开始和 \(conversation.title) 聊天"
        case .group:
            "开始在“\(conversation.title)”中聊天"
        }
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !attachmentURLs.isEmpty {
                HStack {
                    Label(attachmentURLs.first?.lastPathComponent ?? "已选择附件", systemImage: "paperclip")
                        .font(.caption)
                    Spacer()
                    Button("移除附件") {
                        attachmentURLs = []
                    }
                    .buttonStyle(.borderless)
                }
            }

            HStack(alignment: .bottom, spacing: 8) {
                Button {
                    if model.canSendAttachments {
                        presentsFileImporter = true
                    } else {
                        model.showAttachmentUnavailable()
                    }
                } label: {
                    Label("添加附件", systemImage: "paperclip")
                        .labelStyle(.iconOnly)
                        .frame(width: 28, height: 28)
                }
                .disabled(!model.canUseMessaging || model.isPerformingAction)
                .help(model.canSendAttachments ? "添加图片、视频或文件" : "这台 NAS 尚未开放附件发送")
                .accessibilityLabel("添加附件")

                Button {
                    isComposerFocused = true
                    DispatchQueue.main.async {
                        NSApp.orderFrontCharacterPalette(nil)
                    }
                } label: {
                    Label("插入表情", systemImage: "face.smiling")
                        .labelStyle(.iconOnly)
                        .frame(width: 28, height: 28)
                }
                .disabled(!model.canSendText || model.isPerformingAction)
                .help("打开系统表情与符号")
                .accessibilityLabel("插入表情")

                TextField("输入消息", text: draftText, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...5)
                    .focused($isComposerFocused)
                    .disabled(!model.canSendText || model.isPerformingAction)
                    .onSubmit(send)

                Button(action: send) {
                    if model.isPerformingAction {
                        ProgressView()
                            .controlSize(.small)
                            .frame(width: 28, height: 28)
                    } else {
                        Label("发送", systemImage: "paperplane.fill")
                            .frame(minWidth: 52, minHeight: 28)
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canSend)
                .keyboardShortcut(.return, modifiers: .command)
            }
        }
        .padding(12)
        .background(.bar)
    }

    private var canSend: Bool {
        !model.isPerformingAction
            && ((model.canSendText && !model.draftText(for: conversation.id).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                || (model.canSendAttachments && !attachmentURLs.isEmpty))
    }

    private func send() {
        guard canSend else { return }
        let text = model.draftText(for: conversation.id)
        let urls = attachmentURLs
        Task {
            if await model.send(text: text, attachmentURLs: urls) {
                attachmentURLs = []
            }
        }
    }

    private var draftText: Binding<String> {
        Binding(
            get: { model.draftText(for: conversation.id) },
            set: { model.updateDraft($0, for: conversation.id) }
        )
    }

    private func shouldShowDateSeparator(at index: Int) -> Bool {
        guard index > 0 else { return true }
        return !Calendar.current.isDate(
            model.messages[index - 1].sentAt,
            inSameDayAs: model.messages[index].sentAt
        )
    }

    private func selectMessage(_ message: ChatMessage) {
        guard model.canDelete(message), !model.isPerformingAction else { return }
        if NSEvent.modifierFlags.contains(.command) {
            toggleMessageSelection(message.id)
        } else {
            selectedMessageIDs = [message.id]
        }
    }

    private func toggleMessageSelection(_ messageID: String) {
        if selectedMessageIDs.contains(messageID) {
            selectedMessageIDs.remove(messageID)
        } else {
            selectedMessageIDs.insert(messageID)
        }
    }

    private func messageDeletionTargets(from messageID: String) -> Set<String> {
        selectedMessageIDs.contains(messageID) && selectedMessageIDs.count > 1
            ? selectedMessageIDs
            : [messageID]
    }

    private func messageDeletionTitle(for messageID: String) -> String {
        let count = messageDeletionTargets(from: messageID).count
        return count == 1 ? "删除消息" : "删除 \(count) 条消息"
    }

    private func requestMessageDeletion(from messageID: String) {
        let ids = messageDeletionTargets(from: messageID)
        let selectedMessages = model.messages.filter { ids.contains($0.id) }
        guard selectedMessages.count == ids.count,
              selectedMessages.allSatisfy(model.canDelete),
              !model.isPerformingAction else { return }
        pendingMessageDeletion = ids
        presentsMessageDeletionConfirmation = true
    }
}

private struct ChatMessageRow: View {
    let message: ChatMessage
    let users: [ChatUser]
    let isCurrentUser: Bool
    let showsSender: Bool
    let isSelected: Bool
    let failureMessage: String?
    let uploadProgress: Double?
    let onCancel: () -> Void
    let onRetry: () -> Void

    private var senderName: String {
        if isCurrentUser { return "你" }
        return message.senderDisplayName
            ?? users.first(where: { $0.id == message.senderID })?.displayName
            ?? "成员 \(message.senderID)"
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if isCurrentUser { Spacer(minLength: 64) }

            if !isCurrentUser {
                ChatAvatar(
                    name: senderName,
                    imageData: users.first(where: { $0.id == message.senderID })?.avatarData
                )
            }

            VStack(alignment: isCurrentUser ? .trailing : .leading, spacing: 4) {
                if showsSender || message.senderID == "unknown" {
                    Text(senderName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 7) {
                    if let text = message.text {
                        Text(text)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    ForEach(message.attachments) { attachment in
                        Label(attachment.fileName, systemImage: attachmentIcon(attachment.kind))
                            .font(.callout)
                            .padding(8)
                            .background(.background.opacity(0.7), in: RoundedRectangle(cornerRadius: 8))
                    }

                    if let poll = message.poll {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(poll.question)
                                .font(.headline)
                            ForEach(poll.options) { option in
                                Label("\(option.text)（\(option.voteCount) 票）", systemImage: option.isSelectedByCurrentUser ? "checkmark.circle.fill" : "circle")
                                    .font(.callout)
                            }
                        }
                    }

                    HStack(spacing: 4) {
                        Text(Self.fullDateTimeFormatter.string(from: message.sentAt))
                            .monospacedDigit()
                        if message.encryptionState == .unlocked {
                            Image(systemName: "lock.fill")
                                .accessibilityLabel("加密消息")
                        }
                    }
                    .font(.caption2)
                    .foregroundStyle(isCurrentUser ? .white.opacity(0.82) : .secondary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .foregroundStyle(isCurrentUser ? Color.white : Color.primary)
                .background(
                    isCurrentUser ? Color.accentColor : Color(nsColor: .controlBackgroundColor),
                    in: RoundedRectangle(cornerRadius: 14, style: .continuous)
                )
                .help(Self.fullDateTimeFormatter.string(from: message.sentAt))

                if message.deliveryState == .sending {
                    VStack(alignment: .trailing, spacing: 5) {
                        if let uploadProgress {
                            ProgressView(value: uploadProgress)
                                .progressViewStyle(.linear)
                                .frame(width: 140)
                                .accessibilityLabel("附件上传进度")
                                .accessibilityValue("\(Int((uploadProgress * 100).rounded()))%")
                        }
                        HStack(spacing: 7) {
                            if uploadProgress == nil {
                                ProgressView()
                                    .controlSize(.mini)
                            }
                            Text(uploadProgress.map { "正在上传 \(Int(($0 * 100).rounded()))%" } ?? "正在发送")
                            Button("取消", action: onCancel)
                                .buttonStyle(.link)
                                .font(.caption)
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityElement(children: .combine)
                } else if message.deliveryState == .failed {
                    VStack(alignment: .trailing, spacing: 4) {
                        Label("发送失败", systemImage: "exclamationmark.circle.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.red)
                        if let failureMessage {
                            Text(failureMessage)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.trailing)
                                .lineLimit(2)
                        }
                        Button("重新发送", action: onRetry)
                            .buttonStyle(.link)
                            .font(.caption)
                    }
                }
            }

            if !isCurrentUser { Spacer(minLength: 64) }
        }
        .frame(maxWidth: .infinity, alignment: isCurrentUser ? .trailing : .leading)
        .padding(3)
        .background(
            isSelected ? Color.accentColor.opacity(0.10) : Color.clear,
            in: RoundedRectangle(cornerRadius: 10, style: .continuous)
        )
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(Color.accentColor, lineWidth: 1)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(senderName)，\(Self.fullDateTimeFormatter.string(from: message.sentAt))，\(deliveryAccessibilityText)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var deliveryAccessibilityText: String {
        switch message.deliveryState {
        case .sending: "正在发送"
        case .sent: "已发送"
        case .failed: "发送失败"
        }
    }

    private static let fullDateTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.dateFormat = "yyyy年M月d日 HH:mm:ss"
        return formatter
    }()

    private func attachmentIcon(_ kind: ChatAttachmentKind) -> String {
        switch kind {
        case .image: "photo"
        case .video: "film"
        case .file: "doc"
        case .voice: "waveform"
        }
    }
}

private struct ChatAvatar: View {
    let name: String
    var imageData: Data? = nil

    var body: some View {
        Group {
            if let imageData, let image = NSImage(data: imageData) {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    Circle().fill(Color.accentColor.opacity(0.14))
                    Text(String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(1)).uppercased())
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tint)
                }
            }
        }
        .frame(width: 30, height: 30)
        .clipShape(Circle())
        .accessibilityHidden(true)
    }
}

private struct ChatDateSeparator: View {
    let date: Date

    var body: some View {
        HStack(spacing: 10) {
            Rectangle().fill(.separator).frame(height: 1)
            Text(Self.formatter.string(from: date))
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize()
            Rectangle().fill(.separator).frame(height: 1)
        }
        .accessibilityElement(children: .combine)
    }

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.dateFormat = "yyyy年M月d日 EEEE"
        return formatter
    }()
}

private struct NewChatSheet: View {
    private enum Mode: String, CaseIterable, Identifiable {
        case direct
        case group

        var id: Self { self }
        var title: String { self == .direct ? "单聊" : "群聊" }
    }

    @Environment(\.dismiss) private var dismiss
    @Bindable var model: ChatWorkspaceModel
    @State private var mode: Mode = .direct
    @State private var selectedUserIDs: Set<String> = []
    @State private var groupTitle = ""
    @State private var createsEncryptedConversation = false
    @State private var userSearchText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("新建聊天")
                    .font(.title2.bold())
                Spacer()
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }

            Picker("聊天类型", selection: $mode) {
                ForEach(availableModes) { mode in
                    Text(mode.title).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            if mode == .group {
                TextField("群聊名称", text: $groupTitle)
                Text("请填写名称，并至少选择两位成员。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                Text("搜索并选择一位用户。已有会话会直接打开；首次聊天若当前 NAS 不允许创建，会提示下一步操作。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                TextField("搜索用户姓名", text: $userSearchText)
                    .textFieldStyle(.plain)
                if !userSearchText.isEmpty {
                    Button {
                        userSearchText = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("清除用户搜索")
                    .help("清除搜索")
                }
            }
            .padding(.horizontal, 10)
            .frame(minHeight: 30)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 7))

            if filteredUsers.isEmpty {
                ContentUnavailableView {
                    Label(userSearchText.isEmpty ? "没有可选择的用户" : "没有找到用户", systemImage: "person.crop.circle.badge.questionmark")
                } description: {
                    Text(
                        userSearchText.isEmpty
                            ? "没有读取到用户。请先重新连接；如果仍为空，请确认当前账号可以使用群晖 Chat。"
                            : "请尝试输入其他姓名。"
                    )
                }
                .frame(minHeight: 260)
            } else {
                List(filteredUsers) { user in
                    Button {
                        toggleSelection(for: user.id)
                    } label: {
                        HStack(spacing: 10) {
                            ChatAvatar(name: user.displayName, imageData: user.avatarData)
                            Text(user.displayName)
                            Spacer()
                            if selectedUserIDs.contains(user.id) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.tint)
                                    .accessibilityHidden(true)
                            }
                        }
                        .contentShape(Rectangle())
                        .frame(minHeight: 34)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(user.displayName)
                    .accessibilityValue(selectedUserIDs.contains(user.id) ? "已选择" : "未选择")
                }
                .listStyle(.inset)
                .frame(minHeight: 260)
            }

            if mode == .group,
               model.availability.supportedFeatures.contains(.encryptedConversation) {
                Toggle("创建加密群聊", isOn: $createsEncryptedConversation)
            }

            HStack {
                if model.users.isEmpty {
                    Label("尚未读取到用户", systemImage: "info.circle")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    createConversation()
                } label: {
                    if model.isPerformingAction {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text(mode == .direct ? "开始聊天" : "创建群聊")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canSubmit || model.isPerformingAction)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(minWidth: 460, minHeight: 460)
        .onChange(of: mode) { _, _ in
            selectedUserIDs = []
            createsEncryptedConversation = false
            userSearchText = ""
        }
        .onAppear {
            if !availableModes.contains(mode), let firstMode = availableModes.first {
                mode = firstMode
            }
        }
    }

    private var availableModes: [Mode] {
        var modes: [Mode] = []
        if model.canCreateDirectConversation { modes.append(.direct) }
        if model.canCreateGroupConversation { modes.append(.group) }
        return modes
    }

    private var canSubmit: Bool {
        switch mode {
        case .direct:
            selectedUserIDs.count == 1
        case .group:
            selectedUserIDs.count >= 2
                && !groupTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private var filteredUsers: [ChatUser] {
        let candidates = model.users.filter { $0.isCurrentUser != true }
        let query = userSearchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return candidates }
        return candidates.filter {
            $0.displayName.localizedCaseInsensitiveContains(query)
                || $0.id.localizedCaseInsensitiveContains(query)
        }
    }

    private func createConversation() {
        Task {
            let succeeded: Bool
            switch mode {
            case .direct:
                guard let userID = selectedUserIDs.first else { return }
                succeeded = await model.openDirectConversation(userID: userID)
            case .group:
                succeeded = await model.createGroup(
                    title: groupTitle,
                    memberIDs: Array(selectedUserIDs),
                    isEncrypted: createsEncryptedConversation
                )
            }
            if succeeded { dismiss() }
        }
    }

    private func toggleSelection(for userID: String) {
        if selectedUserIDs.contains(userID) {
            selectedUserIDs.remove(userID)
        } else if mode == .direct {
            selectedUserIDs = [userID]
        } else {
            selectedUserIDs.insert(userID)
        }
    }
}
