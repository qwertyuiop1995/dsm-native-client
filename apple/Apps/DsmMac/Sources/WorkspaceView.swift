import AppKit
import DsmCore
import SwiftUI
import UniformTypeIdentifiers

private enum FileViewMode: String, CaseIterable, Identifiable {
    case list
    case grid
    var id: Self { self }
}

private enum FileGrouping: String, CaseIterable, Identifiable {
    case none
    case type
    case date
    case size

    var id: Self { self }

    var title: String {
        switch self {
        case .none: "不分组"
        case .type: "按类型"
        case .date: "按时间"
        case .size: "按大小"
        }
    }
}

struct WorkspaceView: View {
    @Bindable var model: WorkspaceModel
    let profiles: [NasProfile]
    let selectedProfileID: UUID?
    let connectedWorkspaces: [WorkspaceModel]
    let connectionRoute: AppModel.ConnectionRoute?
    let onAddNAS: () -> Void
    let onSelectNAS: (UUID) -> Void
    let onMoveProfiles: (IndexSet, Int) -> Void
    let hasFileClipboard: Bool
    let onCopy: ([FileItem]) -> Void
    let onCut: ([FileItem]) -> Void
    let onPaste: () -> Void
    let onRenameNAS: (String) -> String?
    let onLogout: () async -> Void
    let onSessionExpired: (String) async -> Void

    @State private var deleteTargets: [FileItem] = []
    @State private var restoreTarget: FileItem?
    @State private var viewMode: FileViewMode = .grid
    @AppStorage("LanStash_FileGrouping") private var fileGrouping: FileGrouping = .none
    @State private var sortOrder = [KeyPathComparator<FileItem>]()
    @State private var showingInfoItem: FileItem? = nil
    @State private var previewWindowController: FloatingPreviewWindowController?
    @State private var shareTargets: [FileItem] = []
    @State private var isRestoringSectionAfterUnsavedEdit = false

    var body: some View {
        NavigationSplitView {
            SidebarView(
                model: model,
                profiles: profiles,
                selectedProfileID: selectedProfileID,
                connectionRoute: connectionRoute,
                onAddNAS: onAddNAS,
                onSelectNAS: { profile in onSelectNAS(profile.id) },
                onMoveProfiles: onMoveProfiles,
                onLogout: onLogout
            )
                .navigationSplitViewColumnWidth(min: 210, ideal: 240, max: 300)
        } detail: {
            contentColumn
                .navigationSplitViewColumnWidth(min: 480, ideal: 680)
        }
        .navigationSplitViewStyle(.balanced)
        .task {
            await model.load()
            model.section = .files("/")
            await model.navigate(to: "/", recordingHistory: false)
        }
        .onChange(of: model.section) { previousSection, section in
            if isRestoringSectionAfterUnsavedEdit {
                isRestoringSectionAfterUnsavedEdit = false
                return
            }
            if blockSectionChangeDueToUnsavedEdits(previousSection: previousSection, newSection: section) {
                return
            }
            switch section {
            case .files?, .recycle?:
                break
            default:
                previewWindowController?.closeFromModel()
                model.dismissPreview()
            }
            Task { await model.activate(section) }
        }
        .onChange(of: model.selection) { _, _ in
            // 照片模块的选中态由 PhotoLibraryModel 独立维护，WorkspaceModel.selection 仅在发起预览时被设置，
            // 不应被当作「用户切换选择」而关闭预览窗口。
            guard isFileSection else { return }
            if model.selectionChanged() {
                previewWindowController?.closeFromModel()
            }
        }
        .onChange(of: model.isPreviewPresented) { _, isPresented in
            if isPresented {
                presentFloatingPreview()
            } else {
                previewWindowController?.closeFromModel()
            }
        }
        .onDisappear {
            previewWindowController?.closeFromModel()
            model.dismissPreview()
        }
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button {
                    navigateBack()
                } label: {
                    Label("返回", systemImage: "chevron.backward")
                }
                .disabled(!canNavigateBack)
                .help(isFileSection ? "返回上一个目录（⌘[）" : "返回刚才浏览的文件夹（⌘[）")
                .keyboardShortcut("[", modifiers: .command)

                Button {
                    navigateUp()
                } label: {
                    Label("上一级", systemImage: "arrow.up")
                }
                .disabled(!canNavigateUp)
                .help("前往上一级目录")
            }

            ToolbarItemGroup(placement: .primaryAction) {
                if isFileSection {
                    Button {
                        Task { await model.refresh() }
                    } label: {
                        Label("刷新", systemImage: "arrow.clockwise")
                    }
                    .disabled(model.currentPath.isEmpty || model.isRefreshing)
                    .keyboardShortcut("r", modifiers: .command)

                    Button {
                        presentUploadPanel()
                    } label: {
                        Label("上传", systemImage: "square.and.arrow.up")
                    }
                    .disabled(!isFileSection)
                    .help("上传文件到当前目录")

                    Menu {
                        if model.selectedItems.count > 1 {
                            Button("下载所选项目为压缩包…") {
                                presentBatchDownloadPanel(model.selectedItems)
                            }
                        } else if let item = model.selectedItem {
                            if item.isDirectory {
                                Button("下载为压缩包…") {
                                    presentDownloadPanel(item, folderMode: .archive)
                                }
                                Button("下载为文件夹…") {
                                    presentDownloadPanel(item, folderMode: .directory)
                                }
                            } else {
                                Button("下载…") {
                                    presentDownloadPanel(item, folderMode: .archive)
                                }
                            }
                        }
                    } label: {
                        Label("下载", systemImage: "square.and.arrow.down")
                    }
                    .disabled(model.selectedItem == nil)
                    .help("下载文件夹时默认保存为压缩包，也可以保留原来的文件夹结构")

                    Button {
                        shareTargets = model.selectedItems
                    } label: {
                        Label("分享", systemImage: "link")
                    }
                    .disabled(model.selectedItems.isEmpty)
                    .help("创建可发送给他人的下载链接")

                    Button {
                        deleteTargets = model.selectedItems
                    } label: {
                        Label("删除", systemImage: "trash")
                    }
                    .disabled(model.selectedItems.isEmpty)
                    .help("打开删除确认，不会直接删除")

                    Button {
                        onPaste()
                    } label: {
                        Label("粘贴", systemImage: "doc.on.clipboard")
                    }
                    .disabled(!hasFileClipboard || !isFileSection)
                    .help("复制或移动到当前目录")
                    .keyboardShortcut("v", modifiers: .command)

                    Button {
                        model.section = .transfers
                    } label: {
                        Label("传输", systemImage: "arrow.up.arrow.down.circle")
                    }
                    .badge(model.activeTransferCount)

                    Picker("视图模式", selection: $viewMode) {
                        Label("列表", systemImage: "list.bullet").tag(FileViewMode.list)
                        Label("图标", systemImage: "square.grid.3x3").tag(FileViewMode.grid)
                    }
                    .pickerStyle(.segmented)
                    .disabled(!isFileSection)

                    if viewMode == .grid {
                        groupingMenu
                    }

                } else if model.section == .photos {
                    Button {
                        presentPhotoUploadPanel()
                    } label: {
                        Label("上传", systemImage: "square.and.arrow.up")
                    }
                    .disabled(model.photoLibrary.currentPath.isEmpty)
                    .help("上传照片或视频到当前文件夹")

                    Button {
                        presentBatchDownloadPanel(model.photoLibrary.selectedItems.map(\.fileItem))
                    } label: {
                        Label("下载", systemImage: "square.and.arrow.down")
                    }
                    .disabled(model.photoLibrary.selectedItems.isEmpty)
                    .help("将所选照片或视频保存为压缩包")

                    Button {
                        shareTargets = model.photoLibrary.selectedItems.map(\.fileItem)
                    } label: {
                        Label("分享", systemImage: "link")
                    }
                    .disabled(model.photoLibrary.selectedItems.isEmpty)
                    .help("创建可发送给他人的下载链接")

                    Button {
                        showingInfoItem = model.photoLibrary.selectedItems.first?.fileItem
                    } label: {
                        Label("信息", systemImage: "info.circle")
                    }
                    .disabled(model.photoLibrary.selectedItems.count != 1)
                    .help("查看拍摄时间、大小和所在位置")

                    Button {
                        deleteTargets = model.photoLibrary.selectedItems.map(\.fileItem)
                    } label: {
                        Label("删除", systemImage: "trash")
                    }
                    .disabled(model.photoLibrary.selectedItems.isEmpty)
                    .help("打开删除确认，不会直接删除")

                    Button {
                        model.section = .transfers
                    } label: {
                        Label("传输", systemImage: "arrow.up.arrow.down.circle")
                    }
                    .badge(model.activeTransferCount)

                    Menu {
                        Button {
                            Task { await model.photoLibrary.refreshAll() }
                        } label: {
                            Label("重新扫描全部照片", systemImage: "arrow.clockwise")
                        }
                    } label: {
                        Label("更多照片操作", systemImage: "ellipsis.circle")
                    }
                    .disabled(
                        model.photoLibrary.isLoading
                            || model.photoLibrary.isLoadingTimeline
                            || model.photoLibrary.isRetryingTimelineFolders
                    )
                    .help("更多照片操作")
                } else if model.section == .transfers {
                    Button("清除已完成") {
                        clearCompleted()
                    }
                    .disabled(!canClearCompleted)
                    
                    Button {
                        restoreFileBrowser()
                    } label: {
                        Label("返回文件", systemImage: "folder")
                    }
                } else if model.section == .settings {
                    Button {
                        restoreFileBrowser()
                    } label: {
                        Label("返回文件", systemImage: "folder")
                    }
                }
            }
        }
        .alert(deleteAlertTitle, isPresented: deleteAlertPresented) {
            Button("取消", role: .cancel) {
                deleteTargets = []
            }
            Button(deleteTargets.contains(where: \.isRecyclePath) ? "永久删除" : "删除", role: .destructive) {
                let targets = deleteTargets
                deleteTargets = []
                model.deleteItems(targets)
            }
        } message: {
            Text(deleteAlertMessage)
        }
        .alert("恢复到原位置？", isPresented: restoreAlertPresented) {
            Button("取消", role: .cancel) {
                restoreTarget = nil
            }
            Button("恢复") {
                if let item = restoreTarget {
                    model.restoreToOriginalLocation(item)
                }
                restoreTarget = nil
            }
        } message: {
            Text("恢复前会检查目标目录和同名冲突；不会覆盖已有文件。")
        }
        .sheet(item: $showingInfoItem) { item in
            FilePropertiesView(item: item, model: model)
        }
        .sheet(isPresented: Binding(
            get: { !shareTargets.isEmpty },
            set: { if !$0 { shareTargets = [] } }
        )) {
            ShareCreationView(model: model, targets: shareTargets) {
                shareTargets = []
            }
        }
        .alert("需要重新确认登录", isPresented: $model.requiresReauthentication) {
            Button("重试") {
                model.requiresReauthentication = false
                Task { await model.load() }
            }
            Button("重新登录") {
                let message = model.statusMessage ?? "登录状态已失效，请重新登录。"
                Task { await onSessionExpired(message) }
            }
        } message: {
            Text(reauthenticationMessage)
        }
        .navigationTitle(navigationTitle)
    }

    private var reauthenticationMessage: String {
        "\(model.statusMessage ?? "NAS 没有接受当前登录状态。")你可以先重试；如果仍然失败，请重新登录。"
    }

    /// 如果当前有未保存的文本编辑，弹出警告并阻止切换侧边栏栏目。
    /// 返回 `true` 表示已阻止切换，调用方应直接 `return`。
    private func blockSectionChangeDueToUnsavedEdits(
        previousSection: WorkspaceSection?,
        newSection: WorkspaceSection?
    ) -> Bool {
        guard model.hasUnsavedTextEdits, newSection != previousSection else { return false }
        let alert = NSAlert()
        alert.messageText = "请先处理未保存的修改"
        alert.informativeText = "保存或取消当前文件的修改后，才能离开文件管理。"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "继续编辑")
        alert.runModal()
        isRestoringSectionAfterUnsavedEdit = true
        model.section = previousSection
        return true
    }

    @ViewBuilder
    private var groupingMenu: some View {
        Menu {
            Picker("分组方式", selection: $fileGrouping) {
                ForEach(FileGrouping.allCases) { grouping in
                    Text(grouping.title).tag(grouping)
                }
            }
        } label: {
            Label(fileGrouping.title, systemImage: "rectangle.3.group")
        }
        .help("选择图标视图中的文件分组方式")
    }

    private var navigationTitle: String {
        switch model.section {
        case .favorites:
            return "收藏"
        case .recent:
            return "最近访问"
        case .remoteLocations:
            return "远程位置"
        case .sharedLinks:
            return "分享管理"
        case .photos:
            return "照片"
        case .transfers:
            return "传输中心"
        case .settings:
            return "设置"
        default:
            return (model.currentPath.isEmpty || model.currentPath == "/") ? model.profile.displayName : (model.currentPath.split(separator: "/").last.map(String.init) ?? model.currentPath)
        }
    }

    private var canClearCompleted: Bool {
        connectedWorkspaces.contains(where: { ws in
            ws.transfers.contains(where: { $0.state == .succeeded || $0.state == .cancelled })
        })
    }

    private func clearCompleted() {
        for ws in connectedWorkspaces {
            ws.clearCompletedTransfers()
        }
    }

    @ViewBuilder
    private var contentColumn: some View {
        switch model.section {
        case .favorites:
            LocationCollectionView(
                title: "收藏",
                locations: model.favorites,
                emptyMessage: "还没有收藏的文件夹。",
                onOpen: openLocation,
                onRemove: { location in model.toggleFavorite(path: location.path, name: location.name) }
            )
        case .recent:
            RecentLocationsView(
                locations: model.recentLocations,
                onOpen: { location in Task { await model.openRecentLocation(location) } },
                onRemove: model.removeRecentLocation,
                onClearAll: model.clearRecentLocations
            )
        case .remoteLocations:
            RemoteLocationsView(model: model, onOpen: { item in openLocation(item.path) })
        case .sharedLinks:
            ShareLinksView(model: model)
        case .photos:
            PhotoLibraryView(
                model: model.photoLibrary,
                onPreview: { item in
                    let previewItems = model.photoLibrary.displayedItems
                        .filter { !$0.isFolder }
                        .map(\.fileItem)
                    model.preparePhotoPreview(items: previewItems, selected: item.fileItem)
                    presentFloatingPreview()
                },
                onDownload: presentPhotoDownload,
                onDelete: { deleteTargets = $0.map(\.fileItem) },
                onRestore: { restoreTarget = $0.fileItem },
                onMove: { item, destinationPath in
                    let destination = FileItem(
                        profileID: model.profile.id,
                        name: (destinationPath as NSString).lastPathComponent,
                        path: destinationPath,
                        kind: .directory
                    )
                    model.moveByDragging([item.fileItem], to: destination)
                }
            )
        case .transfers:
            TransferCenterView(model: model, connectedWorkspaces: connectedWorkspaces)
        case .settings:
            SettingsView(model: model, onRenameNAS: onRenameNAS)
        default:
            FileBrowserView(
                model: model,
                viewMode: $viewMode,
                fileGrouping: fileGrouping,
                showingInfoItem: $showingInfoItem,
                onDownload: presentDownloadPanel,
                onDownloadBatch: presentBatchDownloadPanel,
                onShare: { shareTargets = $0 },
                onDelete: { deleteTargets = $0 },
                onRestore: { restoreTarget = $0 },
                onCopy: onCopy,
                onCut: onCut,
                hasFileClipboard: hasFileClipboard,
                onPaste: onPaste
            )
        }
    }

    private func openLocation(_ path: String) {
        model.section = .files(path)
        Task { await model.navigate(to: path, recordingHistory: false) }
    }

    private var canNavigateBack: Bool {
        if isFileSection { return model.canGoBack }
        if model.section == .photos { return model.photoLibrary.canGoBack }
        return model.section != nil
    }

    private func navigateBack() {
        if isFileSection {
            Task { await model.goBack() }
        } else if model.section == .photos {
            Task { await model.photoLibrary.goBack() }
        } else {
            restoreFileBrowser()
        }
    }

    private var canNavigateUp: Bool {
        model.section == .photos ? model.photoLibrary.canGoUp : model.canGoUp
    }

    private func navigateUp() {
        if model.section == .photos {
            Task { await model.photoLibrary.goUp() }
        } else {
            Task { await model.goUp() }
        }
    }

    private func restoreFileBrowser() {
        model.section = model.currentFileSection
    }

    private var isFileSection: Bool {
        switch model.section {
        case .files, .recycle: true
        default: false
        }
    }

    private var shouldShowFloatingPreview: Bool {
        guard (isFileSection || model.section == .photos),
              model.isPreviewPresented,
              let item = model.selectedItem,
              !item.isDirectory else {
            return false
        }
        return PreviewKind.classify(item) != .unsupported
    }

    private func presentFloatingPreview() {
        let controller: FloatingPreviewWindowController
        if let existing = previewWindowController, existing.profileID == model.profile.id {
            controller = existing
        } else {
            previewWindowController?.closeFromModel()
            controller = FloatingPreviewWindowController(
                model: model,
                onDownload: presentDownloadPanel,
                onDelete: { deleteTargets = $0 },
                onRestore: { restoreTarget = $0 }
            )
            previewWindowController = controller
        }
        controller.show()
    }

    private var deleteAlertPresented: Binding<Bool> {
        Binding(
            get: { !deleteTargets.isEmpty },
            set: { if !$0 { deleteTargets = [] } }
        )
    }

    private var restoreAlertPresented: Binding<Bool> {
        Binding(
            get: { restoreTarget != nil },
            set: { if !$0 { restoreTarget = nil } }
        )
    }

    private var deleteAlertTitle: String {
        if deleteTargets.contains(where: \.isRecyclePath) {
            return deleteTargets.count == 1 ? "永久删除这个项目？" : "永久删除 \(deleteTargets.count) 个项目？"
        }
        return deleteTargets.count == 1 ? "删除这个项目？" : "删除 \(deleteTargets.count) 个项目？"
    }

    private var deleteAlertMessage: String {
        if deleteTargets.contains(where: \.isRecyclePath) {
            return "项目位于 #recycle 中，再次删除通常不可恢复。NAS：\(model.profile.displayName)。"
        }
        let locationDescription: String
        if model.section == .photos {
            let parentPaths = Set(deleteTargets.map { ($0.path as NSString).deletingLastPathComponent })
            locationDescription = parentPaths.count == 1
                ? "所在文件夹：\(parentPaths.first ?? model.photoLibrary.currentPath)"
                : "所在位置：多个照片文件夹"
        } else {
            locationDescription = "目录：\(model.currentPath)"
        }
        return "NAS：\(model.profile.displayName)\n\(locationDescription)\n删除后能否恢复取决于共享文件夹的回收站设置，文件可能被永久删除。"
    }

    private func presentUploadPanel() {
        let panel = NSOpenPanel()
        panel.title = "选择要上传的文件"
        panel.prompt = "上传"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        if panel.runModal() == .OK {
            model.enqueueUploads(panel.urls, overwrite: false)
        }
    }

    private func presentPhotoUploadPanel() {
        let panel = NSOpenPanel()
        panel.title = "选择要添加的照片或视频"
        panel.message = "所选项目会上传到当前照片文件夹。"
        panel.prompt = "上传"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        if panel.runModal() == .OK {
            model.enqueueUploads(
                panel.urls,
                to: model.photoLibrary.currentPath,
                overwrite: false
            )
        }
    }

    private func presentDownloadPanel(
        _ item: FileItem,
        folderMode: WorkspaceModel.FolderDownloadMode = .archive
    ) {
        let downloadsDirectoryAsArchive = item.isDirectory && folderMode == .archive
        let panel = NSSavePanel()
        panel.title = downloadsDirectoryAsArchive
            ? "下载“\(item.name)”文件夹"
            : (item.isDirectory ? "下载文件夹 \(item.name)" : "下载 \(item.name)")
        panel.message = downloadsDirectoryAsArchive
            ? "下载后会得到一个压缩包，打开即可查看其中的全部内容。"
            : (item.isDirectory ? "保留原目录结构并逐个下载其中的文件。" : "选择文件的保存位置。")
        panel.nameFieldStringValue = downloadsDirectoryAsArchive ? "\(item.name).zip" : item.name
        if downloadsDirectoryAsArchive {
            panel.allowedContentTypes = [.zip]
        }
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            model.enqueueDownload(item, to: url, folderMode: folderMode)
        }
    }

    private func presentBatchDownloadPanel(_ items: [FileItem]) {
        guard !items.isEmpty else { return }
        let panel = NSSavePanel()
        panel.title = "下载所选项目"
        panel.message = "所选项目会保存为一个压缩包。"
        panel.nameFieldStringValue = "下载项目.zip"
        panel.allowedContentTypes = [.zip]
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            model.enqueueBatchDownload(items, to: url)
        }
    }

    private func presentPhotoDownload(_ items: [PhotoLibraryItem]) {
        let files = items.map(\.fileItem)
        guard let first = files.first else { return }
        if files.count == 1 {
            presentDownloadPanel(first)
        } else {
            presentBatchDownloadPanel(files)
        }
    }

}

@MainActor
private final class FloatingPreviewWindowController: NSObject, NSWindowDelegate {
    let profileID: UUID

    private let model: WorkspaceModel
    private let onDownload: (FileItem, WorkspaceModel.FolderDownloadMode) -> Void
    private let onDelete: ([FileItem]) -> Void
    private let onRestore: (FileItem) -> Void
    private let presentationState = PreviewWindowPresentationState()
    private var window: NSWindow?
    private var isClosingFromModel = false

    init(
        model: WorkspaceModel,
        onDownload: @escaping (FileItem, WorkspaceModel.FolderDownloadMode) -> Void,
        onDelete: @escaping ([FileItem]) -> Void,
        onRestore: @escaping (FileItem) -> Void
    ) {
        profileID = model.profile.id
        self.model = model
        self.onDownload = onDownload
        self.onDelete = onDelete
        self.onRestore = onRestore
    }

    func show() {
        let previewWindow = window ?? makeWindow()
        if !previewWindow.isVisible {
            placeAtScreenCenter(previewWindow)
        }
        previewWindow.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func closeFromModel() {
        guard let window, window.isVisible else { return }
        isClosingFromModel = true
        window.close()
        isClosingFromModel = false
    }

    func windowWillClose(_ notification: Notification) {
        presentationState.isFullScreen = false
        window = nil
        if !isClosingFromModel, model.isPreviewPresented {
            model.dismissPreview()
        }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        if model.isSavingText {
            NSSound.beep()
            return false
        }
        guard model.hasUnsavedTextEdits else { return true }
        let alert = NSAlert()
        alert.messageText = "放弃未保存的修改？"
        alert.informativeText = "关闭后，尚未保存到 NAS 的修改会丢失。"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "继续编辑")
        alert.addButton(withTitle: "放弃修改")
        guard alert.runModal() == .alertSecondButtonReturn else { return false }
        model.cancelTextEditing()
        return true
    }

    func windowWillEnterFullScreen(_ notification: Notification) {
        presentationState.isFullScreen = true
        window?.level = .normal
    }

    func windowWillExitFullScreen(_ notification: Notification) {
        presentationState.isFullScreen = false
    }

    func windowDidExitFullScreen(_ notification: Notification) {
        presentationState.isFullScreen = false
        window?.level = .floating
    }

    private func makeWindow() -> NSWindow {
        let previewWindow = NSWindow(
            contentRect: .zero,
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        previewWindow.title = "项目预览"
        previewWindow.titleVisibility = .hidden
        previewWindow.titlebarAppearsTransparent = true
        previewWindow.isMovableByWindowBackground = false
        previewWindow.isReleasedWhenClosed = false
        previewWindow.level = .floating
        previewWindow.collectionBehavior = [.fullScreenPrimary]
        previewWindow.minSize = NSSize(width: 480, height: 420)
        previewWindow.delegate = self
        previewWindow.contentViewController = NSHostingController(
            rootView: FileDetailView(
                model: model,
                windowState: presentationState,
                onDownload: onDownload,
                onDelete: onDelete,
                onRestore: onRestore
            )
        )
        window = previewWindow
        return previewWindow
    }

    private func placeAtScreenCenter(_ window: NSWindow) {
        let screen = NSApp.keyWindow?.screen ?? NSScreen.main
        let visibleFrame = screen?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1_280, height: 800)
        let contentSize = NSSize(
            width: min(1_080, max(640, visibleFrame.width * 0.68)),
            height: min(860, max(520, visibleFrame.height * 0.78))
        )
        let frame = NSRect(
            x: visibleFrame.midX - contentSize.width / 2,
            y: visibleFrame.midY - contentSize.height / 2,
            width: contentSize.width,
            height: contentSize.height
        )
        window.setFrame(frame, display: true)
    }
}

private struct SidebarView: View {
    @Bindable var model: WorkspaceModel
    let profiles: [NasProfile]
    let selectedProfileID: UUID?
    let connectionRoute: AppModel.ConnectionRoute?
    let onAddNAS: () -> Void
    let onSelectNAS: (NasProfile) -> Void
    let onMoveProfiles: (IndexSet, Int) -> Void
    let onLogout: () async -> Void

    @AppStorage("LanStash_Module_FileStation") private var isFileModuleEnabled = true
    @AppStorage("LanStash_Module_Photos") private var isPhotosModuleEnabled = true
    @State private var isNasListExpanded = true
    @State private var connectingProfileID: UUID? = nil
    @State private var confirmsLogout = false

    var body: some View {
        List(selection: $model.section) {
            Section("NAS 设备", isExpanded: $isNasListExpanded) {
                ForEach(profiles) { profile in
                    let isCurrent = profile.id == selectedProfileID
                    let isConnecting = connectingProfileID == profile.id
                    
                    HStack(spacing: 8) {
                        Image(
                            systemName: isCurrent
                                ? "externaldrive.fill.badge.checkmark"
                                : "externaldrive"
                        )
                        .foregroundStyle(isCurrent ? .blue : .secondary)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(profile.displayName)
                                .font(.headline)
                            Text(isCurrent ? "当前连接" : profile.host)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        
                        Spacer()
                        
                        if isConnecting {
                            ProgressView()
                                .controlSize(.small)
                        } else if isCurrent {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.blue)
                                .font(.system(size: 11, weight: .bold))
                                .accessibilityLabel("当前 NAS")
                        }
                    }
                    .contentShape(Rectangle())
                    .padding(.vertical, 4)
                    .onTapGesture {
                        guard !isCurrent && connectingProfileID == nil else { return }
                        connectingProfileID = profile.id
                        Task {
                            onSelectNAS(profile)
                            try? await Task.sleep(nanoseconds: 800_000_000)
                            connectingProfileID = nil
                        }
                    }
                }
                .onMove(perform: onMoveProfiles)

                HStack {
                    Label("添加 NAS", systemImage: "plus")
                        .foregroundStyle(.blue)
                    Spacer()
                }
                .contentShape(Rectangle())
                .padding(.vertical, 4)
                .onTapGesture {
                    onAddNAS()
                }
            }

            if isFileModuleEnabled {
                Section("文件管理") {
                    NavigationLink(value: model.currentFileSection) {
                        Label("文件浏览器", systemImage: "folder.fill")
                            .foregroundStyle(.blue)
                    }
                    NavigationLink(value: WorkspaceSection.favorites) {
                        Label("收藏", systemImage: "star.fill")
                    }
                    NavigationLink(value: WorkspaceSection.recent) {
                        Label("最近访问", systemImage: "clock")
                    }
                    NavigationLink(value: WorkspaceSection.remoteLocations) {
                        Label("远程位置", systemImage: "network")
                    }
                    NavigationLink(value: WorkspaceSection.sharedLinks) {
                        Label("分享管理", systemImage: "link")
                    }
                }
            }

            if isPhotosModuleEnabled {
                Section("照片管理") {
                    NavigationLink(value: WorkspaceSection.photos) {
                        Label("照片", systemImage: "photo.on.rectangle.angled")
                            .foregroundStyle(.orange)
                    }
                }
            }

            Section {
                NavigationLink(value: WorkspaceSection.transfers) {
                    Label("传输中心", systemImage: "arrow.up.arrow.down.circle")
                        .badge(model.activeTransferCount)
                }
                NavigationLink(value: WorkspaceSection.settings) {
                    Label("设置", systemImage: "gearshape")
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 0) {
                Divider()
                StorageCapacityView(
                    summary: model.storageSpaceSummary,
                    isLoading: model.isLoadingStorageSpace
                )
                Divider()
                HStack(spacing: 10) {
                    Image(systemName: connectionRoute?.systemImage ?? "network")
                        .foregroundStyle(.green)
                        .frame(width: 20)
                        .accessibilityHidden(true)
                    Text(connectionRoute?.title ?? "已连接")
                        .font(.caption.weight(.medium))
                        .lineLimit(1)
                    Spacer(minLength: 6)
                    Button("退出") {
                        if model.activeTransferCount > 0 {
                            confirmsLogout = true
                        } else {
                            Task { await onLogout() }
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(.red)
                    .help("退出这台 NAS")
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
            }
            .background(.bar)
        }
        .alert("退出这台 NAS？", isPresented: $confirmsLogout) {
            Button("继续使用", role: .cancel) {}
            Button("退出并取消任务", role: .destructive) {
                Task { await onLogout() }
            }
        } message: {
            Text("还有 \(model.activeTransferCount) 个任务正在进行。退出后，这些任务会被取消。")
        }
    }
}

private struct StorageCapacityView: View {
    let summary: StorageSpaceSummary?
    let isLoading: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let summary {
                HStack(spacing: 6) {
                    Label("存储空间", systemImage: "internaldrive")
                        .font(.caption.weight(.semibold))
                    Spacer(minLength: 4)
                    Text(Self.format(summary.totalBytes))
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                ProgressView(value: summary.usedFraction)
                    .progressViewStyle(.linear)
                    .accessibilityLabel("存储空间使用情况")
                    .accessibilityValue(
                        "已使用 \(Self.format(summary.usedBytes))，剩余 \(Self.format(summary.remainingBytes))"
                    )
                Text("已用 \(Self.format(summary.usedBytes)) · 剩余 \(Self.format(summary.remainingBytes))")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                if summary.volumeCount > 1 {
                    Text("当前账号可见的 \(summary.volumeCount) 个存储空间合计")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            } else if isLoading {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("正在读取存储空间…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } else {
                Label("暂时无法读取存储空间", systemImage: "internaldrive")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .help("显示当前登录账号可访问的存储空间，不包含无权查看的存储空间。")
    }

    private static func format(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

private struct LocationCollectionView: View {
    let title: String
    let locations: [FavoriteLocation]
    let emptyMessage: String
    let onOpen: (String) -> Void
    var onRemove: ((FavoriteLocation) -> Void)? = nil

    var body: some View {
        Group {
            if locations.isEmpty {
                ContentUnavailableView(title, systemImage: "folder", description: Text(emptyMessage))
            } else {
                List(locations) { location in
                    HStack {
                        Button {
                            onOpen(location.path)
                        } label: {
                            Label {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(location.name)
                                    Text(location.path).font(.caption).foregroundStyle(.secondary)
                                }
                            } icon: {
                                Image(systemName: "folder.fill").foregroundStyle(.blue)
                            }
                        }
                        .buttonStyle(.plain)
                        Spacer()
                        if let onRemove {
                            Button("移除") { onRemove(location) }
                                .buttonStyle(.borderless)
                        }
                    }
                    .contentShape(Rectangle())
                }
            }
        }
        .navigationTitle(title)
    }
}

private struct RecentLocationsView: View {
    let locations: [FavoriteLocation]
    let onOpen: (FavoriteLocation) -> Void
    let onRemove: (FavoriteLocation) -> Void
    let onClearAll: () -> Void
    @State private var selection: FavoriteLocation.ID?
    @State private var confirmsClearAll = false

    var body: some View {
        Group {
            if locations.isEmpty {
                ContentUnavailableView(
                    "暂无最近访问",
                    systemImage: "clock",
                    description: Text("打开过的文件夹会显示在这里。")
                )
            } else {
                List(selection: $selection) {
                    ForEach(locations) { location in
                        HStack {
                            Label {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(location.name)
                                    Text(location.path).font(.caption).foregroundStyle(.secondary)
                                }
                            } icon: {
                                Image(systemName: "folder.fill").foregroundStyle(.blue)
                            }
                            Spacer()
                            Button("移除", systemImage: "xmark.circle") { onRemove(location) }
                                .labelStyle(.iconOnly)
                                .buttonStyle(.borderless)
                                .help("从最近访问中移除")
                        }
                        .contentShape(Rectangle())
                        .tag(location.id)
                        .onTapGesture(count: 2) { onOpen(location) }
                        .contextMenu {
                            Button("从最近访问中移除", role: .destructive) { onRemove(location) }
                        }
                    }
                }
                .toolbar {
                    Button("清除全部", systemImage: "trash") { confirmsClearAll = true }
                        .help("清除全部最近访问记录")
                }
            }
        }
        .navigationTitle("最近访问")
        .alert("清除全部最近访问记录？", isPresented: $confirmsClearAll) {
            Button("取消", role: .cancel) {}
            Button("清除全部", role: .destructive, action: onClearAll)
        } message: {
            Text("这只会清除本机保存的访问记录，不会删除 NAS 中的文件。")
        }
    }
}

private struct RemoteLocationsView: View {
    @Bindable var model: WorkspaceModel
    let onOpen: (FileItem) -> Void
    @State private var showsCreate = false
    @State private var editingItem: FileItem?
    @State private var removingItem: FileItem?

    private var defaultMountPoint: String {
        let parent = model.shares.first(where: { $0.permissions?.canWrite == true })?.path
            ?? model.shares.first?.path
            ?? "/home"
        return parent + "/远程位置"
    }

    var body: some View {
        Group {
            if model.remoteLocations.isEmpty {
                VStack(spacing: 16) {
                    ContentUnavailableView(
                        "没有远程位置",
                        systemImage: "network",
                        description: Text(
                            model.allowsRemoteMountManagement
                                ? "连接另一台设备上的共享文件夹后，会显示在这里。"
                                : "这台 NAS 暂不提供远程位置管理。"
                        )
                    )
                    if model.allowsRemoteMountManagement {
                        Button("连接远程位置") { showsCreate = true }
                    }
                }
            } else {
                List(model.remoteLocations) { location in
                    Button { onOpen(location) } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(location.name)
                                Text(remoteLocationDescription(location))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "network").foregroundStyle(.blue)
                        }
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button("打开") { onOpen(location) }
                        if model.allowsRemoteMountManagement {
                            Divider()
                            Button("修改连接…") { editingItem = location }
                            Button("删除远程位置…", role: .destructive) { removingItem = location }
                        }
                    }
                }
            }
        }
        .navigationTitle("远程位置")
        .toolbar {
            Button {
                showsCreate = true
            } label: {
                Label("连接远程位置", systemImage: "plus")
            }
            .disabled(!model.allowsRemoteMountManagement || model.isManagingRemoteMount)
            .help(
                model.allowsRemoteMountManagement
                    ? "连接另一台设备上的 SMB 或 NFS 共享文件夹"
                    : "这台 NAS 暂不提供远程位置管理"
            )
        }
        .sheet(isPresented: $showsCreate) {
            RemoteMountEditorView(
                existingItem: nil,
                initialMountPoint: defaultMountPoint
            ) { configuration in
                let succeeded = await model.createRemoteMount(configuration)
                return succeeded ? nil : (model.statusMessage ?? "远程位置没有连接成功，请检查设置后重试。")
            }
        }
        .sheet(item: $editingItem) { item in
            RemoteMountEditorView(
                existingItem: item,
                initialMountPoint: item.path
            ) { configuration in
                let succeeded = await model.updateRemoteMount(item, configuration: configuration)
                return succeeded ? nil : (model.statusMessage ?? "远程位置没有更新，请检查设置后重试。")
            }
        }
        .alert("删除这个远程位置？", isPresented: Binding(
            get: { removingItem != nil },
            set: { if !$0 { removingItem = nil } }
        )) {
            Button("取消", role: .cancel) { removingItem = nil }
            Button("删除远程位置", role: .destructive) {
                guard let item = removingItem else { return }
                removingItem = nil
                Task { _ = await model.removeRemoteMount(item) }
            }
        } message: {
            Text("只会断开这个远程位置，不会删除远程设备中的文件。")
        }
    }

    private func remoteLocationDescription(_ item: FileItem) -> String {
        let type = item.mountPointType?.lowercased() ?? ""
        let protocolName = type.contains("nfs") ? "NFS" : type.contains("cifs") || type.contains("smb") ? "SMB" : "远程存储"
        return "\(protocolName) · \(item.path)"
    }
}

private struct RemoteMountEditorView: View {
    let existingItem: FileItem?
    let onSave: (RemoteMountConfiguration) async -> String?

    @Environment(\.dismiss) private var dismiss
    @State private var protocolType: RemoteMountProtocol
    @State private var server = ""
    @State private var remotePath = ""
    @State private var mountPoint: String
    @State private var username = ""
    @State private var password = ""
    @State private var domain = ""
    @State private var readOnly = false
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    init(
        existingItem: FileItem?,
        initialMountPoint: String,
        onSave: @escaping (RemoteMountConfiguration) async -> String?
    ) {
        self.existingItem = existingItem
        self.onSave = onSave
        let rawType = existingItem?.mountPointType?.lowercased() ?? ""
        _protocolType = State(initialValue: rawType.contains("nfs") ? .nfs : .smb)
        _mountPoint = State(initialValue: initialMountPoint)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label(
                existingItem == nil ? "连接远程位置" : "修改远程位置",
                systemImage: "network"
            )
            .font(.title2.weight(.semibold))

            if existingItem != nil {
                Text("为保护连接密码，修改时需要重新填写远程地址和账号。保存时会短暂断开原连接。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                Text("把另一台设备上的共享文件夹连接到这台 NAS。")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Form {
                Picker("连接方式", selection: $protocolType) {
                    Text("SMB（常用）").tag(RemoteMountProtocol.smb)
                    Text("NFS").tag(RemoteMountProtocol.nfs)
                }
                TextField("服务器地址", text: $server, prompt: Text("例如 192.168.1.20"))
                TextField("远程共享文件夹", text: $remotePath, prompt: Text("例如 documents"))
                TextField("挂载到", text: $mountPoint, prompt: Text("例如 /home/远程资料"))

                if protocolType == .smb {
                    TextField("用户名", text: $username)
                    SecureField("密码", text: $password)
                    TextField("域（可选）", text: $domain)
                }
                Toggle("只读连接", isOn: $readOnly)
            }
            .formStyle(.grouped)

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.red)
                    .accessibilityLabel("连接失败：\(errorMessage)")
            }

            HStack {
                Spacer()
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .disabled(isSubmitting)
                Button(existingItem == nil ? "连接" : "保存修改") {
                    submit()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(!canSubmit || isSubmitting)
                .overlay(alignment: .leading) {
                    if isSubmitting {
                        ProgressView().controlSize(.small).offset(x: -24)
                    }
                }
            }
        }
        .padding(24)
        .frame(width: 520)
        .interactiveDismissDisabled(isSubmitting)
    }

    private var canSubmit: Bool {
        !server.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !remotePath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && mountPoint.trimmingCharacters(in: .whitespacesAndNewlines).hasPrefix("/")
    }

    private func submit() {
        guard canSubmit, !isSubmitting else { return }
        isSubmitting = true
        errorMessage = nil
        let configuration = RemoteMountConfiguration(
            protocolType: protocolType,
            server: server,
            remotePath: remotePath,
            mountPoint: mountPoint,
            username: username,
            password: password,
            domain: domain,
            readOnly: readOnly
        )
        Task {
            let failure = await onSave(configuration)
            isSubmitting = false
            if let failure {
                errorMessage = failure
            } else {
                password = ""
                dismiss()
            }
        }
    }
}

private struct ShareCreationView: View {
    @Bindable var model: WorkspaceModel
    let targets: [FileItem]
    let onClose: () -> Void
    @State private var password = ""
    @State private var expirationDays = 0
    @State private var isCreating = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("创建分享链接").font(.title2.weight(.semibold))
            Text(targets.count == 1 ? "分享“\(targets[0].name)”" : "分享所选的 \(targets.count) 个项目")
                .foregroundStyle(.secondary)
            Form {
                VStack(alignment: .leading, spacing: 4) {
                    SecureField("访问密码（可选）", text: $password)
                        .onChange(of: password) { _, value in
                            if value.count > 16 { password = String(value.prefix(16)) }
                        }
                    Text("最多 16 个字符").font(.caption).foregroundStyle(.secondary)
                }
                Picker("有效期", selection: $expirationDays) {
                    Text("长期有效").tag(0)
                    Text("7 天").tag(7)
                    Text("30 天").tag(30)
                    Text("90 天").tag(90)
                }
            }
            HStack {
                Spacer()
                Button("取消", role: .cancel, action: onClose)
                Button {
                    createLink()
                } label: {
                    if isCreating { ProgressView().controlSize(.small) } else { Text("创建并复制链接") }
                }
                .buttonStyle(.borderedProminent)
                .disabled(isCreating)
            }
        }
        .padding(24)
        .frame(width: 440)
    }

    private func createLink() {
        isCreating = true
        Task {
            let expiresAt: String?
            if expirationDays == 0 {
                expiresAt = nil
            } else {
                let date = Calendar.current.date(byAdding: .day, value: expirationDays, to: Date()) ?? Date()
                expiresAt = date.formatted(.iso8601.year().month().day())
            }
            if let link = await model.createShareLink(
                paths: targets.map(\.path),
                password: password.isEmpty ? nil : password,
                expiresAt: expiresAt
            ) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(link.url, forType: .string)
                onClose()
            }
            isCreating = false
        }
    }
}

private struct ShareLinksView: View {
    @Bindable var model: WorkspaceModel
    @State private var linkToDelete: FileShareLink?

    var body: some View {
        Group {
            if model.isLoadingShareLinks {
                ProgressView("正在读取分享…")
            } else if model.shareLinks.isEmpty {
                ContentUnavailableView(
                    "还没有分享链接",
                    systemImage: "link",
                    description: Text("在文件列表中选择项目，然后点按“分享”。")
                )
            } else {
                List(model.shareLinks) { link in
                    HStack(spacing: 12) {
                        Image(systemName: "link.circle.fill").foregroundStyle(.blue)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(link.name.isEmpty ? "已分享项目" : link.name)
                            HStack(spacing: 8) {
                                if link.hasPassword { Label("已设密码", systemImage: "lock.fill") }
                                if let expiration = link.expiresAt { Text("有效期至 \(expiration)") }
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("复制链接") {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(link.url, forType: .string)
                            model.statusIsError = false
                            model.statusMessage = "链接已复制。"
                        }
                        Button("取消分享", role: .destructive) { linkToDelete = link }
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .navigationTitle("分享管理")
        .task { await model.loadShareLinks() }
        .alert("取消这个分享？", isPresented: Binding(
            get: { linkToDelete != nil },
            set: { if !$0 { linkToDelete = nil } }
        )) {
            Button("保留", role: .cancel) { linkToDelete = nil }
            Button("取消分享", role: .destructive) {
                guard let link = linkToDelete else { return }
                linkToDelete = nil
                Task { await model.deleteShareLinks(ids: [link.id]) }
            }
        } message: {
            Text("取消后，收到这个链接的人将无法继续访问。")
        }
    }
}

private struct FileBrowserView: View {
    @Bindable var model: WorkspaceModel
    @Binding var viewMode: FileViewMode
    let fileGrouping: FileGrouping
    @Binding var showingInfoItem: FileItem?
    let onDownload: (FileItem, WorkspaceModel.FolderDownloadMode) -> Void
    let onDownloadBatch: ([FileItem]) -> Void
    let onShare: ([FileItem]) -> Void
    let onDelete: ([FileItem]) -> Void
    let onRestore: (FileItem) -> Void
    let onCopy: ([FileItem]) -> Void
    let onCut: ([FileItem]) -> Void
    let hasFileClipboard: Bool
    let onPaste: () -> Void
    
    @State private var sortOrder = [KeyPathComparator<FileItem>]()
    @State private var showsCreateFolderPrompt = false
    @State private var showsCreateFilePrompt = false
    @State private var renameTarget: FileItem?
    @State private var renameName = ""
    @State private var compressionTargets: [FileItem] = []
    @State private var extractionTarget: FileItem?
    @State private var newItemName = ""
    @State private var hoveredItemID: FileItem.ID?
    @State private var dropTargetItemID: FileItem.ID?
    @State private var gridItemFrames: [FileItem.ID: CGRect] = [:]
    @State private var marqueeStart: CGPoint?
    @State private var marqueeCurrent: CGPoint?
    @State private var marqueeBaseSelection: Set<FileItem.ID> = []
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private struct BreadcrumbItem: Identifiable {
        let id = UUID()
        let name: String
        let path: String
        let isLast: Bool
    }

    private struct FileGridGroup: Identifiable {
        let id: String
        let title: String?
        let items: [FileItem]
    }

    private var breadcrumbItems: [BreadcrumbItem] {
        var items: [BreadcrumbItem] = []
        let isRoot = model.currentPath.isEmpty || model.currentPath == "/"
        items.append(
            BreadcrumbItem(
                name: "文件管理",
                path: "/",
                isLast: isRoot
            )
        )
        if !isRoot {
            let components = model.currentPath.split(separator: "/").map(String.init)
            var currentAccumulatedPath = ""
            for (index, component) in components.enumerated() {
                currentAccumulatedPath += "/" + component
                let isLast = index == components.count - 1
                let displayName = component == "#recycle" ? "回收站" : component
                items.append(
                    BreadcrumbItem(
                        name: displayName,
                        path: currentAccumulatedPath,
                        isLast: isLast
                    )
                )
            }
        }
        return items
    }

    private var showsCompressionSheet: Binding<Bool> {
        Binding(
            get: { !compressionTargets.isEmpty },
            set: { presented in if !presented { compressionTargets.removeAll() } }
        )
    }

    private var archivePasswordBinding: Binding<WorkspaceModel.ArchivePasswordRequest?> {
        Binding(
            get: { model.archivePasswordRequest },
            set: { request in
                if request == nil, model.archivePasswordRequest != nil {
                    model.cancelArchivePasswordRequest()
                }
            }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Image(systemName: model.currentPath == "/" || model.currentPath.isEmpty ? "server.rack" : (model.currentPath.contains("#recycle") ? "trash" : "folder"))
                        .foregroundStyle(.secondary)
                    
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(breadcrumbItems) { item in
                                if item.path != "/" {
                                    Image(systemName: "chevron.right")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                
                                if item.isLast {
                                    Text(item.name)
                                        .font(.headline)
                                        .fontWeight(.bold)
                                        .foregroundStyle(.primary)
                                } else {
                                    Button {
                                        Task {
                                            await model.navigate(to: item.path)
                                        }
                                    } label: {
                                        Text(item.name)
                                            .font(.headline)
                                            .foregroundStyle(.blue)
                                    }
                                    .buttonStyle(.plain)
                                    .onHover { inside in
                                        if inside {
                                            NSCursor.pointingHand.push()
                                        } else {
                                            NSCursor.pop()
                                        }
                                    }
                                }
                            }
                        }
                    }
                    Spacer()
                    if model.isRefreshing {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Text(model.hasMore ? "已载入 \(model.items.count) / \(model.totalItemCount) 项" : "\(model.filteredItems.count) 项")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if model.hasMore {
                        Button {
                            Task { await model.loadMore() }
                        } label: {
                            if model.isLoadingMore {
                                ProgressView()
                                    .controlSize(.small)
                            } else {
                                Text("加载更多")
                            }
                        }
                        .buttonStyle(.borderless)
                        .disabled(model.isLoadingMore)
                    }
                }
                if let message = model.searchErrorMessage ?? model.statusMessage {
                    Label(
                        message,
                        systemImage: model.searchErrorMessage != nil || model.statusIsError
                            ? "exclamationmark.triangle.fill"
                            : "info.circle"
                    )
                        .font(.caption)
                        .foregroundStyle(model.searchErrorMessage != nil || model.statusIsError ? .red : .secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            if model.filteredItems.isEmpty {
                ContentUnavailableView(
                    model.searchText.isEmpty ? "目录为空" : "没有匹配项目",
                    systemImage: model.searchText.isEmpty ? "folder" : "magnifyingglass",
                    description: Text(model.searchText.isEmpty ? "可以上传文件到这个目录。" : "尝试其他搜索词。")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                if viewMode == .list {
                    fileTable
                } else {
                    fileGrid
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .overlay {
            if model.isLoading || model.isRefreshing || model.isSearching {
                ZStack {
                    Rectangle()
                        .fill(.ultraThinMaterial)
                        .background(Color.primary.opacity(0.035))
                    VStack(spacing: 12) {
                        ProgressView()
                            .controlSize(.regular)
                        Text(model.isSearching ? "正在搜索…" : (model.isLoading ? "正在读取目录…" : "正在打开文件夹…"))
                            .font(.callout.weight(.medium))
                        Text("请稍候，完成后即可继续操作。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 18)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
                    .shadow(color: .black.opacity(0.14), radius: 12, y: 5)
                }
                .contentShape(Rectangle())
                .accessibilityElement(children: .combine)
                .accessibilityLabel(model.isSearching ? "正在搜索，请稍候" : "正在加载文件夹，请稍候")
            } else if let undoMessage = model.recentDragMoveUndoMessage {
                VStack {
                    Spacer()
                    HStack(spacing: 12) {
                        Label(undoMessage, systemImage: "arrowshape.turn.up.backward.circle.fill")
                            .lineLimit(1)
                        Button("撤销") {
                            model.undoRecentDragMove()
                        }
                        .keyboardShortcut("z", modifiers: .command)
                        .disabled(model.isMovingItemsByDrag)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                    .shadow(radius: 8, y: 3)
                    .padding(.bottom, 18)
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("\(undoMessage)，可在十秒内撤销")
                }
            }
        }
        .searchable(text: $model.searchText, placement: .toolbar, prompt: "搜索文件")
        .searchScopes($model.searchScope) {
            ForEach(WorkspaceModel.SearchScope.allCases) { scope in
                Text(scope.title).tag(scope)
            }
        }
        .onChange(of: model.searchText) { _, _ in model.updateSearch() }
        .onChange(of: model.searchScope) { _, _ in model.updateSearch() }
        .dropDestination(for: URL.self) { urls, _ in
            model.enqueueUploads(urls)
            return true
        }
        .background {
            FileKeyboardShortcutHandler(
                onAction: handleFileShortcut
            )
        }
        .contextMenu {
            blankAreaContextMenu
        }
        .alert("新建文件夹", isPresented: $showsCreateFolderPrompt) {
            TextField("文件夹名称", text: $newItemName)
            Button("取消", role: .cancel) { newItemName = "" }
            Button("创建") {
                let name = newItemName
                newItemName = ""
                Task { await model.createFolder(named: name) }
            }
            .disabled(newItemName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } message: {
            Text("将在当前目录中创建一个文件夹。")
        }
        .alert("新建空白文件", isPresented: $showsCreateFilePrompt) {
            TextField("文件名，例如 说明.txt", text: $newItemName)
            Button("取消", role: .cancel) { newItemName = "" }
            Button("创建") {
                let name = newItemName
                newItemName = ""
                Task { await model.createEmptyFile(named: name) }
            }
            .disabled(newItemName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } message: {
            Text("将创建一个 0 字节文件；文件类型由扩展名决定。")
        }
        .alert("重命名", isPresented: Binding(
            get: { renameTarget != nil },
            set: { if !$0 { renameTarget = nil } }
        )) {
            TextField("新名称", text: $renameName)
            Button("取消", role: .cancel) {
                renameTarget = nil
            }
            Button("重命名") {
                guard let target = renameTarget else { return }
                let newName = renameName
                renameTarget = nil
                Task { await model.rename(target, to: newName) }
            }
            .disabled(renameName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } message: {
            Text("输入文件或文件夹的新名称。")
        }
        .sheet(isPresented: showsCompressionSheet) {
            ArchiveCreationView(targets: compressionTargets) { name, format, level, password in
                let targets = compressionTargets
                compressionTargets = []
                model.enqueueCompression(
                    targets,
                    archiveName: name,
                    format: format,
                    level: level,
                    password: password
                )
            } onCancel: {
                compressionTargets = []
            }
        }
        .sheet(item: $extractionTarget) { item in
            ArchiveExtractionView(item: item) { createSubfolder, keepDirectoryStructure, overwrite in
                extractionTarget = nil
                Task {
                    await model.prepareExtraction(
                        item,
                        createSubfolder: createSubfolder,
                        keepDirectoryStructure: keepDirectoryStructure,
                        overwrite: overwrite
                    )
                }
            } onCancel: {
                extractionTarget = nil
            }
        }
        .sheet(item: archivePasswordBinding) { request in
            ArchivePasswordView(
                archiveName: request.item.name,
                errorMessage: request.errorMessage,
                isChecking: model.isCheckingArchivePassword,
                onSubmit: { password in Task { await model.submitArchivePassword(password) } },
                onCancel: model.cancelArchivePasswordRequest
            )
        }
        .task(id: displayedItemIDs) {
            model.updateDisplayedItemOrder(displayedItems)
        }
        .navigationTitle(model.currentPath.isEmpty ? "文件" : (model.currentPath as NSString).lastPathComponent)
    }

    private var sortedItems: [FileItem] {
        model.filteredItems.sorted(using: sortOrder)
    }

    private var displayedItems: [FileItem] {
        viewMode == .grid ? fileGridGroups.flatMap(\.items) : sortedItems
    }

    private var displayedItemIDs: [FileItem.ID] {
        displayedItems.map(\.id)
    }

    private func selectIfUnselected(_ item: FileItem) {
        if !model.selection.contains(item.id) {
            DispatchQueue.main.async {
                model.selection = [item.id]
            }
        }
    }

    private func beginRename(_ item: FileItem) {
        guard canRename(item) else { return }
        model.selection = [item.id]
        renameName = item.name
        renameTarget = item
    }

    private func renameSelectedItem() {
        guard let item = model.selectedItem else { return }
        beginRename(item)
    }

    private func toggleQuickPreview() {
        guard let item = model.selectedItem,
              !item.isDirectory,
              PreviewKind.classify(item) != .unsupported else { return }
        if model.isPreviewPresented {
            model.dismissPreview()
        } else {
            model.preparePreview()
        }
    }

    private func handleFileShortcut(_ action: MacFileShortcut) {
        switch action {
        case .preview:
            toggleQuickPreview()
        case .rename:
            renameSelectedItem()
        case .open:
            guard let item = model.selectedItem else { return }
            Task { await model.open(item) }
        case .up:
            Task { await model.goUp() }
        case .selectAll:
            model.selection = Set(model.filteredItems.map(\.id))
        case .copy:
            guard !model.selectedItems.isEmpty else { return }
            onCopy(model.selectedItems)
        case .cut:
            guard !model.selectedItems.isEmpty else { return }
            onCut(model.selectedItems)
        case .paste:
            guard hasFileClipboard && canCreateItems else { return }
            onPaste()
        case .info:
            showingInfoItem = model.selectedItem
        case .delete:
            guard !model.selectedItems.isEmpty else { return }
            onDelete(model.selectedItems)
        case .undo:
            guard model.recentDragMoveUndoMessage != nil else { return }
            model.undoRecentDragMove()
        }
    }

    private func canRename(_ item: FileItem) -> Bool {
        // 重命名取决于父目录权限，文件本身的 write 标记在部分 DSM 版本中会误报。
        // 保留共享根目录和回收站保护，其余情况交给 NAS 接口执行最终权限校验。
        canCreateItems && !item.isRecyclePath
    }

    private func isSupportedArchive(_ item: FileItem) -> Bool {
        guard !item.isDirectory else { return false }
        return ["zip", "gz", "tar", "tgz", "tbz", "bz2", "rar", "7z", "iso"]
            .contains(item.fileExtension?.lowercased() ?? "")
    }

    @ViewBuilder
    private func contextMenuForFile(_ item: FileItem) -> some View {
        let targets = contextTargets(for: item)
        if item.isDirectory {
            Button("打开") {
                Task { await model.open(item) }
            }
        } else if PreviewKind.classify(item) != .unsupported {
            Button("预览") {
                Task { await model.open(item) }
            }
        }
        Button("重命名…") {
            beginRename(item)
        }
        .disabled(!canRename(item))
        .keyboardShortcut(.return, modifiers: [])
        Button(model.favorites.contains(where: { $0.path == item.path }) ? "取消收藏" : "添加到收藏") {
            model.toggleFavorite(item)
        }
        if canCreateItems && !item.isRecyclePath {
            Divider()
            Button(targets.count > 1 ? "压缩所选项目…" : "压缩…") {
                compressionTargets = targets
            }
            if targets.count == 1, isSupportedArchive(item) {
                Button("解压缩…") {
                    extractionTarget = item
                }
            }
        }
        if targets.count > 1 {
            Button("下载所选项目为压缩包…") { onDownloadBatch(targets) }
        } else if item.isDirectory {
            Button("下载为压缩包…") { onDownload(item, .archive) }
            Button("下载为文件夹…") { onDownload(item, .directory) }
        } else {
            Button("下载…") { onDownload(item, .archive) }
        }
        Button(targets.count > 1 ? "分享所选项目…" : "分享…") { onShare(targets) }
        Divider()
        Button("复制") {
            onCopy(contextTargets(for: item))
        }
        .keyboardShortcut("c", modifiers: .command)
        Button("剪切") {
            onCut(contextTargets(for: item))
        }
        .keyboardShortcut("x", modifiers: .command)
        Button("移动…") {
            onCut(contextTargets(for: item))
        }
        if item.isRecyclePath, model.allowsVerifiedRestore {
            Divider()
            Button("恢复到原位置…") { onRestore(item) }
        }
        Divider()
        Button("查看详情") {
            showingInfoItem = item
        }
        .keyboardShortcut("i", modifiers: .command)
        Divider()
        Button(item.isRecyclePath ? "永久删除…" : "删除…", role: .destructive) {
            onDelete([item])
        }
        .keyboardShortcut(.delete, modifiers: .command)
    }

    private func contextTargets(for item: FileItem) -> [FileItem] {
        model.selection.contains(item.id) && !model.selectedItems.isEmpty
            ? model.selectedItems
            : [item]
    }

    @ViewBuilder
    private var blankAreaContextMenu: some View {
        Button("刷新") {
            Task { await model.refresh() }
        }
        .disabled(model.isRefreshing)
        Divider()
        Button("粘贴") { onPaste() }
        .disabled(!hasFileClipboard || !canCreateItems)
        Divider()
        Button("新建文件夹…") {
            newItemName = "未命名文件夹"
            showsCreateFolderPrompt = true
        }
        .disabled(!canCreateItems)
        Button("新建空白文件…") {
            newItemName = "未命名.txt"
            showsCreateFilePrompt = true
        }
        .disabled(!canCreateItems)
    }

    private var canCreateItems: Bool {
        !model.currentPath.isEmpty && model.currentPath != "/" && !model.currentPath.split(separator: "/").contains("#recycle")
    }

    private var fileGrid: some View {
        GeometryReader { availableSpace in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 22) {
                    ForEach(fileGridGroups) { group in
                        VStack(alignment: .leading, spacing: 12) {
                            if let title = group.title {
                                HStack(spacing: 8) {
                                    Text(title)
                                        .font(.headline)
                                    Text("\(group.items.count) 项")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                }
                                .accessibilityElement(children: .combine)
                            }

                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 104, maximum: 104), spacing: 16)], spacing: 16) {
                                ForEach(group.items) { item in
                                    FileGridCell(
                                        model: model,
                                        item: item,
                                        isSelected: model.selection.contains(item.id),
                                        isDropTarget: dropTargetItemID == item.id,
                                        onSelect: {
                                            if NSEvent.modifierFlags.contains(.command) {
                                                if model.selection.contains(item.id) {
                                                    model.selection.remove(item.id)
                                                } else {
                                                    model.selection.insert(item.id)
                                                }
                                            } else {
                                                model.selection = [item.id]
                                            }
                                        },
                                        onOpen: {
                                            Task { await model.open(item) }
                                        },
                                        contextMenuContent: AnyView(
                                            contextMenuForFile(item)
                                        )
                                    )
                                    .background {
                                        GeometryReader { proxy in
                                            Color.clear.preference(
                                                key: FileGridFramePreferenceKey.self,
                                                value: [item.id: proxy.frame(in: .named("FileGridSelectionSpace"))]
                                            )
                                        }
                                    }
                                    .draggable(item.id)
                                    .dropDestination(for: String.self) { ids, _ in
                                        handleInternalDrop(ids, onto: item)
                                    } isTargeted: { isTargeted in
                                        updateDropTarget(item, isTargeted: isTargeted)
                                    }
                                }
                            }
                        }
                    }
                }
                .frame(minHeight: availableSpace.size.height, alignment: .top)
                .contentShape(Rectangle())
                .coordinateSpace(name: "FileGridSelectionSpace")
                .overlay(alignment: .topLeading) {
                    if let rectangle = marqueeRectangle {
                        Rectangle()
                            .fill(Color.accentColor.opacity(0.10))
                            .overlay {
                                Rectangle()
                                    .stroke(Color.accentColor.opacity(0.75), lineWidth: 1)
                            }
                            .frame(width: rectangle.width, height: rectangle.height)
                            .offset(x: rectangle.minX, y: rectangle.minY)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                }
                .simultaneousGesture(marqueeSelectionGesture)
                .simultaneousGesture(
                    SpatialTapGesture().onEnded { value in
                        if !gridItemFrames.values.contains(where: { $0.contains(value.location) }) {
                            model.selection.removeAll()
                        }
                    }
                )
                .onPreferenceChange(FileGridFramePreferenceKey.self) { gridItemFrames = $0 }
                .padding(16)
            }
            .background(Color(NSColor.controlBackgroundColor).opacity(0.2))
        }
    }

    private var marqueeRectangle: CGRect? {
        guard let start = marqueeStart, let current = marqueeCurrent else { return nil }
        return CGRect(
            x: min(start.x, current.x),
            y: min(start.y, current.y),
            width: abs(current.x - start.x),
            height: abs(current.y - start.y)
        )
    }

    private var marqueeSelectionGesture: some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .named("FileGridSelectionSpace"))
            .onChanged { value in
                if marqueeStart == nil {
                    guard !gridItemFrames.values.contains(where: { $0.contains(value.startLocation) }) else { return }
                    marqueeStart = value.startLocation
                    marqueeBaseSelection = NSEvent.modifierFlags.intersection([.command, .shift]).isEmpty
                        ? []
                        : model.selection
                }
                guard marqueeStart != nil else { return }
                marqueeCurrent = value.location
                guard let rectangle = marqueeRectangle else { return }
                let enclosed = Set(gridItemFrames.compactMap { id, frame in
                    frame.intersects(rectangle) ? id : nil
                })
                model.selection = marqueeBaseSelection.union(enclosed)
            }
            .onEnded { _ in
                marqueeStart = nil
                marqueeCurrent = nil
                marqueeBaseSelection.removeAll()
            }
    }

    private func updateDropTarget(_ item: FileItem, isTargeted: Bool) {
        guard item.isDirectory,
              !model.selectedItems.contains(where: { $0.id == item.id }) else {
            if dropTargetItemID == item.id { dropTargetItemID = nil }
            return
        }
        if isTargeted {
            dropTargetItemID = item.id
        } else if dropTargetItemID == item.id {
            dropTargetItemID = nil
        }
    }

    private var fileGridGroups: [FileGridGroup] {
        guard fileGrouping != .none else {
            return [FileGridGroup(id: "all", title: nil, items: sortedItems)]
        }

        var buckets: [String: [FileItem]] = [:]
        var titles: [String: String] = [:]
        for item in sortedItems {
            let group = gridGroup(for: item)
            buckets[group.id, default: []].append(item)
            titles[group.id] = group.title
        }

        return gridGroupOrder.compactMap { id in
            guard let items = buckets[id], !items.isEmpty else { return nil }
            return FileGridGroup(id: id, title: titles[id], items: items)
        }
    }

    private var gridGroupOrder: [String] {
        switch fileGrouping {
        case .none:
            ["all"]
        case .type:
            ["folder", "image", "video", "audio", "document", "other"]
        case .date:
            ["today", "yesterday", "week", "month", "earlier", "unknown-date"]
        case .size:
            ["folder", "tiny", "small", "medium", "large", "unknown-size"]
        }
    }

    private func gridGroup(for item: FileItem) -> (id: String, title: String) {
        switch fileGrouping {
        case .none:
            return ("all", "全部")
        case .type:
            if item.isDirectory { return ("folder", "文件夹") }
            switch PreviewKind.classify(item) {
            case .image: return ("image", "图片")
            case .video: return ("video", "视频")
            case .audio: return ("audio", "音频")
            case .pdf, .text: return ("document", "文档")
            case .unsupported: return ("other", "其他文件")
            }
        case .date:
            guard let date = item.times?.modifiedAt else { return ("unknown-date", "时间未知") }
            let calendar = Calendar.current
            if calendar.isDateInToday(date) { return ("today", "今天") }
            if calendar.isDateInYesterday(date) { return ("yesterday", "昨天") }
            if let week = calendar.dateInterval(of: .weekOfYear, for: Date()), week.contains(date) {
                return ("week", "本周")
            }
            if let month = calendar.dateInterval(of: .month, for: Date()), month.contains(date) {
                return ("month", "本月")
            }
            return ("earlier", "更早")
        case .size:
            if item.isDirectory { return ("folder", "文件夹") }
            guard let size = item.sizeBytes else { return ("unknown-size", "大小未知") }
            if size < 10 * 1_024 * 1_024 { return ("tiny", "小于 10 MB") }
            if size < 100 * 1_024 * 1_024 { return ("small", "10 MB – 100 MB") }
            if size < 1_024 * 1_024 * 1_024 { return ("medium", "100 MB – 1 GB") }
            return ("large", "1 GB 以上")
        }
    }

    private func handleInternalDrop(_ ids: [String], onto destination: FileItem) -> Bool {
        defer { dropTargetItemID = nil }
        guard canCreateItems,
              destination.isDirectory,
              let draggedID = ids.first,
              let draggedItem = model.filteredItems.first(where: { $0.id == draggedID }) else {
            return false
        }
        let targets = model.selection.contains(draggedID) && !model.selectedItems.isEmpty
            ? model.selectedItems
            : [draggedItem]
        model.moveByDragging(targets, to: destination)
        return true
    }

    private var fileTable: some View {
        Table(sortedItems, selection: $model.selection, sortOrder: $sortOrder) {
            TableColumn("名称", value: \.name) { item in
                hoverableTableCell(item) {
                    HStack(spacing: 8) {
                        FileIcon(item: item)
                        Text(item.name)
                            .lineLimit(1)
                    }
                    .contentShape(Rectangle())
                    .onDrag {
                        selectIfUnselected(item)
                        return NSItemProvider(object: item.id as NSString)
                    } preview: {
                        Label(item.name, systemImage: item.isDirectory ? "folder.fill" : "doc.fill")
                            .padding(8)
                    }
                }
            }
            .width(min: 220, ideal: 320)

            TableColumn("大小", value: \.sizeForSort) { item in
                hoverableTableCell(item) {
                    Text(item.isDirectory ? "—" : item.sizeBytes.map {
                        ByteCountFormatter.string(fromByteCount: $0, countStyle: .file)
                    } ?? "—")
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            .width(min: 80, ideal: 100)

            TableColumn("类型", value: \.fileTypeDisplay) { item in
                hoverableTableCell(item) {
                    Text(item.fileTypeDisplay)
                        .foregroundStyle(.secondary)
                }
            }
            .width(min: 80, ideal: 100)

            TableColumn("修改日期", value: \.modifiedTimeForSort) { item in
                hoverableTableCell(item) {
                    Group {
                        if let date = item.times?.modifiedAt {
                            Text(date, format: .dateTime.year().month().day().hour().minute())
                                .foregroundStyle(.secondary)
                        } else {
                            Text("—").foregroundStyle(.tertiary)
                        }
                    }
                }
            }
            .width(min: 130, ideal: 160)

            TableColumn("所有者", value: \.ownerForSort) { item in
                hoverableTableCell(item) {
                    Text(item.owner ?? "—")
                        .foregroundStyle(.secondary)
                }
            }
            .width(min: 80, ideal: 100)
        }
        .tableStyle(.inset(alternatesRowBackgrounds: false))
        .accessibilityLabel("\(model.currentPath) 文件列表")
        .background {
            TableDoubleClickHandler(items: sortedItems) { itemID in
                guard let item = sortedItems.first(where: { $0.id == itemID }) else { return }
                Task { await model.open(item) }
            }
        }
        .overlay {
            BlankTableContextMenuArea(
                canPaste: hasFileClipboard && canCreateItems,
                canCreateItems: canCreateItems,
                isRefreshing: model.isRefreshing,
                onPaste: onPaste,
                onCreateFolder: {
                    newItemName = "未命名文件夹"
                    showsCreateFolderPrompt = true
                },
                onCreateFile: {
                    newItemName = "未命名.txt"
                    showsCreateFilePrompt = true
                },
                onRefresh: {
                    Task { await model.refresh() }
                }
            )
            .id("BlankTableContext-\(hasFileClipboard)-\(canCreateItems)-\(model.isRefreshing)")
        }
        .contextMenu(forSelectionType: FileItem.ID.self) { selectedIds in
            if let firstId = selectedIds.first,
               let item = sortedItems.first(where: { $0.id == firstId }) {
                contextMenuForFile(item)
            } else {
                blankAreaContextMenu
            }
        }
    }

    private func hoverableTableCell<Content: View>(
        _ item: FileItem,
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .background {
                if dropTargetItemID == item.id {
                    Color.accentColor.opacity(0.20)
                } else if hoveredItemID == item.id, !model.selection.contains(item.id) {
                    Color.accentColor.opacity(0.10)
                }
            }
            .overlay {
                if dropTargetItemID == item.id {
                    RoundedRectangle(cornerRadius: 4)
                        .stroke(Color.accentColor.opacity(0.85), lineWidth: 2)
                        .padding(.vertical, 1)
                }
            }
            .dropDestination(for: String.self) { ids, _ in
                handleInternalDrop(ids, onto: item)
            } isTargeted: { isTargeted in
                updateDropTarget(item, isTargeted: isTargeted)
            }
            .onHover { isHovered in
                if isHovered {
                    hoveredItemID = item.id
                } else if hoveredItemID == item.id {
                    hoveredItemID = nil
                }
            }
            .animation(
                reduceMotion ? nil : .easeOut(duration: 0.15),
                value: hoveredItemID == item.id
            )
    }
}

private struct FileGridFramePreferenceKey: PreferenceKey {
    static let defaultValue: [FileItem.ID: CGRect] = [:]

    static func reduce(value: inout [FileItem.ID: CGRect], nextValue: () -> [FileItem.ID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { _, new in new })
    }
}

private enum MacFileShortcut {
    case preview, rename, open, up, selectAll, copy, cut, paste, info, delete, undo
}

private struct FileKeyboardShortcutHandler: NSViewRepresentable {
    let onAction: (MacFileShortcut) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onAction: onAction)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.attach(to: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.onAction = onAction
        context.coordinator.attach(to: nsView)
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.detach()
    }

    @MainActor
    final class Coordinator: NSObject {
        var onAction: (MacFileShortcut) -> Void
        private weak var hostView: NSView?
        private var monitor: Any?

        init(onAction: @escaping (MacFileShortcut) -> Void) {
            self.onAction = onAction
        }

        func attach(to view: NSView) {
            hostView = view
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { @MainActor [weak self] event in
                guard let self,
                      !event.isARepeat,
                      event.window === self.hostView?.window,
                      !self.isEditingText(in: event.window) else {
                    return event
                }
                let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
                let action: MacFileShortcut?
                if modifiers.isEmpty {
                    switch event.keyCode {
                    case 49: action = .preview // 空格
                    case 36, 76: action = .rename // Return 与数字键盘 Enter
                    default: action = nil
                    }
                } else if modifiers == .command {
                    switch event.keyCode {
                    case 0: action = .selectAll // ⌘A
                    case 6: action = .undo // ⌘Z
                    case 7: action = .cut // ⌘X
                    case 8: action = .copy // ⌘C
                    case 9: action = .paste // ⌘V
                    case 34: action = .info // ⌘I
                    case 51: action = .delete // ⌘Delete
                    case 125: action = .open // ⌘↓
                    case 126: action = .up // ⌘↑
                    default: action = nil
                    }
                } else {
                    action = nil
                }
                guard let action else { return event }
                self.onAction(action)
                return nil
            }
        }

        func detach() {
            if let monitor { NSEvent.removeMonitor(monitor) }
            monitor = nil
        }

        private func isEditingText(in window: NSWindow?) -> Bool {
            window?.firstResponder is NSTextView
        }
    }
}

private struct TableDoubleClickHandler: NSViewRepresentable {
    let items: [FileItem]
    let onOpen: (FileItem.ID) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        context.coordinator.attach(to: view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.items = items.map(\.id)
        context.coordinator.onOpen = onOpen
        context.coordinator.attach(to: nsView)
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.detach()
    }

    @MainActor
    final class Coordinator: NSObject {
        var items: [FileItem.ID] = []
        var onOpen: (FileItem.ID) -> Void = { _ in }
        private weak var hostView: NSView?
        private var monitor: Any?

        func attach(to view: NSView) {
            hostView = view
            guard monitor == nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { @MainActor [weak self] event in
                    guard let self,
                          event.clickCount == 2,
                          event.window === self.hostView?.window,
                          let table = self.tableView(at: event.locationInWindow, in: event.window) else {
                        return event
                    }
                    let row = table.row(at: table.convert(event.locationInWindow, from: nil))
                    guard self.items.indices.contains(row) else { return event }
                    self.onOpen(self.items[row])
                    return event
            }
        }

        func detach() {
            if let monitor {
                NSEvent.removeMonitor(monitor)
            }
            monitor = nil
        }

        private func tableView(at point: NSPoint, in window: NSWindow?) -> NSTableView? {
            guard let contentView = window?.contentView else { return nil }
            return findTable(in: contentView, point: point)
        }

        private func findTable(in view: NSView, point: NSPoint) -> NSTableView? {
            if let table = view as? NSTableView {
                let localPoint = table.convert(point, from: nil)
                if table.visibleRect.contains(localPoint), table.row(at: localPoint) >= 0 {
                    return table
                }
            }
            for subview in view.subviews.reversed() {
                if let table = findTable(in: subview, point: point) {
                    return table
                }
            }
            return nil
        }
    }
}

private struct BlankTableContextMenuArea: NSViewRepresentable {
    let canPaste: Bool
    let canCreateItems: Bool
    let isRefreshing: Bool
    let onPaste: () -> Void
    let onCreateFolder: () -> Void
    let onCreateFile: () -> Void
    let onRefresh: () -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> BlankTableContextNSView {
        let view = BlankTableContextNSView()
        view.coordinator = context.coordinator
        return view
    }

    func updateNSView(_ nsView: BlankTableContextNSView, context: Context) {
        context.coordinator.canPaste = canPaste
        context.coordinator.canCreateItems = canCreateItems
        context.coordinator.isRefreshing = isRefreshing
        context.coordinator.onPaste = onPaste
        context.coordinator.onCreateFolder = onCreateFolder
        context.coordinator.onCreateFile = onCreateFile
        context.coordinator.onRefresh = onRefresh
    }

    final class Coordinator: NSObject {
        var canPaste = false
        var canCreateItems = false
        var isRefreshing = false
        var onPaste: () -> Void = {}
        var onCreateFolder: () -> Void = {}
        var onCreateFile: () -> Void = {}
        var onRefresh: () -> Void = {}

        func showMenu(for event: NSEvent, in view: NSView) {
            let menu = NSMenu()
            
            let refreshItem = NSMenuItem(title: "刷新", action: #selector(refresh), keyEquivalent: "")
            refreshItem.target = self
            refreshItem.isEnabled = !isRefreshing
            menu.addItem(refreshItem)
            
            menu.addItem(.separator())
            
            let pasteItem = NSMenuItem(title: "粘贴", action: #selector(paste), keyEquivalent: "")
            pasteItem.target = self
            pasteItem.isEnabled = canPaste
            menu.addItem(pasteItem)
            
            menu.addItem(.separator())

            let folderItem = NSMenuItem(title: "新建文件夹…", action: #selector(createFolder), keyEquivalent: "")
            folderItem.target = self
            folderItem.isEnabled = canCreateItems
            menu.addItem(folderItem)

            let fileItem = NSMenuItem(title: "新建空白文件…", action: #selector(createFile), keyEquivalent: "")
            fileItem.target = self
            fileItem.isEnabled = canCreateItems
            menu.addItem(fileItem)
            
            NSMenu.popUpContextMenu(menu, with: event, for: view)
        }

        @objc private func refresh() { onRefresh() }
        @objc private func paste() { onPaste() }
        @objc private func createFolder() { onCreateFolder() }
        @objc private func createFile() { onCreateFile() }
    }
}

private final class BlankTableContextNSView: NSView {
    weak var coordinator: BlankTableContextMenuArea.Coordinator?

    override func hitTest(_ point: NSPoint) -> NSView? {
        guard let event = NSApp.currentEvent,
              event.type == .rightMouseDown,
              let table = tableView(atWindowPoint: event.locationInWindow) else {
            return nil
        }
        let tablePoint = table.convert(event.locationInWindow, from: nil)
        return table.row(at: tablePoint) == -1 ? self : nil
    }

    override func rightMouseDown(with event: NSEvent) {
        coordinator?.showMenu(for: event, in: self)
    }

    private func tableView(atWindowPoint windowPoint: NSPoint) -> NSTableView? {
        guard let window else { return nil }
        return window.contentView.flatMap { findTable(in: $0, windowPoint: windowPoint) }
    }

    private func findTable(in view: NSView, windowPoint: NSPoint) -> NSTableView? {
        if let table = view as? NSTableView,
           table.visibleRect.contains(table.convert(windowPoint, from: nil)) {
            return table
        }
        for subview in view.subviews.reversed() {
            if let table = findTable(in: subview, windowPoint: windowPoint) {
                return table
            }
        }
        return nil
    }
}

private struct ArchiveCreationView: View {
    let targets: [FileItem]
    let onCreate: (String, ArchiveFormat, ArchiveCompressionLevel, String?) -> Void
    let onCancel: () -> Void

    @State private var archiveName: String
    @State private var format: ArchiveFormat = .zip
    @State private var level: ArchiveCompressionLevel = .moderate
    @State private var password = ""
    @State private var showsPassword = false

    init(
        targets: [FileItem],
        onCreate: @escaping (String, ArchiveFormat, ArchiveCompressionLevel, String?) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.targets = targets
        self.onCreate = onCreate
        self.onCancel = onCancel
        let baseName = targets.count == 1 ? targets[0].name : "压缩项目"
        _archiveName = State(initialValue: "\(baseName).zip")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("创建压缩包", systemImage: "archivebox.fill")
                .font(.title2.weight(.semibold))
            Text(targets.count == 1 ? "压缩“\(targets[0].name)”" : "压缩所选的 \(targets.count) 个项目")
                .foregroundStyle(.secondary)
            Form {
                TextField("压缩包名称", text: $archiveName)
                Picker("格式", selection: $format) {
                    Text("ZIP（兼容性更好）").tag(ArchiveFormat.zip)
                    Text("7z（通常更节省空间）").tag(ArchiveFormat.sevenZip)
                }
                .onChange(of: format) { _, newFormat in
                    let desired = newFormat == .zip ? "zip" : "7z"
                    let current = (archiveName as NSString).pathExtension
                    if !current.isEmpty {
                        archiveName = (archiveName as NSString).deletingPathExtension + "." + desired
                    }
                }
                Picker("压缩程度", selection: $level) {
                    Text("均衡（推荐）").tag(ArchiveCompressionLevel.moderate)
                    Text("仅打包，不压缩").tag(ArchiveCompressionLevel.store)
                    Text("更快完成").tag(ArchiveCompressionLevel.fastest)
                    Text("尽量节省空间").tag(ArchiveCompressionLevel.best)
                }
                HStack {
                    Group {
                        if showsPassword {
                            TextField("密码（可选）", text: $password)
                        } else {
                            SecureField("密码（可选）", text: $password)
                        }
                    }
                    Button(showsPassword ? "隐藏" : "显示") { showsPassword.toggle() }
                        .buttonStyle(.borderless)
                }
            }
            Text("压缩过程由 NAS 完成，关闭此窗口后可在传输中心查看进度。")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("取消", role: .cancel, action: onCancel)
                Button("开始压缩") {
                    onCreate(archiveName, format, level, password.isEmpty ? nil : password)
                }
                .buttonStyle(.borderedProminent)
                .disabled(archiveName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(24)
        .frame(width: 500)
    }
}

private struct ArchiveExtractionView: View {
    let item: FileItem
    let onExtract: (Bool, Bool, Bool) -> Void
    let onCancel: () -> Void

    @State private var createSubfolder = true
    @State private var keepDirectoryStructure = true
    @State private var overwrite = false
    @State private var confirmsOverwrite = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label("解压缩", systemImage: "archivebox.fill")
                .font(.title2.weight(.semibold))
            Text("将“\(item.name)”解压到当前文件夹")
                .foregroundStyle(.secondary)
            Form {
                Toggle("创建同名文件夹", isOn: $createSubfolder)
                Toggle("保留压缩包内的文件夹结构", isOn: $keepDirectoryStructure)
                Toggle("替换同名文件", isOn: $overwrite)
                if overwrite {
                    Label("已有的同名文件可能会被替换。开始前会再次确认。", systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            Text("支持 ZIP、7z、RAR、TAR、GZ、BZ2 和 ISO 等常见格式。")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("取消", role: .cancel, action: onCancel)
                Button("开始解压") {
                    if overwrite {
                        confirmsOverwrite = true
                    } else {
                        startExtraction()
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(width: 500)
        .alert("替换同名文件？", isPresented: $confirmsOverwrite) {
            Button("取消", role: .cancel) {}
            Button("替换并继续", role: .destructive, action: startExtraction)
        } message: {
            Text("当前文件夹中已有的同名文件可能会被替换，原内容可能无法恢复。")
        }
    }

    private func startExtraction() {
        onExtract(createSubfolder, keepDirectoryStructure, overwrite)
    }
}

private struct ArchivePasswordView: View {
    let archiveName: String
    let errorMessage: String?
    let isChecking: Bool
    let onSubmit: (String) -> Void
    let onCancel: () -> Void
    @State private var password = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label("需要压缩包密码", systemImage: "lock.fill")
                .font(.title2.weight(.semibold))
            Text("“\(archiveName)”已加密，请输入密码后继续解压。")
                .foregroundStyle(.secondary)
            SecureField("压缩包密码", text: $password)
                .textFieldStyle(.roundedBorder)
                .onSubmit { submit() }
            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.circle.fill")
                    .font(.callout)
                    .foregroundStyle(.red)
            }
            HStack {
                if isChecking { ProgressView().controlSize(.small) }
                Spacer()
                Button("取消", role: .cancel, action: onCancel)
                Button("继续解压", action: submit)
                    .buttonStyle(.borderedProminent)
                    .disabled(password.isEmpty || isChecking)
            }
        }
        .padding(24)
        .frame(width: 440)
    }

    private func submit() {
        guard !password.isEmpty, !isChecking else { return }
        onSubmit(password)
        password = ""
    }
}

struct FileIcon: View {
    let item: FileItem

    var body: some View {
        Image(systemName: symbol)
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(color)
            .frame(width: 22)
            .accessibilityHidden(true)
    }

    private var symbol: String {
        if item.name == "#recycle" { return "trash.square.fill" }
        if item.isDirectory { return "folder.fill" }
        switch PreviewKind.classify(item) {
        case .image: return "photo.fill"
        case .pdf: return "doc.richtext.fill"
        case .text: return "doc.text.fill"
        case .video: return "video.fill"
        case .audio: return "waveform.circle.fill"
        case .unsupported:
            if ["zip", "rar", "7z", "tar", "gz"].contains(item.fileExtension ?? "") {
                return "archivebox.fill"
            }
            return "doc.fill"
        }
    }

    private var color: Color {
        if item.name == "#recycle" { return .orange }
        if item.isDirectory { return .blue }
        switch PreviewKind.classify(item) {
        case .image: return .purple
        case .pdf: return .red
        case .text: return .secondary
        case .video: return .blue
        case .audio: return .green
        case .unsupported: return .orange
        }
    }
}

private struct FilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption)
                .fontWeight(.medium)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    Capsule()
                        .fill(isSelected ? Color.blue : Color.secondary.opacity(0.12))
                )
                .foregroundStyle(isSelected ? Color.white : Color.primary.opacity(0.85))
        }
        .buttonStyle(.plain)
    }
}

private struct TransferCenterView: View {
    @Bindable var model: WorkspaceModel
    let connectedWorkspaces: [WorkspaceModel]

    @State private var selectedNasID: UUID?
    @State private var activeFilter: TaskFilterType? = nil

    private enum TaskFilterType: Hashable {
        case upload
        case download
        case fileOperation
        case completed
        case failed

        var displayName: String {
            switch self {
            case .upload: return "上传"
            case .download: return "下载"
            case .fileOperation: return "文件操作"
            case .completed: return "已完成"
            case .failed: return "已失败"
            }
        }
    }

    private var allConnectedTasks: [ActivityTask] {
        connectedWorkspaces.flatMap { $0.transfers }
    }

    private var baseTasks: [ActivityTask] {
        if let selectedNasID {
            if let ws = connectedWorkspaces.first(where: { $0.profile.id == selectedNasID }) {
                return ws.transfers
            }
            return []
        } else {
            return allConnectedTasks
        }
    }

    private func isTaskFinished(_ task: ActivityTask) -> Bool {
        task.state == .succeeded || task.state == .failed || task.state == .cancelled
    }

    private var availableFilters: [TaskFilterType] {
        var filters: [TaskFilterType] = []
        if baseTasks.contains(where: { $0.kind == .upload && !isTaskFinished($0) }) {
            filters.append(.upload)
        }
        if baseTasks.contains(where: { $0.kind == .download && !isTaskFinished($0) }) {
            filters.append(.download)
        }
        if baseTasks.contains(where: { ($0.kind == .copy || $0.kind == .move || $0.kind == .delete || $0.kind == .restore || $0.kind == .compress || $0.kind == .extract) && !isTaskFinished($0) }) {
            filters.append(.fileOperation)
        }
        if baseTasks.contains(where: { $0.state == .succeeded }) {
            filters.append(.completed)
        }
        if baseTasks.contains(where: { $0.state == .failed || $0.state == .cancelled }) {
            filters.append(.failed)
        }
        return filters
    }

    private var currentActiveFilter: TaskFilterType? {
        let available = availableFilters
        if let activeFilter, available.contains(activeFilter) {
            return activeFilter
        }
        return nil
    }

    private var filteredTasks: [ActivityTask] {
        let tasks = baseTasks
        guard let filter = currentActiveFilter else {
            return tasks
        }
        switch filter {
        case .upload:
            return tasks.filter { $0.kind == .upload && !isTaskFinished($0) }
        case .download:
            return tasks.filter { $0.kind == .download && !isTaskFinished($0) }
        case .fileOperation:
            return tasks.filter { ($0.kind == .copy || $0.kind == .move || $0.kind == .delete || $0.kind == .restore || $0.kind == .compress || $0.kind == .extract) && !isTaskFinished($0) }
        case .completed:
            return tasks.filter { $0.state == .succeeded }
        case .failed:
            return tasks.filter { $0.state == .failed || $0.state == .cancelled }
        }
    }

    private func countForFilter(_ filter: TaskFilterType) -> Int {
        switch filter {
        case .upload:
            return baseTasks.filter { $0.kind == .upload && !isTaskFinished($0) }.count
        case .download:
            return baseTasks.filter { $0.kind == .download && !isTaskFinished($0) }.count
        case .fileOperation:
            return baseTasks.filter { ($0.kind == .copy || $0.kind == .move || $0.kind == .delete || $0.kind == .restore || $0.kind == .compress || $0.kind == .extract) && !isTaskFinished($0) }.count
        case .completed:
            return baseTasks.filter { $0.state == .succeeded }.count
        case .failed:
            return baseTasks.filter { $0.state == .failed || $0.state == .cancelled }.count
        }
    }

    private var canClearCompleted: Bool {
        if let selectedNasID {
            if let ws = connectedWorkspaces.first(where: { $0.profile.id == selectedNasID }) {
                return ws.transfers.contains(where: { $0.state == .succeeded || $0.state == .cancelled })
            }
            return false
        } else {
            return connectedWorkspaces.contains(where: { ws in
                ws.transfers.contains(where: { $0.state == .succeeded || $0.state == .cancelled })
            })
        }
    }

    private func clearCompleted() {
        if let selectedNasID {
            if let ws = connectedWorkspaces.first(where: { $0.profile.id == selectedNasID }) {
                ws.clearCompletedTransfers()
            }
        } else {
            for ws in connectedWorkspaces {
                ws.clearCompletedTransfers()
            }
        }
    }

    var body: some View {
        Group {
            if allConnectedTasks.isEmpty {
                ContentUnavailableView(
                    "暂无传输任务",
                    systemImage: "arrow.up.arrow.down.circle",
                    description: Text("上传、下载和文件操作会显示在这里。")
                )
            } else {
                VStack(spacing: 0) {
                    HStack {
                        Text("\(model.profile.displayName) · 上传、下载和文件操作")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 6)

                    HStack(spacing: 12) {
                        if connectedWorkspaces.count > 1 {
                            HStack(spacing: 6) {
                                Text("NAS:")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                
                                FilterChip(title: "全部", isSelected: selectedNasID == nil) {
                                    selectedNasID = nil
                                }
                                
                                ForEach(connectedWorkspaces, id: \.profile.id) { ws in
                                    FilterChip(title: ws.profile.displayName, isSelected: selectedNasID == ws.profile.id) {
                                        selectedNasID = ws.profile.id
                                    }
                                }
                            }
                            
                            Divider()
                                .frame(height: 14)
                                .foregroundStyle(.secondary.opacity(0.3))
                        }

                        let activeFilters = availableFilters
                        if !activeFilters.isEmpty {
                            HStack(spacing: 6) {
                                Text("类型:")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                
                                FilterChip(title: "全部", isSelected: currentActiveFilter == nil) {
                                    activeFilter = nil
                                }
                                
                                ForEach(activeFilters, id: \.self) { filter in
                                    let count = countForFilter(filter)
                                    FilterChip(title: "\(filter.displayName) (\(count))", isSelected: currentActiveFilter == filter) {
                                        if activeFilter == filter {
                                            activeFilter = nil
                                        } else {
                                            activeFilter = filter
                                        }
                                    }
                                }
                            }
                        }
                        
                        Spacer()
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)

                    Divider()

                    if filteredTasks.isEmpty {
                        ContentUnavailableView(
                            "没有匹配的传输任务",
                            systemImage: "arrow.up.arrow.down.circle",
                            description: Text("当前过滤条件下没有任务显示，可尝试切换标签。")
                        )
                    } else {
                        ScrollView {
                            LazyVStack(spacing: 12) {
                                ForEach(filteredTasks) { task in
                                    let taskWorkspace = connectedWorkspaces.first(where: { ws in
                                        ws.transfers.contains(where: { $0.id == task.id })
                                    }) ?? model

                                    TransferRow(
                                        task: task,
                                        onPause: { taskWorkspace.pauseTransfer(task.id) },
                                        onResume: { taskWorkspace.resumeTransfer(task.id) },
                                        onRetry: { taskWorkspace.retryTransfer(task.id) },
                                        onCancel: { taskWorkspace.cancelTransfer(task.id) },
                                        onDelete: { taskWorkspace.deleteTransfer(task.id) }
                                    )
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                        }
                    }
                }
            }
        }
        .onAppear {
            if selectedNasID == nil {
                selectedNasID = model.profile.id
            }
        }
    }
}

private struct TransferRow: View {
    let task: ActivityTask
    let onPause: () -> Void
    let onResume: () -> Void
    let onRetry: () -> Void
    let onCancel: () -> Void
    let onDelete: () -> Void
    
    @State private var isConfirmingDeletion = false
    @State private var isHovered = false

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // 头部：图标 + 文件名/路径 + 状态 Badge
            HStack(alignment: .center, spacing: 12) {
                // 圆形高亮类型图标
                ZStack {
                    Circle()
                        .fill(iconThemeColor.opacity(0.12))
                        .frame(width: 36, height: 36)
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(iconThemeColor)
                }
                .accessibilityHidden(true)
                
                // 任务名称与详情路径
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(task.displayName)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.primary)
                            .lineLimit(1)
                        
                        Text(kindBadgeLabel)
                            .font(.system(size: 10, weight: .medium))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.primary.opacity(0.06))
                            .foregroundStyle(.secondary)
                            .clipShape(Capsule())
                    }
                    
                    if let failure = task.failureMessage {
                        Text(failure)
                            .font(.caption)
                            .foregroundStyle(.red)
                            .lineLimit(1)
                    } else {
                        Text(task.remotePath)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
                
                Spacer(minLength: 8)
                
                // 状态彩色胶囊 Tag
                Text(stateLabel)
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(stateBadgeBackground)
                    .foregroundStyle(stateBadgeForeground)
                    .clipShape(Capsule())
            }

            // 进度条
            if let total = task.totalUnits, total > 0 {
                ProgressView(
                    value: Double(min(max(task.completedUnits, 0), total)),
                    total: Double(total)
                )
                .progressViewStyle(.linear)
                .tint(progressTint)
                .accessibilityLabel("\(task.displayName)传输进度")
                .accessibilityValue(progressAccessibilityValue(total: total))
            } else if task.state == .running || task.state == .cancelling {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            // 底部元信息与突出显眼的操作按钮区
            HStack(alignment: .center, spacing: 8) {
                if let transferDetails {
                    Text(transferDetails)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                
                Spacer()

                HStack(spacing: 8) {
                    if task.state == .running, task.kind == .download || task.kind == .upload {
                        TransferActionButton(icon: "pause.fill", label: "暂停", color: .blue, action: onPause)
                    } else if task.state == .paused {
                        TransferActionButton(icon: "play.fill", label: task.kind == .upload ? "重新上传" : "继续", color: .green, action: onResume)
                    } else if task.state == .failed || task.state == .cancelled {
                        TransferActionButton(icon: "arrow.clockwise", label: "重试", color: .blue, action: onRetry)
                    }
                    
                    if task.state == .queued || task.state == .running || task.state == .paused {
                        TransferActionButton(icon: "xmark", label: "取消", color: .orange, action: onCancel)
                    }
                    
                    // 醒目明确的删除任务按钮
                    TransferDeleteButton(
                        label: isFinishedState ? "删除记录" : "删除任务",
                        action: {
                            if !isFinishedState {
                                isConfirmingDeletion = true
                            } else {
                                onDelete()
                            }
                        }
                    )
                }
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(NSColor.controlBackgroundColor))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isHovered ? Color.accentColor.opacity(0.35) : Color.primary.opacity(0.08), lineWidth: 1)
        )
        .onHover { inside in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = inside
            }
        }
        .accessibilityElement(children: .combine)
        .contextMenu {
            if task.state == .running, task.kind == .download || task.kind == .upload {
                Button("暂停", action: onPause)
            }
            if task.state == .paused {
                Button(task.kind == .upload ? "重新上传" : "继续", action: onResume)
            }
            if task.state == .failed || task.state == .cancelled {
                Button("重试", action: onRetry)
            }
            if task.state == .queued || task.state == .running || task.state == .paused {
                Button("取消任务", action: onCancel)
            }
            Divider()
            Button(
                isFinishedState ? "删除传输记录" : "取消并删除任务",
                role: .destructive,
                action: {
                    if !isFinishedState {
                        isConfirmingDeletion = true
                    } else {
                        onDelete()
                    }
                }
            )
        }
        .confirmationDialog(
            "删除这个传输任务？",
            isPresented: $isConfirmingDeletion,
            titleVisibility: .visible
        ) {
            Button(
                "取消并删除任务",
                role: .destructive,
                action: onDelete
            )
            Button("保留任务", role: .cancel) {}
        } message: {
            Text(task.kind == .download
                ? "任务记录和未下载完成的临时文件都会被删除。"
                : "任务记录会被删除，正在进行的操作也会先取消。")
        }
    }

    private var isFinishedState: Bool {
        task.state == .succeeded || task.state == .failed || task.state == .cancelled
    }

    private var icon: String {
        switch task.kind {
        case .upload: "arrow.up"
        case .download: "arrow.down"
        case .copy: "doc.on.doc"
        case .move: "folder.badge.gearshape"
        case .delete: "trash"
        case .restore: "arrow.uturn.backward"
        case .compress: "archivebox"
        case .extract: "doc.zipper"
        }
    }

    private var iconThemeColor: Color {
        switch task.kind {
        case .upload: .blue
        case .download: .green
        case .copy, .move: .purple
        case .delete: .red
        case .restore: .orange
        case .compress, .extract: .indigo
        }
    }

    private var kindBadgeLabel: String {
        switch task.kind {
        case .upload: "上传"
        case .download: "下载"
        case .copy: "复制"
        case .move: "移动"
        case .delete: "删除"
        case .restore: "恢复"
        case .compress: "压缩"
        case .extract: "解压"
        }
    }

    private var stateBadgeBackground: Color {
        switch task.state {
        case .succeeded: .green.opacity(0.12)
        case .failed: .red.opacity(0.12)
        case .paused: .orange.opacity(0.12)
        case .cancelled: .secondary.opacity(0.12)
        default: .blue.opacity(0.12)
        }
    }

    private var stateBadgeForeground: Color {
        switch task.state {
        case .succeeded: .green
        case .failed: .red
        case .paused: .orange
        case .cancelled: .secondary
        default: .blue
        }
    }

    private var progressTint: Color {
        switch task.state {
        case .succeeded: .green
        case .failed: .red
        case .paused: .orange
        default: .blue
        }
    }

    private var stateLabel: String {
        switch task.state {
        case .queued: return "等待中"
        case .running:
            if let total = task.totalUnits, total > 0 {
                let percentage = Int((Double(task.completedUnits) / Double(total) * 100).rounded())
                return "\(min(max(percentage, 0), 100))%"
            }
            return "进行中"
        case .paused: return task.kind == .upload ? "已暂停（继续重传）" : "已暂停"
        case .cancelling: return "正在取消"
        case .succeeded: return "已完成"
        case .failed: return "失败"
        case .cancelled: return "已取消"
        }
    }

    private var transferDetails: String? {
        guard task.kind == .upload
                || task.kind == .download
                || task.kind == .copy
                || task.kind == .move else {
            return nil
        }

        var parts: [String] = []
        if let fileSize = task.fileSizeBytes {
            parts.append("大小 \(formatBytes(fileSize))")
        }
        if let total = task.totalUnits, total > 0 {
            let prefix: String
            if (task.kind == .copy || task.kind == .move), task.fileSizeBytes != nil {
                prefix = "中转 "
            } else if task.kind == .copy || task.kind == .move {
                prefix = "进度 "
            } else {
                prefix = ""
            }
            parts.append("\(prefix)\(formatBytes(task.completedUnits)) / \(formatBytes(total))")
        } else if task.completedUnits > 0 {
            parts.append("已完成 \(formatBytes(task.completedUnits))")
        }
        if let speed = task.bytesPerSecond, speed > 0,
           task.state == .running || task.state == .cancelling {
            parts.append("\(formatBytes(Int64(speed)))/s")
        }
        if let remaining = task.estimatedSecondsRemaining, remaining.isFinite, remaining > 0,
           task.state == .running {
            parts.append("剩余 \(formatDuration(remaining))")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: max(bytes, 0), countStyle: .file)
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let rounded = max(Int(seconds.rounded(.up)), 1)
        if rounded < 60 {
            return "\(rounded)秒"
        }
        if rounded < 3_600 {
            return "\((rounded + 59) / 60)分钟"
        }
        let hours = rounded / 3_600
        let minutes = (rounded % 3_600 + 59) / 60
        return minutes > 0 ? "\(hours)小时\(minutes)分" : "\(hours)小时"
    }

    private func progressAccessibilityValue(total: Int64) -> String {
        let percentage = Int((Double(task.completedUnits) / Double(total) * 100).rounded())
        return "\(min(max(percentage, 0), 100))%"
    }
}

private struct TransferActionButton: View {
    let icon: String
    let label: String
    let color: Color
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .bold))
                Text(label)
                    .font(.system(size: 11, weight: .semibold))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isHovered ? color.opacity(0.18) : color.opacity(0.10))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(color.opacity(0.25), lineWidth: 1)
        )
        .foregroundStyle(color)
        .onHover { inside in
            withAnimation(.easeInOut(duration: 0.12)) {
                isHovered = inside
            }
        }
    }
}

private struct TransferDeleteButton: View {
    let label: String
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                Image(systemName: "trash.fill")
                    .font(.system(size: 10, weight: .bold))
                Text(label)
                    .font(.system(size: 11, weight: .bold))
            }
            .foregroundStyle(Color.red)
            .padding(.horizontal, 9)
            .padding(.vertical, 4.5)
            .background(
                RoundedRectangle(cornerRadius: 6)
                    .fill(isHovered ? Color.red.opacity(0.18) : Color.red.opacity(0.10))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(Color.red.opacity(0.25), lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { inside in
            withAnimation(.easeInOut(duration: 0.12)) {
                isHovered = inside
            }
        }
        .help("删除此传输任务记录")
    }
}


private struct SettingsSectionCard<Content: View>: View {
    let title: String
    let icon: String
    let iconColor: Color
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.headline)
                    .foregroundStyle(iconColor)
                Text(title)
                    .font(.headline.weight(.semibold))
            }
            
            VStack(alignment: .leading, spacing: 12) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(NSColor.controlBackgroundColor).opacity(0.4))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.secondary.opacity(0.12), lineWidth: 1)
        )
    }
}

private struct SettingsRow: View {
    let label: String
    let value: String
    var isMonospaced: Bool = false

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .foregroundStyle(.secondary)
                .layoutPriority(1)
            Spacer()
            Text(value)
                .foregroundStyle(.primary)
                .font(isMonospaced ? .system(.body, design: .monospaced) : .body)
                .textSelection(.enabled)
                .multilineTextAlignment(.trailing)
        }
    }
}

struct CacheCleanupOptions: OptionSet {
    let rawValue: Int
    static let safeTrash = CacheCleanupOptions(rawValue: 1 << 0)
    static let photoCache = CacheCleanupOptions(rawValue: 1 << 1)
    static let all: CacheCleanupOptions = [.safeTrash, .photoCache]
}

private struct AppStorageSnapshot {
    let previewCache: Int64
    let photoCache: Int64
    let systemCache: Int64
    let protectedData: Int64

    var safeTrash: Int64 { previewCache + systemCache }
    var reclaimable: Int64 { safeTrash + photoCache }
    var total: Int64 { reclaimable + protectedData }
}

private enum AppStorageInspector {
    static func snapshot() -> AppStorageSnapshot {
        AppStorageSnapshot(
            previewCache: size(of: previewDirectory),
            photoCache: size(of: photoCacheDirectory) + size(of: photoThumbnailDirectory),
            systemCache: size(of: cacheDirectory),
            protectedData: size(of: secureDataDirectory)
        )
    }

    static func clearReclaimableData(options: CacheCleanupOptions = .safeTrash) throws {
        if options.contains(.safeTrash) {
            try removeContents(of: previewDirectory, expectedLastComponent: "LanStashPreview")
            if let bundleID = Bundle.main.bundleIdentifier {
                try removeContents(of: cacheDirectory, expectedLastComponent: bundleID)
            }
            URLCache.shared.removeAllCachedResponses()
        }
        if options.contains(.photoCache) {
            try removeContents(of: photoCacheDirectory, expectedLastComponent: "lanstash-photo-cache")
            try removeContents(of: photoThumbnailDirectory, expectedLastComponent: "lanstash-photo-thumbnails")
        }
    }

    private static var photoCacheDirectory: URL {
        let root = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        return root.appendingPathComponent("lanstash-photo-cache", isDirectory: true)
    }

    private static var photoThumbnailDirectory: URL {
        let root = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        return root.appendingPathComponent("lanstash-photo-thumbnails", isDirectory: true)
    }

    private static var previewDirectory: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent("LanStashPreview", isDirectory: true)
    }

    private static var cacheDirectory: URL {
        let root = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        return root.appendingPathComponent(Bundle.main.bundleIdentifier ?? "io.github.qwertyuiop1995.dsmnativeclient", isDirectory: true)
    }

    private static var secureDataDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
            .appendingPathComponent("LanStashSecureStore", isDirectory: true)
    }

    private static func size(of root: URL) -> Int64 {
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .fileSizeKey],
            options: []
        ) else { return 0 }
        var total: Int64 = 0
        for case let url as URL in enumerator {
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            if values?.isRegularFile == true { total += Int64(values?.fileSize ?? 0) }
        }
        return total
    }

    private static func removeContents(of directory: URL, expectedLastComponent: String) throws {
        guard directory.lastPathComponent == expectedLastComponent else { return }
        let manager = FileManager.default
        guard manager.fileExists(atPath: directory.path) else { return }
        for child in try manager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
            try manager.removeItem(at: child)
        }
    }
}

private struct SettingsView: View {
    @Bindable var model: WorkspaceModel
    let onRenameNAS: (String) -> String?
    @State private var showsRenamePrompt = false
    @State private var renamedNAS = ""
    @State private var renameError: String?
    @AppStorage("LanStash_DownloadChunkSize") private var chunkSizeSetting = 8
    @AppStorage("LanStash_Module_FileStation") private var isFileModuleEnabled = true
    @AppStorage("LanStash_Module_Photos") private var isPhotosModuleEnabled = true
    @State private var storage = AppStorageInspector.snapshot()
    @State private var confirmsCacheCleanup = false
    @State private var showsSelectiveCleanupSheet = false
    @State private var storageMessage: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {

                // 1. 连接信息
                SettingsSectionCard(
                    title: "连接信息",
                    icon: "server.rack",
                    iconColor: .blue
                ) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("设备名称")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(model.profile.displayName)
                            .textSelection(.enabled)
                        Button("修改…") {
                            renamedNAS = model.profile.displayName
                            renameError = nil
                            showsRenamePrompt = true
                        }
                    }
                    if let renameError {
                        Label(renameError, systemImage: "exclamationmark.triangle.fill")
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    Divider().opacity(0.3)
                    SettingsRow(label: "主机地址", value: "https://\(model.profile.host):\(model.profile.port)")
                    Divider().opacity(0.3)
                    SettingsRow(label: "用户名", value: model.profile.usernameHint ?? "未保存")
                    Divider().opacity(0.3)
                    SettingsRow(label: "连接状态", value: "已安全连接")
                }

                // 4. 功能模块管理
                SettingsSectionCard(
                    title: "功能",
                    icon: "square.grid.3x3.fill",
                    iconColor: .blue
                ) {
                    VStack(alignment: .leading, spacing: 14) {
                        Toggle(isOn: $isFileModuleEnabled) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("文件管理")
                                    .font(.body.weight(.medium))
                                Text("在侧边栏显示共享文件夹、回收站入口，支持文件浏览、下载和管理。")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .toggleStyle(.switch)
                        
                        Divider().opacity(0.3)
                        
                        Toggle(isOn: $isPhotosModuleEnabled) {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 6) {
                                    Text("照片管理")
                                        .font(.body.weight(.medium))
                                }
                                Text("在侧边栏显示个人和共享照片空间，支持按相册浏览照片与视频。")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .toggleStyle(.switch)
                    }
                }

                // 5. 传输设置
                SettingsSectionCard(
                    title: "传输设置",
                    icon: "arrow.up.and.down.and.sparkles",
                    iconColor: .orange
                ) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("下载性能")
                                .font(.body)
                            Spacer()
                            Picker("", selection: $chunkSizeSetting) {
                                Text("网络不稳定（4 MB）").tag(4)
                                Text("标准（8 MB）").tag(8)
                                Text("较快网络（16 MB）").tag(16)
                                Text("高速网络（32 MB）").tag(32)
                                Text("超高速网络（64 MB）").tag(64)
                            }
                            .pickerStyle(.menu)
                            .frame(width: 155)
                        }
                        
                        Text("通常保持“标准”即可。如果下载经常中断，可以选择“网络不稳定”；网络稳定且速度较快时，可以选择更高的档位。")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(nil)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                SettingsSectionCard(
                    title: "存储管理",
                    icon: "internaldrive.fill",
                    iconColor: .teal
                ) {
                    SettingsRow(label: "本地数据与缓存", value: ByteCountFormatter.string(fromByteCount: storage.total, countStyle: .file))
                    Divider().opacity(0.3)
                    SettingsRow(label: "无风险临时垃圾 (默认清理)", value: ByteCountFormatter.string(fromByteCount: storage.safeTrash, countStyle: .file))
                    Divider().opacity(0.3)
                    SettingsRow(label: "照片库时间线缓存", value: ByteCountFormatter.string(fromByteCount: storage.photoCache, countStyle: .file))
                    Divider().opacity(0.3)
                    SettingsRow(label: "登录与设置数据 (强制保护)", value: ByteCountFormatter.string(fromByteCount: storage.protectedData, countStyle: .file))
                    Text("默认清理仅删除无影响的临时文件与网络缓存。您可在‘选择性清理’中单独清除照片索引缓存，清理后再次进入照片会自动从 NAS 重新同步。")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    HStack {
                        if let storageMessage {
                            Text(storageMessage).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("重新计算") { storage = AppStorageInspector.snapshot() }
                        Button("选择性清理…") { showsSelectiveCleanupSheet = true }
                            .disabled(storage.reclaimable == 0)
                        Button("清理无风险垃圾") { confirmsCacheCleanup = true }
                            .disabled(storage.safeTrash == 0)
                    }
                }
            }
            .padding(32)
            .frame(maxWidth: 680, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .task { storage = AppStorageInspector.snapshot() }
        .alert("清理无风险应用垃圾？", isPresented: $confirmsCacheCleanup) {
            Button("取消", role: .cancel) {}
            Button("清理", role: .destructive) {
                model.dismissPreview()
                do {
                    try AppStorageInspector.clearReclaimableData(options: .safeTrash)
                    storage = AppStorageInspector.snapshot()
                    storageMessage = "无风险临时垃圾已成功清理。"
                } catch {
                    storageMessage = "部分缓存未能清理，请稍后重试。"
                }
            }
        } message: {
            Text("将清理文件预览临时解包文件和系统 HTTP 缓存，对应用正常使用没有任何影响。")
        }
        .sheet(isPresented: $showsSelectiveCleanupSheet) {
            SelectiveCacheCleanupSheet(storage: storage) { options in
                model.dismissPreview()
                do {
                    try AppStorageInspector.clearReclaimableData(options: options)
                    storage = AppStorageInspector.snapshot()
                    storageMessage = "选定缓存已成功清理。"
                } catch {
                    storageMessage = "部分缓存未能清理，请稍后重试。"
                }
            }
        }
        .alert("修改 NAS 名称", isPresented: $showsRenamePrompt) {
            TextField("设备名称", text: $renamedNAS)
            Button("取消", role: .cancel) {}
            Button("保存") {
                renameError = onRenameNAS(renamedNAS)
            }
            .disabled(renamedNAS.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } message: {
            Text("这里只修改岚仓中的显示名称，不会更改 NAS 本身的名称。")
        }
    }
}

extension FileItem {
    var modifiedTimeForSort: Date {
        times?.modifiedAt ?? Date.distantPast
    }
    
    var sizeForSort: Int64 {
        sizeBytes ?? -1
    }
    
    var fileTypeDisplay: String {
        if isDirectory { return "文件夹" }
        return fileExtension?.uppercased() ?? "未知文件"
    }
    
    var ownerForSort: String {
        owner ?? ""
    }
}

struct FileGridCell: View {
    @Bindable var model: WorkspaceModel
    let item: FileItem
    let isSelected: Bool
    let isDropTarget: Bool
    let onSelect: () -> Void
    let onOpen: () -> Void
    let contextMenuContent: AnyView
    @State private var isHovered = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 6) {
            FileGridThumbnail(model: model, item: item)
                .frame(width: 64, height: 48)
            
            Text(item.name)
                .font(.subheadline)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(height: 30, alignment: .top)
        }
        .padding(8)
        .frame(width: 104, height: 104)
        .contentShape(Rectangle())
        .background(
            RightClickDetector {
                onSelect()
            }
        )
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(
                    isDropTarget
                        ? Color.accentColor.opacity(0.22)
                        : isSelected
                        ? Color.accentColor.opacity(0.15)
                        : (isHovered ? Color.accentColor.opacity(0.10) : Color.clear)
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(
                    isDropTarget
                        ? Color.accentColor.opacity(0.90)
                        : isSelected
                        ? Color.accentColor.opacity(0.35)
                        : (isHovered ? Color.accentColor.opacity(0.18) : Color.clear),
                    lineWidth: isDropTarget ? 2 : 1
                )
        )
        .onHover { isHovered = $0 }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.15), value: isHovered)
        .onTapGesture {
            onSelect()
        }
        .simultaneousGesture(
            TapGesture(count: 2).onEnded {
                onOpen()
            }
        )
        .contextMenu {
            contextMenuContent
        }
    }
}

private struct FileGridThumbnail: View {
    @Bindable var model: WorkspaceModel
    let item: FileItem
    @State private var thumbnailData: Data?

    var body: some View {
        Group {
            if let thumbnailData, let decoded = decodedImage(from: thumbnailData) {
                ZStack {
                    Image(decorative: decoded.cgImage, scale: 1, orientation: decoded.orientation)
                        .resizable()
                        .interpolation(.medium)
                        .scaledToFill()
                        .frame(width: 64, height: 48)
                        .clipped()

                    if PreviewKind.classify(item) == .video {
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 20))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(.white, .black.opacity(0.48))
                            .shadow(radius: 2)
                    }
                }
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .stroke(Color(nsColor: .separatorColor).opacity(0.35), lineWidth: 1)
                }
            } else {
                FileLargeIcon(item: item)
                    .frame(width: 44, height: 44)
            }
        }
        .task(id: item.id) {
            thumbnailData = await model.thumbnailData(for: item)
        }
        .accessibilityHidden(true)
    }
}

struct FileLargeIcon: View {
    let item: FileItem
    
    var body: some View {
        Image(systemName: symbol)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .symbolRenderingMode(.hierarchical)
            .foregroundStyle(color)
            .accessibilityHidden(true)
    }
    
    private var symbol: String {
        if item.name == "#recycle" { return "trash.square.fill" }
        if item.isDirectory { return "folder.fill" }
        switch PreviewKind.classify(item) {
        case .image: return "photo.fill"
        case .pdf: return "doc.richtext.fill"
        case .text: return "doc.text.fill"
        case .video: return "video.fill"
        case .audio: return "waveform.circle.fill"
        case .unsupported:
            if ["zip", "rar", "7z", "tar", "gz"].contains(item.fileExtension ?? "") {
                return "archivebox.fill"
            }
            return "doc.fill"
        }
    }
    
    private var color: Color {
        if item.name == "#recycle" { return .orange }
        if item.isDirectory { return .blue }
        switch PreviewKind.classify(item) {
        case .image: return .teal
        case .pdf: return .red
        case .text: return .secondary
        case .video: return .purple
        case .audio: return .orange
        case .unsupported: return .secondary
        }
    }
}

struct FilePropertiesView: View {
    let item: FileItem
    let model: WorkspaceModel
    @Environment(\.dismiss) private var dismiss
    @State private var folderStatistics: FolderStatistics?
    @State private var isCalculatingFolderSize = false
    @State private var folderSizeError: String?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("查看详情")
                    .font(.headline.weight(.semibold))
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
            .background(Color(NSColor.windowBackgroundColor))
            
            Divider()

            ScrollView {
                VStack(spacing: 20) {
                    // 大图标与名称
                    VStack(spacing: 12) {
                        FileLargeIcon(item: item)
                            .frame(width: 64, height: 64)
                            .shadow(color: .black.opacity(0.1), radius: 4, x: 0, y: 2)
                        
                        Text(item.name)
                            .font(.title3.weight(.bold))
                            .multilineTextAlignment(.center)
                            .textSelection(.enabled)
                    }
                    .padding(.top, 16)
                    
                    // 1. 基本信息卡片
                    SettingsSectionCard(
                        title: "基本信息",
                        icon: "info.circle",
                        iconColor: .blue
                    ) {
                        SettingsRow(label: "种类", value: item.fileTypeDisplay)
                        Divider().opacity(0.3)
                        HStack(alignment: .firstTextBaseline) {
                            Text("大小")
                                .foregroundStyle(.secondary)
                            Spacer()
                            if isCalculatingFolderSize {
                                ProgressView()
                                    .controlSize(.small)
                                Text("正在计算…")
                                    .foregroundStyle(.secondary)
                            } else {
                                Text(sizeDisplayValue)
                                    .monospacedDigit()
                                    .multilineTextAlignment(.trailing)
                            }
                        }
                        if let folderStatistics {
                            Divider().opacity(0.3)
                            SettingsRow(
                                label: "内容",
                                value: "\(folderStatistics.fileCount) 个文件，\(folderStatistics.folderCount) 个文件夹"
                            )
                        } else if let folderSizeError {
                            Text(folderSizeError)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                        Divider().opacity(0.3)
                        SettingsRow(label: "位置", value: item.path, isMonospaced: true)
                    }

                    // 2. 时间卡片
                    SettingsSectionCard(
                        title: "时间节点",
                        icon: "calendar",
                        iconColor: .purple
                    ) {
                        SettingsRow(label: "修改时间", value: formatDateString(item.times?.modifiedAt))
                        if let createdAt = item.times?.createdAt {
                            Divider().opacity(0.3)
                            SettingsRow(label: "创建时间", value: formatDateString(createdAt))
                        }
                        if let accessedAt = item.times?.accessedAt {
                            Divider().opacity(0.3)
                            SettingsRow(label: "访问时间", value: formatDateString(accessedAt))
                        }
                    }

                    // 3. 所有权卡片
                    SettingsSectionCard(
                        title: "权限管理",
                        icon: "person.badge.key",
                        iconColor: .green
                    ) {
                        SettingsRow(label: "所有者", value: item.owner ?? "—")
                        Divider().opacity(0.3)
                        SettingsRow(label: "用户组", value: item.group ?? "—")
                        Divider().opacity(0.3)
                        SettingsRow(label: "权限码", value: item.permissions?.posixMode != nil ? String(format: "%o", item.permissions!.posixMode!) : "—")
                    }
                }
                .padding(20)
            }
        }
        .frame(width: 420, height: 500)
        .task(id: item.id) {
            guard item.isDirectory else { return }
            isCalculatingFolderSize = true
            folderSizeError = nil
            do {
                folderStatistics = try await model.folderStatistics(for: item)
            } catch is CancellationError {
                return
            } catch {
                folderSizeError = "暂时无法计算大小，请检查连接后重新打开详情。"
            }
            isCalculatingFolderSize = false
        }
    }

    private var sizeDisplayValue: String {
        if item.isDirectory {
            guard let statistics = folderStatistics else { return "—" }
            return formatBytesDetailed(statistics.sizeBytes, isComplete: statistics.isComplete)
        }
        if let size = item.sizeBytes {
            return formatBytesDetailed(size, isComplete: true)
        }
        return "—"
    }

    private func formatBytesDetailed(_ bytes: Int64, isComplete: Bool) -> String {
        let prefix = isComplete ? "" : "至少 "
        if bytes < 0 {
            return "\(prefix)0 字节"
        }
        if bytes < 1024 {
            return "\(prefix)\(bytes) 字节"
        }

        let doubleBytes = Double(bytes)
        let formattedSize: String

        if bytes < 1024 * 1024 {
            let kb = doubleBytes / 1024.0
            formattedSize = "\(trimTrailingZeros(kb)) KB"
        } else if bytes < 1024 * 1024 * 1024 {
            let mb = doubleBytes / (1024.0 * 1024.0)
            formattedSize = "\(trimTrailingZeros(mb)) MB"
        } else if bytes < 1024 * 1024 * 1024 * 1024 {
            let gb = doubleBytes / (1024.0 * 1024.0 * 1024.0)
            formattedSize = "\(trimTrailingZeros(gb)) GB"
        } else {
            let tb = doubleBytes / (1024.0 * 1024.0 * 1024.0 * 1024.0)
            formattedSize = "\(trimTrailingZeros(tb)) TB"
        }

        return "\(prefix)\(formattedSize)"
    }

    private func trimTrailingZeros(_ value: Double) -> String {
        var str = String(format: "%.2f", value)
        while str.hasSuffix("0") {
            str.removeLast()
        }
        if str.hasSuffix(".") {
            str.removeLast()
        }
        return str
    }

    private func formatDateString(_ date: Date?) -> String {
        guard let date = date else { return "—" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter.string(from: date)
    }
}

private struct SelectiveCacheCleanupSheet: View {
    let storage: AppStorageSnapshot
    let onClean: (CacheCleanupOptions) -> Void
    @Environment(\.dismiss) private var dismiss

    @State private var cleanSafeTrash = true
    @State private var cleanPhotoCache = false

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Image(systemName: "trash.circle.fill")
                    .font(.title)
                    .foregroundStyle(.teal)
                Text("选择性清理本地缓存")
                    .font(.title2.weight(.bold))
            }

            Text("请勾选您希望清理的项。清理本地缓存绝对不会删除登录凭据、设置项或 NAS 中的真实文件。")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 14) {
                Toggle(isOn: $cleanSafeTrash) {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text("无风险临时垃圾")
                                .font(.body.weight(.medium))
                            Spacer()
                            Text(ByteCountFormatter.string(fromByteCount: storage.safeTrash, countStyle: .file))
                                .foregroundStyle(.secondary)
                        }
                        Text("包含文件临时解包预览和网络请求缓存，清理对应用使用没有任何影响（推荐清理）。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Divider()

                Toggle(isOn: $cleanPhotoCache) {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text("照片库时间线索引缓存")
                                .font(.body.weight(.medium))
                            Spacer()
                            Text(ByteCountFormatter.string(fromByteCount: storage.photoCache, countStyle: .file))
                                .foregroundStyle(.secondary)
                        }
                        Text("包含磁盘存储的照片索引元数据。清理后不会影响 NAS 照片，下次进入照片功能会自动重新扫描。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(14)
            .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 10))

            HStack {
                Spacer()
                Button("取消") { dismiss() }
                    .keyboardShortcut(.escape, modifiers: [])
                Button("清理选中项") {
                    var selected: CacheCleanupOptions = []
                    if cleanSafeTrash { selected.insert(.safeTrash) }
                    if cleanPhotoCache { selected.insert(.photoCache) }
                    onClean(selected)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(!cleanSafeTrash && !cleanPhotoCache)
            }
        }
        .padding(24)
        .frame(width: 480)
    }
}

struct RightClickDetector: NSViewRepresentable {
    let action: () -> Void

    func makeNSView(context: Context) -> NSView {
        RightClickNSView(action: action)
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

class RightClickNSView: NSView {
    let action: () -> Void

    init(action: @escaping () -> Void) {
        self.action = action
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func rightMouseDown(with event: NSEvent) {
        action()
        super.rightMouseDown(with: event)
    }
}
