import DsmCore
import SwiftUI
import UniformTypeIdentifiers

struct ChatWorkspaceView: View {
    @Bindable var model: ChatWorkspaceModel
    @State private var presentsNewConversation = false

    var body: some View {
        HSplitView {
            conversationColumn
                .frame(minWidth: 240, idealWidth: 280, maxWidth: 360)
            conversationDetail
                .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .task {
            await model.loadIfNeeded()
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    presentsNewConversation = true
                } label: {
                    Label("新建聊天", systemImage: "square.and.pencil")
                }
                .disabled(!model.canCreateDirectConversation && !model.canCreateGroupConversation)
                .help(newConversationHelp)

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
    }

    private var newConversationHelp: String {
        if model.canCreateDirectConversation || model.canCreateGroupConversation {
            return "选择用户开始聊天或创建私人群聊"
        }
        return "这台 NAS 的消息功能尚未准备好"
    }

    private var conversationColumn: some View {
        VStack(spacing: 0) {
            HStack {
                Text("会话")
                    .font(.headline)
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
                    }
                }
                .listStyle(.inset)
                .scrollContentBackground(.hidden)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var conversationSelection: Binding<String?> {
        Binding(
            get: { model.selectedConversationID },
            set: { id in Task { await model.selectConversation(id: id) } }
        )
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
    @State private var draftText = ""
    @State private var attachmentURLs: [URL] = []
    @State private var presentsFileImporter = false

    var body: some View {
        VStack(spacing: 0) {
            conversationHeader
            Divider()

            if model.isLoadingMessages {
                ProgressView("正在载入消息…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.messages.isEmpty {
                ContentUnavailableView(
                    "还没有消息",
                    systemImage: "bubble.left",
                    description: Text("发送第一条消息，开始这段聊天。")
                )
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(Array(model.messages.enumerated()), id: \.element.id) { index, message in
                                if shouldShowDateSeparator(at: index) {
                                    ChatDateSeparator(date: message.sentAt)
                                        .padding(.vertical, index == 0 ? 2 : 10)
                                }
                                ChatMessageRow(
                                    message: message,
                                    users: model.users,
                                    isCurrentUser: model.isCurrentUser(message),
                                    showsSender: conversation.kind == .group
                                )
                                    .id(message.id)
                            }
                        }
                        .padding(.horizontal, 24)
                        .padding(.vertical, 16)
                        .frame(maxWidth: .infinity)
                    }
                    .background(Color(nsColor: .textBackgroundColor))
                    .onChange(of: model.messages.count) { _, _ in
                        guard let lastID = model.messages.last?.id else { return }
                        proxy.scrollTo(lastID, anchor: .bottom)
                    }
                }
            }

            if let statusMessage = model.statusMessage, model.statusIsError {
                Label(statusMessage, systemImage: "exclamationmark.circle.fill")
                    .font(.callout)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.red.opacity(0.08))
                    .accessibilityElement(children: .combine)
            }

            Divider()
            composer
        }
        .fileImporter(
            isPresented: $presentsFileImporter,
            allowedContentTypes: [.item],
            allowsMultipleSelection: true
        ) { result in
            if case .success(let urls) = result {
                attachmentURLs = urls
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
            if conversation.isEncrypted {
                Label("已加密", systemImage: "lock.fill")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var composer: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !attachmentURLs.isEmpty {
                HStack {
                    Label("已选择 \(attachmentURLs.count) 个附件", systemImage: "paperclip")
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
                    presentsFileImporter = true
                } label: {
                    Label("添加附件", systemImage: "paperclip")
                        .labelStyle(.iconOnly)
                        .frame(width: 28, height: 28)
                }
                .disabled(!model.canSendAttachments || model.isPerformingAction)
                .help(model.canSendAttachments ? "添加图片、视频或文件" : "这台 NAS 尚未开放附件发送")
                .accessibilityLabel("添加附件")

                TextField("输入消息", text: $draftText, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...5)
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
            && ((model.canSendText && !draftText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                || (model.canSendAttachments && !attachmentURLs.isEmpty))
    }

    private func send() {
        guard canSend else { return }
        let text = draftText
        let urls = attachmentURLs
        Task {
            if await model.send(text: text, attachmentURLs: urls) {
                draftText = ""
                attachmentURLs = []
            }
        }
    }

    private func shouldShowDateSeparator(at index: Int) -> Bool {
        guard index > 0 else { return true }
        return !Calendar.current.isDate(
            model.messages[index - 1].sentAt,
            inSameDayAs: model.messages[index].sentAt
        )
    }
}

private struct ChatMessageRow: View {
    let message: ChatMessage
    let users: [ChatUser]
    let isCurrentUser: Bool
    let showsSender: Bool

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
            }

            if !isCurrentUser { Spacer(minLength: 64) }
        }
        .frame(maxWidth: .infinity, alignment: isCurrentUser ? .trailing : .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(senderName)，\(Self.fullDateTimeFormatter.string(from: message.sentAt))")
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
