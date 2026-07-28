import DsmCore
import DsmLocalization
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
            .navigationTitle(L10n.string("ui.4aeb6d92cbbff699"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    AppLanguagePicker()
                        .labelsHidden()
                        .pickerStyle(.menu)
                }
            }
        }
        .confirmationDialog(
            L10n.string(
                "profile.remove.confirm",
                profileToRemove?.displayName ?? ""
            ),
            isPresented: Binding(
                get: { profileToRemove != nil },
                set: { if !$0 { profileToRemove = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(L10n.string("ui.6135d4159e892541"), role: .destructive) {
                if let profileToRemove {
                    model.removeProfile(profileToRemove)
                }
                profileToRemove = nil
            }
            Button(L10n.string("ui.2cd0f3be8738a86c"), role: .cancel) {
                profileToRemove = nil
            }
        } message: {
            Text(L10n.string("ui.1a6ef7d4ed0db37d"))
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
                Text(L10n.string("ui.4aeb6d92cbbff699"))
                    .font(.largeTitle.bold())
                Text(L10n.string("app.name"))
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
                Text(L10n.string("ui.df2b9b2dc2e69cf5"))
                    .font(.headline)
                Spacer()
                Button {
                    model.newProfile()
                } label: {
                    Label(L10n.string("ui.7a8a11ead50742a2"), systemImage: "plus")
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
                        .accessibilityLabel(L10n.string("ui.d2bf10e7bab2699a"))
                        Button(role: .destructive) {
                            profileToRemove = profile
                        } label: {
                            Image(systemName: "trash")
                                .frame(width: 44, height: 44)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(L10n.string("ui.06a972a9c2683c33"))
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
            Text(L10n.string("ui.3b0927418e9ca90b"))
                .font(.title2.bold())
                .accessibilityAddTraits(.isHeader)
            TextField(L10n.string("ui.a98585871c5313ff"), text: $model.displayName)
                .textContentType(.organizationName)
                .textFieldStyle(.roundedBorder)
            TextField(
                L10n.string("ui.add3d846c43e6f54"),
                text: $model.host,
                prompt: Text(L10n.string("ui.0eb5bf18b9814bd1"))
            )
                .textContentType(.URL)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textFieldStyle(.roundedBorder)
            TextField(L10n.string("ui.311bb313fdeca6aa"), text: $model.username)
                .textContentType(.username)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textFieldStyle(.roundedBorder)
            SecureField(L10n.string("ui.a621ab606db2a11f"), text: $model.password)
                .textContentType(.password)
                .textFieldStyle(.roundedBorder)
                .onSubmit { model.connect() }
            if model.needsOTP || !model.otpCode.isEmpty {
                TextField(L10n.string("ui.0c00c2f57088c5fa"), text: $model.otpCode)
                    .textContentType(.oneTimeCode)
                    .keyboardType(.numberPad)
                    .textFieldStyle(.roundedBorder)
            }
            Toggle(
                L10n.string("ui.9327bc0813de581c"),
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
            Text(L10n.string("ui.b7a6112dd90ce389"))
                .font(.caption)
                .foregroundStyle(.secondary)
            Toggle(
                L10n.string("ui.afe5b2261f44779b"),
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
            Text(L10n.string("ui.4eb0633bb44abe01"))
                .font(.caption)
                .foregroundStyle(.secondary)
            DisclosureGroup(
                isExpanded: $showsAdvancedConnectionSettings
            ) {
                VStack(alignment: .leading, spacing: 6) {
                    TextField(L10n.string("ui.9aa2d5f46c68bf78"), text: $model.port)
                        .keyboardType(.numberPad)
                        .textFieldStyle(.roundedBorder)
                    Text(L10n.string("ui.7ea0491272acd294"))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.top, 8)
            } label: {
                Label(L10n.string("ui.c6d9285846a8f1b4"), systemImage: "gearshape")
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
                    Text(model.isConnecting ? L10n.string("ui.8be0ea36a9bba286") : L10n.string("ui.a5574109f0208e89"))
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
                        .navigationTitle(model.activeProfile?.displayName ?? L10n.string("ui.4aeb6d92cbbff699"))
                } detail: {
                    moduleDetail
                }
                .navigationSplitViewStyle(.balanced)
            } else {
                NavigationStack(path: $path) {
                    moduleList
                        .navigationTitle(model.activeProfile?.displayName ?? L10n.string("ui.4aeb6d92cbbff699"))
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
                    .accessibilityLabel(L10n.string("ui.36b7dfe53cf9b5df"))
            }
        }
        .alert(
            L10n.string("ui.f56c6c82203b33f6"),
            isPresented: Binding(
                get: { model.message != nil },
                set: { if !$0 { model.message = nil } }
            )
        ) {
            Button(L10n.string("ui.f867f34178594f89")) {
                model.message = nil
            }
        } message: {
            Text(model.message ?? "")
        }
    }

    private var moduleList: some View {
        List {
            Section(L10n.string("ui.b3bd5ac7cc4d668b")) {
                moduleRow(.files)
                moduleRow(.photos)
            }
            Section(L10n.string("ui.aadb2d9d805f9164")) {
                moduleRow(.chat)
            }
            Section(L10n.string("ui.d7617d7b3b1fa180")) {
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
                    Label(L10n.string("ui.3ab8cc15939f3b5c"), systemImage: "rectangle.portrait.and.arrow.right")
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
                    title: L10n.string("ui.025279f9c408a51b"),
                    message: L10n.string("ui.c8066901cae15044"),
                    systemImage: "arrow.up.arrow.down"
                )
            case .settings:
                MobileSettingsView(model: model)
            }
            if model.isLoading {
                ProgressView(L10n.string("ui.86b6d0d63062ba81"))
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
                .accessibilityLabel(L10n.string("ui.aee88743413144a2"))
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
                    title: L10n.string("ui.45d5c590513a6fdc"),
                    message: L10n.string("ui.6aabdc2485f34c84"),
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
                                Text(item.isDirectory ? L10n.string("ui.7c7802d8adaed72e") : ByteCountFormatter.string(
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
                            .accessibilityLabel(L10n.string("ui.9f07d2ce4115f575"))
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .searchable(text: $search, prompt: L10n.string("ui.9c8bd1565def7849"))
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
                    .accessibilityLabel(L10n.string("ui.2bab713fde4ebc53"))
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    isCreatingFolder = true
                } label: {
                    Label(L10n.string("ui.84244abc71de03ac"), systemImage: "folder.badge.plus")
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
                Button(L10n.string("ui.c771248e511fbf93")) {
                    if let itemForActions {
                        model.openDirectory(itemForActions)
                    }
                    itemForActions = nil
                }
            }
            Button(L10n.string("ui.0d0cbac2eee54113")) {
                itemToRename = itemForActions
                itemForActions = nil
            }
            Button(L10n.string("ui.2f9daa828907b93f"), role: .destructive) {
                itemToDelete = itemForActions
                itemForActions = nil
            }
            Button(L10n.string("ui.2cd0f3be8738a86c"), role: .cancel) {
                itemForActions = nil
            }
        }
        .sheet(isPresented: $isCreatingFolder) {
            MobileTextInputSheet(
                title: L10n.string("ui.84244abc71de03ac"),
                label: L10n.string("ui.bacf701908d8cf45"),
                actionTitle: L10n.string("ui.cde2cd071d25bbab")
            ) { name in
                model.createFolder(name: name)
                isCreatingFolder = false
            }
            .presentationDetents([.medium])
        }
        .sheet(item: $itemToRename) { item in
            MobileTextInputSheet(
                title: L10n.string("ui.0d0cbac2eee54113"),
                label: L10n.string("ui.92ddb51db6c45cf7"),
                initialValue: item.name,
                actionTitle: L10n.string("ui.a3030bf8f16dc63c")
            ) { name in
                model.rename(item, to: name)
                itemToRename = nil
            }
            .presentationDetents([.medium])
        }
        .confirmationDialog(
            L10n.string(
                "file.delete.confirm",
                itemToDelete?.name ?? ""
            ),
            isPresented: Binding(
                get: { itemToDelete != nil },
                set: { if !$0 { itemToDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(L10n.string("ui.2f9daa828907b93f"), role: .destructive) {
                if let itemToDelete {
                    model.delete([itemToDelete])
                }
                itemToDelete = nil
            }
            Button(L10n.string("ui.2cd0f3be8738a86c"), role: .cancel) {
                itemToDelete = nil
            }
        } message: {
            Text(L10n.string("ui.01c3021b19039967"))
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
                title: L10n.string("ui.7ac5626d1ad8df4e"),
                message: L10n.string("ui.69e9a23473708e14"),
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
                title: L10n.string("ui.6c5e17bc9823f3b3"),
                message: L10n.string("ui.e779d9db48c695e6"),
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
                        Text(conversation.lastMessageSummary ?? L10n.string("ui.edc93fc6672e581a", String(describing: conversation.memberCount ?? 0)))
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
                            .accessibilityLabel(L10n.string("ui.d03793ec01fb7aee", String(describing: conversation.unreadCount)))
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
                    title: L10n.string("ui.e0c9f46a0d2db5c0"),
                    message: L10n.string("ui.2b2a88ea06320786"),
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
                    Label(L10n.string("ui.52b312406b04b9a7"), systemImage: "plus")
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
            Button(L10n.string("ui.8d12fc0d4eb26021")) {
                if let selectedTask {
                    model.controlDownload(selectedTask, action: .pause)
                }
                selectedTask = nil
            }
            Button(L10n.string("ui.7c9691192f1b7340")) {
                if let selectedTask {
                    model.controlDownload(selectedTask, action: .resume)
                }
                selectedTask = nil
            }
            Button(L10n.string("ui.629aa1d4eb56d351"), role: .destructive) {
                taskToDelete = selectedTask
                selectedTask = nil
            }
            Button(L10n.string("ui.2cd0f3be8738a86c"), role: .cancel) {
                selectedTask = nil
            }
        }
        .confirmationDialog(
            L10n.string("ui.55fcd31b99791e0a"),
            isPresented: Binding(
                get: { taskToDelete != nil },
                set: { if !$0 { taskToDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button(L10n.string("ui.219d13da55a2a9dd"), role: .destructive) {
                if let taskToDelete {
                    model.deleteDownload(taskToDelete, removeData: false)
                }
                taskToDelete = nil
            }
            Button(L10n.string("ui.5297eed6982a576a"), role: .destructive) {
                if let taskToDelete {
                    model.deleteDownload(taskToDelete, removeData: true)
                }
                taskToDelete = nil
            }
            Button(L10n.string("ui.2cd0f3be8738a86c"), role: .cancel) {
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
                Section(L10n.string("ui.e2f01c220af7045b")) {
                    TextField(L10n.string("ui.ef4b8ad47f1e998e"), text: $uri, axis: .vertical)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                }
                Section(L10n.string("ui.0b7e2876922e4662")) {
                    TextField(L10n.string("ui.c4cabe337e8400f7"), text: $destination)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
            }
            .navigationTitle(L10n.string("ui.52b312406b04b9a7"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(L10n.string("ui.2cd0f3be8738a86c")) { isPresented = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(L10n.string("ui.cde2cd071d25bbab")) {
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
                Text(L10n.string("ui.6d23f04b26967d64")).tag(0)
                Text(L10n.string("ui.ceb4432ba2356217")).tag(1)
                Text(L10n.string("ui.97b31b5d63f57e51")).tag(2)
                Text(L10n.string("ui.79f326be4409d51f")).tag(3)
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
                    $0.isInUse ? L10n.string("ui.fa48e89389404e60") : ByteCountFormatter.string(
                        fromByteCount: $0.sizeBytes ?? 0,
                        countStyle: .file
                    )
                }
            case 2:
                resourceList(model.containerSnapshot?.networks ?? []) { item in
                    networkToDelete = item
                } title: { $0.name } detail: {
                    L10n.string("ui.0b8b8f8e7062c3de", String(describing: $0.driver), String(describing: $0.connectedContainerCount))
                }
            default:
                resourceList(model.containerSnapshot?.projects ?? []) { _ in
                } title: { $0.name } detail: { L10n.string("ui.0b8b8f8e7062c3de", String(describing: $0.status), String(describing: $0.containerCount)) }
            }
        }
        .toolbar {
            if tab == 2 {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        isCreatingNetwork = true
                    } label: {
                        Label(L10n.string("ui.bbb95fc4344b8391"), systemImage: "plus")
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
            Button(L10n.string("ui.56410fc65314dfb5")) {
                if let selectedContainer {
                    model.controlContainer(selectedContainer, action: .start)
                }
                selectedContainer = nil
            }
            Button(L10n.string("ui.ca4d973c0b006b75")) {
                if let selectedContainer {
                    model.controlContainer(selectedContainer, action: .stop)
                }
                selectedContainer = nil
            }
            Button(L10n.string("ui.4c7c6cc2eb16ec30")) {
                if let selectedContainer {
                    model.controlContainer(selectedContainer, action: .restart)
                }
                selectedContainer = nil
            }
            Button(L10n.string("ui.2f9daa828907b93f"), role: .destructive) {
                containerToDelete = selectedContainer
                selectedContainer = nil
            }
            Button(L10n.string("ui.2cd0f3be8738a86c"), role: .cancel) {
                selectedContainer = nil
            }
        }
        .deleteConfirmation(
            title: containerToDelete.map { L10n.string("ui.58e4c3955dcfae87", String(describing: $0.name)) } ?? "",
            message: L10n.string("ui.d146f8b315800ce5"),
            item: $containerToDelete,
            action: model.deleteContainer
        )
        .deleteConfirmation(
            title: imageToDelete.map { L10n.string("ui.bbbd5f8974e6dbfa", String(describing: $0.repository), String(describing: $0.tag)) } ?? "",
            message: L10n.string("ui.80da3b4aa4e0bc1d"),
            item: $imageToDelete,
            action: model.deleteContainerImage
        )
        .deleteConfirmation(
            title: networkToDelete.map { L10n.string("ui.58e4c3955dcfae87", String(describing: $0.name)) } ?? "",
            message: L10n.string("ui.caa80c90b89fc069"),
            item: $networkToDelete,
            action: model.deleteContainerNetwork
        )
        .sheet(isPresented: $isCreatingNetwork) {
            MobileTextInputSheet(
                title: L10n.string("ui.49fe5148286aa7f8"),
                label: L10n.string("ui.ac8d90dfa36e5134"),
                actionTitle: L10n.string("ui.cde2cd071d25bbab")
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

    private let tabs = [L10n.string("ui.f3fb4b3a41570007"), L10n.string("ui.e87d9f23a3f5a830"), L10n.string("ui.a3434acddb75d8fb"), L10n.string("ui.97b31b5d63f57e51"), L10n.string("ui.ceb4432ba2356217"), L10n.string("ui.0f810a7901cf0422"), L10n.string("ui.7dbac1c20f237bd4")]

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
            Button(L10n.string("ui.56410fc65314dfb5")) {
                if let selectedMachine {
                    model.controlVirtualMachine(selectedMachine, action: .powerOn)
                }
                selectedMachine = nil
            }
            Button(L10n.string("ui.0c6d079c4c60bcf5")) {
                if let selectedMachine {
                    model.controlVirtualMachine(selectedMachine, action: .shutdown)
                }
                selectedMachine = nil
            }
            Button(L10n.string("ui.63cd126ae15f4036"), role: .destructive) {
                if let selectedMachine {
                    model.controlVirtualMachine(selectedMachine, action: .powerOff)
                }
                selectedMachine = nil
            }
            Button(L10n.string("ui.2f9daa828907b93f"), role: .destructive) {
                machineToDelete = selectedMachine
                selectedMachine = nil
            }
            Button(L10n.string("ui.2cd0f3be8738a86c"), role: .cancel) {
                selectedMachine = nil
            }
        }
        .deleteConfirmation(
            title: machineToDelete.map { L10n.string("ui.58e4c3955dcfae87", String(describing: $0.name)) } ?? "",
            message: L10n.string("ui.67d3d2f7145c7bb6"),
            item: $machineToDelete,
            action: model.deleteVirtualMachine
        )
        .deleteConfirmation(
            title: networkToDelete.map { L10n.string("ui.58e4c3955dcfae87", String(describing: $0.name)) } ?? "",
            message: L10n.string("ui.e022c53aee84c353"),
            item: $networkToDelete,
            action: model.deleteVirtualMachineNetwork
        )
        .deleteConfirmation(
            title: imageToDelete.map { L10n.string("ui.58e4c3955dcfae87", String(describing: $0.name)) } ?? "",
            message: L10n.string("ui.e4520afef33a9eaa"),
            item: $imageToDelete,
            action: model.deleteVirtualMachineImage
        )
        .sheet(item: $networkToEdit) { network in
            MobileTextInputSheet(
                title: L10n.string("ui.d1650277320baac5"),
                label: L10n.string("ui.ac8d90dfa36e5134"),
                initialValue: network.name,
                actionTitle: L10n.string("ui.a3030bf8f16dc63c")
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
                Text(L10n.string("ui.677050193f34702b")).tag(0)
                Text(L10n.string("ui.457b5e7e319ab16a")).tag(1)
                Text(L10n.string("ui.00213c7f272b9a59")).tag(2)
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
                    Text(L10n.string("ui.5c55a67935af8f45")).tag("")
                    Text(L10n.string("ui.e7028601e7da793d")).tag("info")
                    Text(L10n.string("ui.a8b7a4480407ac8a")).tag("warning")
                    Text(L10n.string("ui.0bc1fb72ae1be5c5")).tag("error")
                }
                .labelsHidden()
                .frame(maxWidth: 150)
                TextField(L10n.string("ui.1b9b75f51d2061d7"), text: $logSearch)
                    .textFieldStyle(.roundedBorder)
            }
            .padding()
            if events.isEmpty {
                MobileEmptyView(
                    title: L10n.string("ui.da494cd706341a64"),
                    message: L10n.string("ui.fccab2a7972c8817"),
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
                title: L10n.string("ui.193f5172b1a610e3"),
                message: L10n.string("ui.8a5055f70e40226c"),
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
                        .accessibilityLabel(L10n.string("ui.051836569928a9f9"))
                    }
                    if let delete {
                        Button(role: .destructive) {
                            delete(resource)
                        } label: {
                            Image(systemName: "trash")
                                .frame(width: 44, height: 44)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(L10n.string("ui.2f9daa828907b93f"))
                    }
                }
            }
        }
    }
}

private struct MobileNasSettingsView: View {
    @Bindable var model: MobileAppModel
    @State private var tab = 0
    private let tabs = [L10n.string("ui.fea405f9b01d1416"), L10n.string("ui.a3434acddb75d8fb"), L10n.string("ui.58be5abb3cf57752"), L10n.string("ui.311bb313fdeca6aa"), L10n.string("ui.7dbac1c20f237bd4"), L10n.string("ui.a5574109f0208e89")]

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
                    MobileSummaryCard(title: L10n.string("ui.5b50d7c4b5950dc5"), systemImage: "server.rack") {
                        summaryLine(L10n.string("ui.65d8f92232ae77b0"), overview.serverName)
                        summaryLine(L10n.string("ui.322408c53beda26b"), overview.model ?? "—")
                        summaryLine("DSM", overview.version ?? "—")
                        summaryLine(L10n.string("ui.43b8de30fe4bab74"), overview.cpuModel ?? "—")
                        summaryLine(
                            L10n.string("ui.7d8f8c37ec7885bc"),
                            ByteCountFormatter.string(
                                fromByteCount: overview.memoryBytes ?? 0,
                                countStyle: .memory
                            )
                        )
                    }
                }
                HStack(spacing: 12) {
                    metricCard(L10n.string("ui.26de3dd933ce00e3"), "\(model.storageSnapshot?.volumes.count ?? 0)", "externaldrive")
                    metricCard(L10n.string("ui.58be5abb3cf57752"), "\(model.packages.count)", "shippingbox")
                }
                HStack(spacing: 12) {
                    metricCard(
                        L10n.string("ui.311bb313fdeca6aa"),
                        "\(model.accountsAndGroups?.users.count ?? 0)",
                        "person.2"
                    )
                    metricCard(
                        L10n.string("ui.3726bcb6903fa086"),
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
            Section(L10n.string("ui.26de3dd933ce00e3")) {
                ForEach(model.storageSnapshot?.volumes ?? []) { volume in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(volume.name)
                        Text(volume.status ?? "")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Section(L10n.string("ui.ba380b79ff47c4c2")) {
                ForEach(model.storageSnapshot?.pools ?? []) { pool in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(pool.name)
                        Text(pool.status ?? "")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Section(L10n.string("ui.1e7098fe0f6eaae2")) {
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
            Section(L10n.string("ui.311bb313fdeca6aa")) {
                ForEach(model.accountsAndGroups?.users ?? []) { account in
                    accountRow(account)
                }
            }
            Section(L10n.string("ui.f3f8bcf3f57de41f")) {
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
                Text(
                    L10n.string(
                        "connection.account_protocol",
                        connection.account,
                        connection.protocolName ?? L10n.string("protocol.dsm")
                    )
                )
                Text(connection.source ?? connection.location ?? L10n.string("ui.8ca01a9ba438675d"))
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
            Section(L10n.string("settings.language.title")) {
                AppLanguagePicker()
                Text(L10n.string("settings.language.footer"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Section(L10n.string("ui.7785a5282f543671")) {
                ForEach(MobileModule.allCases) { module in
                    HStack {
                        Label(module.title, systemImage: module.systemImage)
                        Spacer()
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                            .accessibilityLabel(L10n.string("ui.dfb802238b38fbd4"))
                    }
                }
            }
            Section(L10n.string("ui.afb63a620bdcff15")) {
                Label(
                    L10n.string("ui.fd5992f83ae2e9a9"),
                    systemImage: "lock.shield"
                )
            }
            Section {
                Button(L10n.string("ui.3ab8cc15939f3b5c"), role: .destructive) {
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
                    Button(L10n.string("ui.2cd0f3be8738a86c")) { dismiss() }
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
            Button(L10n.string("ui.2f9daa828907b93f"), role: .destructive) {
                if let value = item.wrappedValue {
                    action(value)
                }
                item.wrappedValue = nil
            }
            Button(L10n.string("ui.2cd0f3be8738a86c"), role: .cancel) {
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
                title: L10n.string("ui.193f5172b1a610e3"),
                message: L10n.string("ui.8a5055f70e40226c"),
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
