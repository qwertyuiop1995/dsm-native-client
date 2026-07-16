import DsmCore
import DsmNetwork
import Foundation
import Observation

enum WorkspaceSection: Hashable, Identifiable {
    case files(String)
    case recycle(String)
    case transfers
    case settings

    var id: String {
        switch self {
        case .files(let path): "files:\(path)"
        case .recycle(let path): "recycle:\(path)"
        case .transfers: "transfers"
        case .settings: "settings"
        }
    }
}

enum FilePreviewState {
    case empty
    case loading
    case image(Data)
    case text(String, truncated: Bool)
    case pdf(URL)
    case video(MediaStreamSource)
    case audio(MediaStreamSource)
    case unsupported(String)
    case failed(String)
}

struct TransferProgressEstimator {
    private(set) var lastCompleted: Int64?
    private(set) var lastDate: Date?
    private(set) var smoothedBytesPerSecond: Double?

    mutating func update(
        completed: Int64,
        total: Int64?,
        at date: Date = Date()
    ) -> (speed: Double?, remaining: TimeInterval?) {
        guard let previousCompleted = lastCompleted,
              let previousDate = lastDate else {
            lastCompleted = completed
            lastDate = date
            smoothedBytesPerSecond = nil
            return (nil, nil)
        }

        guard completed >= previousCompleted else {
            lastCompleted = completed
            lastDate = date
            smoothedBytesPerSecond = nil
            return (nil, nil)
        }

        let elapsed = date.timeIntervalSince(previousDate)
        let delta = completed - previousCompleted
        guard elapsed >= 0.2, delta > 0 else {
            return metrics(completed: completed, total: total)
        }

        lastCompleted = completed
        lastDate = date

        let instantSpeed = Double(delta) / elapsed
        if let previousSpeed = smoothedBytesPerSecond {
            smoothedBytesPerSecond = previousSpeed * 0.7 + instantSpeed * 0.3
        } else {
            smoothedBytesPerSecond = instantSpeed
        }
        return metrics(completed: completed, total: total)
    }

    private func metrics(
        completed: Int64,
        total: Int64?
    ) -> (speed: Double?, remaining: TimeInterval?) {
        guard let speed = smoothedBytesPerSecond, speed > 0 else {
            return (nil, nil)
        }
        guard let total, total > completed else {
            return (speed, nil)
        }
        return (speed, Double(total - completed) / speed)
    }
}

@MainActor
@Observable
final class WorkspaceModel {
    let profile: NasProfile
    let isDemo: Bool
    let allowsVerifiedRestore: Bool

    var shares: [FileItem] = []
    var recycleRoots: [FileItem] = []
    var section: WorkspaceSection?
    var items: [FileItem] = []
    var currentPath = ""
    var selection: Set<FileItem.ID> = []
    var searchText = ""
    var isLoading = false
    var isRefreshing = false
    var isLoadingMore = false
    var hasMore = false
    var totalItemCount = 0
    var statusMessage: String?
    var statusIsError = false
    var requiresReauthentication = false
    var preview: FilePreviewState = .empty
    var transfers: [ActivityTask] = []

    @ObservationIgnored private let repository: any FileRepository
    @ObservationIgnored private var history: [String] = []
    @ObservationIgnored private var navigationGeneration = 0
    @ObservationIgnored private var nextOffset = 0
    @ObservationIgnored private var previewTask: Task<Void, Never>?
    @ObservationIgnored private var previewFileURL: URL?
    @ObservationIgnored private var runningTasks: [UUID: Task<Void, Never>] = [:]
    @ObservationIgnored private var progressEstimators: [UUID: TransferProgressEstimator] = [:]

    init(profile: NasProfile, repository: any FileRepository) {
        self.profile = profile
        self.repository = repository
        self.isDemo = repository.isDemo
        self.allowsVerifiedRestore = repository.allowsVerifiedRestore
        Self.purgeStalePreviewCache()
    }

    var filteredItems: [FileItem] {
        let visible = items.filter { item in
            searchText.isEmpty || item.name.localizedCaseInsensitiveContains(searchText)
        }
        return visible.sorted { lhs, rhs in
            if lhs.isDirectory != rhs.isDirectory {
                return lhs.isDirectory
            }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    var selectedItems: [FileItem] {
        items.filter { selection.contains($0.id) }
    }

    var selectedItem: FileItem? {
        guard selection.count == 1, let id = selection.first else {
            return nil
        }
        return items.first { $0.id == id }
    }

    var canGoBack: Bool {
        !history.isEmpty
    }

    var canGoUp: Bool {
        currentPath.split(separator: "/").count > 1
    }

    var activeTransferCount: Int {
        transfers.filter { $0.state == .queued || $0.state == .running || $0.state == .cancelling }.count
    }

    func load() async {
        guard shares.isEmpty else {
            return
        }
        isLoading = true
        statusMessage = nil
        do {
            let page = try await repository.listShares(offset: 0, limit: 200)
            shares = page.items
            isLoading = false
            if let first = shares.first {
                section = .files(first.path)
                await navigate(to: first.path, recordingHistory: false)
            } else {
                items = []
                statusMessage = "当前用户没有可访问的共享文件夹。"
            }
            await discoverRecycleRoots()
        } catch {
            isLoading = false
            show(error)
        }
    }

    func activate(_ newSection: WorkspaceSection?) async {
        guard let newSection else {
            return
        }
        switch newSection {
        case .files(let path), .recycle(let path):
            if path != currentPath {
                history.removeAll()
                await navigate(to: path, recordingHistory: false)
            }
        case .transfers, .settings:
            break
        }
    }

    func navigate(to path: String, recordingHistory: Bool = true) async {
        let previousPath = currentPath
        navigationGeneration += 1
        let generation = navigationGeneration
        isLoading = items.isEmpty
        isRefreshing = !items.isEmpty
        statusMessage = nil

        do {
            let page = try await repository.listFolder(path: path, offset: 0, limit: 500)
            guard generation == navigationGeneration else {
                return
            }
            if recordingHistory, !previousPath.isEmpty, previousPath != path {
                history.append(previousPath)
            }
            currentPath = path
            let isRecycleFolder = path.split(separator: "/").contains("#recycle")
            items = page.items.filter { isRecycleFolder || $0.name != "#recycle" }
            hasMore = page.hasMore
            totalItemCount = page.total
            nextOffset = page.offset + page.items.count
            selection.removeAll()
            clearPreview()
            isLoading = false
            isRefreshing = false
        } catch {
            guard generation == navigationGeneration else {
                return
            }
            isLoading = false
            isRefreshing = false
            show(error)
        }
    }

    func loadMore() async {
        guard hasMore, !isLoadingMore, !currentPath.isEmpty else {
            return
        }
        isLoadingMore = true
        defer { isLoadingMore = false }
        do {
            let page = try await repository.listFolder(
                path: currentPath,
                offset: nextOffset,
                limit: 500
            )
            let existing = Set(items.map(\.path))
            items.append(contentsOf: page.items.filter { !existing.contains($0.path) })
            hasMore = page.hasMore
            totalItemCount = page.total
            nextOffset = page.offset + page.items.count
        } catch {
            show(error)
        }
    }

    func refresh() async {
        guard !currentPath.isEmpty else {
            return
        }
        await navigate(to: currentPath, recordingHistory: false)
    }

    func goBack() async {
        guard let previous = history.popLast() else {
            return
        }
        await navigate(to: previous, recordingHistory: false)
    }

    func goUp() async {
        guard canGoUp else {
            return
        }
        let parent = URL(fileURLWithPath: currentPath).deletingLastPathComponent().path
        await navigate(to: parent, recordingHistory: true)
    }

    func open(_ item: FileItem) async {
        if item.isDirectory {
            await navigate(to: item.path)
        } else {
            selection = [item.id]
            preparePreview()
        }
    }

    func selectionChanged() {
        preparePreview()
    }

    func preparePreview() {
        previewTask?.cancel()
        clearPreviewFile()
        guard let item = selectedItem else {
            preview = .empty
            return
        }
        guard !item.isDirectory else {
            preview = .unsupported("文件夹包含 \(item.sizeBytes.map(String.init) ?? "未知") 字节数据。双击可打开。")
            return
        }

        preview = .loading
        let kind = PreviewKind.classify(item)
        previewTask = Task { [weak self] in
            guard let self else { return }
            do {
                switch kind {
                case .image:
                    let data = try await repository.getThumbnail(path: item.path, size: .large)
                    try Task.checkCancellation()
                    preview = .image(data)
                case .text:
                    let limit: Int64 = 5 * 1_024 * 1_024
                    if let size = item.sizeBytes, size > limit {
                        preview = .unsupported("这个文本文件较大，请下载后打开。")
                        return
                    }
                    let url = temporaryPreviewURL(for: item)
                    try await repository.download(remotePath: item.path, to: url) { _, _ in }
                    try Task.checkCancellation()
                    let data = try Data(contentsOf: url)
                    let text = Self.decodeText(data) ?? "无法识别文本编码。"
                    previewFileURL = url
                    preview = .text(text, truncated: false)
                case .pdf:
                    let url = temporaryPreviewURL(for: item)
                    try await repository.download(remotePath: item.path, to: url) { _, _ in }
                    try Task.checkCancellation()
                    previewFileURL = url
                    preview = .pdf(url)
                case .video:
                    let source = try await repository.mediaStreamSource(
                        remotePath: item.path,
                        fileExtension: item.fileExtension,
                        expectedContentLength: item.sizeBytes
                    )
                    try Task.checkCancellation()
                    preview = .video(source)
                case .audio:
                    let source = try await repository.mediaStreamSource(
                        remotePath: item.path,
                        fileExtension: item.fileExtension,
                        expectedContentLength: item.sizeBytes
                    )
                    try Task.checkCancellation()
                    preview = .audio(source)
                case .unsupported:
                    preview = .unsupported("此类型不支持应用内预览，可以下载后使用其他应用打开。")
                }
            } catch is CancellationError {
                return
            } catch {
                if !Self.isCancellation(error) {
                    preview = .failed(Self.userMessage(for: error))
                }
            }
        }
    }

    func enqueueDownload(_ item: FileItem, to localURL: URL) {
        let taskID = addTransfer(
            kind: .download,
            displayName: item.name,
            remotePath: item.path,
            totalUnits: item.sizeBytes
        )
        let operation = Task { [weak self] in
            guard let self else { return }
            let scoped = localURL.startAccessingSecurityScopedResource()
            defer {
                if scoped { localURL.stopAccessingSecurityScopedResource() }
                runningTasks[taskID] = nil
            }
            do {
                setTransferState(taskID, .running)
                try await repository.download(
                    remotePath: item.path,
                    to: localURL,
                    progress: progressHandler(for: taskID)
                )
                finishTransfer(taskID)
                statusIsError = false
                statusMessage = "“\(item.name)”下载完成。"
            } catch is CancellationError {
                setTransferState(taskID, .cancelled)
            } catch {
                if Self.isCancellation(error) {
                    setTransferState(taskID, .cancelled)
                } else {
                    failTransfer(taskID, error: error)
                }
            }
        }
        runningTasks[taskID] = operation
    }

    func enqueueUploads(_ urls: [URL], overwrite: Bool = false) {
        guard !currentPath.isEmpty else {
            return
        }
        for url in urls {
            let taskID = addTransfer(
                kind: .upload,
                displayName: url.lastPathComponent,
                remotePath: currentPath
            )
            let operation = Task { [weak self] in
                guard let self else { return }
                let scoped = url.startAccessingSecurityScopedResource()
                defer {
                    if scoped { url.stopAccessingSecurityScopedResource() }
                    runningTasks[taskID] = nil
                }
                do {
                    setTransferState(taskID, .running)
                    try await repository.upload(
                        localURL: url,
                        to: currentPath,
                        overwrite: overwrite,
                        progress: progressHandler(for: taskID)
                    )
                    finishTransfer(taskID)
                    await refresh()
                    statusIsError = false
                    statusMessage = "“\(url.lastPathComponent)”上传完成。"
                } catch is CancellationError {
                    setTransferState(taskID, .cancelled)
                } catch {
                    if Self.isCancellation(error) {
                        setTransferState(taskID, .cancelled)
                    } else {
                        failTransfer(taskID, error: error)
                    }
                }
            }
            runningTasks[taskID] = operation
        }
    }

    func deleteItems(_ targets: [FileItem]) {
        guard !targets.isEmpty else {
            return
        }
        let displayName = targets.count == 1 ? targets[0].name : "\(targets.count) 个项目"
        let taskID = addTransfer(
            kind: .delete,
            displayName: displayName,
            remotePath: currentPath,
            totalUnits: Int64(targets.count)
        )
        let paths = targets.map(\.path)
        let operation = Task { [weak self] in
            guard let self else { return }
            do {
                setTransferState(taskID, .running)
                try await repository.delete(paths: paths, progress: progressHandler(for: taskID))
                await refresh()
                let remaining = Set(items.map(\.path))
                guard paths.allSatisfy({ !remaining.contains($0) }) else {
                    throw AppError(
                        category: .partialFailure,
                        isRetryable: false,
                        safeUserMessage: "删除任务结束，但部分项目仍然存在。"
                    )
                }
                finishTransfer(taskID)
                statusIsError = false
                statusMessage = "删除完成。是否可恢复取决于共享文件夹的回收站设置。"
            } catch is CancellationError {
                setTransferState(taskID, .cancelled)
            } catch {
                if Self.isCancellation(error) {
                    setTransferState(taskID, .cancelled)
                } else {
                    failTransfer(taskID, error: error)
                }
            }
            runningTasks[taskID] = nil
        }
        runningTasks[taskID] = operation
    }

    func restoreToOriginalLocation(_ item: FileItem) {
        guard allowsVerifiedRestore else {
            statusIsError = true
            statusMessage = "当前 NAS 尚未确认支持恢复到原位置，请先下载文件。"
            return
        }
        guard let location = RecycleLocation(recyclePath: item.path) else {
            statusIsError = true
            statusMessage = "找不到这个文件原来的位置。"
            return
        }

        let taskID = addTransfer(
            kind: .restore,
            displayName: item.name,
            remotePath: item.path,
            totalUnits: item.sizeBytes
        )
        let operation = Task { [weak self] in
            guard let self else { return }
            do {
                setTransferState(taskID, .running)
                let destination = try await repository.listFolder(
                    path: location.originalParentPath,
                    offset: 0,
                    limit: 500
                )
                guard !destination.items.contains(where: { $0.name == item.name }) else {
                    throw AppError(
                        category: .conflict,
                        isRetryable: false,
                        safeUserMessage: "原位置已有同名项目，已取消恢复。"
                    )
                }
                try await repository.move(
                    paths: [item.path],
                    to: location.originalParentPath,
                    overwrite: false,
                    progress: progressHandler(for: taskID)
                )
                await refresh()
                guard !items.contains(where: { $0.path == item.path }) else {
                    throw AppError(
                        category: .partialFailure,
                        isRetryable: false,
                        safeUserMessage: "恢复任务结束，但回收站源仍然存在。"
                    )
                }
                let verifiedDestination = try await repository.listFolder(
                    path: location.originalParentPath,
                    offset: 0,
                    limit: 500
                )
                guard verifiedDestination.items.contains(where: { $0.path == location.originalPath }) else {
                    throw AppError(
                        category: .partialFailure,
                        isRetryable: false,
                        safeUserMessage: "恢复任务结束，但无法确认原位置文件。"
                    )
                }
                finishTransfer(taskID)
                statusIsError = false
                statusMessage = "“\(item.name)”已恢复到原位置。"
            } catch is CancellationError {
                setTransferState(taskID, .cancelled)
            } catch {
                if Self.isCancellation(error) {
                    setTransferState(taskID, .cancelled)
                } else {
                    failTransfer(taskID, error: error)
                }
            }
            runningTasks[taskID] = nil
        }
        runningTasks[taskID] = operation
    }

    func cancelTransfer(_ taskID: UUID) {
        setTransferState(taskID, .cancelling)
        runningTasks[taskID]?.cancel()
    }

    func clearCompletedTransfers() {
        transfers.removeAll { $0.state == .succeeded || $0.state == .cancelled }
    }

    func cancelAllWork() {
        previewTask?.cancel()
        runningTasks.values.forEach { $0.cancel() }
        runningTasks.removeAll()
        clearPreviewFile()
    }

    private func discoverRecycleRoots() async {
        var discovered: [FileItem] = []
        for share in shares {
            let path = "\(share.path)/#recycle"
            if (try? await repository.listFolder(path: path, offset: 0, limit: 1)) != nil {
                discovered.append(
                    FileItem(
                        profileID: profile.id,
                        name: share.name,
                        path: path,
                        kind: .directory,
                        isRecyclePath: true
                    )
                )
            }
        }
        recycleRoots = discovered
    }

    private func temporaryPreviewURL(for item: FileItem) -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LanStashPreview", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let ext = item.fileExtension.map { ".\($0)" } ?? ""
        return directory.appendingPathComponent("\(UUID().uuidString)\(ext)")
    }

    private func clearPreview() {
        previewTask?.cancel()
        clearPreviewFile()
        preview = .empty
    }

    private func clearPreviewFile() {
        if let previewFileURL {
            try? FileManager.default.removeItem(at: previewFileURL)
        }
        previewFileURL = nil
    }

    private func addTransfer(
        kind: ActivityKind,
        displayName: String,
        remotePath: String,
        totalUnits: Int64? = nil
    ) -> UUID {
        let task = ActivityTask(
            kind: kind,
            displayName: displayName,
            remotePath: remotePath,
            totalUnits: totalUnits
        )
        transfers.insert(task, at: 0)
        return task.id
    }

    private func progressHandler(for taskID: UUID) -> FileTransferProgress {
        { [weak self] completed, total in
            Task { @MainActor [weak self] in
                guard let self, let index = transfers.firstIndex(where: { $0.id == taskID }) else {
                    return
                }
                transfers[index].completedUnits = completed
                if let total {
                    transfers[index].totalUnits = total
                }
                var estimator = progressEstimators[taskID] ?? TransferProgressEstimator()
                let metrics = estimator.update(
                    completed: completed,
                    total: transfers[index].totalUnits
                )
                progressEstimators[taskID] = estimator
                transfers[index].bytesPerSecond = metrics.speed
                transfers[index].estimatedSecondsRemaining = metrics.remaining
            }
        }
    }

    private func setTransferState(_ taskID: UUID, _ state: ActivityState) {
        guard let index = transfers.firstIndex(where: { $0.id == taskID }) else {
            return
        }
        transfers[index].state = state
        if state == .running {
            progressEstimators[taskID] = TransferProgressEstimator()
        } else if state == .cancelled || state == .failed {
            progressEstimators[taskID] = nil
            transfers[index].bytesPerSecond = nil
            transfers[index].estimatedSecondsRemaining = nil
        }
    }

    private func finishTransfer(_ taskID: UUID) {
        guard let index = transfers.firstIndex(where: { $0.id == taskID }) else {
            return
        }
        if let total = transfers[index].totalUnits {
            transfers[index].completedUnits = total
        }
        transfers[index].state = .succeeded
        transfers[index].bytesPerSecond = nil
        transfers[index].estimatedSecondsRemaining = nil
        progressEstimators[taskID] = nil
    }

    private func failTransfer(_ taskID: UUID, error: Error) {
        guard let index = transfers.firstIndex(where: { $0.id == taskID }) else {
            return
        }
        transfers[index].state = .failed
        transfers[index].failureMessage = Self.userMessage(for: error)
        transfers[index].bytesPerSecond = nil
        transfers[index].estimatedSecondsRemaining = nil
        progressEstimators[taskID] = nil
        show(error)
    }

    private func show(_ error: Error) {
        statusIsError = true
        statusMessage = Self.userMessage(for: error)
        if let error = error as? AppError {
            if error.category == .authenticationRequired {
                requiresReauthentication = true
            }
        } else if error is DsmCertificateTrustError {
            requiresReauthentication = true
        }
    }

    private static func userMessage(for error: Error) -> String {
        if let error = error as? AppError {
            return error.safeUserMessage
        }
        if let error = error as? DsmCertificateTrustError {
            return error.localizedDescription
        }
        return "操作没有完成，请重试。"
    }

    private static func decodeText(_ data: Data) -> String? {
        String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .utf16)
            ?? String(data: data, encoding: .utf16LittleEndian)
            ?? String(data: data, encoding: .utf16BigEndian)
    }

    private static func purgeStalePreviewCache() {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LanStashPreview", isDirectory: true)
        try? FileManager.default.removeItem(at: directory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    private static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError {
            return true
        }
        if let error = error as? AppError {
            return error.category == .cancelled
        }
        if let error = error as? URLError {
            return error.code == .cancelled
        }
        return false
    }
}
