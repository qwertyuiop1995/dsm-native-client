import AppKit
import DsmCore
import SwiftUI
import UniformTypeIdentifiers

struct ChatWorkspaceView: View {
    @Environment(\.accessibilityReduceMotion) private var reducesMotion
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
                    .zIndex(10)
                    .onTapGesture {
                        model.dismissToast()
                    }
                    .accessibilityHint("点按可关闭提示")
            }
        }
        .animation(
            reducesMotion ? nil : .spring(response: 0.3, dampingFraction: 0.82),
            value: model.activeToast?.id
        )
        .task {
            await model.loadIfNeeded()
            await model.refreshForegroundChat()
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
                .fillsAvailableContentArea()
            } else {
                List(selection: conversationSelection) {
                    ForEach(model.conversations) { conversation in
                        ConversationRow(
                            conversation: conversation,
                            users: model.users,
                            currentUserID: model.currentUserID,
                            isPinned: model.isConversationPinned(conversation.id)
                        )
                            .tag(conversation.id)
                            .contextMenu {
                                Button {
                                    model.toggleConversationPin(id: conversation.id)
                                } label: {
                                    Label(
                                        model.isConversationPinned(conversation.id)
                                            ? "取消置顶"
                                            : "置顶会话",
                                        systemImage: model.isConversationPinned(conversation.id)
                                            ? "pin.slash"
                                            : "pin"
                                    )
                                }

                                Divider()

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
            .fillsAvailableContentArea()
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
    let isPinned: Bool

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
                    if isPinned {
                        Image(systemName: "pin.fill")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .accessibilityLabel("已置顶")
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
        .fillsAvailableContentArea()
    }
}

private struct ChatConversationView: View {
    @Bindable var model: ChatWorkspaceModel
    let conversation: ChatConversation
    @State private var attachmentURLs: [URL] = []
    @State private var presentsFileImporter = false
    @State private var presentsPollComposer = false
    @State private var presentsReminderList = false
    @State private var presentsGroupMembers = false
    @State private var presentsPinnedMessages = false
    @State private var reminderMessage: ChatMessage?
    @State private var presentsScheduledMessageComposer = false
    @State private var presentsScheduledMessageList = false
    @State private var selectedMessageIDs: Set<String> = []
    @State private var presentsForwardSheet = false
    @State private var pendingMessageDeletion: Set<String> = []
    @State private var presentsMessageDeletionConfirmation = false
    @State private var scrollToLatestRequest = 0
    @State private var presentsImagePreview = false
    @State private var previewedImage: NSImage?
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
                                    downloadProgress: model.attachmentDownloadProgress(for: message.id),
                                    thumbnailData: model.thumbnailData(for: message.id),
                                    canDownloadAttachments: model.canDownloadAttachments,
                                    onCancel: { model.cancelMessageSend(id: message.id) },
                                    onRetry: { Task { await model.retryMessage(id: message.id) } },
                                    onCancelDownload: {
                                        model.cancelAttachmentDownload(messageID: message.id)
                                    },
                                    onLoadThumbnail: { attachment in
                                        Task {
                                            await model.loadAttachmentThumbnail(
                                                messageID: message.id,
                                                attachment: attachment
                                            )
                                        }
                                    },
                                    onPreviewImage: { attachment in
                                        presentImagePreview(message: message, attachment: attachment)
                                    },
                                    onSaveAttachment: { attachment in
                                        saveAttachment(message: message, attachment: attachment)
                                    }
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
                                        } else {
                                            if let attachment = message.attachments.first,
                                               model.canDownloadAttachments {
                                                if attachment.kind == .image {
                                                    Button {
                                                        presentImagePreview(message: message, attachment: attachment)
                                                    } label: {
                                                        Label("预览图片", systemImage: "photo")
                                                    }
                                                }
                                                Button {
                                                    saveAttachment(message: message, attachment: attachment)
                                                } label: {
                                                    Label("将附件另存为…", systemImage: "square.and.arrow.down")
                                                }
                                                Divider()
                                            }
                                            if model.canManageReminders {
                                                Button {
                                                    reminderMessage = message
                                                } label: {
                                                    Label(
                                                        model.reminder(for: message.id) == nil ? "设置提醒…" : "修改提醒…",
                                                        systemImage: "bell"
                                                    )
                                                }
                                                .disabled(model.isPerformingAction)
                                            }
                                            if model.canPin(message) {
                                                Button {
                                                    Task {
                                                        _ = await model.setMessagePinned(
                                                            message,
                                                            isPinned: !message.isPinned
                                                        )
                                                    }
                                                } label: {
                                                    Label(
                                                        message.isPinned ? "从群公告中移除" : "设为群公告",
                                                        systemImage: message.isPinned ? "pin.slash" : "pin"
                                                    )
                                                }
                                                .disabled(model.isPerformingAction)
                                            }
                                            if model.canForward(message) {
                                                Divider()
                                                Button {
                                                    toggleMessageSelection(message.id)
                                                } label: {
                                                    Label(
                                                        selectedMessageIDs.contains(message.id) ? "取消选择" : "选择此消息",
                                                        systemImage: selectedMessageIDs.contains(message.id) ? "checkmark.circle.fill" : "circle"
                                                    )
                                                }
                                                Button {
                                                    presentForwardSheet(from: message.id)
                                                } label: {
                                                    Label("转发…", systemImage: "arrowshape.turn.up.right")
                                                }
                                                .disabled(model.isPerformingAction)
                                            }
                                            if model.canDelete(message) {
                                                Divider()
                                                Button(role: .destructive) {
                                                    requestMessageDeletion(from: message.id)
                                                } label: {
                                                    Label(messageDeletionTitle(for: message.id), systemImage: "trash")
                                                }
                                                .disabled(model.isPerformingAction)
                                            }
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

            if !selectedMessageIDs.isEmpty {
                selectionBar
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
        .sheet(isPresented: $presentsPollComposer) {
            CreatePollSheet(model: model, conversation: conversation)
        }
        .sheet(isPresented: $presentsReminderList) {
            ReminderListSheet(model: model)
        }
        .sheet(isPresented: $presentsGroupMembers) {
            GroupMembersSheet(model: model, conversation: conversation)
        }
        .sheet(isPresented: $presentsPinnedMessages) {
            PinnedMessagesSheet(model: model, conversation: conversation)
        }
        .sheet(isPresented: $presentsScheduledMessageComposer) {
            ScheduledMessageComposerSheet(model: model, conversation: conversation)
        }
        .sheet(isPresented: $presentsScheduledMessageList) {
            ScheduledMessageListSheet(model: model)
        }
        .sheet(item: $reminderMessage) { message in
            ReminderEditorSheet(model: model, message: message)
        }
        .sheet(isPresented: $presentsImagePreview) {
            ChatImagePreviewSheet(image: previewedImage)
        }
        .sheet(isPresented: $presentsForwardSheet) {
            ForwardMessagesSheet(
                model: model,
                messageIDs: selectedMessageIDs
            ) {
                selectedMessageIDs = []
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
            presentsForwardSheet = false
            presentsImagePreview = false
            previewedImage = nil
        }
    }

    private var selectionBar: some View {
        HStack(spacing: 10) {
            Label(
                "已选择 \(selectedMessageIDs.count) 条消息",
                systemImage: "checkmark.circle.fill"
            )
            .font(.callout.weight(.medium))
            .foregroundStyle(.secondary)

            Spacer()

            Button {
                presentsForwardSheet = true
            } label: {
                Label("转发", systemImage: "arrowshape.turn.up.right")
            }
            .buttonStyle(.borderedProminent)
            .disabled(
                selectedMessages.count != selectedMessageIDs.count
                    || !selectedMessages.allSatisfy(model.canForward)
                    || model.isPerformingAction
            )

            if selectedMessages.count == selectedMessageIDs.count,
               selectedMessages.allSatisfy(model.canDelete) {
                Button(role: .destructive) {
                    requestMessageDeletion(for: selectedMessageIDs)
                } label: {
                    Label("删除", systemImage: "trash")
                }
                .disabled(model.isPerformingAction)
            }

            Button("取消选择") {
                selectedMessageIDs = []
            }
            .keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 9)
        .background(.bar)
    }

    private var selectedMessages: [ChatMessage] {
        model.messages.filter { selectedMessageIDs.contains($0.id) }
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
            if conversation.kind == .group, model.canViewGroupMembers {
                Button {
                    presentsGroupMembers = true
                } label: {
                    Label("群成员", systemImage: "person.2")
                        .labelStyle(.iconOnly)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.borderless)
                .help("查看群成员")
                .accessibilityLabel("查看群成员")
            }
            if conversation.kind == .group, model.canManagePinnedMessages {
                Button {
                    presentsPinnedMessages = true
                } label: {
                    Label("群公告", systemImage: "pin")
                        .labelStyle(.iconOnly)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.borderless)
                .help("查看群公告")
                .accessibilityLabel("查看群公告")
            }
            if model.canManageReminders {
                Button {
                    presentsReminderList = true
                } label: {
                    Label("提醒", systemImage: model.reminders.isEmpty ? "bell" : "bell.badge")
                        .labelStyle(.iconOnly)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.borderless)
                .help("查看消息提醒")
                .accessibilityLabel("查看消息提醒")
            }
            if model.canScheduleMessages {
                Button {
                    presentsScheduledMessageList = true
                } label: {
                    Label(
                        "定时消息",
                        systemImage: model.scheduledMessages.isEmpty ? "clock" : "clock.badge"
                    )
                    .labelStyle(.iconOnly)
                    .frame(width: 28, height: 28)
                }
                .buttonStyle(.borderless)
                .help("查看定时消息")
                .accessibilityLabel("查看定时消息")
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

                Button {
                    presentsPollComposer = true
                } label: {
                    Label("创建投票", systemImage: "chart.bar.xaxis")
                        .labelStyle(.iconOnly)
                        .frame(width: 28, height: 28)
                }
                .disabled(!model.canCreatePoll || model.isPerformingAction)
                .help(model.canCreatePoll ? "创建投票" : "这台 NAS 尚未开放投票")
                .accessibilityLabel("创建投票")

                Button {
                    presentsScheduledMessageComposer = true
                } label: {
                    Label("定时发送", systemImage: "calendar.badge.clock")
                        .labelStyle(.iconOnly)
                        .frame(width: 28, height: 28)
                }
                .disabled(!model.canScheduleMessages || model.isPerformingAction)
                .help(model.canScheduleMessages ? "安排定时消息" : "这台 NAS 尚未开放定时消息")
                .accessibilityLabel("安排定时消息")

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
        guard model.canForward(message), !model.isPerformingAction else { return }
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
        guard selectedMessageIDs.contains(messageID) else { return [messageID] }
        let deletableIDs = Set(
            model.messages
                .filter { selectedMessageIDs.contains($0.id) && model.canDelete($0) }
                .map(\.id)
        )
        return deletableIDs.contains(messageID) ? deletableIDs : [messageID]
    }

    private func messageDeletionTitle(for messageID: String) -> String {
        let count = messageDeletionTargets(from: messageID).count
        return count == 1 ? "删除消息" : "删除 \(count) 条消息"
    }

    private func requestMessageDeletion(from messageID: String) {
        requestMessageDeletion(for: messageDeletionTargets(from: messageID))
    }

    private func requestMessageDeletion(for ids: Set<String>) {
        let selectedMessages = model.messages.filter { ids.contains($0.id) }
        guard selectedMessages.count == ids.count,
              selectedMessages.allSatisfy(model.canDelete),
              !model.isPerformingAction else { return }
        pendingMessageDeletion = ids
        presentsMessageDeletionConfirmation = true
    }

    private func presentForwardSheet(from messageID: String) {
        if !selectedMessageIDs.contains(messageID) {
            selectedMessageIDs = [messageID]
        }
        presentsForwardSheet = true
    }

    private func presentImagePreview(message: ChatMessage, attachment: ChatAttachment) {
        guard attachment.kind == .image,
              model.canDownloadAttachments,
              !model.isPerformingAction,
              let image = model.thumbnailData(for: message.id).flatMap(NSImage.init(data:)) else { return }
        previewedImage = image
        presentsImagePreview = true
    }

    private func saveAttachment(message: ChatMessage, attachment: ChatAttachment) {
        guard model.canDownloadAttachments, !model.isPerformingAction else { return }
        let panel = NSSavePanel()
        panel.nameFieldStringValue = URL(fileURLWithPath: attachment.fileName).lastPathComponent
        panel.canCreateDirectories = true
        panel.title = "保存附件"
        panel.prompt = "保存"
        panel.begin { response in
            guard response == .OK, let destination = panel.url else { return }
            Task {
                _ = await model.downloadAttachment(
                    messageID: message.id,
                    attachment: attachment,
                    to: destination
                )
            }
        }
    }
}

private struct ChatImagePreviewSheet: View {
    @Environment(\.dismiss) private var dismiss
    let image: NSImage?

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black
                .ignoresSafeArea()
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding(20)
                    .accessibilityLabel("图片预览")
            } else {
                ProgressView()
                    .controlSize(.large)
                    .tint(.white)
                    .accessibilityLabel("正在载入图片")
            }
            Button {
                dismiss()
            } label: {
                Label("关闭预览", systemImage: "xmark")
                    .labelStyle(.iconOnly)
                    .frame(width: 32, height: 32)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white)
            .background(.black.opacity(0.55), in: Circle())
            .padding(16)
            .keyboardShortcut(.cancelAction)
            .help("关闭预览")
        }
        .frame(minWidth: 720, idealWidth: 960, minHeight: 520, idealHeight: 720)
    }
}

private struct ForwardMessagesSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var model: ChatWorkspaceModel
    let messageIDs: Set<String>
    let onComplete: () -> Void
    @State private var selectedConversationIDs: Set<String> = []
    @State private var selectedUserIDs: Set<String> = []
    @State private var searchText = ""
    @State private var forwardErrorMessage: String?

    private var conversationCandidates: [ChatConversation] {
        model.conversations.filter { conversation in
            guard conversation.id != model.selectedConversationID else { return false }
            let query = normalizedSearchText
            return query.isEmpty
                || conversation.title.localizedCaseInsensitiveContains(query)
        }
    }

    private var contactCandidates: [ChatUser] {
        let existingDirectUserIDs = Set(
            model.conversations
                .filter { $0.kind == .direct }
                .flatMap(\.memberIDs)
        )
        return model.users.filter { user in
            guard user.isCurrentUser != true,
                  user.id != model.currentUserID,
                  !user.isDisabled,
                  !existingDirectUserIDs.contains(user.id) else {
                return false
            }
            return normalizedSearchText.isEmpty
                || user.displayName.localizedCaseInsensitiveContains(normalizedSearchText)
                || user.id.localizedCaseInsensitiveContains(normalizedSearchText)
        }
    }

    private var normalizedSearchText: String {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var selectedTargetCount: Int {
        selectedConversationIDs.count + selectedUserIDs.count
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("转发消息")
                        .font(.title2.bold())
                    Text("将 \(messageIDs.count) 条消息发送到其他会话或联系人")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(20)

            Divider()

            TextField("搜索会话或联系人", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .padding(.horizontal, 20)
                .padding(.vertical, 12)

            if conversationCandidates.isEmpty, contactCandidates.isEmpty {
                ContentUnavailableView(
                    normalizedSearchText.isEmpty ? "没有可用的转发目标" : "没有找到转发目标",
                    systemImage: normalizedSearchText.isEmpty ? "person.2.slash" : "magnifyingglass",
                    description: Text(normalizedSearchText.isEmpty ? "当前没有其他会话或可联系的用户。" : "请尝试其他关键词。")
                )
                .fillsAvailableContentArea()
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        if !conversationCandidates.isEmpty {
                            recipientSectionTitle("已有会话")
                            ForEach(conversationCandidates) { conversation in
                                recipientButton(
                                    title: conversation.title,
                                    subtitle: model.memberSummary(for: conversation),
                                    systemImage: conversation.kind == .group
                                        ? "person.2.fill"
                                        : "person.crop.circle.fill",
                                    isSelected: selectedConversationIDs.contains(conversation.id)
                                ) {
                                    toggleConversationSelection(conversation.id)
                                }
                            }
                        }

                        if !contactCandidates.isEmpty {
                            recipientSectionTitle("联系人")
                                .padding(.top, conversationCandidates.isEmpty ? 0 : 10)
                            ForEach(contactCandidates) { user in
                                recipientButton(
                                    title: user.displayName,
                                    subtitle: "尚未开始聊天",
                                    systemImage: "person.crop.circle.badge.plus",
                                    isSelected: selectedUserIDs.contains(user.id)
                                ) {
                                    toggleUserSelection(user.id)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 12)
                }
            }

            if let forwardErrorMessage {
                Label(forwardErrorMessage, systemImage: "exclamationmark.circle.fill")
                    .font(.callout)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
            }

            Divider()

            HStack {
                Text(selectedTargetCount == 0
                    ? "请选择至少一个目标"
                    : "已选择 \(selectedTargetCount) 个目标")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("取消") { dismiss() }
                Button {
                    Task {
                        forwardErrorMessage = nil
                        let succeeded = await model.forwardMessages(
                            ids: messageIDs,
                            to: selectedConversationIDs,
                            newDirectUserIDs: selectedUserIDs
                        )
                        if succeeded {
                            onComplete()
                            dismiss()
                        } else {
                            forwardErrorMessage = model.statusMessage
                                ?? "消息没有转发完成，请稍后重试。"
                        }
                    }
                } label: {
                    if model.isPerformingAction {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Label("转发", systemImage: "arrowshape.turn.up.right")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(selectedTargetCount == 0 || model.isPerformingAction)
                .keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .frame(minWidth: 480, idealWidth: 520, minHeight: 480, idealHeight: 600)
    }

    private func recipientSectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .accessibilityAddTraits(.isHeader)
    }

    private func recipientButton(
        title: String,
        subtitle: String,
        systemImage: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: systemImage)
                    .font(.title3)
                    .foregroundStyle(.tint)
                    .frame(width: 30, height: 30)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.body.weight(.medium))
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .contentShape(Rectangle())
            .background(
                isSelected ? Color.accentColor.opacity(0.10) : Color.clear,
                in: RoundedRectangle(cornerRadius: 9, style: .continuous)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(title)，\(subtitle)，\(isSelected ? "已选择" : "未选择")")
        .accessibilityValue(isSelected ? "已选择" : "未选择")
    }

    private func toggleConversationSelection(_ id: String) {
        if selectedConversationIDs.contains(id) {
            selectedConversationIDs.remove(id)
        } else {
            selectedConversationIDs.insert(id)
        }
    }

    private func toggleUserSelection(_ id: String) {
        if selectedUserIDs.contains(id) {
            selectedUserIDs.remove(id)
        } else {
            selectedUserIDs.insert(id)
        }
    }
}

private struct GroupMembersSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var model: ChatWorkspaceModel
    let conversation: ChatConversation

    var body: some View {
        VStack(spacing: 0) {
            sheetHeader(
                title: "群成员",
                subtitle: "\(conversation.title) · \(model.conversationMembers.count) 位成员"
            )
            Divider()

            if model.isLoadingConversationMembers {
                ProgressView("正在载入群成员…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = model.conversationMemberLoadError {
                retryState(
                    title: "无法载入群成员",
                    message: error,
                    systemImage: "person.2.slash"
                ) {
                    Task { await model.loadConversationMembers() }
                }
            } else if model.conversationMembers.isEmpty {
                ContentUnavailableView(
                    "没有可显示的成员",
                    systemImage: "person.2",
                    description: Text("群成员信息可能受当前账号权限限制。")
                )
                .fillsAvailableContentArea()
            } else {
                List(model.conversationMembers) { member in
                    HStack(spacing: 12) {
                        ChatAvatar(name: member.displayName, imageData: member.avatarData, size: 32)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(member.displayName)
                                .font(.body.weight(.medium))
                            if member.isCurrentUser == true {
                                Text("你")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        if member.isDisabled {
                            Text("已停用")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .frame(minWidth: 460, minHeight: 420)
        .task { await model.loadConversationMembers() }
    }

    private func sheetHeader(title: String, subtitle: String) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.title2.bold())
                Text(subtitle)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("完成") { dismiss() }
                .keyboardShortcut(.cancelAction)
        }
        .padding(16)
    }

    private func retryState(
        title: String,
        message: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
        } description: {
            Text(message)
        } actions: {
            Button("重试", action: action)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct PinnedMessagesSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var model: ChatWorkspaceModel
    let conversation: ChatConversation

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("群公告")
                        .font(.title2.bold())
                    Text(conversation.title)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("完成") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(16)
            Divider()

            if model.isLoadingPinnedMessages {
                ProgressView("正在载入群公告…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = model.pinnedMessageLoadError {
                ContentUnavailableView {
                    Label("无法载入群公告", systemImage: "pin.slash")
                } description: {
                    Text(error)
                } actions: {
                    Button("重试") {
                        Task { await model.loadPinnedMessages() }
                    }
                }
                .fillsAvailableContentArea()
            } else if model.pinnedMessages.isEmpty {
                ContentUnavailableView(
                    "还没有群公告",
                    systemImage: "pin",
                    description: Text("在消息上点按右键并选择“设为群公告”。")
                )
                .fillsAvailableContentArea()
            } else {
                List(model.pinnedMessages) { message in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "pin.fill")
                            .foregroundStyle(.tint)
                            .frame(width: 24)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(messageSummary(message))
                                .lineLimit(3)
                            HStack(spacing: 6) {
                                Text(message.senderDisplayName ?? model.displayName(for: message.senderID) ?? "群成员")
                                if let pinnedAt = message.pinnedAt {
                                    Text("·")
                                    Text(Self.formatter.string(from: pinnedAt))
                                }
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button {
                            Task {
                                _ = await model.setMessagePinned(message, isPinned: false)
                            }
                        } label: {
                            Label("从群公告中移除", systemImage: "pin.slash")
                                .labelStyle(.iconOnly)
                                .frame(width: 28, height: 28)
                        }
                        .buttonStyle(.borderless)
                        .help("从群公告中移除")
                        .accessibilityLabel("从群公告中移除")
                        .disabled(model.isPerformingAction)
                    }
                    .padding(.vertical, 5)
                }
            }
        }
        .frame(minWidth: 520, minHeight: 420)
        .task { await model.loadPinnedMessages() }
    }

    private func messageSummary(_ message: ChatMessage) -> String {
        if let text = message.text?.trimmingCharacters(in: .whitespacesAndNewlines),
           !text.isEmpty {
            return text
        }
        if let attachment = message.attachments.first {
            return "附件：\(attachment.fileName)"
        }
        return "一条群消息"
    }

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}

private struct ScheduledMessageComposerSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var model: ChatWorkspaceModel
    let conversation: ChatConversation
    @State private var text = ""
    @State private var sendAt = Date().addingTimeInterval(3_600)

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("定时发送")
                        .font(.title2.bold())
                    Text("发送到“\(conversation.title)”")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }

            TextField("消息内容", text: $text, axis: .vertical)
                .lineLimit(3...8)
                .textFieldStyle(.roundedBorder)

            DatePicker(
                "发送时间",
                selection: $sendAt,
                in: Date()...,
                displayedComponents: [.date, .hourAndMinute]
            )
            .datePickerStyle(.field)

            Text("消息会由群晖 Chat 在设定时间发送。关闭岚仓不会取消这项安排。")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Spacer()
                Button {
                    Task {
                        if await model.createScheduledMessage(text: text, sendAt: sendAt) {
                            dismiss()
                        }
                    }
                } label: {
                    if model.isPerformingAction {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("安排发送")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(
                    text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || sendAt <= Date()
                        || model.isPerformingAction
                )
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(minWidth: 460, minHeight: 300)
    }
}

private struct ScheduledMessageListSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var model: ChatWorkspaceModel
    @State private var pendingDeletion: ChatScheduledMessage?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("定时消息")
                    .font(.title2.bold())
                Spacer()
                Button("完成") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(16)
            Divider()

            if model.isLoadingScheduledMessages {
                ProgressView("正在载入定时消息…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = model.scheduledMessageLoadError {
                ContentUnavailableView {
                    Label("无法载入定时消息", systemImage: "clock.badge.exclamationmark")
                } description: {
                    Text(error)
                } actions: {
                    Button("重试") {
                        Task { await model.loadScheduledMessages() }
                    }
                }
                .fillsAvailableContentArea()
            } else if model.scheduledMessages.isEmpty {
                ContentUnavailableView(
                    "没有定时消息",
                    systemImage: "clock",
                    description: Text("在消息输入区选择时钟按钮，可以安排以后发送。")
                )
                .fillsAvailableContentArea()
            } else {
                List(model.scheduledMessages) { scheduled in
                    HStack(spacing: 12) {
                        Image(systemName: "clock.badge.checkmark")
                            .foregroundStyle(.tint)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(scheduled.text)
                                .lineLimit(2)
                            Text(Self.formatter.string(from: scheduled.sendAt))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(role: .destructive) {
                            pendingDeletion = scheduled
                        } label: {
                            Label("取消定时发送", systemImage: "xmark.circle")
                                .labelStyle(.iconOnly)
                                .frame(width: 28, height: 28)
                        }
                        .buttonStyle(.borderless)
                        .help("取消定时发送")
                        .accessibilityLabel("取消定时发送")
                        .disabled(model.isPerformingAction)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .frame(minWidth: 520, minHeight: 360)
        .task { await model.loadScheduledMessages() }
        .alert("取消这条定时消息？", isPresented: Binding(
            get: { pendingDeletion != nil },
            set: { if !$0 { pendingDeletion = nil } }
        )) {
            Button("保留安排", role: .cancel) { pendingDeletion = nil }
            Button("取消发送", role: .destructive) {
                guard let scheduled = pendingDeletion else { return }
                pendingDeletion = nil
                Task { _ = await model.deleteScheduledMessage(id: scheduled.id) }
            }
        } message: {
            Text("取消后这条消息不会按原计划发送。此操作不能撤销。")
        }
    }

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}

private struct ReminderEditorSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var model: ChatWorkspaceModel
    let message: ChatMessage
    @State private var remindAt = Date().addingTimeInterval(3_600)

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(model.reminder(for: message.id) == nil ? "设置提醒" : "修改提醒")
                        .font(.title2.bold())
                    Text(message.text?.isEmpty == false ? message.text! : "附件消息")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer()
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }

            DatePicker(
                "提醒时间",
                selection: $remindAt,
                in: Date()...,
                displayedComponents: [.date, .hourAndMinute]
            )
            .datePickerStyle(.field)

            Text("到达设定时间后，群晖 Chat 会按账号的通知设置提醒你。")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                if model.reminder(for: message.id) != nil {
                    Button("取消现有提醒", role: .destructive) {
                        Task {
                            if await model.deleteReminder(messageID: message.id) {
                                dismiss()
                            }
                        }
                    }
                    .disabled(model.isPerformingAction)
                }
                Spacer()
                Button {
                    Task {
                        if await model.setReminder(messageID: message.id, remindAt: remindAt) {
                            dismiss()
                        }
                    }
                } label: {
                    if model.isPerformingAction {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("保存提醒")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(remindAt <= Date() || model.isPerformingAction)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(minWidth: 420, minHeight: 220)
        .onAppear {
            if let existing = model.reminder(for: message.id) {
                remindAt = max(existing.remindAt, Date().addingTimeInterval(60))
            }
        }
    }
}

private struct ReminderListSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var model: ChatWorkspaceModel
    @State private var pendingDeletion: ChatReminder?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("消息提醒")
                    .font(.title2.bold())
                Spacer()
                Button("完成") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(16)
            Divider()

            if model.isLoadingReminders {
                ProgressView("正在载入提醒…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = model.reminderLoadError {
                ContentUnavailableView {
                    Label("无法载入消息提醒", systemImage: "bell.slash")
                } description: {
                    Text(error)
                } actions: {
                    Button("重试") {
                        Task { await model.loadReminders() }
                    }
                }
                .fillsAvailableContentArea()
            } else if model.reminders.isEmpty {
                ContentUnavailableView(
                    "没有消息提醒",
                    systemImage: "bell.slash",
                    description: Text("在消息上点按右键，可以为它设置提醒。")
                )
                .fillsAvailableContentArea()
            } else {
                List(model.reminders) { reminder in
                    HStack(spacing: 12) {
                        Image(systemName: "bell.fill")
                            .foregroundStyle(.tint)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(messageSummary(for: reminder))
                                .lineLimit(2)
                            Text(Self.formatter.string(from: reminder.remindAt))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button(role: .destructive) {
                            pendingDeletion = reminder
                        } label: {
                            Label("取消提醒", systemImage: "bell.slash")
                                .labelStyle(.iconOnly)
                                .frame(width: 28, height: 28)
                        }
                        .buttonStyle(.borderless)
                        .help("取消提醒")
                        .accessibilityLabel("取消提醒")
                        .disabled(model.isPerformingAction)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .frame(minWidth: 500, minHeight: 360)
        .task { await model.loadReminders() }
        .alert("取消这条提醒？", isPresented: Binding(
            get: { pendingDeletion != nil },
            set: { if !$0 { pendingDeletion = nil } }
        )) {
            Button("保留提醒", role: .cancel) { pendingDeletion = nil }
            Button("取消提醒", role: .destructive) {
                guard let reminder = pendingDeletion else { return }
                pendingDeletion = nil
                Task { _ = await model.deleteReminder(messageID: reminder.messageID) }
            }
        } message: {
            Text("取消后将不再收到这条消息的提醒。你之后仍可重新设置。")
        }
    }

    private func messageSummary(for reminder: ChatReminder) -> String {
        guard let message = model.messages.first(where: { $0.id == reminder.messageID }) else {
            return "一条聊天消息"
        }
        return message.text?.isEmpty == false
            ? message.text!
            : message.attachments.first?.fileName ?? "一条聊天消息"
    }

    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = .autoupdatingCurrent
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}

private struct CreatePollSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Bindable var model: ChatWorkspaceModel
    let conversation: ChatConversation
    @State private var question = ""
    @State private var options = ["", ""]
    @State private var allowsMultipleSelection = false
    @State private var isAnonymous = false
    @FocusState private var focusedField: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("创建投票")
                        .font(.title2.bold())
                    Text("发送到“\(conversation.title)”")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }

            TextField("投票问题", text: $question, axis: .vertical)
                .lineLimit(1...3)
                .textFieldStyle(.roundedBorder)

            VStack(alignment: .leading, spacing: 8) {
                Text("选项")
                    .font(.headline)
                ForEach(options.indices, id: \.self) { index in
                    HStack {
                        TextField("选项 \(index + 1)", text: $options[index])
                            .focused($focusedField, equals: index)
                        if options.count > 2 {
                            Button {
                                options.remove(at: index)
                            } label: {
                                Label("移除选项 \(index + 1)", systemImage: "minus.circle")
                                    .labelStyle(.iconOnly)
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
                if options.count < 10 {
                    Button {
                        options.append("")
                        focusedField = options.count - 1
                    } label: {
                        Label("添加选项", systemImage: "plus.circle")
                    }
                    .buttonStyle(.borderless)
                }
            }

            Toggle("允许选择多个选项", isOn: $allowsMultipleSelection)
            Toggle("匿名投票", isOn: $isAnonymous)

            HStack {
                Text("至少填写两个不同的选项。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    Task {
                        if await model.createPoll(
                            question: question,
                            options: options,
                            allowsMultipleSelection: allowsMultipleSelection,
                            isAnonymous: isAnonymous
                        ) {
                            dismiss()
                        }
                    }
                } label: {
                    if model.isPerformingAction {
                        ProgressView().controlSize(.small)
                    } else {
                        Text("发送投票")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canSubmit || model.isPerformingAction)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(minWidth: 460, minHeight: 390)
    }

    private var canSubmit: Bool {
        let normalizedQuestion = question.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedOptions = options
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        let canonical = normalizedOptions.map { $0.lowercased() }
        return !normalizedQuestion.isEmpty
            && normalizedOptions.count >= 2
            && Set(canonical).count == normalizedOptions.count
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
    let downloadProgress: Double?
    let thumbnailData: Data?
    let canDownloadAttachments: Bool
    let onCancel: () -> Void
    let onRetry: () -> Void
    let onCancelDownload: () -> Void
    let onLoadThumbnail: (ChatAttachment) -> Void
    let onPreviewImage: (ChatAttachment) -> Void
    let onSaveAttachment: (ChatAttachment) -> Void

    private var senderName: String {
        if isCurrentUser { return "你" }
        return message.senderDisplayName
            ?? users.first(where: { $0.id == message.senderID })?.displayName
            ?? "成员 \(message.senderID)"
    }

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if isCurrentUser { Spacer(minLength: 72) }

            VStack(alignment: isCurrentUser ? .trailing : .leading, spacing: 6) {
                metadata
                messageBubble
                deliveryStatus
            }
            .frame(maxWidth: 560, alignment: isCurrentUser ? .trailing : .leading)

            if !isCurrentUser { Spacer(minLength: 72) }
        }
        .frame(maxWidth: .infinity, alignment: isCurrentUser ? .trailing : .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(
            isSelected ? Color.accentColor.opacity(0.09) : Color.clear,
            in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .overlay(alignment: isCurrentUser ? .topLeading : .topTrailing) {
            if isSelected {
                Image(systemName: "checkmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(.tint)
                    .background(Color(nsColor: .textBackgroundColor), in: Circle())
                    .padding(8)
                    .accessibilityHidden(true)
            }
        }
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Color.accentColor.opacity(0.65), lineWidth: 1)
            }
        }
        .accessibilityElement(children: message.attachments.isEmpty ? .combine : .contain)
        .accessibilityLabel("\(senderName)，\(Self.fullDateTimeFormatter.string(from: message.sentAt))，\(deliveryAccessibilityText)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var metadata: some View {
        HStack(spacing: 7) {
            if !isCurrentUser {
                senderAvatar
                if showsSender || message.senderID == "unknown" {
                    Text(senderName)
                        .fontWeight(.semibold)
                        .lineLimit(1)
                }
            }

            HStack(spacing: 4) {
                Text(Self.fullDateTimeFormatter.string(from: message.sentAt))
                    .monospacedDigit()
                if message.encryptionState == .unlocked {
                    Image(systemName: "lock.fill")
                        .accessibilityLabel("加密消息")
                }
                if message.isPinned {
                    Image(systemName: "pin.fill")
                        .accessibilityLabel("群公告")
                }
            }

            if isCurrentUser {
                Text("你")
                    .fontWeight(.semibold)
                senderAvatar
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
    }

    private var senderAvatar: some View {
        ChatAvatar(
            name: senderName,
            imageData: users.first(where: {
                isCurrentUser ? $0.isCurrentUser == true : $0.id == message.senderID
            })?.avatarData,
            size: 24
        )
    }

    private var messageBubble: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let text = message.text {
                Text(text)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ForEach(message.attachments) { attachment in
                attachmentCard(attachment)
            }

            if let poll = message.poll {
                VStack(alignment: .leading, spacing: 7) {
                    Text(poll.question)
                        .font(.headline)
                    ForEach(poll.options) { option in
                        Label(
                            "\(option.text)（\(option.voteCount) 票）",
                            systemImage: option.isSelectedByCurrentUser ? "checkmark.circle.fill" : "circle"
                        )
                        .font(.callout)
                    }
                }
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 10)
        .foregroundStyle(isCurrentUser ? Color.white : Color.primary)
        .background(
            isCurrentUser ? Color.accentColor : Color(nsColor: .controlBackgroundColor),
            in: RoundedRectangle(cornerRadius: 13, style: .continuous)
        )
        .overlay {
            if !isCurrentUser {
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .stroke(Color(nsColor: .separatorColor).opacity(0.45), lineWidth: 1)
            }
        }
        .help(Self.fullDateTimeFormatter.string(from: message.sentAt))
    }

    private func attachmentCard(_ attachment: ChatAttachment) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            if canDownloadAttachments,
               attachment.kind == .image,
               let thumbnailData,
               let image = NSImage(data: thumbnailData) {
                Button {
                    onPreviewImage(attachment)
                } label: {
                    Image(nsImage: image)
                        .resizable()
                        .scaledToFit()
                        .frame(maxWidth: 300, maxHeight: 220)
                        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
                }
                .buttonStyle(.plain)
                .help("预览“\(attachment.fileName)”")
                .accessibilityLabel("预览图片 \(attachment.fileName)")
            }
            HStack(spacing: 8) {
                Label(attachment.fileName, systemImage: attachmentIcon(attachment.kind))
                    .font(.callout)
                    .lineLimit(2)
                if canDownloadAttachments {
                    Spacer(minLength: 8)
                    Button {
                        onSaveAttachment(attachment)
                    } label: {
                        Label("保存附件", systemImage: "square.and.arrow.down")
                            .labelStyle(.iconOnly)
                    }
                    .buttonStyle(.borderless)
                    .help("将附件另存为")
                    .accessibilityLabel("将附件另存为")
                }
            }
            if let downloadProgress {
                HStack(spacing: 8) {
                    ProgressView(value: downloadProgress)
                        .progressViewStyle(.linear)
                        .accessibilityLabel("附件下载进度")
                        .accessibilityValue("\(Int((downloadProgress * 100).rounded()))%")
                    Button("取消", action: onCancelDownload)
                        .buttonStyle(.link)
                        .font(.caption)
                }
            }
        }
        .frame(maxWidth: 380)
        .padding(9)
        .background(
            isCurrentUser ? Color.white.opacity(0.16) : Color(nsColor: .windowBackgroundColor),
            in: RoundedRectangle(cornerRadius: 9, style: .continuous)
        )
        .task(id: message.id) {
            if canDownloadAttachments, attachment.kind == .image, thumbnailData == nil {
                onLoadThumbnail(attachment)
            }
        }
    }

    @ViewBuilder
    private var deliveryStatus: some View {
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
    var size: CGFloat = 30

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
                        .font(.system(size: max(10, size * 0.4), weight: .semibold))
                        .foregroundStyle(.tint)
                }
            }
        }
        .frame(width: size, height: size)
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
