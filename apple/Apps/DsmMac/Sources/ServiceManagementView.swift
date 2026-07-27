import AppKit
import DsmCore
import SwiftUI
import UniformTypeIdentifiers
import WebKit

struct ServiceManagementView: View {
    let module: ServiceManagementModel.Module
    @Bindable var model: ServiceManagementModel

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .top) {
                Group {
                    switch module {
                    case .downloads:
                        DownloadStationView(model: model)
                    case .containers:
                        ContainerManagerView(model: model)
                    case .virtualMachines:
                        VirtualMachineManagerView(model: model)
                    }
                }

                if let message = model.message {
                    FloatingToastView(
                        message: message,
                        isError: model.messageIsError,
                        onDismiss: { model.message = nil }
                    )
                    .padding(.top, max(24, geo.size.height * 0.20))
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(999)
                }
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: model.message)
        .task(id: module) {
            await model.activate(module)
        }
        .task(id: model.message) {
            if model.message != nil {
                try? await Task.sleep(for: .seconds(3.5))
                withAnimation {
                    model.message = nil
                }
            }
        }
    }
}

private struct ServiceHeader: View {
    let title: String
    let subtitle: String
    let icon: String
    let tint: Color
    let isLoading: Bool
    let refresh: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.title2.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 44, height: 44)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 12))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.title2.weight(.semibold))
                Text(subtitle).font(.subheadline).foregroundStyle(.secondary)
            }
            Spacer()
            if isLoading {
                ProgressView().controlSize(.small).accessibilityLabel("正在刷新")
            }
            Button(action: refresh) {
                Label("刷新", systemImage: "arrow.clockwise")
            }
            .disabled(isLoading)
            .keyboardShortcut("r", modifiers: .command)
        }
    }
}

private struct FloatingToastView: View {
    let message: String
    let isError: Bool
    let onDismiss: () -> Void

    private var statusColor: Color {
        isError ? .red : .green
    }

    private var statusIcon: String {
        isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill"
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: statusIcon)
                .font(.headline)
                .foregroundStyle(statusColor)

            Text(message)
                .font(.callout.weight(.medium))
                .foregroundStyle(.primary)
                .lineLimit(2)

            Button {
                onDismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .padding(.leading, 4)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial, in: Capsule())
        .background(
            Capsule()
                .fill(statusColor.opacity(0.12))
        )
        .overlay(
            Capsule()
                .stroke(statusColor.opacity(0.3), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.12), radius: 10, x: 0, y: 4)
        .accessibilityElement(children: .combine)
    }
}

private struct EmptyServiceState: View {
    let title: String
    let message: String
    let icon: String

    var body: some View {
        ContentUnavailableView(title, systemImage: icon, description: Text(message))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct DownloadStationView: View {
    enum Filter: String, CaseIterable, Identifiable {
        case all
        case active
        case finished
        case paused

        var id: Self { self }
        var title: String {
            switch self {
            case .all: "全部"
            case .active: "进行中"
            case .finished: "已完成"
            case .paused: "已暂停"
            }
        }
    }

    @Bindable var model: ServiceManagementModel
    @State private var filter: Filter = .all
    @State private var showsCreate = false
    @State private var showsSettings = false
    @State private var deleteChoice: DeleteChoice?

    private enum DeleteChoice {
        case taskOnly
        case taskAndData
    }

    private var tasks: [DownloadStationTask] {
        let source = model.downloads?.tasks ?? []
        return source.filter { task in
            let status = task.status.lowercased()
            switch filter {
            case .all:
                return true
            case .active:
                return ["downloading", "uploading", "seeding", "waiting", "hash_checking"]
                    .contains(status)
            case .finished:
                return ["finished", "completed"].contains(status)
            case .paused:
                return ["paused", "stopped"].contains(status)
            }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ServiceHeader(
                title: "下载管理",
                subtitle: speedSummary,
                icon: "arrow.down.circle.fill",
                tint: .green,
                isLoading: model.isLoading
            ) { Task { await model.activate(.downloads, force: true) } }

            HStack {
                Picker("", selection: $filter) {
                    ForEach(Filter.allCases) { Text($0.title).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 360)
                Spacer()
                Button {
                    Task { await model.controlDownloads(.resume) }
                } label: {
                    Label("继续", systemImage: "play.fill")
                }
                .disabled(model.downloadSelection.isEmpty || model.isPerformingAction)
                Button {
                    Task { await model.controlDownloads(.pause) }
                } label: {
                    Label("暂停", systemImage: "pause.fill")
                }
                .disabled(model.downloadSelection.isEmpty || model.isPerformingAction)
                Menu {
                    Button("仅移除任务", role: .destructive) {
                        deleteChoice = .taskOnly
                    }
                    Button("移除任务和已下载数据", role: .destructive) {
                        deleteChoice = .taskAndData
                    }
                } label: {
                    Label("移除", systemImage: "trash")
                }
                .disabled(model.downloadSelection.isEmpty || model.isPerformingAction)
                Button {
                    showsSettings = true
                } label: {
                    Label("设置", systemImage: "gearshape")
                }
                .disabled(model.isPerformingAction)
                Button {
                    showsCreate = true
                } label: {
                    Label("添加下载", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.isPerformingAction)
            }

            if tasks.isEmpty, !model.isLoading {
                EmptyServiceState(
                    title: filter == .all ? "还没有下载任务" : "没有符合条件的任务",
                    message: "你可以选择任务文件，或输入下载网址。",
                    icon: "arrow.down.doc"
                )
            } else {
                List(tasks, selection: $model.downloadSelection) { task in
                    DownloadTaskRow(task: task)
                        .tag(task.id)
                        .contextMenu {
                            Button("继续") {
                                model.downloadSelection = [task.id]
                                Task { await model.controlDownloads(.resume) }
                            }
                            Button("暂停") {
                                model.downloadSelection = [task.id]
                                Task { await model.controlDownloads(.pause) }
                            }
                        }
                }
                .listStyle(.inset)
            }
        }
        .padding(20)
        .sheet(isPresented: $showsCreate) {
            CreateDownloadSheet(
                defaultDestination: model.downloads?.defaultDestination,
                loadFolders: { path in
                    try await model.loadDownloadDestinationFolders(in: path)
                },
                submitURL: { uri, destination in
                    let succeeded = await model.createDownload(uri: uri, destination: destination)
                    if succeeded { showsCreate = false }
                    return succeeded
                },
                submitFile: { fileURL, destination, unzipPassword in
                    let succeeded = await model.createDownload(
                        fileURL: fileURL,
                        destination: destination,
                        unzipPassword: unzipPassword
                    )
                    if succeeded { showsCreate = false }
                    return succeeded
                }
            )
        }
        .sheet(isPresented: $showsSettings) {
            DownloadSettingsSheet(
                loadFolders: { path in
                    try await model.loadDownloadDestinationFolders(in: path)
                },
                load: {
                    try await model.loadDownloadSettings()
                },
                save: { settings in
                    let succeeded = await model.saveDownloadSettings(settings)
                    if succeeded { showsSettings = false }
                    return succeeded
                }
            )
        }
        .confirmationDialog(
            "移除所选下载任务？",
            isPresented: Binding(
                get: { deleteChoice != nil },
                set: { if !$0 { deleteChoice = nil } }
            )
        ) {
            Button(
                deleteChoice == .taskAndData ? "移除任务和数据" : "仅移除任务",
                role: .destructive
            ) {
                let removeData = deleteChoice == .taskAndData
                deleteChoice = nil
                Task { await model.deleteDownloads(removeData: removeData) }
            }
            Button("取消", role: .cancel) { deleteChoice = nil }
        } message: {
            Text(
                deleteChoice == .taskAndData
                    ? "这会同时删除 NAS 上已经下载的数据，无法撤销。"
                    : "已下载的数据会保留在 NAS 上。"
            )
        }
    }

    private var speedSummary: String {
        let down = ServiceFormat.speed(model.downloads?.downloadBytesPerSecond ?? 0)
        let up = ServiceFormat.speed(model.downloads?.uploadBytesPerSecond ?? 0)
        return "下载 \(down) · 上传 \(up)"
    }
}

private struct DownloadTaskRow: View {
    let task: DownloadStationTask

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Image(systemName: statusIcon)
                    .foregroundStyle(statusColor)
                    .accessibilityHidden(true)
                Text(task.title).font(.body.weight(.medium)).lineLimit(1)
                Spacer()
                Text(ServiceFormat.status(task.status))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(statusColor)
            }
            if let progress = task.progress {
                ProgressView(value: progress)
                    .accessibilityLabel(task.title)
                    .accessibilityValue("\(Int(progress * 100))%")
            }
            HStack {
                Text(sizeSummary)
                Spacer()
                Label(
                    ServiceFormat.speed(task.downloadBytesPerSecond ?? 0),
                    systemImage: "arrow.down"
                )
                Label(
                    ServiceFormat.speed(task.uploadBytesPerSecond ?? 0),
                    systemImage: "arrow.up"
                )
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 5)
        .accessibilityElement(children: .combine)
    }

    private var sizeSummary: String {
        guard let total = task.sizeBytes else { return "大小未知" }
        let completed = ServiceFormat.bytes(task.downloadedBytes ?? 0)
        return "\(completed) / \(ServiceFormat.bytes(total))"
    }

    private var statusIcon: String {
        switch task.status.lowercased() {
        case "finished", "completed": "checkmark.circle.fill"
        case "paused", "stopped": "pause.circle.fill"
        case "error": "exclamationmark.triangle.fill"
        default: "arrow.down.circle.fill"
        }
    }

    private var statusColor: Color {
        switch task.status.lowercased() {
        case "finished", "completed": .green
        case "paused", "stopped": .orange
        case "error": .red
        default: .blue
        }
    }
}

private struct CreateDownloadSheet: View {
    private enum Source: String, CaseIterable, Identifiable {
        case file
        case url

        var id: Self { self }
        var title: String {
            switch self {
            case .file: "打开文件"
            case .url: "输入网址"
            }
        }
    }

    let defaultDestination: String?
    let loadFolders: (String?) async throws -> [FileItem]
    let submitURL: (String, String?) async -> Bool
    let submitFile: (URL, String?, String?) async -> Bool
    @Environment(\.dismiss) private var dismiss
    @State private var source: Source = .file
    @State private var uri = ""
    @State private var selectedFileURL: URL?
    @State private var unzipPassword = ""
    @State private var destination = ""
    @State private var isSubmitting = false
    @State private var showsDestinationPicker = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("添加下载").font(.title2.weight(.semibold))
            Picker("任务来源", selection: $source) {
                ForEach(Source.allCases) { source in
                    Text(source.title).tag(source)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            Form {
                if source == .file {
                    LabeledContent("任务文件") {
                        HStack(spacing: 8) {
                            Label(
                                selectedFileURL?.lastPathComponent ?? "尚未选择文件",
                                systemImage: "doc.badge.plus"
                            )
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            Button("选择文件…", action: chooseTaskFile)
                        }
                    }
                    SecureField("解压密码（可选）", text: $unzipPassword)
                } else {
                    TextField("下载网址或磁力链接", text: $uri, axis: .vertical)
                        .lineLimit(3...6)
                }
                LabeledContent("保存位置") {
                    HStack(spacing: 8) {
                        Label(destinationDisplay, systemImage: "folder")
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .accessibilityLabel("当前保存位置：\(destinationDisplay)")
                        if destination != normalizedDefaultDestination {
                            Button("恢复默认") {
                                destination = normalizedDefaultDestination
                            }
                        }
                        Button("选择…") {
                            showsDestinationPicker = true
                        }
                    }
                }
            }
            Text(helpText)
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("取消", role: .cancel) { dismiss() }
                Button("添加下载") {
                    isSubmitting = true
                    Task {
                        let selectedDestination =
                            destination.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            ? defaultDestination
                            : destination
                        switch source {
                        case .file:
                            if let selectedFileURL {
                                _ = await submitFile(
                                    selectedFileURL,
                                    selectedDestination,
                                    unzipPassword.trimmingCharacters(in: .whitespacesAndNewlines)
                                )
                            }
                        case .url:
                            _ = await submitURL(uri, selectedDestination)
                        }
                        isSubmitting = false
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canSubmit || isSubmitting)
            }
        }
        .padding(24)
        .frame(width: 620)
        .onAppear { destination = normalizedDefaultDestination }
        .sheet(isPresented: $showsDestinationPicker) {
            DownloadDestinationPicker(
                selectedDestination: destination,
                loadFolders: loadFolders,
                onSelect: {
                    destination = $0
                    showsDestinationPicker = false
                },
                onCancel: {
                    showsDestinationPicker = false
                }
            )
        }
    }

    private var normalizedDefaultDestination: String {
        Self.normalizeDestination(defaultDestination ?? "")
    }

    private var destinationDisplay: String {
        destination.isEmpty ? "使用 Download Station 默认位置" : "/\(destination)"
    }

    private var canSubmit: Bool {
        switch source {
        case .file:
            selectedFileURL != nil
        case .url:
            !uri.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    private var helpText: String {
        switch source {
        case .file:
            "支持 .torrent、.nzb 和包含下载网址的 .txt 文件。文件只会发送到当前 NAS。"
        case .url:
            "支持 HTTP、HTTPS、FTP 和磁力链接；网址仅用于本次提交，不会写入应用日志。"
        }
    }

    private func chooseTaskFile() {
        let panel = NSOpenPanel()
        panel.title = "选择下载任务文件"
        panel.prompt = "选择"
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = ["torrent", "nzb", "txt"].compactMap {
            UTType(filenameExtension: $0)
        }
        guard panel.runModal() == .OK else { return }
        selectedFileURL = panel.url
    }

    private static func normalizeDestination(_ path: String) -> String {
        path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }
}

private struct DownloadSettingsSheet: View {
    let loadFolders: (String?) async throws -> [FileItem]
    let load: () async throws -> DownloadStationSettings
    let save: (DownloadStationSettings) async -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var settings: DownloadStationSettings?
    @State private var errorMessage: String?
    @State private var isLoading = true
    @State private var isSaving = false
    @State private var showsDestinationPicker = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("下载设置").font(.title2.weight(.semibold))
                Spacer()
                if isLoading || isSaving {
                    ProgressView().controlSize(.small)
                }
            }

            if let settingsBinding {
                Form {
                    Section("常规") {
                        LabeledContent("默认保存位置") {
                            HStack(spacing: 8) {
                                Label(
                                    destinationDisplay(settingsBinding.wrappedValue),
                                    systemImage: "folder"
                                )
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                Button("选择…") {
                                    showsDestinationPicker = true
                                }
                            }
                        }
                        Toggle("启用 eMule 下载", isOn: settingsBinding.isEMuleEnabled)
                        Toggle("允许自动解压缩", isOn: settingsBinding.isAutoExtractEnabled)
                    }

                    Section("速度限制") {
                        speedField("BT 下载", value: settingsBinding.btDownloadLimit)
                        speedField("BT 上传", value: settingsBinding.btUploadLimit)
                        speedField("网页与 FTP 下载", value: webLimitBinding(settingsBinding))
                        speedField("NZB 下载", value: settingsBinding.nzbDownloadLimit)
                        speedField("eMule 下载", value: settingsBinding.emuleDownloadLimit)
                        speedField("eMule 上传", value: settingsBinding.emuleUploadLimit)
                        Text("填写 0 表示不限速。速度单位为 KB/s。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Section("下载计划") {
                        Toggle("启用下载计划", isOn: settingsBinding.isScheduleEnabled)
                        Toggle("将计划用于 eMule", isOn: settingsBinding.isEMuleScheduleEnabled)
                            .disabled(!settingsBinding.wrappedValue.isScheduleEnabled)
                    }
                }
                .formStyle(.grouped)
            } else if let errorMessage {
                ContentUnavailableView(
                    "无法读取下载设置",
                    systemImage: "gearshape.fill",
                    description: Text(errorMessage)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                Spacer()
            }

            HStack {
                Spacer()
                Button("取消", role: .cancel) { dismiss() }
                Button("保存") {
                    guard let settings else { return }
                    isSaving = true
                    Task {
                        _ = await save(settings)
                        isSaving = false
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(settings == nil || isLoading || isSaving)
            }
        }
        .padding(24)
        .frame(width: 680, height: 650)
        .task {
            do {
                settings = try await load()
            } catch let error as AppError {
                errorMessage = error.safeUserMessage
            } catch {
                errorMessage = "请确认当前账号拥有 Download Station 管理权限，然后重试。"
            }
            isLoading = false
        }
        .sheet(isPresented: $showsDestinationPicker) {
            DownloadDestinationPicker(
                selectedDestination: settings?.defaultDestination ?? "",
                loadFolders: loadFolders,
                onSelect: {
                    settings?.defaultDestination = $0
                    showsDestinationPicker = false
                },
                onCancel: {
                    showsDestinationPicker = false
                }
            )
        }
    }

    private var settingsBinding: Binding<DownloadStationSettings>? {
        guard settings != nil else { return nil }
        return Binding(
            get: { settings ?? DownloadStationSettings() },
            set: { settings = $0 }
        )
    }

    private func speedField(_ title: String, value: Binding<Int>) -> some View {
        LabeledContent(title) {
            HStack(spacing: 6) {
                TextField("0", value: value, format: .number)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 110)
                Text("KB/s").foregroundStyle(.secondary)
            }
        }
    }

    private func webLimitBinding(
        _ settings: Binding<DownloadStationSettings>
    ) -> Binding<Int> {
        Binding(
            get: { settings.wrappedValue.ftpDownloadLimit },
            set: {
                settings.wrappedValue.httpDownloadLimit = max(0, $0)
                settings.wrappedValue.ftpDownloadLimit = max(0, $0)
            }
        )
    }

    private func destinationDisplay(_ settings: DownloadStationSettings) -> String {
        let path = settings.defaultDestination.trimmingCharacters(
            in: CharacterSet(charactersIn: "/")
        )
        return path.isEmpty ? "尚未设置" : "/\(path)"
    }
}

private struct DownloadDestinationPicker: View {
    private struct Location {
        let path: String?
        let canWrite: Bool
    }

    let selectedDestination: String
    let loadFolders: (String?) async throws -> [FileItem]
    let onSelect: (String) -> Void
    let onCancel: () -> Void

    @State private var location = Location(path: nil, canWrite: false)
    @State private var history: [Location] = []
    @State private var folders: [FileItem] = []
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("选择 NAS 文件夹")
                    .font(.headline)
                Spacer()
                Button("取消") { onCancel() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)

            Divider()

            HStack(spacing: 8) {
                Button {
                    Task { await goBack() }
                } label: {
                    Label("返回", systemImage: "chevron.backward")
                }
                .labelStyle(.iconOnly)
                .disabled(history.isEmpty || isLoading)
                .help("返回上一级")
                Text(locationTitle)
                    .font(.subheadline)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .accessibilityLabel("当前位置：\(locationTitle)")
                Spacer()
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("正在载入文件夹")
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            Group {
                if isLoading && folders.isEmpty {
                    ProgressView("正在载入文件夹…")
                        .fillsAvailableContentArea()
                } else if let errorMessage {
                    ContentUnavailableView {
                        Label("无法读取文件夹", systemImage: "exclamationmark.triangle")
                    } description: {
                        Text(errorMessage)
                    } actions: {
                        Button("重新载入") {
                            Task { await reload() }
                        }
                    }
                    .fillsAvailableContentArea()
                } else if folders.isEmpty {
                    ContentUnavailableView(
                        "这里没有子文件夹",
                        systemImage: "folder",
                        description: Text(
                            location.path == nil
                                ? "当前账号没有可用的共享文件夹。"
                                : "可以选择当前文件夹，或返回上一级继续查找。"
                        )
                    )
                    .fillsAvailableContentArea()
                } else {
                    folderList
                }
            }

            Divider()

            HStack(spacing: 12) {
                Text(selectionHint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                Spacer()
                Button("取消") { onCancel() }
                Button("选择此文件夹") {
                    guard let path = location.path else { return }
                    onSelect(Self.downloadStationPath(from: path))
                }
                .buttonStyle(.borderedProminent)
                .disabled(location.path == nil || !location.canWrite || isLoading)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .frame(minWidth: 540, minHeight: 440)
        .task { await reload() }
    }

    private var folderList: some View {
        List(folders) { folder in
            let canWrite = folder.permissions?.canWrite != false
            Button {
                Task { await open(folder) }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: canWrite ? "folder.fill" : "folder.badge.minus")
                        .foregroundStyle(canWrite ? Color.blue : Color.secondary)
                        .accessibilityHidden(true)
                    Text(folder.name)
                        .lineLimit(1)
                    if Self.downloadStationPath(from: folder.path) == selectedDestination {
                        Text("当前选择")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .disabled(isLoading)
            .accessibilityHint(
                canWrite
                    ? "打开文件夹"
                    : "打开文件夹；此文件夹本身不可作为保存位置"
            )
        }
        .listStyle(.inset)
    }

    private var locationTitle: String {
        location.path ?? "共享文件夹"
    }

    private var selectionHint: String {
        guard location.path != nil else {
            return "请选择一个共享文件夹。"
        }
        return location.canWrite
            ? "下载内容将保存到当前文件夹。"
            : "当前账号不能写入这个文件夹，请选择其他位置。"
    }

    private func open(_ folder: FileItem) async {
        let previous = location
        history.append(previous)
        location = Location(
            path: folder.path,
            canWrite: folder.permissions?.canWrite != false
        )
        await reload()
    }

    private func goBack() async {
        guard let previous = history.popLast() else { return }
        location = previous
        await reload()
    }

    private func reload() async {
        isLoading = true
        errorMessage = nil
        do {
            folders = try await loadFolders(location.path)
            isLoading = false
        } catch {
            folders = []
            errorMessage = (error as? AppError)?.safeUserMessage
                ?? "NAS 没有返回文件夹列表，请检查连接后重试。"
            isLoading = false
        }
    }

    private static func downloadStationPath(from fileStationPath: String) -> String {
        fileStationPath.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    }
}

private struct ContainerManagerView: View {
    enum Pane: String, CaseIterable, Identifiable {
        case overview
        case containers
        case images
        case networks
        case projects
        case events

        var id: Self { self }
        var title: String {
            switch self {
            case .overview: "总览"
            case .containers: "容器"
            case .images: "映像"
            case .networks: "网络"
            case .projects: "项目"
            case .events: "活动记录"
            }
        }
    }

    @Bindable var model: ServiceManagementModel
    @State private var pane: Pane = .overview
    @State private var confirmsContainerDelete = false
    @State private var confirmsImageDelete = false
    @State private var confirmsNetworkDelete = false
    @State private var showsPullImage = false
    @State private var showsCreateNetwork = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ServiceHeader(
                title: "容器管理",
                subtitle: containerSummary,
                icon: "shippingbox.fill",
                tint: .blue,
                isLoading: model.isLoading
            ) { Task { await model.activate(.containers, force: true) } }
            Picker("", selection: $pane) {
                ForEach(Pane.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            Group {
                switch pane {
                case .overview: overview
                case .containers: containerList
                case .images: imageList
                case .networks: networkList
                case .projects: projectList
                case .events: eventList(model.containers?.events ?? [])
                }
            }
        }
        .padding(20)
        .confirmationDialog("删除所选容器？", isPresented: $confirmsContainerDelete) {
            Button("删除容器", role: .destructive) {
                Task { await model.deleteContainers() }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("容器会从 NAS 移除。映像和共享文件夹中的数据不会自动删除。")
        }
        .confirmationDialog("删除所选映像？", isPresented: $confirmsImageDelete) {
            Button("删除映像", role: .destructive) {
                Task { await model.deleteImages() }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("正在使用的映像不会被删除；请先停止并移除相关容器。")
        }
        .confirmationDialog("删除所选网络？", isPresented: $confirmsNetworkDelete) {
            Button("删除网络", role: .destructive) {
                Task { await model.deleteNetworks() }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("请先确认没有容器仍连接到这些网络。")
        }
        .sheet(isPresented: $showsPullImage) {
            PullImageSheet(
                search: { try await model.searchImages(query: $0) },
                loadTags: { try await model.loadImageTags(repositoryName: $0) },
                submit: { repository, tag in
                    let succeeded = await model.pullImage(repositoryName: repository, tag: tag)
                    if succeeded {
                        showsPullImage = false
                        return nil
                    }
                    return model.message ?? "映像下载未能开始，请检查连接后重试。"
                }
            )
        }
        .sheet(isPresented: $showsCreateNetwork) {
            CreateNetworkSheet { name, driver in
                let succeeded = await model.createNetwork(name: name, driver: driver)
                if succeeded { showsCreateNetwork = false }
                return succeeded
            }
        }
    }

    private var containerSummary: String {
        let containers = model.containers?.containers ?? []
        let running = containers.filter {
            ["running", "started", "up"].contains($0.status.lowercased())
        }.count
        return "\(running) 个正在运行 · 共 \(containers.count) 个"
    }

    private var overview: some View {
        let snapshot = model.containers
        return LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 180), spacing: 14)],
            spacing: 14
        ) {
            SummaryCard(title: "容器", value: "\(snapshot?.containers.count ?? 0)", icon: "shippingbox", tint: .blue)
            SummaryCard(title: "映像", value: "\(snapshot?.images.count ?? 0)", icon: "square.stack.3d.up", tint: .purple)
            SummaryCard(title: "网络", value: "\(snapshot?.networks.count ?? 0)", icon: "network", tint: .green)
            SummaryCard(title: "项目", value: "\(snapshot?.projects.count ?? 0)", icon: "square.grid.2x2", tint: .orange)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.top, 8)
    }

    private var containerList: some View {
        VStack(spacing: 10) {
            HStack {
                Button("启动") { Task { await model.controlContainers(.start) } }
                Button("停止") { Task { await model.controlContainers(.stop) } }
                Button("重新启动") { Task { await model.controlContainers(.restart) } }
                Spacer()
                Button("删除", role: .destructive) { confirmsContainerDelete = true }
            }
            .disabled(model.containerSelection.isEmpty || model.isPerformingAction)
            List(model.containers?.containers ?? [], selection: $model.containerSelection) { item in
                HStack {
                    StatusDot(status: item.status)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.name).fontWeight(.medium)
                        Text(item.image).font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    if let cpu = item.cpuUsage {
                        Text("处理器 \(cpu, specifier: "%.1f")%")
                    }
                    if let memory = item.memoryBytes {
                        Text(ServiceFormat.bytes(memory))
                    }
                    Text(ServiceFormat.status(item.status))
                        .foregroundStyle(.secondary)
                }
                .font(.callout)
                .padding(.vertical, 4)
                .tag(item.id)
            }
            .listStyle(.inset)
        }
    }

    private var imageList: some View {
        VStack(spacing: 10) {
            HStack {
                Spacer()
                Button("删除", role: .destructive) { confirmsImageDelete = true }
                    .disabled(model.imageSelection.isEmpty || model.isPerformingAction)
                Button {
                    model.clearMessage()
                    showsPullImage = true
                } label: {
                    Label("搜索并下载", systemImage: "magnifyingglass")
                }
                .buttonStyle(.borderedProminent)
            }
            List(model.containers?.images ?? [], selection: $model.imageSelection) { image in
                HStack {
                    Image(systemName: "square.stack.3d.up.fill").foregroundStyle(.purple)
                    Text(image.repository).fontWeight(.medium)
                    Text(image.tag).foregroundStyle(.secondary)
                    Spacer()
                    Text(ServiceFormat.bytes(image.sizeBytes ?? 0)).foregroundStyle(.secondary)
                    if image.isInUse {
                        Text("使用中")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.green)
                    }
                }
                .padding(.vertical, 4)
                .tag(image.id)
            }
            .listStyle(.inset)
        }
    }

    private var networkList: some View {
        VStack(spacing: 10) {
            HStack {
                Spacer()
                Button("删除", role: .destructive) { confirmsNetworkDelete = true }
                    .disabled(model.networkSelection.isEmpty || model.isPerformingAction)
                Button {
                    showsCreateNetwork = true
                } label: {
                    Label("新建网络", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
            }
            List(model.containers?.networks ?? [], selection: $model.networkSelection) { network in
                HStack {
                    Image(systemName: "network").foregroundStyle(.green)
                    Text(network.name).fontWeight(.medium)
                    Text(network.driver).foregroundStyle(.secondary)
                    Spacer()
                    Text("\(network.connectedContainerCount) 个容器")
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 4)
                .tag(network.id)
            }
            .listStyle(.inset)
        }
    }

    private var projectList: some View {
        List(model.containers?.projects ?? []) { project in
            HStack {
                StatusDot(status: project.status)
                Text(project.name).fontWeight(.medium)
                Spacer()
                Text("\(project.containerCount) 个容器").foregroundStyle(.secondary)
                Text(ServiceFormat.status(project.status)).foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
        }
        .listStyle(.inset)
    }

    private func eventList(_ events: [ServiceEvent]) -> some View {
        List(events) { event in
            HStack(alignment: .top) {
                Text(event.timestamp?.formatted(date: .numeric, time: .standard) ?? "—")
                    .foregroundStyle(.secondary)
                    .frame(width: 150, alignment: .leading)
                Text(event.level).frame(width: 72, alignment: .leading)
                Text(event.message).textSelection(.enabled)
            }
            .font(.callout)
            .padding(.vertical, 3)
        }
        .listStyle(.inset)
    }
}

private struct VirtualMachineManagerView: View {
    enum Pane: String, CaseIterable, Identifiable {
        case machines
        case hosts
        case storages
        case networks
        case images
        case protection
        case events

        var id: Self { self }
        var title: String {
            switch self {
            case .machines: "虚拟机"
            case .hosts: "主机"
            case .storages: "存储"
            case .networks: "网络"
            case .images: "映像"
            case .protection: "保护"
            case .events: "日志"
            }
        }
    }

    enum ProtectionPane: String, CaseIterable, Identifiable {
        case plans
        case schedules
        case retentions

        var id: Self { self }
        var title: String {
            switch self {
            case .plans: "保护计划"
            case .schedules: "计划策略"
            case .retentions: "保留策略"
            }
        }
    }

    @Bindable var model: ServiceManagementModel
    @State private var pane: Pane = .machines
    @State private var protectionPane: ProtectionPane = .plans
    @State private var pendingPowerAction: VirtualMachinePowerAction?
    @State private var confirmsDelete = false
    @State private var confirmsNetworkDelete = false
    @State private var confirmsImageDelete = false
    @State private var deletingImage: VirtualizationResource?
    @State private var showsCreation = false
    @State private var editingMachine: VirtualMachine?
    @State private var editingNetwork: VirtualizationResource?
    @State private var logSearch = ""
    @State private var logLevel = "全部"
    @State private var consoleWindowController: VirtualMachineConsoleWindowController?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ServiceHeader(
                title: "虚拟机管理",
                subtitle: "\(model.virtualMachines?.machines.count ?? 0) 台虚拟机",
                icon: "desktopcomputer",
                tint: .indigo,
                isLoading: model.isLoading
            ) { Task { await model.activate(.virtualMachines, force: true) } }
            Picker("", selection: $pane) {
                ForEach(Pane.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            switch pane {
            case .machines: machineList
            case .hosts:
                resourceList(
                    model.virtualMachines?.hosts ?? [],
                    icon: "server.rack",
                    section: .hosts
                )
            case .storages:
                resourceList(
                    model.virtualMachines?.storages ?? [],
                    icon: "internaldrive",
                    section: .storages
                )
            case .networks: networkList
            case .images: imageList
            case .protection: protectionView
            case .events: eventList
            }
        }
        .padding(20)
        .confirmationDialog(
            powerConfirmationTitle,
            isPresented: Binding(
                get: { pendingPowerAction != nil },
                set: { if !$0 { pendingPowerAction = nil } }
            )
        ) {
            Button(powerConfirmationButton, role: pendingPowerAction == .powerOff ? .destructive : nil) {
                guard let action = pendingPowerAction else { return }
                pendingPowerAction = nil
                Task { await model.controlVirtualMachines(action) }
            }
            Button("取消", role: .cancel) { pendingPowerAction = nil }
        } message: {
            Text(powerConfirmationMessage)
        }
        .confirmationDialog("删除所选虚拟机？", isPresented: $confirmsDelete) {
            Button("删除虚拟机", role: .destructive) {
                Task { await model.deleteVirtualMachines() }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("虚拟机及其配置会被移除。请先确认重要数据已有备份。")
        }
        .confirmationDialog("删除所选网络？", isPresented: $confirmsNetworkDelete) {
            Button("删除网络", role: .destructive) {
                Task { await model.deleteVirtualMachineNetworks() }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("使用中的网络可能无法删除。删除后，连接到该网络的虚拟机可能无法正常通信。")
        }
        .confirmationDialog(
            deletingImage != nil ? "确定要删除映像“\(deletingImage?.name ?? "")”吗？" : "删除所选映像？",
            isPresented: Binding(
                get: { confirmsImageDelete || deletingImage != nil },
                set: { if !$0 { confirmsImageDelete = false; deletingImage = nil } }
            )
        ) {
            Button("删除映像", role: .destructive) {
                if let image = deletingImage {
                    model.virtualMachineImageSelection = [image.id]
                }
                deletingImage = nil
                confirmsImageDelete = false
                Task { await model.deleteVirtualMachineImages() }
            }
            Button("取消", role: .cancel) {
                deletingImage = nil
                confirmsImageDelete = false
            }
        } message: {
            if let image = deletingImage {
                Text("映像“\(image.name)”将会从这台 NAS 移除。已使用此映像安装的虚拟机不会被删除。")
            } else {
                Text("映像会从这台 NAS 移除。已使用此映像安装的虚拟机不会被删除。")
            }
        }
        .sheet(isPresented: $showsCreation) {
            CreateVirtualMachineSheet(
                snapshot: model.virtualMachines,
                submit: { await model.createVirtualMachine($0) }
            )
        }
        .sheet(item: $editingMachine) { machine in
            EditVirtualMachineSheet(
                machine: machine,
                submit: { await model.updateVirtualMachine(id: machine.id, configuration: $0) }
            )
        }
        .sheet(item: $editingNetwork) { network in
            EditVirtualMachineNetworkSheet(
                network: network,
                submit: {
                    await model.updateVirtualMachineNetwork(
                        id: network.id,
                        configuration: $0
                    )
                }
            )
        }
    }

    private var machineList: some View {
        VStack(spacing: 10) {
            HStack {
                Button {
                    showsCreation = true
                } label: {
                    Label("新建", systemImage: "plus")
                }
                .keyboardShortcut("n", modifiers: .command)
                .disabled(
                    model.isPerformingAction
                        || model.virtualMachines?.storages.isEmpty != false
                        || model.virtualMachines?.networks.isEmpty != false
                )
                Button {
                    editingMachine = selectedMachine
                } label: {
                    Label("修改", systemImage: "slider.horizontal.3")
                }
                .disabled(selectedMachine == nil || model.isPerformingAction)
                Button {
                    if let consoleWindowController {
                        consoleWindowController.show()
                        return
                    }
                    guard let machine = selectedMachine else { return }
                    Task {
                        guard let session = await model.openVirtualMachineConsole(id: machine.id) else {
                            return
                        }
                        let controller = VirtualMachineConsoleWindowController(
                            machineName: machine.name,
                            session: session
                        )
                        controller.onClose = {
                            consoleWindowController = nil
                        }
                        consoleWindowController = controller
                        controller.show()
                    }
                } label: {
                    Label("远程连接", systemImage: "display")
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(
                    selectedMachine == nil
                        || selectedMachine.map { !isRunning($0.status) } == true
                        || model.isPerformingAction
                )
                Divider().frame(height: 18)
                Button("启动") { pendingPowerAction = .powerOn }
                Button("正常关机") { pendingPowerAction = .shutdown }
                Menu("更多") {
                    Button("重新启动") { pendingPowerAction = .restart }
                    Divider()
                    Button("强制断电…", role: .destructive) {
                        pendingPowerAction = .powerOff
                    }
                    Button("删除…", role: .destructive) { confirmsDelete = true }
                }
                Spacer()
            }
            .disabled(model.virtualMachineSelection.isEmpty || model.isPerformingAction)

            let machines = model.virtualMachines?.machines ?? []
            if machines.isEmpty, !model.isLoading {
                EmptyServiceState(
                    title: "还没有虚拟机",
                    message: "选择“新建”即可配置处理器、内存、存储、网络和安装映像。",
                    icon: "desktopcomputer"
                )
            } else {
                List(machines, selection: $model.virtualMachineSelection) { machine in
                    HStack {
                        StatusDot(status: machine.status)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(machine.name).fontWeight(.medium)
                            Text(machine.host ?? "未分配主机")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if let cpu = machine.cpuCount { Text("\(cpu) 核") }
                        if let memory = machine.memoryBytes { Text(ServiceFormat.bytes(memory)) }
                        Text(ServiceFormat.status(machine.status)).foregroundStyle(.secondary)
                    }
                    .font(.callout)
                    .padding(.vertical, 4)
                    .tag(machine.id)
                }
                .listStyle(.inset)
            }
        }
    }

    private var selectedMachine: VirtualMachine? {
        guard model.virtualMachineSelection.count == 1,
              let id = model.virtualMachineSelection.first else {
            return nil
        }
        return model.virtualMachines?.machines.first(where: { $0.id == id })
    }

    private func isRunning(_ status: String) -> Bool {
        ["running", "started", "up", "online"].contains(status.lowercased())
    }

    private func resourceList(
        _ resources: [VirtualizationResource],
        icon: String,
        section: VirtualMachineManagerSection? = nil
    ) -> some View {
        Group {
            if let section, isUnavailable(section) {
                unavailableState(icon: icon)
            } else if resources.isEmpty, !model.isLoading {
                EmptyServiceState(
                    title: "没有可显示的项目",
                    message: "这台 NAS 没有返回当前类别的内容。",
                    icon: icon
                )
            } else {
                List(resources) { resource in
                    HStack {
                        Image(systemName: icon).foregroundStyle(.indigo)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(resource.name).fontWeight(.medium)
                            if let detail = resource.detail {
                                Text(detail).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        if let status = resource.status {
                            Text(ServiceFormat.status(status)).foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                }
                .listStyle(.inset)
            }
        }
    }

    private var networkList: some View {
        VStack(spacing: 10) {
            HStack {
                Button {
                    editingNetwork = selectedNetwork
                } label: {
                    Label("修改", systemImage: "pencil")
                }
                .disabled(selectedNetwork == nil || model.isPerformingAction)
                Button(role: .destructive) {
                    confirmsNetworkDelete = true
                } label: {
                    Label("删除", systemImage: "trash")
                }
                .disabled(
                    model.virtualMachineNetworkSelection.isEmpty
                        || model.isPerformingAction
                )
                Spacer()
            }

            if isUnavailable(.networks) {
                unavailableState(icon: "network")
            } else {
                selectableResourceList(
                    model.virtualMachines?.networks ?? [],
                    selection: $model.virtualMachineNetworkSelection,
                    icon: "network",
                    emptyMessage: "这台 NAS 还没有可管理的虚拟网络。"
                )
            }
        }
    }

    private var imageList: some View {
        Group {
            if isUnavailable(.images) {
                unavailableState(icon: "opticaldisc")
            } else {
                selectableResourceList(
                    model.virtualMachines?.images ?? [],
                    selection: $model.virtualMachineImageSelection,
                    icon: "opticaldisc",
                    emptyMessage: "这台 NAS 还没有可管理的安装映像。",
                    onDelete: { resource in
                        deletingImage = resource
                        model.virtualMachineImageSelection = [resource.id]
                        confirmsImageDelete = true
                    }
                )
            }
        }
    }

    private func selectableResourceList(
        _ resources: [VirtualizationResource],
        selection: Binding<Set<String>>,
        icon: String,
        emptyMessage: String,
        onDelete: ((VirtualizationResource) -> Void)? = nil
    ) -> some View {
        Group {
            if resources.isEmpty, !model.isLoading {
                EmptyServiceState(
                    title: "没有可显示的项目",
                    message: emptyMessage,
                    icon: icon
                )
            } else {
                List(resources, selection: selection) { resource in
                    HStack {
                        Image(systemName: icon)
                            .foregroundStyle(.indigo)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(resource.name).fontWeight(.medium)
                            if let detail = resource.detail {
                                Text(detail)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        if let status = resource.status {
                            Text(ServiceFormat.status(status))
                                .foregroundStyle(.secondary)
                        }
                        if let onDelete {
                            Button(role: .destructive) {
                                onDelete(resource)
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                            .buttonStyle(.borderless)
                            .disabled(model.isPerformingAction)
                            .help("删除此项目")
                        }
                    }
                    .font(.callout)
                    .padding(.vertical, 4)
                    .tag(resource.id)
                    .contextMenu {
                        if let onDelete {
                            Button(role: .destructive) {
                                onDelete(resource)
                            } label: {
                                Label("删除", systemImage: "trash")
                            }
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
    }

    private var selectedNetwork: VirtualizationResource? {
        guard model.virtualMachineNetworkSelection.count == 1,
              let id = model.virtualMachineNetworkSelection.first else {
            return nil
        }
        return model.virtualMachines?.networks.first(where: { $0.id == id })
    }

    private var protectionView: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("保护内容", selection: $protectionPane) {
                ForEach(ProtectionPane.allCases) { item in
                    Text(item.title).tag(item)
                }
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 420)

            if isUnavailable(.protection) {
                unavailableState(icon: "shield.checkered")
            } else {
                switch protectionPane {
                case .plans:
                    resourceList(
                        model.virtualMachines?.protectionPlans ?? [],
                        icon: "shield.checkered"
                    )
                case .schedules:
                    resourceList(
                        model.virtualMachines?.protectionSchedulePolicies ?? [],
                        icon: "calendar.badge.clock"
                    )
                case .retentions:
                    resourceList(
                        model.virtualMachines?.protectionRetentionPolicies ?? [],
                        icon: "clock.arrow.circlepath"
                    )
                }
            }
        }
    }

    private var eventList: some View {
        VStack(spacing: 10) {
            HStack {
                Picker("级别", selection: $logLevel) {
                    ForEach(logLevels, id: \.self) { Text($0).tag($0) }
                }
                .frame(width: 150)
                TextField("搜索日志", text: $logSearch)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 280)
                Spacer()
                Text("\(filteredEvents.count) 条")
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("共 \(filteredEvents.count) 条日志")
            }

            if isUnavailable(.logs) {
                unavailableState(icon: "list.bullet.rectangle")
            } else if filteredEvents.isEmpty, !model.isLoading {
                EmptyServiceState(
                    title: logSearch.isEmpty && logLevel == "全部" ? "还没有日志" : "没有匹配的日志",
                    message: logSearch.isEmpty && logLevel == "全部"
                        ? "这台 NAS 暂时没有返回虚拟机管理日志。"
                        : "请尝试其他关键词或级别。",
                    icon: "list.bullet.rectangle"
                )
            } else {
                List(filteredEvents) { event in
                    HStack(alignment: .top, spacing: 12) {
                        Text(event.timestamp?.formatted(date: .numeric, time: .standard) ?? "—")
                            .foregroundStyle(.secondary)
                            .frame(width: 150, alignment: .leading)
                        Text(event.level)
                            .foregroundStyle(logColor(event.level))
                            .frame(width: 72, alignment: .leading)
                        Text(event.user ?? "—")
                            .foregroundStyle(.secondary)
                            .frame(width: 120, alignment: .leading)
                        Text(event.message)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .font(.callout)
                    .padding(.vertical, 3)
                }
                .listStyle(.inset)
            }
        }
    }

    private var logLevels: [String] {
        let levels = Set((model.virtualMachines?.events ?? []).map(\.level))
        return ["全部"] + levels.sorted()
    }

    private var filteredEvents: [ServiceEvent] {
        (model.virtualMachines?.events ?? []).filter { event in
            let matchesLevel = logLevel == "全部" || event.level == logLevel
            let query = logSearch.trimmingCharacters(in: .whitespacesAndNewlines)
            guard matchesLevel, !query.isEmpty else { return matchesLevel }
            return event.message.localizedCaseInsensitiveContains(query)
                || event.level.localizedCaseInsensitiveContains(query)
                || event.user?.localizedCaseInsensitiveContains(query) == true
        }
    }

    private func logColor(_ level: String) -> Color {
        let normalized = level.lowercased()
        if normalized.contains("error") || level.contains("错误") { return .red }
        if normalized.contains("warn") || level.contains("警告") { return .orange }
        return .primary
    }

    private func isUnavailable(_ section: VirtualMachineManagerSection) -> Bool {
        model.virtualMachines?.unavailableSections.contains(section) == true
    }

    private func unavailableState(icon: String) -> some View {
        VStack(spacing: 12) {
            EmptyServiceState(
                title: "暂时无法读取",
                message: "这台 NAS 没有返回当前内容。请刷新；如果仍然失败，请确认账号有虚拟机管理权限。",
                icon: icon
            )
            Button("重新加载") {
                Task { await model.activate(.virtualMachines, force: true) }
            }
            .disabled(model.isLoading)
        }
    }

    private var powerConfirmationTitle: String {
        switch pendingPowerAction {
        case .powerOn: "启动所选虚拟机？"
        case .shutdown: "让所选虚拟机正常关机？"
        case .powerOff: "强制断电？"
        case .restart: "重新启动所选虚拟机？"
        case nil: ""
        }
    }

    private var powerConfirmationButton: String {
        switch pendingPowerAction {
        case .powerOn: "启动"
        case .shutdown: "正常关机"
        case .powerOff: "强制断电"
        case .restart: "重新启动"
        case nil: ""
        }
    }

    private var powerConfirmationMessage: String {
        pendingPowerAction == .powerOff
            ? "强制断电可能导致虚拟机内尚未保存的数据丢失。优先使用“正常关机”。"
            : "请确认虚拟机中的工作已妥善保存。"
    }
}

private struct EditVirtualMachineNetworkSheet: View {
    let network: VirtualizationResource
    let submit: (VirtualMachineNetworkUpdate) async -> Bool
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var isSaving = false

    init(
        network: VirtualizationResource,
        submit: @escaping (VirtualMachineNetworkUpdate) async -> Bool
    ) {
        self.network = network
        self.submit = submit
        _name = State(initialValue: network.name)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("修改网络")
                .font(.title2.bold())
            Form {
                TextField("名称", text: $name)
                    .textFieldStyle(.roundedBorder)
            }
            Text("修改名称不会改变虚拟机当前的网络连接。")
                .font(.callout)
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("取消", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(isSaving ? "正在保存…" : "保存") {
                    isSaving = true
                    Task {
                        let succeeded = await submit(
                            VirtualMachineNetworkUpdate(
                                name: name.trimmingCharacters(in: .whitespacesAndNewlines)
                            )
                        )
                        isSaving = false
                        if succeeded { dismiss() }
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(
                    isSaving
                        || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )
            }
        }
        .padding(24)
        .frame(width: 440)
        .interactiveDismissDisabled(isSaving)
    }
}

private struct CreateVirtualMachineSheet: View {
    let snapshot: VirtualMachineManagerSnapshot?
    let submit: (VirtualMachineCreation) async -> Bool
    @Environment(\.dismiss) private var dismiss
    @State private var step = 0
    @State private var name = ""
    @State private var operatingSystem: VirtualMachineOperatingSystem = .linux
    @State private var description = ""
    @State private var cpuCount = 2
    @State private var memoryGiB = 2
    @State private var diskGiB = 20
    @State private var storageID = ""
    @State private var networkID = ""
    @State private var imageID = ""
    @State private var firmware: VirtualMachineFirmware = .legacy
    @State private var autoStart = false
    @State private var powerOnAfterCreation = false
    @State private var confirmsCreation = false
    @State private var isSubmitting = false

    private let stepTitles = ["基本信息", "计算资源", "存储与启动"]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("新建虚拟机").font(.title2.weight(.semibold))
                    Text("第 \(step + 1) 步，共 \(stepTitles.count) 步 · \(stepTitles[step])")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                ProgressView(value: Double(step + 1), total: Double(stepTitles.count))
                    .frame(width: 180)
                    .accessibilityLabel("创建进度")
                    .accessibilityValue("第 \(step + 1) 步，共 \(stepTitles.count) 步")
            }
            .padding(20)

            Divider()

            Form {
                switch step {
                case 0:
                    Section("虚拟机") {
                        TextField("名称", text: $name)
                            .accessibilityHint("输入一个不与现有虚拟机重复的名称")
                        Picker("操作系统", selection: $operatingSystem) {
                            Text("Microsoft Windows").tag(VirtualMachineOperatingSystem.windows)
                            Text("Linux").tag(VirtualMachineOperatingSystem.linux)
                            Text("其他").tag(VirtualMachineOperatingSystem.other)
                        }
                        TextField("描述（可选）", text: $description, axis: .vertical)
                            .lineLimit(2...4)
                    }
                case 1:
                    Section("处理器与内存") {
                        Stepper("处理器：\(cpuCount) 核", value: $cpuCount, in: 1...64)
                        Stepper("内存：\(memoryGiB) GB", value: $memoryGiB, in: 1...1_024)
                        Text("请为 NAS 和其他虚拟机保留足够资源。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                default:
                    Section("存储与网络") {
                        Picker("存储空间", selection: $storageID) {
                            ForEach(snapshot?.storages ?? []) { resource in
                                Text(resource.name).tag(resource.id)
                            }
                        }
                        Stepper("虚拟磁盘：\(diskGiB) GB", value: $diskGiB, in: 1...1_048_576)
                        Picker("网络", selection: $networkID) {
                            ForEach(snapshot?.networks ?? []) { resource in
                                Text(resource.name).tag(resource.id)
                            }
                        }
                    }
                    Section("启动") {
                        Picker("安装映像", selection: $imageID) {
                            Text("暂不挂载").tag("")
                            ForEach(snapshot?.images ?? []) { resource in
                                Text(resource.name).tag(resource.id)
                            }
                        }
                        Picker("固件", selection: $firmware) {
                            Text("Legacy BIOS").tag(VirtualMachineFirmware.legacy)
                            Text("UEFI").tag(VirtualMachineFirmware.uefi)
                        }
                        Toggle("NAS 启动后自动启动这台虚拟机", isOn: $autoStart)
                        Toggle("创建完成后立即启动", isOn: $powerOnAfterCreation)
                    }
                }
            }
            .formStyle(.grouped)
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            HStack {
                Button("取消", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                if step > 0 {
                    Button("上一步") { step -= 1 }
                        .disabled(isSubmitting)
                }
                if step < stepTitles.count - 1 {
                    Button("下一步") { step += 1 }
                        .buttonStyle(.borderedProminent)
                        .keyboardShortcut(.defaultAction)
                        .disabled(!canContinue || isSubmitting)
                } else {
                    Button {
                        confirmsCreation = true
                    } label: {
                        if isSubmitting {
                            ProgressView().controlSize(.small)
                        } else {
                            Text("创建虚拟机…")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canCreate || isSubmitting)
                }
            }
            .padding(20)
        }
        .frame(minWidth: 620, idealWidth: 680, minHeight: 500, idealHeight: 580)
        .onAppear {
            storageID = storageID.isEmpty ? snapshot?.storages.first?.id ?? "" : storageID
            networkID = networkID.isEmpty ? snapshot?.networks.first?.id ?? "" : networkID
        }
        .interactiveDismissDisabled(isSubmitting)
        .confirmationDialog("创建这台虚拟机？", isPresented: $confirmsCreation) {
            Button("创建虚拟机") {
                Task {
                    isSubmitting = true
                    let succeeded = await submit(configuration)
                    isSubmitting = false
                    if succeeded { dismiss() }
                }
            }
            Button("返回检查", role: .cancel) {}
        } message: {
            Text("将占用 \(cpuCount) 核处理器、\(memoryGiB) GB 内存和 \(diskGiB) GB 存储空间。创建过程中请勿关闭 NAS。")
        }
    }

    private var normalizedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var canContinue: Bool {
        switch step {
        case 0:
            !normalizedName.isEmpty
                && normalizedName.count <= 255
                && description.count <= 1_024
        default:
            true
        }
    }

    private var canCreate: Bool {
        !normalizedName.isEmpty && !storageID.isEmpty && !networkID.isEmpty
    }

    private var configuration: VirtualMachineCreation {
        VirtualMachineCreation(
            name: normalizedName,
            operatingSystem: operatingSystem,
            storageID: storageID,
            networkID: networkID,
            bootImageID: imageID.isEmpty ? nil : imageID,
            cpuCount: cpuCount,
            memoryMiB: memoryGiB * 1_024,
            diskGiB: diskGiB,
            description: description.trimmingCharacters(in: .whitespacesAndNewlines),
            firmware: firmware,
            autoStart: autoStart,
            powerOnAfterCreation: powerOnAfterCreation
        )
    }
}

private struct EditVirtualMachineSheet: View {
    let machine: VirtualMachine
    let submit: (VirtualMachineUpdate) async -> Bool
    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var description: String
    @State private var cpuCount: Int
    @State private var memoryGiB: Int
    @State private var priority: Int
    @State private var autoStart: Bool
    @State private var confirmsSave = false
    @State private var isSubmitting = false

    init(
        machine: VirtualMachine,
        submit: @escaping (VirtualMachineUpdate) async -> Bool
    ) {
        self.machine = machine
        self.submit = submit
        _name = State(initialValue: machine.name)
        _description = State(initialValue: machine.description ?? "")
        _cpuCount = State(initialValue: machine.cpuCount ?? 1)
        _memoryGiB = State(
            initialValue: max(1, Int((machine.memoryBytes ?? 1_073_741_824) / 1_073_741_824))
        )
        _priority = State(initialValue: machine.cpuWeight ?? 256)
        _autoStart = State(initialValue: machine.autoStart)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("修改虚拟机").font(.title2.weight(.semibold))
                Text(machine.name).font(.callout).foregroundStyle(.secondary)
            }
            .padding(20)

            Divider()

            Form {
                Section("常规") {
                    TextField("名称", text: $name)
                    TextField("描述（可选）", text: $description, axis: .vertical)
                        .lineLimit(2...4)
                    Picker("运行优先级", selection: $priority) {
                        Text("较低").tag(128)
                        Text("标准").tag(256)
                        Text("较高").tag(512)
                    }
                    Toggle("NAS 启动后自动启动这台虚拟机", isOn: $autoStart)
                }
                Section("处理器与内存") {
                    Stepper("处理器：\(cpuCount) 核", value: $cpuCount, in: 1...64)
                        .disabled(isRunning)
                    Stepper("内存：\(memoryGiB) GB", value: $memoryGiB, in: 1...1_024)
                        .disabled(isRunning)
                    if isRunning {
                        Label(
                            "虚拟机正在运行。名称、描述、优先级和自动启动可以立即保存；处理器和内存需先正常关机。",
                            systemImage: "info.circle"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .accessibilityElement(children: .combine)
                    }
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Button("取消", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("保存修改…") { confirmsSave = true }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!isValid || !hasChanges || isSubmitting)
            }
            .padding(20)
        }
        .frame(minWidth: 560, idealWidth: 620, minHeight: 460, idealHeight: 520)
        .interactiveDismissDisabled(isSubmitting)
        .confirmationDialog("保存这些修改？", isPresented: $confirmsSave) {
            Button("保存修改") {
                Task {
                    isSubmitting = true
                    let succeeded = await submit(update)
                    isSubmitting = false
                    if succeeded { dismiss() }
                }
            }
            Button("返回检查", role: .cancel) {}
        } message: {
            Text(isRunning ? "在线可修改的设置会立即生效。" : "新的处理器和内存配置将在下次启动时使用。")
        }
    }

    private var isRunning: Bool {
        ["running", "started", "up", "online"].contains(machine.status.lowercased())
    }

    private var normalizedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var isValid: Bool {
        !normalizedName.isEmpty && normalizedName.count <= 255 && description.count <= 1_024
    }

    private var hasChanges: Bool {
        normalizedName != machine.name
            || description != (machine.description ?? "")
            || priority != (machine.cpuWeight ?? 256)
            || autoStart != machine.autoStart
            || (!isRunning && cpuCount != (machine.cpuCount ?? 1))
            || (!isRunning
                && memoryGiB
                    != max(1, Int((machine.memoryBytes ?? 1_073_741_824) / 1_073_741_824)))
    }

    private var update: VirtualMachineUpdate {
        VirtualMachineUpdate(
            name: normalizedName == machine.name ? nil : normalizedName,
            description: description == (machine.description ?? "") ? nil : description,
            cpuCount: !isRunning && cpuCount != (machine.cpuCount ?? 1) ? cpuCount : nil,
            memoryMiB: !isRunning
                && memoryGiB
                    != max(1, Int((machine.memoryBytes ?? 1_073_741_824) / 1_073_741_824))
                ? memoryGiB * 1_024
                : nil,
            cpuWeight: priority == (machine.cpuWeight ?? 256) ? nil : priority,
            autoStart: autoStart == machine.autoStart ? nil : autoStart
        )
    }
}

@MainActor
private final class VirtualMachineConsoleWindowController: NSWindowController, NSWindowDelegate {
    var onClose: (() -> Void)?

    init(machineName: String, session: VirtualMachineConsoleSession) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1_100, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "\(machineName) — 远程控制台"
        window.minSize = NSSize(width: 720, height: 480)
        window.collectionBehavior.insert(.fullScreenPrimary)
        window.tabbingMode = .disallowed
        window.isReleasedWhenClosed = false

        super.init(window: window)
        window.delegate = self
        window.contentView = NSHostingView(
            rootView: VirtualMachineConsoleWindowView(
                machineName: machineName,
                session: session,
                close: { [weak self] in
                    self?.close()
                },
                toggleFullScreen: { [weak self] in
                    self?.window?.toggleFullScreen(nil)
                }
            )
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("不支持从归档创建远程控制台窗口。")
    }

    func show() {
        window?.center()
        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func windowWillClose(_ notification: Notification) {
        // 立即释放非持久网页视图，避免控制台会话在窗口关闭后继续驻留。
        window?.contentView = nil
        onClose?()
        onClose = nil
    }
}

private struct VirtualMachineConsoleWindowView: View {
    let machineName: String
    let session: VirtualMachineConsoleSession
    let close: () -> Void
    let toggleFullScreen: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label(machineName, systemImage: "display")
                    .font(.headline)
                Spacer()
                Text("远程控制台")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Button {
                    toggleFullScreen()
                } label: {
                    Label("切换全屏", systemImage: "arrow.up.left.and.arrow.down.right")
                }
                .keyboardShortcut("f", modifiers: [.command, .control])
                .help("进入或退出全屏（Control–Command–F）")
                .accessibilityHint("进入或退出全屏显示")
                Button("关闭") { close() }
                    .keyboardShortcut("w", modifiers: .command)
            }
            .padding(12)
            Divider()
            VirtualMachineConsoleWebView(session: session)
                .accessibilityLabel("\(machineName) 的远程控制台")
        }
        .frame(minWidth: 720, idealWidth: 1_100, minHeight: 480, idealHeight: 760)
    }
}

private struct VirtualMachineConsoleWebView: NSViewRepresentable {
    let session: VirtualMachineConsoleSession

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.allowsMagnification = true
        guard let host = session.url.host,
              let cookie = HTTPCookie(properties: [
                  .domain: host,
                  .path: "/",
                  .name: "id",
                  .value: session.sessionCookieValue,
                  .secure: "TRUE"
              ]) else {
            return webView
        }
        configuration.websiteDataStore.httpCookieStore.setCookie(cookie) {
            webView.load(URLRequest(url: session.url))
        }
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {}

    static func dismantleNSView(_ webView: WKWebView, coordinator: ()) {
        webView.stopLoading()
    }
}

private struct SummaryCard: View {
    let title: String
    let value: String
    let icon: String
    let tint: Color

    var body: some View {
        HStack(spacing: 13) {
            Image(systemName: icon)
                .font(.title3.weight(.semibold))
                .foregroundStyle(tint)
                .frame(width: 38, height: 38)
                .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
            VStack(alignment: .leading, spacing: 2) {
                Text(value).font(.title2.weight(.semibold)).monospacedDigit()
                Text(title).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(14)
        .background(
            Color(nsColor: .controlBackgroundColor),
            in: RoundedRectangle(cornerRadius: 12)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(Color.primary.opacity(0.08))
        )
        .accessibilityElement(children: .combine)
    }
}

private struct StatusDot: View {
    let status: String

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 9, height: 9)
            .overlay(Circle().stroke(Color.primary.opacity(0.14)))
            .accessibilityLabel(ServiceFormat.status(status))
    }

    private var color: Color {
        switch status.lowercased() {
        case "running", "started", "up", "healthy", "online": .green
        case "paused", "stopped", "shutdown", "offline": .secondary
        case "error", "failed", "unhealthy": .red
        default: .orange
        }
    }
}

private struct PullImageSheet: View {
    let search: (String) async throws -> [ContainerRegistryImage]
    let loadTags: (String) async throws -> [String]
    let submit: (String, String) async -> String?
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var results: [ContainerRegistryImage] = []
    @State private var selectedImageID: String?
    @State private var repository = ""
    @State private var tags: [String] = []
    @State private var tag = "latest"
    @State private var hasSearched = false
    @State private var isSearching = false
    @State private var isLoadingTags = false
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    private var tagSuggestions: [String] {
        let normalized = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        let matches = normalized.isEmpty
            ? tags
            : tags.filter { $0.localizedCaseInsensitiveContains(normalized) }
        return Array(matches.prefix(8))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // 顶部 Header
            VStack(alignment: .leading, spacing: 12) {
                Text("下载映像")
                    .font(.title2.weight(.semibold))

                HStack(spacing: 8) {
                    TextField("搜索 Docker Hub 映像（例如 aliyunpan、nginx）", text: $query)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { Task { await performSearch() } }
                        .accessibilityHint("输入映像名称后按回车搜索")
                    Button {
                        Task { await performSearch() }
                    } label: {
                        if isSearching {
                            ProgressView().controlSize(.small)
                        } else {
                            Label("搜索", systemImage: "magnifyingglass")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(
                        query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || isSearching
                            || isSubmitting
                    )
                    .keyboardShortcut(.defaultAction)
                }
            }
            .padding(18)

            Divider()

            // 中央主列表区：充满剩余的全部垂直高度！
            Group {
                if isSearching {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("正在搜索 Docker Hub 镜像…")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if hasSearched && results.isEmpty {
                    ContentUnavailableView(
                        "没有找到相关映像",
                        systemImage: "magnifyingglass",
                        description: Text("请尝试缩短关键词，或输入具体的仓库名称。")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if results.isEmpty {
                    ContentUnavailableView(
                        "搜索镜像仓库",
                        systemImage: "shippingbox",
                        description: Text("在上方输入关键词搜索 Docker Hub 映像，然后选择标签下载。")
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(results, selection: $selectedImageID) { image in
                        HStack(alignment: .top, spacing: 12) {
                            Image(
                                systemName: image.isOfficial
                                    ? "checkmark.seal.fill"
                                    : "shippingbox"
                            )
                            .foregroundStyle(image.isOfficial ? .blue : .secondary)
                            .frame(width: 22)
                            .accessibilityHidden(true)
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 8) {
                                    Text(image.name).fontWeight(.medium)
                                    if image.isOfficial {
                                        Text("官方")
                                            .font(.caption2.weight(.semibold))
                                            .foregroundStyle(.blue)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(Color.blue.opacity(0.1), in: Capsule())
                                    }
                                }
                                if let description = image.description {
                                    Text(description)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(2)
                                }
                            }
                            Spacer()
                            if image.starCount > 0 {
                                Label("\(image.starCount)", systemImage: "star.fill")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.vertical, 5)
                        .tag(image.id)
                        .accessibilityElement(children: .combine)
                    }
                    .listStyle(.inset)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // 已选镜像与标签选择框
            if !repository.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Label("已选择 \(repository)", systemImage: "checkmark.circle.fill")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(Color.accentColor)
                        Spacer()
                        if isLoadingTags {
                            ProgressView().controlSize(.small)
                                .accessibilityLabel("正在读取标签")
                        }
                    }
                    HStack(spacing: 8) {
                        Text("标签:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        TextField("例如 latest", text: $tag)
                            .textFieldStyle(.roundedBorder)
                            .disabled(isLoadingTags || isSubmitting)
                            .accessibilityHint("输入标签名称，或从下方建议中选择")
                    }
                    if !tagSuggestions.isEmpty && !isLoadingTags {
                        ScrollView(.horizontal) {
                            HStack(spacing: 6) {
                                ForEach(tagSuggestions, id: \.self) { suggestion in
                                    Button(suggestion) { tag = suggestion }
                                        .buttonStyle(.bordered)
                                        .controlSize(.small)
                                }
                            }
                        }
                        .scrollIndicators(.hidden)
                    }
                }
                .padding(12)
                .background(Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
                .padding(.horizontal, 18)
                .padding(.vertical, 8)
            }

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.red)
                    .padding(.horizontal, 18)
                    .padding(.bottom, 8)
                    .accessibilityElement(children: .combine)
            }

            Divider()

            // 固底 Footer 操作栏
            HStack {
                Spacer()
                Button("取消", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("下载映像") {
                    isSubmitting = true
                    errorMessage = nil
                    Task {
                        errorMessage = await submit(repository, tag)
                        isSubmitting = false
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(
                    repository.isEmpty
                        || tag.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || !tags.contains(
                            tag.trimmingCharacters(in: .whitespacesAndNewlines)
                        )
                        || isLoadingTags
                        || isSubmitting
                )
            }
            .padding(16)
        }
        .frame(width: 620, height: 540)
        .onChange(of: selectedImageID) { _, newValue in
            guard let image = results.first(where: { $0.id == newValue }) else { return }
            repository = image.name
            tag = "latest"
            tags = []
            errorMessage = nil
            Task { await performTagLoad(for: image.name) }
        }
    }

    @MainActor
    private func performSearch() async {
        let normalized = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty, !isSearching else { return }
        isSearching = true
        errorMessage = nil
        selectedImageID = nil
        repository = ""
        tags = []
        isLoadingTags = false
        do {
            results = try await search(normalized)
            hasSearched = true
        } catch {
            results = []
            hasSearched = true
            errorMessage = userMessage(for: error, fallback: "搜索失败，请检查连接后重试。")
        }
        isSearching = false
    }

    @MainActor
    private func performTagLoad(for repository: String) async {
        isLoadingTags = true
        errorMessage = nil
        do {
            let loadedTags = try await loadTags(repository)
            guard self.repository == repository else { return }
            tags = loadedTags
            if !tags.contains(tag), let first = tags.first {
                tag = first
            }
            if tags.isEmpty {
                errorMessage = "这个映像没有可下载的标签，请选择其他映像。"
            }
        } catch {
            guard self.repository == repository else { return }
            tags = []
            errorMessage = userMessage(
                for: error,
                fallback: "标签读取失败，请重新选择映像后重试。"
            )
        }
        if self.repository == repository {
            isLoadingTags = false
        }
    }

    private func userMessage(for error: Error, fallback: String) -> String {
        (error as? AppError)?.safeUserMessage ?? fallback
    }
}

private struct CreateNetworkSheet: View {
    let submit: (String, String) async -> Bool
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var driver = "bridge"
    @State private var isSubmitting = false

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("新建容器网络").font(.title2.weight(.semibold))
            Form {
                TextField("网络名称", text: $name)
                Picker("网络类型", selection: $driver) {
                    Text("桥接").tag("bridge")
                    Text("主机").tag("host")
                }
            }
            HStack {
                Spacer()
                Button("取消", role: .cancel) { dismiss() }
                Button("创建网络") {
                    isSubmitting = true
                    Task {
                        _ = await submit(name, driver)
                        isSubmitting = false
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.isEmpty || isSubmitting)
            }
        }
        .padding(24)
        .frame(width: 440)
    }
}

private enum ServiceFormat {
    static func bytes(_ value: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: value, countStyle: .file)
    }

    static func speed(_ value: Int64) -> String {
        "\(bytes(value))/秒"
    }

    static func status(_ raw: String) -> String {
        switch raw.lowercased() {
        case "running", "started", "up": "正在运行"
        case "stopped", "shutdown", "offline": "已停止"
        case "paused": "已暂停"
        case "waiting": "正在等待"
        case "downloading": "正在下载"
        case "uploading", "seeding": "正在上传"
        case "finished", "completed": "已完成"
        case "error", "failed": "需要处理"
        case "healthy", "online": "正常"
        case "unhealthy": "状态异常"
        default: raw.isEmpty ? "未知状态" : raw
        }
    }
}
