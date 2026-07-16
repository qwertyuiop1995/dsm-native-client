import AppKit
import DsmCore
import SwiftUI

private enum FileViewMode: String, CaseIterable, Identifiable {
    case list
    case grid
    var id: Self { self }
}

struct WorkspaceView: View {
    @Bindable var model: WorkspaceModel
    let onLogout: () async -> Void
    let onSessionExpired: (String) async -> Void

    @State private var deleteTargets: [FileItem] = []
    @State private var restoreTarget: FileItem?
    @State private var viewMode: FileViewMode = .list
    @State private var sortOrder = [KeyPathComparator<FileItem>]()
    @State private var showingInfoItem: FileItem? = nil

    var body: some View {
        NavigationSplitView {
            SidebarView(model: model)
                .navigationSplitViewColumnWidth(min: 210, ideal: 240, max: 300)
        } content: {
            contentColumn
                .navigationSplitViewColumnWidth(min: 480, ideal: 680)
        } detail: {
            FileDetailView(
                model: model,
                onDownload: presentDownloadPanel,
                onDelete: { deleteTargets = $0 },
                onRestore: { restoreTarget = $0 }
            )
            .navigationSplitViewColumnWidth(min: 250, ideal: 380, max: 1200)
        }
        .navigationSplitViewStyle(.balanced)
        .task {
            await model.load()
        }
        .onChange(of: model.section) { _, section in
            Task { await model.activate(section) }
        }
        .onChange(of: model.selection) { _, _ in
            model.selectionChanged()
        }
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                Button {
                    Task { await model.goBack() }
                } label: {
                    Label("返回", systemImage: "chevron.backward")
                }
                .disabled(!model.canGoBack)
                .help("返回上一个目录（⌘[）")
                .keyboardShortcut("[", modifiers: .command)

                Button {
                    Task { await model.goUp() }
                } label: {
                    Label("上一级", systemImage: "arrow.up")
                }
                .disabled(!model.canGoUp)
                .help("前往上一级目录")
            }

            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    Task { await model.refresh() }
                } label: {
                    Label("刷新", systemImage: "arrow.clockwise")
                }
                .disabled(model.currentPath.isEmpty || model.isRefreshing)
                .keyboardShortcut("r", modifiers: .command)

                Menu {
                    Button("选择文件上传…") {
                        presentUploadPanel(overwrite: false)
                    }
                    Button("上传并覆盖同名文件…") {
                        presentUploadPanel(overwrite: true)
                    }
                } label: {
                    Label("上传", systemImage: "square.and.arrow.up")
                }
                .disabled(!isFileSection)
                .help("上传文件到当前目录")

                Button {
                    if let item = model.selectedItem, !item.isDirectory {
                        presentDownloadPanel(item)
                    }
                } label: {
                    Label("下载", systemImage: "square.and.arrow.down")
                }
                .disabled(model.selectedItem?.isDirectory != false)

                Button {
                    deleteTargets = model.selectedItems
                } label: {
                    Label("删除", systemImage: "trash")
                }
                .disabled(model.selectedItems.isEmpty)
                .help("打开删除确认，不会直接删除")

                Button {
                    model.section = .transfers
                } label: {
                    Label("传输", systemImage: "arrow.up.arrow.down.circle")
                }
                .badge(model.activeTransferCount)

                Picker("视图模式", selection: $viewMode) {
                    Label("列表", systemImage: "list.bullet").tag(FileViewMode.list)
                    Label("网格", systemImage: "grid").tag(FileViewMode.grid)
                }
                .pickerStyle(.segmented)
                .disabled(!isFileSection)

                Menu {
                    Button("退出登录") {
                        Task { await onLogout() }
                    }
                    Button("设置") {
                        model.section = .settings
                    }
                } label: {
                    Label("更多", systemImage: "ellipsis.circle")
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
            FilePropertiesView(item: item)
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
            Text(
                "\(model.statusMessage ?? "NAS 没有接受当前登录状态。")你可以先重试；如果仍然失败，请重新登录。"
            )
        }
    }

    @ViewBuilder
    private var contentColumn: some View {
        switch model.section {
        case .transfers:
            TransferCenterView(model: model)
        case .settings:
            SettingsView(model: model, onLogout: onLogout)
        default:
            FileBrowserView(
                model: model,
                viewMode: $viewMode,
                showingInfoItem: $showingInfoItem,
                onDownload: presentDownloadPanel,
                onDelete: { deleteTargets = $0 },
                onRestore: { restoreTarget = $0 }
            )
        }
    }

    private var isFileSection: Bool {
        switch model.section {
        case .files, .recycle: true
        default: false
        }
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
        return "NAS：\(model.profile.displayName)\n目录：\(model.currentPath)\n删除后能否恢复取决于共享文件夹的回收站设置，文件可能被永久删除。"
    }

    private func presentUploadPanel(overwrite: Bool) {
        let panel = NSOpenPanel()
        panel.title = overwrite ? "选择要覆盖上传的文件" : "选择要上传的文件"
        panel.prompt = overwrite ? "上传并覆盖" : "上传"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = true
        if panel.runModal() == .OK {
            model.enqueueUploads(panel.urls, overwrite: overwrite)
        }
    }

    private func presentDownloadPanel(_ item: FileItem) {
        let panel = NSSavePanel()
        panel.title = "下载 \(item.name)"
        panel.nameFieldStringValue = item.name
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            model.enqueueDownload(item, to: url)
        }
    }
}

private struct SidebarView: View {
    @Bindable var model: WorkspaceModel

    var body: some View {
        List(selection: $model.section) {
            Section {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.profile.displayName)
                            .font(.headline)
                        Text(model.isDemo ? "演示模式" : "已安全连接")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: model.isDemo ? "sparkles.rectangle.stack" : "externaldrive.fill.badge.checkmark")
                        .foregroundStyle(.blue)
                }
            }

            Section("共享文件夹") {
                ForEach(model.shares) { share in
                    NavigationLink(value: WorkspaceSection.files(share.path)) {
                        Label(share.name, systemImage: "folder.fill")
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.blue)
                    }
                }
                if model.shares.isEmpty, !model.isLoading {
                    Text("没有可访问的共享")
                        .foregroundStyle(.secondary)
                }
            }

            Section("回收站") {
                ForEach(model.recycleRoots) { root in
                    NavigationLink(value: WorkspaceSection.recycle(root.path)) {
                        Label(root.name, systemImage: "trash.square.fill")
                    }
                }
                if model.recycleRoots.isEmpty {
                    Text(model.isLoading ? "正在检查…" : "没有可访问的回收站")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                NavigationLink(value: WorkspaceSection.transfers) {
                    Label("传输中心", systemImage: "arrow.up.arrow.down.circle")
                        .badge(model.activeTransferCount)
                }
                NavigationLink(value: WorkspaceSection.settings) {
                    Label("这台 NAS", systemImage: "gearshape")
                }
            }
        }
        .listStyle(.sidebar)
    }
}

private struct FileBrowserView: View {
    @Bindable var model: WorkspaceModel
    @Binding var viewMode: FileViewMode
    @Binding var showingInfoItem: FileItem?
    let onDownload: (FileItem) -> Void
    let onDelete: ([FileItem]) -> Void
    let onRestore: (FileItem) -> Void
    
    @State private var sortOrder = [KeyPathComparator<FileItem>]()

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: model.currentPath.contains("#recycle") ? "trash" : "folder")
                        .foregroundStyle(.secondary)
                    Text(model.currentPath.isEmpty ? "文件" : model.currentPath)
                        .font(.headline)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
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
                if let message = model.statusMessage {
                    Label(message, systemImage: model.statusIsError ? "exclamationmark.triangle.fill" : "info.circle")
                        .font(.caption)
                        .foregroundStyle(model.statusIsError ? .red : .secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            if model.isLoading {
                VStack(spacing: 12) {
                    ProgressView()
                    Text("正在读取目录…")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.filteredItems.isEmpty {
                ContentUnavailableView(
                    model.searchText.isEmpty ? "目录为空" : "没有匹配项目",
                    systemImage: model.searchText.isEmpty ? "folder" : "magnifyingglass",
                    description: Text(model.searchText.isEmpty ? "可以上传文件到这个目录。" : "尝试其他搜索词。")
                )
            } else {
                if viewMode == .list {
                    fileTable
                } else {
                    fileGrid
                }
            }
        }
        .searchable(text: $model.searchText, placement: .toolbar, prompt: "筛选当前目录")
        .dropDestination(for: URL.self) { urls, _ in
            model.enqueueUploads(urls)
            return true
        }
    }

    private var sortedItems: [FileItem] {
        model.filteredItems.sorted(using: sortOrder)
    }

    private func selectIfUnselected(_ item: FileItem) {
        if !model.selection.contains(item.id) {
            DispatchQueue.main.async {
                model.selection = [item.id]
            }
        }
    }

    @ViewBuilder
    private func contextMenuForFile(_ item: FileItem) -> some View {
        Button(item.isDirectory ? "打开" : "预览") {
            Task { await model.open(item) }
        }
        if !item.isDirectory {
            Button("下载…") { onDownload(item) }
        }
        if item.isRecyclePath, model.allowsVerifiedRestore {
            Divider()
            Button("恢复到原位置…") { onRestore(item) }
        }
        Divider()
        Button("显示简介") {
            showingInfoItem = item
        }
        Divider()
        Button(item.isRecyclePath ? "永久删除…" : "删除…", role: .destructive) {
            onDelete([item])
        }
    }

    private var fileGrid: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 90, maximum: 120), spacing: 16)], spacing: 16) {
                ForEach(sortedItems) { item in
                    FileGridCell(
                        item: item,
                        isSelected: model.selection.contains(item.id),
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
                }
            }
            .padding(16)
        }
        .background(Color(NSColor.controlBackgroundColor).opacity(0.2))
    }

    private var fileTable: some View {
        Table(sortedItems, selection: $model.selection, sortOrder: $sortOrder) {
            TableColumn("名称", value: \.name) { item in
                HStack(spacing: 8) {
                    FileIcon(item: item)
                    Text(item.name)
                        .lineLimit(1)
                }
                .contentShape(Rectangle())
            }
            .width(min: 220, ideal: 320)

            TableColumn("大小", value: \.sizeForSort) { item in
                Text(item.isDirectory ? "—" : ByteCountFormatter.string(fromByteCount: item.sizeBytes ?? 0, countStyle: .file))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            .width(min: 80, ideal: 100)

            TableColumn("类型", value: \.fileTypeDisplay) { item in
                Text(item.fileTypeDisplay)
                    .foregroundStyle(.secondary)
            }
            .width(min: 80, ideal: 100)

            TableColumn("修改日期", value: \.modifiedTimeForSort) { item in
                if let date = item.times?.modifiedAt {
                    Text(date, format: .dateTime.year().month().day().hour().minute())
                        .foregroundStyle(.secondary)
                } else {
                    Text("—").foregroundStyle(.tertiary)
                }
            }
            .width(min: 130, ideal: 160)

            TableColumn("所有者", value: \.ownerForSort) { item in
                Text(item.owner ?? "—")
                    .foregroundStyle(.secondary)
            }
            .width(min: 80, ideal: 100)
        }
        .tableStyle(.inset(alternatesRowBackgrounds: true))
        .accessibilityLabel("\(model.currentPath) 文件列表")
        .contextMenu(forSelectionType: FileItem.ID.self) { selectedIds in
            if let firstId = selectedIds.first,
               let item = sortedItems.first(where: { $0.id == firstId }) {
                contextMenuForFile(item)
            }
        }
        .simultaneousGesture(
            TapGesture(count: 2).onEnded {
                if let item = model.selectedItem {
                    Task { await model.open(item) }
                }
            }
        )
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

private struct TransferCenterView: View {
    @Bindable var model: WorkspaceModel

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("传输中心")
                        .font(.title2.weight(.semibold))
                    Text("上传、下载、删除和恢复任务")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("清除已完成") {
                    model.clearCompletedTransfers()
                }
                .disabled(!model.transfers.contains(where: { $0.state == .succeeded || $0.state == .cancelled }))
            }
            .padding(16)
            Divider()

            if model.transfers.isEmpty {
                ContentUnavailableView(
                    "暂无传输任务",
                    systemImage: "arrow.up.arrow.down.circle",
                    description: Text("上传、下载和文件操作会显示在这里。")
                )
            } else {
                List(model.transfers) { task in
                    TransferRow(task: task) {
                        model.cancelTransfer(task.id)
                    }
                }
            }
        }
    }
}

private struct TransferRow: View {
    let task: ActivityTask
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(iconColor)
                .frame(width: 28)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(task.displayName)
                        .fontWeight(.medium)
                        .lineLimit(1)
                    Spacer()
                    Text(stateLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let total = task.totalUnits, total > 0 {
                    ProgressView(
                        value: Double(min(max(task.completedUnits, 0), total)),
                        total: Double(total)
                    )
                    .accessibilityLabel("\(task.displayName)传输进度")
                    .accessibilityValue(progressAccessibilityValue(total: total))
                } else if task.state == .running || task.state == .cancelling {
                    ProgressView()
                        .controlSize(.small)
                }
                if let transferDetails {
                    Text(transferDetails)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                if let failure = task.failureMessage {
                    Text(failure)
                        .font(.caption)
                        .foregroundStyle(.red)
                } else {
                    Text(task.remotePath)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
            if task.state == .queued || task.state == .running {
                Button("取消", action: onCancel)
                    .buttonStyle(.borderless)
            }
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }

    private var icon: String {
        switch task.kind {
        case .upload: "arrow.up.circle.fill"
        case .download: "arrow.down.circle.fill"
        case .delete: "trash.circle.fill"
        case .restore: "arrow.uturn.backward.circle.fill"
        }
    }

    private var iconColor: Color {
        switch task.state {
        case .succeeded: .green
        case .failed: .red
        case .cancelled: .secondary
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
        case .cancelling: return "正在取消"
        case .succeeded: return "已完成"
        case .failed: return "失败"
        case .cancelled: return "已取消"
        }
    }

    private var transferDetails: String? {
        guard task.kind == .upload || task.kind == .download else {
            return nil
        }

        var parts: [String] = []
        if let total = task.totalUnits, total > 0 {
            parts.append("\(formatBytes(task.completedUnits)) / \(formatBytes(total))")
        } else if task.completedUnits > 0 {
            parts.append("已传输 \(formatBytes(task.completedUnits))")
        }
        if let speed = task.bytesPerSecond, speed > 0,
           task.state == .running || task.state == .cancelling {
            parts.append("\(formatBytes(Int64(speed)))/秒")
        }
        if let remaining = task.estimatedSecondsRemaining, remaining.isFinite, remaining > 0,
           task.state == .running {
            parts.append("剩余约 \(formatDuration(remaining))")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: max(bytes, 0), countStyle: .file)
    }

    private func formatDuration(_ seconds: TimeInterval) -> String {
        let rounded = max(Int(seconds.rounded(.up)), 1)
        if rounded < 60 {
            return "\(rounded) 秒"
        }
        if rounded < 3_600 {
            return "\((rounded + 59) / 60) 分钟"
        }
        let hours = rounded / 3_600
        let minutes = (rounded % 3_600 + 59) / 60
        return minutes > 0 ? "\(hours) 小时 \(minutes) 分钟" : "\(hours) 小时"
    }

    private func progressAccessibilityValue(total: Int64) -> String {
        let percentage = Int((Double(task.completedUnits) / Double(total) * 100).rounded())
        return "\(min(max(percentage, 0), 100))%"
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

private struct SettingsView: View {
    @Bindable var model: WorkspaceModel
    let onLogout: () async -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // 页面大标题
                HStack(spacing: 12) {
                    Image(systemName: "square.stack.3d.up.fill")
                        .font(.title)
                        .foregroundStyle(.blue.gradient)
                    
                    VStack(alignment: .leading, spacing: 2) {
                        Text("这台 NAS")
                            .font(.title2.weight(.bold))
                        Text("管理当前连接的 NAS 存储节点与安全配置")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.bottom, 8)

                // 1. 连接信息
                SettingsSectionCard(
                    title: "连接信息",
                    icon: "server.rack",
                    iconColor: .blue
                ) {
                    SettingsRow(label: "设备名称", value: model.profile.displayName)
                    Divider().opacity(0.3)
                    SettingsRow(label: "主机地址", value: "https://\(model.profile.host):\(model.profile.port)")
                    Divider().opacity(0.3)
                    SettingsRow(label: "用户名", value: model.profile.usernameHint ?? "未保存")
                    Divider().opacity(0.3)
                    SettingsRow(label: "连接状态", value: model.isDemo ? "演示模式" : "已安全连接")
                }

                // 2. 连接安全
                SettingsSectionCard(
                    title: "连接安全",
                    icon: "lock.shield",
                    iconColor: .green
                ) {
                    if let fingerprint = model.profile.pinnedCertificateSHA256 {
                        SettingsRow(label: "验证方式", value: "已核对并记住此证书")
                        Divider().opacity(0.3)
                        VStack(alignment: .leading, spacing: 6) {
                            Text("安全指纹 (SHA-256)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            
                            Text(fingerprint)
                                .font(.system(.subheadline, design: .monospaced))
                                .foregroundStyle(.primary)
                                .textSelection(.enabled)
                                .padding(8)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.secondary.opacity(0.08))
                                .cornerRadius(6)
                        }
                    } else {
                        SettingsRow(label: "验证方式", value: model.isDemo ? "示例不连接网络" : "由 macOS 系统自动验证")
                    }
                }

                // 3. 文件恢复
                SettingsSectionCard(
                    title: "回收站恢复",
                    icon: "arrow.triangle.2.circlepath.camera",
                    iconColor: .purple
                ) {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: model.allowsVerifiedRestore ? "checkmark.circle.fill" : "info.circle.fill")
                            .font(.title3)
                            .foregroundStyle(model.allowsVerifiedRestore ? .green : .orange)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text(model.allowsVerifiedRestore ? "已开启完全恢复" : "只读浏览模式")
                                .font(.body.weight(.medium))
                            Text(model.allowsVerifiedRestore
                                    ? "可以将回收站的文件直接还原到它们被删除前的位置；如果有同名冲突，岚仓将不会覆盖已有文件。"
                                    : "当前只能查看和下载回收站内的文件，暂不支持直接将文件原路还原。")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(nil)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                // 4. 操作区域
                HStack {
                    Spacer()
                    Button {
                        Task { await onLogout() }
                    } label: {
                        HStack {
                            Image(systemName: "power")
                            Text("退出登录")
                        }
                        .font(.body.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 10)
                        .background(Color.red.gradient)
                        .cornerRadius(8)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 8)
            }
            .padding(32)
            .frame(maxWidth: 680, alignment: .leading)
            .frame(maxWidth: .infinity)
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
    let item: FileItem
    let isSelected: Bool
    let onSelect: () -> Void
    let onOpen: () -> Void
    let contextMenuContent: AnyView

    var body: some View {
        VStack(spacing: 8) {
            FileLargeIcon(item: item)
                .frame(width: 48, height: 48)
            
            Text(item.name)
                .font(.subheadline)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(height: 36, alignment: .top)
        }
        .padding(8)
        .contentShape(Rectangle())
        .background(
            RightClickDetector {
                onSelect()
            }
        )
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(isSelected ? Color.blue.opacity(0.15) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(isSelected ? Color.blue.opacity(0.3) : Color.clear, lineWidth: 1)
        )
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
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("显示简介")
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
                        SettingsRow(label: "大小", value: formatBytesDetailed(item.sizeBytes))
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
    }

    private func formatBytesDetailed(_ bytes: Int64?) -> String {
        guard let bytes = bytes, item.isDirectory == false else { return "—" }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        let bytesString = formatter.string(from: NSNumber(value: bytes)) ?? "\(bytes)"
        let readableString = ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
        return "\(bytesString) 字节 (\(readableString))"
    }

    private func formatDateString(_ date: Date?) -> String {
        guard let date = date else { return "—" }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        return formatter.string(from: date)
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
