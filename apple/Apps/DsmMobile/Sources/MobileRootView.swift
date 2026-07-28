import DsmCore
import SwiftUI

struct MobileRootView: View {
    @Bindable var model: MobileAppModel

    var body: some View {
        Group {
            if model.isConnected {
                MobileWorkspaceView(model: model)
            } else {
                MobileLoginView(model: model)
            }
        }
        .tint(.blue)
    }
}

private struct MobileLoginView: View {
    @Bindable var model: MobileAppModel
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var profileToRemove: NasProfile?
    @State private var showsAdvancedConnectionSettings = false

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                ScrollView {
                    if horizontalSizeClass == .regular {
                        HStack(alignment: .top, spacing: 36) {
                            savedProfiles
                                .frame(width: min(340, proxy.size.width * 0.34))
                            loginForm
                                .frame(maxWidth: 520)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(32)
                    } else {
                        VStack(spacing: 24) {
                            brandHeader
                            if !model.profiles.isEmpty {
                                savedProfiles
                            }
                            loginForm
                        }
                        .padding(20)
                    }
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle("岚仓")
            .navigationBarTitleDisplayMode(.inline)
        }
        .confirmationDialog(
            "移除“\(profileToRemove?.displayName ?? "")”？",
            isPresented: Binding(
                get: { profileToRemove != nil },
                set: { if !$0 { profileToRemove = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("移除", role: .destructive) {
                if let profileToRemove {
                    model.removeProfile(profileToRemove)
                }
                profileToRemove = nil
            }
            Button("取消", role: .cancel) {
                profileToRemove = nil
            }
        } message: {
            Text("这会删除本机保存的地址和登录信息，不会删除 NAS 上的任何文件。")
        }
    }

    private var brandHeader: some View {
        HStack(spacing: 16) {
            Image("BrandLogo")
                .resizable()
                .scaledToFit()
                .frame(width: 68, height: 68)
                .clipShape(.rect(cornerRadius: 18))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("岚仓")
                    .font(.largeTitle.bold())
                Text("LanStash")
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
    }

    private var savedProfiles: some View {
        VStack(alignment: .leading, spacing: 12) {
            if horizontalSizeClass == .regular {
                brandHeader
                    .padding(.bottom, 8)
            }
            HStack {
                Text("已保存的 NAS")
                    .font(.headline)
                Spacer()
                Button {
                    model.newProfile()
                } label: {
                    Label("添加", systemImage: "plus")
                }
            }
            ForEach(model.profiles) { profile in
                Button {
                    model.selectProfile(profile)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "externaldrive.connected.to.line.below")
                            .font(.title3)
                            .foregroundStyle(.blue)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(profile.displayName)
                                .fontWeight(.semibold)
                                .foregroundStyle(.primary)
                            Text(profile.usernameHint ?? profile.host)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button {
                            model.restore(profile)
                        } label: {
                            Image(systemName: "play.fill")
                                .frame(width: 44, height: 44)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("使用保存的登录连接")
                        Button(role: .destructive) {
                            profileToRemove = profile
                        } label: {
                            Image(systemName: "trash")
                                .frame(width: 44, height: 44)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("移除保存的 NAS")
                    }
                    .padding(12)
                    .background(
                        model.selectedProfileID == profile.id
                            ? Color.blue.opacity(0.12)
                            : Color.secondary.opacity(0.08),
                        in: .rect(cornerRadius: 14)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var loginForm: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("连接 Synology NAS")
                .font(.title2.bold())
                .accessibilityAddTraits(.isHeader)
            TextField("显示名称", text: $model.displayName)
                .textContentType(.organizationName)
                .textFieldStyle(.roundedBorder)
            TextField(
                "NAS 地址或 QuickConnect ID",
                text: $model.host,
                prompt: Text("例如 nas.example.com 或你的 QuickConnect ID")
            )
                .textContentType(.URL)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textFieldStyle(.roundedBorder)
            TextField("账号", text: $model.username)
                .textContentType(.username)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textFieldStyle(.roundedBorder)
            SecureField("密码", text: $model.password)
                .textContentType(.password)
                .textFieldStyle(.roundedBorder)
                .onSubmit { model.connect() }
            if model.needsOTP || !model.otpCode.isEmpty {
                TextField("双重验证代码", text: $model.otpCode)
                    .textContentType(.oneTimeCode)
                    .keyboardType(.numberPad)
                    .textFieldStyle(.roundedBorder)
            }
            Toggle(
                "在这台设备上记住密码",
                isOn: Binding(
                    get: { model.rememberPassword },
                    set: { enabled in
                        model.rememberPassword = enabled
                        if !enabled {
                            model.autoLoginEnabled = false
                        }
                    }
                )
            )
            Text("密码由系统钥匙串安全保护。")
                .font(.caption)
                .foregroundStyle(.secondary)
            Toggle(
                "自动登录",
                isOn: Binding(
                    get: { model.autoLoginEnabled },
                    set: { enabled in
                        model.autoLoginEnabled = enabled
                        if enabled {
                            model.rememberPassword = true
                        }
                    }
                )
            )
            Text("下次打开岚仓时自动连接这台 NAS。")
                .font(.caption)
                .foregroundStyle(.secondary)
            DisclosureGroup(
                isExpanded: $showsAdvancedConnectionSettings
            ) {
                VStack(alignment: .leading, spacing: 6) {
                    TextField("自定义 HTTPS 端口", text: $model.port)
                        .keyboardType(.numberPad)
                        .textFieldStyle(.roundedBorder)
                    Text("留空时由岚仓自动选择；填写后优先使用这个端口。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 8)
            } label: {
                Label("高级连接设置", systemImage: "gearshape")
            }
            if let connectionStatus = model.connectionStatus {
                Label(connectionStatus, systemImage: "network")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .accessibilityElement(children: .combine)
            }
            if let loginError = model.loginError {
                Label(loginError, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.red)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.red.opacity(0.1), in: .rect(cornerRadius: 12))
                    .accessibilityElement(children: .combine)
            }
            Button {
                model.connect()
            } label: {
                HStack {
                    if model.isConnecting {
                        ProgressView()
                            .tint(.white)
                    }
                    Text(model.isConnecting ? "正在连接…" : "连接")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity, minHeight: 32)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(model.isConnecting)
        }
        .padding(20)
        .background(.regularMaterial, in: .rect(cornerRadius: 22))
    }
}

private struct MobileWorkspaceView: View {
    @Bindable var model: MobileAppModel
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var path = NavigationPath()

    var body: some View {
        Group {
            if horizontalSizeClass == .regular {
                NavigationSplitView {
                    moduleList
                        .navigationTitle(model.activeProfile?.displayName ?? "岚仓")
                } detail: {
                    moduleDetail
                }
                .navigationSplitViewStyle(.balanced)
            } else {
                NavigationStack(path: $path) {
                    moduleList
                        .navigationTitle(model.activeProfile?.displayName ?? "岚仓")
                        .navigationDestination(for: MobileModule.self) { module in
                            moduleDetail
                                .navigationTitle(module.title)
                                .navigationBarTitleDisplayMode(.inline)
                        }
                }
            }
        }
        .overlay(alignment: .top) {
            if model.actionInProgress {
                ProgressView()
                    .controlSize(.small)
                    .padding(10)
                    .background(.regularMaterial, in: .capsule)
                    .padding(.top, 8)
                    .accessibilityLabel("正在处理操作")
            }
        }
        .alert(
            "提示",
            isPresented: Binding(
                get: { model.message != nil },
                set: { if !$0 { model.message = nil } }
            )
        ) {
            Button("好") {
                model.message = nil
            }
        } message: {
            Text(model.message ?? "")
        }
    }

    private var moduleList: some View {
        List {
            Section("文件管理") {
                moduleRow(.files)
                moduleRow(.photos)
            }
            Section("沟通") {
                moduleRow(.chat)
            }
            Section("套件管理") {
                moduleRow(.downloads)
                moduleRow(.containers)
                moduleRow(.virtualMachines)
            }
            Section {
                moduleRow(.nasSettings)
                moduleRow(.transfers)
                moduleRow(.settings)
            }
            Section {
                Button(role: .destructive) {
                    model.logout()
                } label: {
                    Label("退出登录", systemImage: "rectangle.portrait.and.arrow.right")
                }
            }
        }
    }

    @ViewBuilder
    private func moduleRow(_ module: MobileModule) -> some View {
        if horizontalSizeClass == .regular {
            Button {
                model.selectModule(module)
            } label: {
                Label(module.title, systemImage: module.systemImage)
            }
            .foregroundStyle(model.selectedModule == module ? .blue : .primary)
            .accessibilityAddTraits(model.selectedModule == module ? .isSelected : [])
        } else {
            NavigationLink(value: module) {
                Label(module.title, systemImage: module.systemImage)
            }
            .simultaneousGesture(TapGesture().onEnded {
                model.selectModule(module)
            })
        }
    }

    @ViewBuilder
    private var moduleDetail: some View {
        ZStack {
            switch model.selectedModule {
            case .files:
                MobileFileBrowser(model: model)
            case .photos:
                MobilePhotosView(model: model)
            case .chat:
                MobileChatView(model: model)
            case .downloads:
                MobileDownloadsView(model: model)
            case .containers:
                MobileContainersView(model: model)
            case .virtualMachines:
                MobileVirtualMachinesView(model: model)
            case .nasSettings:
                MobileNasSettingsView(model: model)
            case .transfers:
                MobileEmptyView(
                    title: "没有传输任务",
                    message: "上传、下载和 NAS 后台任务会显示在这里。",
                    systemImage: "arrow.up.arrow.down"
                )
            case .settings:
                MobileSettingsView(model: model)
            }
            if model.isLoading {
                ProgressView("正在读取…")
                    .padding(20)
                    .background(.regularMaterial, in: .rect(cornerRadius: 16))
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    Task { await model.loadSelectedModule() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .accessibilityLabel("刷新")
            }
        }
    }
}

private struct MobileFileBrowser: View {
    @Bindable var model: MobileAppModel
    @State private var search = ""
    @State private var itemForActions: FileItem?
    @State private var itemToRename: FileItem?
    @State private var itemToDelete: FileItem?
    @State private var isCreatingFolder = false

    var body: some View {
        Group {
            if model.files.isEmpty && !model.isLoading {
                MobileEmptyView(
                    title: "这个位置是空的",
                    message: "这里还没有文件或文件夹。",
                    systemImage: "folder"
                )
            } else {
                List(model.files) { item in
                    Button {
                        if item.isDirectory {
                            model.openDirectory(item)
                        } else {
                            itemForActions = item
                        }
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: item.isDirectory ? "folder.fill" : fileIcon(item))
                                .font(.title3)
                                .foregroundStyle(item.isDirectory ? .blue : .secondary)
                                .frame(width: 28)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.name)
                                    .lineLimit(1)
                                Text(item.isDirectory ? "文件夹" : ByteCountFormatter.string(
                                    fromByteCount: item.sizeBytes ?? 0,
                                    countStyle: .file
                                ))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button {
                                itemForActions = item
                            } label: {
                                Image(systemName: "ellipsis")
                                    .frame(width: 44, height: 44)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("更多操作")
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .searchable(text: $search, prompt: "搜索文件")
        .onSubmit(of: .search) {
            model.searchFiles(search)
        }
        .toolbar {
            if !model.pathHistory.isEmpty {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        model.goBackDirectory()
                    } label: {
                        Image(systemName: "arrow.up")
                    }
                    .accessibilityLabel("返回上一级")
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    isCreatingFolder = true
                } label: {
                    Label("新建文件夹", systemImage: "folder.badge.plus")
                }
            }
        }
        .confirmationDialog(
            itemForActions?.name ?? "",
            isPresented: Binding(
                get: { itemForActions != nil },
                set: { if !$0 { itemForActions = nil } }
            ),
            titleVisibility: .visible
        ) {
            if itemForActions?.isDirectory == true {
                Button("打开") {
                    if let itemForActions {
                        model.openDirectory(itemForActions)
                    }
                    itemForActions = nil
                }
            }
            Button("重命名") {
                itemToRename = itemForActions
                itemForActions = nil
            }
            Button("删除", role: .destructive) {
                itemToDelete = itemForActions
                itemForActions = nil
            }
            Button("取消", role: .cancel) {
                itemForActions = nil
            }
        }
        .sheet(isPresented: $isCreatingFolder) {
            MobileTextInputSheet(
                title: "新建文件夹",
                label: "文件夹名称",
                actionTitle: "创建"
            ) { name in
                model.createFolder(name: name)
                isCreatingFolder = false
            }
            .presentationDetents([.medium])
        }
        .sheet(item: $itemToRename) { item in
            MobileTextInputSheet(
                title: "重命名",
                label: "新名称",
                initialValue: item.name,
                actionTitle: "保存"
            ) { name in
                model.rename(item, to: name)
                itemToRename = nil
            }
            .presentationDetents([.medium])
        }
        .confirmationDialog(
            "删除“\(itemToDelete?.name ?? "")”？",
            isPresented: Binding(
                get: { itemToDelete != nil },
                set: { if !$0 { itemToDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("删除", role: .destructive) {
                if let itemToDelete {
                    model.delete([itemToDelete])
                }
                itemToDelete = nil
            }
            Button("取消", role: .cancel) {
                itemToDelete = nil
            }
        } message: {
            Text("删除后能否恢复取决于共享文件夹的回收站设置。")
        }
    }
}

private struct MobilePhotosView: View {
    @Bindable var model: MobileAppModel
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var media: [FileItem] {
        let extensions = Set(["jpg", "jpeg", "png", "gif", "heic", "heif", "webp", "mov", "mp4"])
        return model.files.filter { !$0.isDirectory && extensions.contains($0.fileExtension ?? "") }
    }

    var body: some View {
        if media.isEmpty && !model.isLoading {
            MobileEmptyView(
                title: "没有找到照片",
                message: "当前目录没有可显示的照片或视频。",
                systemImage: "photo.on.rectangle.angled"
            )
        } else {
            ScrollView {
                LazyVGrid(
                    columns: [
                        GridItem(
                            .adaptive(minimum: horizontalSizeClass == .regular ? 180 : 116),
                            spacing: 8
                        )
                    ],
                    spacing: 8
                ) {
                    ForEach(media) { item in
                        VStack(alignment: .leading, spacing: 0) {
                            ZStack {
                                Color.blue.opacity(0.1)
                                Image(systemName: "photo")
                                    .font(.largeTitle)
                                    .foregroundStyle(.blue)
                            }
                            .aspectRatio(1, contentMode: .fit)
                            Text(item.name)
                                .font(.caption)
                                .lineLimit(2)
                                .padding(8)
                        }
                        .background(.regularMaterial, in: .rect(cornerRadius: 12))
                    }
                }
                .padding(12)
            }
        }
    }
}

private struct MobileChatView: View {
    @Bindable var model: MobileAppModel

    var body: some View {
        if model.conversations.isEmpty && !model.isLoading {
            MobileEmptyView(
                title: "还没有会话",
                message: "在 Synology Chat 中开始会话后会显示在这里。",
                systemImage: "bubble.left.and.bubble.right"
            )
        } else {
            List(model.conversations) { conversation in
                HStack(spacing: 14) {
                    Image(systemName: "person.2.circle.fill")
                        .font(.title)
                        .foregroundStyle(.blue)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(conversation.title)
                            .fontWeight(.semibold)
                        Text(conversation.lastMessageSummary ?? "\(conversation.memberCount ?? 0) 位成员")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Spacer()
                    if conversation.unreadCount > 0 {
                        Text("\(conversation.unreadCount)")
                            .font(.caption.bold())
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.blue, in: .capsule)
                            .accessibilityLabel("\(conversation.unreadCount) 条未读消息")
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }
}

private struct MobileDownloadsView: View {
    @Bindable var model: MobileAppModel
    @State private var isCreating = false
    @State private var selectedTask: DownloadStationTask?
    @State private var taskToDelete: DownloadStationTask?

    var body: some View {
        Group {
            let tasks = model.downloadSnapshot?.tasks ?? []
            if tasks.isEmpty && !model.isLoading {
                MobileEmptyView(
                    title: "没有下载任务",
                    message: "添加网址或磁力链接开始下载。",
                    systemImage: "arrow.down.circle"
                )
            } else {
                List(tasks) { task in
                    Button {
                        selectedTask = task
                    } label: {
                        HStack(spacing: 14) {
                            statusIcon(task.status)
                            VStack(alignment: .leading, spacing: 5) {
                                Text(task.title)
                                    .foregroundStyle(.primary)
                                    .lineLimit(1)
                                Text(task.status)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                if let progress = task.progress {
                                    ProgressView(value: progress)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    isCreating = true
                } label: {
                    Label("添加下载", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $isCreating) {
            MobileDownloadSheet(model: model, isPresented: $isCreating)
        }
        .confirmationDialog(
            selectedTask?.title ?? "",
            isPresented: Binding(
                get: { selectedTask != nil },
                set: { if !$0 { selectedTask = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("暂停") {
                if let selectedTask {
                    model.controlDownload(selectedTask, action: .pause)
                }
                selectedTask = nil
            }
            Button("继续") {
                if let selectedTask {
                    model.controlDownload(selectedTask, action: .resume)
                }
                selectedTask = nil
            }
            Button("移除任务", role: .destructive) {
                taskToDelete = selectedTask
                selectedTask = nil
            }
            Button("取消", role: .cancel) {
                selectedTask = nil
            }
        }
        .confirmationDialog(
            "移除下载任务？",
            isPresented: Binding(
                get: { taskToDelete != nil },
                set: { if !$0 { taskToDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("只移除任务", role: .destructive) {
                if let taskToDelete {
                    model.deleteDownload(taskToDelete, removeData: false)
                }
                taskToDelete = nil
            }
            Button("移除任务和已下载文件", role: .destructive) {
                if let taskToDelete {
                    model.deleteDownload(taskToDelete, removeData: true)
                }
                taskToDelete = nil
            }
            Button("取消", role: .cancel) {
                taskToDelete = nil
            }
        }
    }
}

private struct MobileDownloadSheet: View {
    @Bindable var model: MobileAppModel
    @Binding var isPresented: Bool
    @State private var uri = ""
    @State private var destination = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("下载来源") {
                    TextField("网址或磁力链接", text: $uri, axis: .vertical)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                }
                Section("保存位置") {
                    TextField("NAS 文件夹（可选）", text: $destination)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
            }
            .navigationTitle("添加下载")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { isPresented = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("创建") {
                        model.createDownload(
                            uri: uri,
                            destination: destination.isEmpty ? nil : destination
                        )
                        isPresented = false
                    }
                    .disabled(uri.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

private struct MobileContainersView: View {
    @Bindable var model: MobileAppModel
    @State private var tab = 0
    @State private var selectedContainer: ContainerInstance?
    @State private var containerToDelete: ContainerInstance?
    @State private var imageToDelete: ContainerImage?
    @State private var networkToDelete: ContainerNetwork?
    @State private var isCreatingNetwork = false

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $tab) {
                Text("容器").tag(0)
                Text("映像").tag(1)
                Text("网络").tag(2)
                Text("项目").tag(3)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding()
            switch tab {
            case 0:
                resourceList(model.containerSnapshot?.containers ?? []) { item in
                    selectedContainer = item
                } title: { $0.name } detail: { "\($0.image) · \($0.status)" }
            case 1:
                resourceList(model.containerSnapshot?.images ?? []) { item in
                    imageToDelete = item
                } title: { "\($0.repository):\($0.tag)" } detail: {
                    $0.isInUse ? "使用中" : ByteCountFormatter.string(
                        fromByteCount: $0.sizeBytes ?? 0,
                        countStyle: .file
                    )
                }
            case 2:
                resourceList(model.containerSnapshot?.networks ?? []) { item in
                    networkToDelete = item
                } title: { $0.name } detail: {
                    "\($0.driver) · \($0.connectedContainerCount) 个容器"
                }
            default:
                resourceList(model.containerSnapshot?.projects ?? []) { _ in
                } title: { $0.name } detail: { "\($0.status) · \($0.containerCount) 个容器" }
            }
        }
        .toolbar {
            if tab == 2 {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isCreatingNetwork = true
                    } label: {
                        Label("新建网络", systemImage: "plus")
                    }
                }
            }
        }
        .confirmationDialog(
            selectedContainer?.name ?? "",
            isPresented: Binding(
                get: { selectedContainer != nil },
                set: { if !$0 { selectedContainer = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("启动") {
                if let selectedContainer {
                    model.controlContainer(selectedContainer, action: .start)
                }
                selectedContainer = nil
            }
            Button("停止") {
                if let selectedContainer {
                    model.controlContainer(selectedContainer, action: .stop)
                }
                selectedContainer = nil
            }
            Button("重新启动") {
                if let selectedContainer {
                    model.controlContainer(selectedContainer, action: .restart)
                }
                selectedContainer = nil
            }
            Button("删除", role: .destructive) {
                containerToDelete = selectedContainer
                selectedContainer = nil
            }
            Button("取消", role: .cancel) {
                selectedContainer = nil
            }
        }
        .deleteConfirmation(
            title: containerToDelete.map { "删除“\($0.name)”？" } ?? "",
            message: "容器会从 NAS 移除。映像和共享文件夹中的数据不会自动删除。",
            item: $containerToDelete,
            action: model.deleteContainer
        )
        .deleteConfirmation(
            title: imageToDelete.map { "删除“\($0.repository):\($0.tag)”？" } ?? "",
            message: "正在使用的映像无法删除，请先移除相关容器。",
            item: $imageToDelete,
            action: model.deleteContainerImage
        )
        .deleteConfirmation(
            title: networkToDelete.map { "删除“\($0.name)”？" } ?? "",
            message: "请先确认没有容器仍连接到这个网络。",
            item: $networkToDelete,
            action: model.deleteContainerNetwork
        )
        .sheet(isPresented: $isCreatingNetwork) {
            MobileTextInputSheet(
                title: "新建容器网络",
                label: "网络名称",
                actionTitle: "创建"
            ) { name in
                model.createContainerNetwork(name: name, driver: "bridge")
                isCreatingNetwork = false
            }
            .presentationDetents([.medium])
        }
    }
}

private struct MobileVirtualMachinesView: View {
    @Bindable var model: MobileAppModel
    @State private var tab = 0
    @State private var protectionTab = 0
    @State private var selectedMachine: VirtualMachine?
    @State private var machineToDelete: VirtualMachine?
    @State private var networkToEdit: VirtualizationResource?
    @State private var networkToDelete: VirtualizationResource?
    @State private var imageToDelete: VirtualizationResource?
    @State private var logLevel = ""
    @State private var logSearch = ""

    private let tabs = ["虚拟机", "主机", "存储", "网络", "映像", "保护", "日志"]

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(tabs.indices, id: \.self) { index in
                        Button(tabs[index]) {
                            tab = index
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(tab == index ? .blue : .secondary.opacity(0.35))
                        .foregroundStyle(tab == index ? .white : .primary)
                        .accessibilityAddTraits(tab == index ? .isSelected : [])
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 10)
            }
            Divider()
            switch tab {
            case 0:
                resourceList(model.virtualMachineSnapshot?.machines ?? []) { item in
                    selectedMachine = item
                } title: { $0.name } detail: { $0.status }
            case 1:
                virtualizationList(model.virtualMachineSnapshot?.hosts ?? [])
            case 2:
                virtualizationList(model.virtualMachineSnapshot?.storages ?? [])
            case 3:
                virtualizationList(
                    model.virtualMachineSnapshot?.networks ?? [],
                    edit: { networkToEdit = $0 },
                    delete: { networkToDelete = $0 }
                )
            case 4:
                virtualizationList(
                    model.virtualMachineSnapshot?.images ?? [],
                    delete: { imageToDelete = $0 }
                )
            case 5:
                protectionView
            default:
                logView
            }
        }
        .confirmationDialog(
            selectedMachine?.name ?? "",
            isPresented: Binding(
                get: { selectedMachine != nil },
                set: { if !$0 { selectedMachine = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("启动") {
                if let selectedMachine {
                    model.controlVirtualMachine(selectedMachine, action: .powerOn)
                }
                selectedMachine = nil
            }
            Button("正常关机") {
                if let selectedMachine {
                    model.controlVirtualMachine(selectedMachine, action: .shutdown)
                }
                selectedMachine = nil
            }
            Button("强制关机", role: .destructive) {
                if let selectedMachine {
                    model.controlVirtualMachine(selectedMachine, action: .powerOff)
                }
                selectedMachine = nil
            }
            Button("删除", role: .destructive) {
                machineToDelete = selectedMachine
                selectedMachine = nil
            }
            Button("取消", role: .cancel) {
                selectedMachine = nil
            }
        }
        .deleteConfirmation(
            title: machineToDelete.map { "删除“\($0.name)”？" } ?? "",
            message: "虚拟机及其配置会被移除。请先确认重要数据已有备份。",
            item: $machineToDelete,
            action: model.deleteVirtualMachine
        )
        .deleteConfirmation(
            title: networkToDelete.map { "删除“\($0.name)”？" } ?? "",
            message: "删除后，连接到这个网络的虚拟机可能无法正常通信。",
            item: $networkToDelete,
            action: model.deleteVirtualMachineNetwork
        )
        .deleteConfirmation(
            title: imageToDelete.map { "删除“\($0.name)”？" } ?? "",
            message: "映像会从 NAS 移除，已安装的虚拟机不会被删除。",
            item: $imageToDelete,
            action: model.deleteVirtualMachineImage
        )
        .sheet(item: $networkToEdit) { network in
            MobileTextInputSheet(
                title: "修改网络",
                label: "网络名称",
                initialValue: network.name,
                actionTitle: "保存"
            ) { name in
                model.updateVirtualMachineNetwork(network, name: name)
                networkToEdit = nil
            }
            .presentationDetents([.medium])
        }
    }

    private var protectionView: some View {
        VStack(spacing: 0) {
            Picker("", selection: $protectionTab) {
                Text("保护计划").tag(0)
                Text("计划策略").tag(1)
                Text("保留策略").tag(2)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding()
            let resources = switch protectionTab {
            case 1: model.virtualMachineSnapshot?.protectionSchedulePolicies ?? []
            case 2: model.virtualMachineSnapshot?.protectionRetentionPolicies ?? []
            default: model.virtualMachineSnapshot?.protectionPlans ?? []
            }
            virtualizationList(resources)
        }
    }

    private var logView: some View {
        let events = (model.virtualMachineSnapshot?.events ?? []).filter { event in
            (logLevel.isEmpty || event.level.localizedCaseInsensitiveContains(logLevel)) &&
                (logSearch.isEmpty ||
                    event.message.localizedCaseInsensitiveContains(logSearch) ||
                    (event.user?.localizedCaseInsensitiveContains(logSearch) ?? false))
        }
        return VStack(spacing: 0) {
            HStack(spacing: 10) {
                Picker("", selection: $logLevel) {
                    Text("全部").tag("")
                    Text("信息").tag("info")
                    Text("警告").tag("warning")
                    Text("错误").tag("error")
                }
                .labelsHidden()
                .frame(maxWidth: 150)
                TextField("搜索日志", text: $logSearch)
                    .textFieldStyle(.roundedBorder)
            }
            .padding()
            if events.isEmpty {
                MobileEmptyView(
                    title: "没有日志",
                    message: "当前筛选条件下没有可显示的记录。",
                    systemImage: "list.bullet.rectangle"
                )
            } else {
                List(events) { event in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(event.message)
                        HStack {
                            Text(event.level)
                            if let user = event.user {
                                Text(user)
                            }
                            if let timestamp = event.timestamp {
                                Text(timestamp, format: .dateTime.year().month().day().hour().minute())
                            }
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func virtualizationList(
        _ resources: [VirtualizationResource],
        edit: ((VirtualizationResource) -> Void)? = nil,
        delete: ((VirtualizationResource) -> Void)? = nil
    ) -> some View {
        if resources.isEmpty && !model.isLoading {
            MobileEmptyView(
                title: "没有可显示的项目",
                message: "当前 NAS 没有返回这个分类的内容。",
                systemImage: "shield"
            )
        } else {
            List(resources) { resource in
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(resource.name)
                        Text(resource.detail ?? resource.status ?? "")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let edit {
                        Button {
                            edit(resource)
                        } label: {
                            Image(systemName: "pencil")
                                .frame(width: 44, height: 44)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("编辑")
                    }
                    if let delete {
                        Button(role: .destructive) {
                            delete(resource)
                        } label: {
                            Image(systemName: "trash")
                                .frame(width: 44, height: 44)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("删除")
                    }
                }
            }
        }
    }
}

private struct MobileNasSettingsView: View {
    @Bindable var model: MobileAppModel
    @State private var tab = 0
    private let tabs = ["概览", "存储", "套件", "账号", "日志", "连接"]

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(tabs.indices, id: \.self) { index in
                        Button(tabs[index]) {
                            tab = index
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(tab == index ? .blue : .secondary.opacity(0.35))
                        .foregroundStyle(tab == index ? .white : .primary)
                    }
                }
                .padding()
            }
            Divider()
            switch tab {
            case 0:
                overview
            case 1:
                storage
            case 2:
                packages
            case 3:
                accounts
            case 4:
                logEntries
            default:
                connectionEntries
            }
        }
    }

    private var overview: some View {
        ScrollView {
            VStack(spacing: 14) {
                if let overview = model.systemOverview {
                    MobileSummaryCard(title: "系统", systemImage: "server.rack") {
                        summaryLine("设备名称", overview.serverName)
                        summaryLine("型号", overview.model ?? "—")
                        summaryLine("DSM", overview.version ?? "—")
                        summaryLine("处理器", overview.cpuModel ?? "—")
                        summaryLine(
                            "内存",
                            ByteCountFormatter.string(
                                fromByteCount: overview.memoryBytes ?? 0,
                                countStyle: .memory
                            )
                        )
                    }
                }
                HStack(spacing: 12) {
                    metricCard("存储空间", "\(model.storageSnapshot?.volumes.count ?? 0)", "externaldrive")
                    metricCard("套件", "\(model.packages.count)", "shippingbox")
                }
                HStack(spacing: 12) {
                    metricCard(
                        "账号",
                        "\(model.accountsAndGroups?.users.count ?? 0)",
                        "person.2"
                    )
                    metricCard(
                        "活动连接",
                        "\(model.connections?.connections.count ?? 0)",
                        "network"
                    )
                }
            }
            .padding()
        }
    }

    private var storage: some View {
        List {
            Section("存储空间") {
                ForEach(model.storageSnapshot?.volumes ?? []) { volume in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(volume.name)
                        Text(volume.status ?? "")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Section("存储池") {
                ForEach(model.storageSnapshot?.pools ?? []) { pool in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(pool.name)
                        Text(pool.status ?? "")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Section("硬盘") {
                ForEach(model.storageSnapshot?.disks ?? []) { disk in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(disk.name)
                        Text(disk.status ?? "")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var packages: some View {
        List(model.packages) { package in
            HStack(spacing: 12) {
                Image(systemName: "shippingbox.fill")
                    .foregroundStyle(.blue)
                VStack(alignment: .leading, spacing: 3) {
                    Text(package.name)
                    Text([package.version, package.statusDescription].compactMap { $0 }.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var accounts: some View {
        List {
            Section("账号") {
                ForEach(model.accountsAndGroups?.users ?? []) { account in
                    accountRow(account)
                }
            }
            Section("群组") {
                ForEach(model.accountsAndGroups?.groups ?? []) { account in
                    accountRow(account)
                }
            }
        }
    }

    private var logEntries: some View {
        List(model.logs?.entries ?? []) { entry in
            VStack(alignment: .leading, spacing: 4) {
                Text(entry.message)
                Text(
                    [entry.level, entry.account, entry.source]
                        .compactMap { $0 }
                        .joined(separator: " · ")
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }

    private var connectionEntries: some View {
        List(model.connections?.connections ?? []) { connection in
            VStack(alignment: .leading, spacing: 4) {
                Text("\(connection.account) · \(connection.protocolName ?? "DSM")")
                Text(connection.source ?? connection.location ?? "未知设备")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func accountRow(_ account: NasAccount) -> some View {
        HStack {
            Image(systemName: account.kind == .user ? "person.circle" : "person.2.circle")
            VStack(alignment: .leading, spacing: 3) {
                Text(account.name)
                Text(account.description ?? account.email ?? "")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func metricCard(_ title: String, _ value: String, _ icon: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(.blue)
            Text(value)
                .font(.title.bold())
            Text(title)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(.regularMaterial, in: .rect(cornerRadius: 16))
    }
}

private struct MobileSettingsView: View {
    @Bindable var model: MobileAppModel

    var body: some View {
        List {
            Section("功能模块") {
                ForEach(MobileModule.allCases) { module in
                    HStack {
                        Label(module.title, systemImage: module.systemImage)
                        Spacer()
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .accessibilityLabel("已启用")
                    }
                }
            }
            Section("安全") {
                Label(
                    "只有开启“记住密码”后，密码才会由系统钥匙串安全保护。",
                    systemImage: "lock.shield"
                )
            }
            Section {
                Button("退出登录", role: .destructive) {
                    model.logout()
                }
            }
        }
    }
}

private struct MobileTextInputSheet: View {
    let title: String
    let label: String
    let initialValue: String
    let actionTitle: String
    let action: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var value: String

    init(
        title: String,
        label: String,
        initialValue: String = "",
        actionTitle: String,
        action: @escaping (String) -> Void
    ) {
        self.title = title
        self.label = label
        self.initialValue = initialValue
        self.actionTitle = actionTitle
        self.action = action
        _value = State(initialValue: initialValue)
    }

    var body: some View {
        NavigationStack {
            Form {
                TextField(label, text: $value)
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(actionTitle) {
                        action(value.trimmingCharacters(in: .whitespacesAndNewlines))
                        dismiss()
                    }
                    .disabled(value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}

private struct MobileEmptyView: View {
    let title: String
    let message: String
    let systemImage: String

    var body: some View {
        ContentUnavailableView(title, systemImage: systemImage, description: Text(message))
    }
}

private struct MobileSummaryCard<Content: View>: View {
    let title: String
    let systemImage: String
    @ViewBuilder let content: Content

    init(
        title: String,
        systemImage: String,
        @ViewBuilder content: () -> Content
    ) {
        self.title = title
        self.systemImage = systemImage
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: systemImage)
                .font(.headline)
            content
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.regularMaterial, in: .rect(cornerRadius: 16))
    }
}

private extension View {
    func deleteConfirmation<Item>(
        title: String,
        message: String,
        item: Binding<Item?>,
        action: @escaping (Item) -> Void
    ) -> some View {
        confirmationDialog(
            title,
            isPresented: Binding(
                get: { item.wrappedValue != nil },
                set: { if !$0 { item.wrappedValue = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("删除", role: .destructive) {
                if let value = item.wrappedValue {
                    action(value)
                }
                item.wrappedValue = nil
            }
            Button("取消", role: .cancel) {
                item.wrappedValue = nil
            }
        } message: {
            Text(message)
        }
    }
}

@MainActor
private func resourceList<Item: Identifiable>(
    _ items: [Item],
    action: @escaping (Item) -> Void,
    title: @escaping (Item) -> String,
    detail: @escaping (Item) -> String
) -> some View {
    Group {
        if items.isEmpty {
            MobileEmptyView(
                title: "没有可显示的项目",
                message: "当前 NAS 没有返回这个分类的内容。",
                systemImage: "tray"
            )
        } else {
            List(items) { item in
                Button {
                    action(item)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(title(item))
                                .foregroundStyle(.primary)
                            Text(detail(item))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "ellipsis")
                    }
                }
            }
        }
    }
}

private func summaryLine(_ label: String, _ value: String) -> some View {
    HStack {
        Text(label)
            .foregroundStyle(.secondary)
        Spacer()
        Text(value)
            .fontWeight(.medium)
            .multilineTextAlignment(.trailing)
    }
}

private func fileIcon(_ item: FileItem) -> String {
    switch item.fileExtension {
    case "jpg", "jpeg", "png", "gif", "heic", "heif", "webp":
        "photo"
    case "mov", "mp4", "mkv":
        "film"
    case "mp3", "m4a", "flac", "wav":
        "music.note"
    case "pdf":
        "doc.richtext"
    case "zip", "7z", "rar", "tar", "gz":
        "archivebox"
    default:
        "doc"
    }
}

private func statusIcon(_ status: String) -> some View {
    let normalized = status.lowercased()
    let image = if normalized.contains("down") || normalized.contains("seed") {
        "arrow.down.circle.fill"
    } else if normalized.contains("pause") {
        "pause.circle.fill"
    } else if normalized.contains("error") {
        "exclamationmark.circle.fill"
    } else {
        "clock.fill"
    }
    return Image(systemName: image)
        .font(.title2)
        .foregroundStyle(normalized.contains("error") ? Color.red : Color.blue)
}
