import DsmCore
import Foundation
import Observation
import DsmLocalization

enum NasSettingsPage: String, CaseIterable, Identifiable {
    case overview
    case storage
    case fileServices
    case terminal
    case network
    case interfaces
    case hardware
    case remoteAccess
    case security
    case region
    case ddns
    case packages
    case tasks
    case accounts
    case logs
    case connections

    var id: Self { self }
}

struct StorageUsagePoint: Identifiable, Equatable, Sendable {
    let id = UUID()
    let recordedAt: Date
    let volumeID: String
    let volumeName: String
    let usedBytes: Int64
}

struct StorageAnalysisShare: Identifiable, Equatable, Sendable {
    var id: String { path }
    let name: String
    let path: String
    let usedBytes: Int64
    let fileCount: Int
}

struct StorageAnalysisCategory: Identifiable, Equatable, Sendable {
    var id: String { name }
    let name: String
    let usedBytes: Int64
    let fileCount: Int
}

struct StorageAnalysisOwner: Identifiable, Equatable, Sendable {
    var id: String { name }
    let name: String
    let usedBytes: Int64
    let fileCount: Int
}

struct StorageDuplicateGroup: Identifiable, Equatable, Sendable {
    let id: String
    let sizeBytes: Int64
    let files: [FileItem]

    var reclaimableBytes: Int64 {
        Int64(max(files.count - 1, 0)) * sizeBytes
    }
}

struct StorageAnalysisSnapshot: Equatable, Sendable {
    let generatedAt: Date
    let shares: [StorageAnalysisShare]
    let categories: [StorageAnalysisCategory]
    let owners: [StorageAnalysisOwner]
    let largeFiles: [FileItem]
    let recentlyModifiedFiles: [FileItem]
    let leastRecentlyAccessedFiles: [FileItem]
    let duplicateGroups: [StorageDuplicateGroup]
    let scannedFileCount: Int
    let scannedBytes: Int64
    let duplicateCheckWasLimited: Bool
    let duplicateCheckUnavailable: Bool
}

struct StorageAnalysisProgress: Equatable, Sendable {
    let title: String
    let completed: Int
    let total: Int

    var fraction: Double? {
        guard total > 0 else { return nil }
        return min(max(Double(completed) / Double(total), 0), 1)
    }
}

private actor StorageAnalysisEngine {
    private struct Usage {
        var bytes: Int64 = 0
        var count = 0

        mutating func add(_ bytes: Int64) {
            self.bytes += max(bytes, 0)
            count += 1
        }
    }

    private let repository: any FileRepository
    private let maximumDuplicateCandidates = 400

    init(repository: any FileRepository) {
        self.repository = repository
    }

    func analyze(
        progress: @escaping @MainActor @Sendable (StorageAnalysisProgress) -> Void
    ) async throws -> StorageAnalysisSnapshot {
        var shares: [FileItem] = []
        var offset = 0
        repeat {
            let page = try await repository.listShares(offset: offset, limit: 200)
            shares.append(
                contentsOf: page.items.filter {
                    guard !$0.isRecyclePath else { return false }
                    guard let mountType = $0.mountPointType?.lowercased(), !mountType.isEmpty else {
                        return true
                    }
                    return mountType == "normal"
                }
            )
            offset += page.items.count
            if !page.hasMore || page.items.isEmpty { break }
        } while true

        var allFiles: [FileItem] = []
        var shareRows: [StorageAnalysisShare] = []
        for (index, share) in shares.enumerated() {
            try Task.checkCancellation()
            await progress(
                StorageAnalysisProgress(
                    title: L10n.string("ui.8cbbfd3cde8b7d20", String(describing: share.name)),
                    completed: index,
                    total: shares.count
                )
            )
            let files = try await repository.search(folderPath: share.path, query: "*")
                .filter { $0.kind == .file && !$0.isRecyclePath }
            let usedBytes = files.reduce(Int64(0)) { $0 + max($1.sizeBytes ?? 0, 0) }
            shareRows.append(
                StorageAnalysisShare(
                    name: share.name,
                    path: share.path,
                    usedBytes: usedBytes,
                    fileCount: files.count
                )
            )
            allFiles.append(contentsOf: files)
        }

        await progress(
            StorageAnalysisProgress(
                title: L10n.string("ui.428cdf164eefc170"),
                completed: 0,
                total: 1
            )
        )
        let duplicateResult = try await duplicateGroups(in: allFiles, progress: progress)
        try Task.checkCancellation()

        var categories: [String: Usage] = [:]
        var owners: [String: Usage] = [:]
        for file in allFiles {
            let size = max(file.sizeBytes ?? 0, 0)
            categories[Self.category(for: file), default: Usage()].add(size)
            owners[file.owner?.isEmpty == false ? file.owner! : L10n.string("ui.c8b0ccfade8f4591"), default: Usage()].add(size)
        }

        let categoryRows = categories.map {
            StorageAnalysisCategory(name: $0.key, usedBytes: $0.value.bytes, fileCount: $0.value.count)
        }
        .sorted { $0.usedBytes > $1.usedBytes }
        let ownerRows = owners.map {
            StorageAnalysisOwner(name: $0.key, usedBytes: $0.value.bytes, fileCount: $0.value.count)
        }
        .sorted { $0.usedBytes > $1.usedBytes }
        let largeFiles = Array(
            allFiles.sorted { ($0.sizeBytes ?? 0) > ($1.sizeBytes ?? 0) }.prefix(200)
        )
        let recentFiles = Array(
            allFiles
                .filter { $0.times?.modifiedAt != nil }
                .sorted { $0.times!.modifiedAt! > $1.times!.modifiedAt! }
                .prefix(200)
        )
        let oldAccessFiles = Array(
            allFiles
                .filter { $0.times?.accessedAt != nil }
                .sorted { $0.times!.accessedAt! < $1.times!.accessedAt! }
                .prefix(200)
        )

        await progress(
            StorageAnalysisProgress(
                title: L10n.string("ui.0ff9cc7e060ea234"),
                completed: 1,
                total: 1
            )
        )
        return StorageAnalysisSnapshot(
            generatedAt: Date(),
            shares: shareRows.sorted { $0.usedBytes > $1.usedBytes },
            categories: categoryRows,
            owners: ownerRows,
            largeFiles: largeFiles,
            recentlyModifiedFiles: recentFiles,
            leastRecentlyAccessedFiles: oldAccessFiles,
            duplicateGroups: duplicateResult.groups,
            scannedFileCount: allFiles.count,
            scannedBytes: allFiles.reduce(Int64(0)) { $0 + max($1.sizeBytes ?? 0, 0) },
            duplicateCheckWasLimited: duplicateResult.wasLimited,
            duplicateCheckUnavailable: duplicateResult.wasUnavailable
        )
    }

    private func duplicateGroups(
        in files: [FileItem],
        progress: @escaping @MainActor @Sendable (StorageAnalysisProgress) -> Void
    ) async throws -> (groups: [StorageDuplicateGroup], wasLimited: Bool, wasUnavailable: Bool) {
        let sameSizeGroups = Dictionary(
            grouping: files.filter { ($0.sizeBytes ?? 0) > 0 },
            by: { $0.sizeBytes! }
        )
        .values
        .filter { $0.count > 1 }
        .sorted { ($0.first?.sizeBytes ?? 0) > ($1.first?.sizeBytes ?? 0) }
        let allCandidates = sameSizeGroups.flatMap { $0 }
        let candidates = Array(allCandidates.prefix(maximumDuplicateCandidates))
        var checksums: [String: [FileItem]] = [:]
        var unavailable = false

        for (index, file) in candidates.enumerated() {
            try Task.checkCancellation()
            await progress(
                StorageAnalysisProgress(
                    title: L10n.string("ui.428cdf164eefc170"),
                    completed: index,
                    total: candidates.count
                )
            )
            do {
                let checksum = try await repository.fileMD5(remotePath: file.path)
                checksums["\(file.sizeBytes ?? 0):\(checksum)", default: []].append(file)
            } catch let error as AppError where error.category == .apiUnavailable {
                unavailable = true
                break
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                continue
            }
        }

        let groups = checksums.compactMap { key, files -> StorageDuplicateGroup? in
            guard files.count > 1 else { return nil }
            return StorageDuplicateGroup(
                id: key,
                sizeBytes: files.first?.sizeBytes ?? 0,
                files: files.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
            )
        }
        .sorted { $0.reclaimableBytes > $1.reclaimableBytes }
        return (groups, allCandidates.count > candidates.count, unavailable)
    }

    private static func category(for file: FileItem) -> String {
        let ext = file.fileExtension?.lowercased() ?? ""
        if ["jpg", "jpeg", "png", "gif", "heic", "heif", "webp", "tif", "tiff", "bmp", "raw"].contains(ext) {
            return L10n.string("ui.d24c10d37db0feea")
        }
        if ["mp4", "m4v", "mov", "avi", "mkv", "webm", "mpeg", "mpg", "ts", "m2ts"].contains(ext) {
            return L10n.string("ui.c20f7618d330a854")
        }
        if ["mp3", "m4a", "aac", "flac", "wav", "ogg", "ape", "alac"].contains(ext) {
            return L10n.string("ui.296c632ec857a0ba")
        }
        if ["pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx", "txt", "md", "rtf", "pages", "numbers", "key"].contains(ext) {
            return L10n.string("ui.2687ccdbb1d2288a")
        }
        if ["zip", "rar", "7z", "tar", "gz", "bz2", "xz", "dmg", "iso"].contains(ext) {
            return L10n.string("ui.e3a3e47360e24f0b")
        }
        return ext.isEmpty ? L10n.string("ui.905ace3177aa8af8") : L10n.string("ui.d2909f1647e7c891")
    }
}

actor UnavailableNasAdministrationRepository: NasSettingsRepository {
    private func unavailable() -> AppError {
        AppError(
            category: .apiUnavailable,
            isRetryable: false,
            safeUserMessage: L10n.string("ui.45f2d65c5f20a7b9")
        )
    }

    func loadSystemOverview() async throws -> NasSystemOverview { throw unavailable() }
    func loadPerformanceSnapshot() async throws -> NasPerformanceSnapshot { throw unavailable() }
    func loadStorage() async throws -> NasStorageSnapshot { throw unavailable() }
    func loadPackages() async throws -> [NasPackage] { throw unavailable() }
    func loadScheduledTasks() async throws -> [NasScheduledTask] { throw unavailable() }
    func loadAccountsAndGroups() async throws -> NasAccountDirectory { throw unavailable() }
    func loadLogs(offset: Int, limit: Int) async throws -> NasLogPage { throw unavailable() }
    func loadConnections(offset: Int, limit: Int) async throws -> NasConnectionPage { throw unavailable() }
}

@MainActor
@Observable
final class NasSettingsModel {
    var selectedPage: NasSettingsPage = .overview
    var isLiveUpdatesPaused = false

    var logCurrentPage: Int = 1
    var logPageSize: Int = 50

    private(set) var overview: NasSystemOverview?
    private(set) var performanceHistory: [NasPerformanceSnapshot] = []
    private(set) var storage: NasStorageSnapshot?
    private(set) var storageUsageHistory: [StorageUsagePoint] = []
    private(set) var storageAnalysis: StorageAnalysisSnapshot?
    private(set) var storageAnalysisProgress: StorageAnalysisProgress?
    private(set) var storageAnalysisError: String?
    private(set) var isAnalyzingStorage = false
    private(set) var fileServices: NasFileServiceSettings?
    private(set) var terminal: NasTerminalSettings?
    private(set) var proxy: NasProxySettings?
    private(set) var ethernetInterfaces: [NasEthernetInterface] = []
    private(set) var hardware: NasHardwareSettings?
    private(set) var remoteAccess: NasRemoteAccessSettings?
    private(set) var security: NasSecuritySettings?
    private(set) var region: NasRegionSettings?
    private(set) var ddns: NasDDNSDirectory?
    private(set) var diskTestStatuses: [String: NasDiskTestStatus] = [:]
    private(set) var packages: [NasPackage] = []
    private(set) var tasks: [NasScheduledTask] = []
    private(set) var accounts: NasAccountDirectory?
    private(set) var logs: NasLogPage?
    private(set) var connections: NasConnectionPage?
    private(set) var packageOperationIDs: Set<String> = []
    private(set) var taskOperationIDs: Set<String> = []
    private(set) var connectionOperationIDs: Set<String> = []
    private(set) var accountOperationIDs: Set<String> = []
    private(set) var diskOperationIDs: Set<String> = []
    private(set) var ddnsOperationIDs: Set<String> = []
    private(set) var networkOperationIDs: Set<String> = []
    private(set) var performanceIsLoading = false
    private(set) var isSavingServiceSettings = false
    private(set) var isModuleEnabled = false
    private var loadingPages: Set<NasSettingsPage> = []
    private var loadedPages: Set<NasSettingsPage> = []
    private var errors: [NasSettingsPage: String] = [:]

    @ObservationIgnored private let repository: any NasSettingsRepository
    @ObservationIgnored private let storageAnalysisEngine: StorageAnalysisEngine?
    @ObservationIgnored private var storageAnalysisTask: Task<Void, Never>?
    @ObservationIgnored private var requestGenerations: [NasSettingsPage: Int] = [:]
    @ObservationIgnored private var performanceGeneration = 0

    init(
        repository: any NasSettingsRepository = UnavailableNasAdministrationRepository(),
        fileRepository: (any FileRepository)? = nil
    ) {
        self.repository = repository
        self.storageAnalysisEngine = fileRepository.map(StorageAnalysisEngine.init(repository:))
    }

    func setModuleEnabled(_ enabled: Bool) {
        isModuleEnabled = enabled
        guard !enabled else { return }
        performanceGeneration += 1
        for page in NasSettingsPage.allCases {
            requestGenerations[page, default: 0] += 1
        }
        loadingPages.removeAll()
        packageOperationIDs.removeAll()
        taskOperationIDs.removeAll()
        connectionOperationIDs.removeAll()
        accountOperationIDs.removeAll()
        diskOperationIDs.removeAll()
        ddnsOperationIDs.removeAll()
        networkOperationIDs.removeAll()
        diskTestStatuses.removeAll()
        storageAnalysisTask?.cancel()
        storageAnalysisTask = nil
        isAnalyzingStorage = false
        storageAnalysisProgress = nil
        storageAnalysisError = nil
        isSavingServiceSettings = false
        performanceIsLoading = false
        errors.removeAll()
    }

    func isLoading(_ page: NasSettingsPage) -> Bool {
        loadingPages.contains(page)
    }

    func hasLoaded(_ page: NasSettingsPage) -> Bool {
        loadedPages.contains(page)
    }

    func errorMessage(for page: NasSettingsPage) -> String? {
        errors[page]
    }

    func activate(_ page: NasSettingsPage? = nil, force: Bool = false) async {
        guard isModuleEnabled else { return }
        if let page { selectedPage = page }
        let target = selectedPage
        if !force, loadedPages.contains(target) {
            if target == .overview {
                if performanceHistory.isEmpty {
                    await refreshPerformance()
                }
                if connections == nil {
                    await fetchConnectionsForOverview()
                }
            }
            return
        }

        switch target {
        case .overview:
            await loadOverview(force: force)
            await refreshPerformance(force: force)
            await fetchConnectionsForOverview()
        case .storage:
            await loadPage(.storage, operation: { [repository] in
                try await repository.loadStorage()
            }, apply: { applyStorage($0) })
        case .fileServices:
            await loadPage(.fileServices, operation: { [repository] in
                try await repository.loadFileServiceSettings()
            }, apply: { fileServices = $0 })
        case .terminal:
            await loadPage(.terminal, operation: { [repository] in
                try await repository.loadTerminalSettings()
            }, apply: { terminal = $0 })
        case .network:
            await loadPage(.network, operation: { [repository] in
                try await repository.loadProxySettings()
            }, apply: { proxy = $0 })
        case .interfaces:
            await loadPage(.interfaces, operation: { [repository] in
                try await repository.loadEthernetInterfaces()
            }, apply: { ethernetInterfaces = $0 })
        case .hardware:
            await loadPage(.hardware, operation: { [repository] in
                try await repository.loadHardwareSettings()
            }, apply: { hardware = $0 })
        case .remoteAccess:
            await loadPage(.remoteAccess, operation: { [repository] in
                try await repository.loadRemoteAccessSettings()
            }, apply: { remoteAccess = $0 })
        case .security:
            await loadPage(.security, operation: { [repository] in
                try await repository.loadSecuritySettings()
            }, apply: { security = $0 })
        case .region:
            await loadPage(.region, operation: { [repository] in
                try await repository.loadRegionSettings()
            }, apply: { region = $0 })
        case .ddns:
            await loadPage(.ddns, operation: { [repository] in
                try await repository.loadDDNS()
            }, apply: { ddns = $0 })
        case .packages:
            await loadPage(.packages, operation: { [repository] in
                try await repository.loadPackages()
            }, apply: { packages = $0 })
        case .tasks:
            await loadPage(.tasks, operation: { [repository] in
                try await repository.loadScheduledTasks()
            }, apply: { tasks = $0 })
        case .accounts:
            await loadPage(.accounts, operation: { [repository] in
                try await repository.loadAccountsAndGroups()
            }, apply: { accounts = $0 })
        case .logs:
            await fetchLogs(page: logCurrentPage, pageSize: logPageSize)
        case .connections:
            await loadPage(.connections, operation: { [repository] in
                try await repository.loadConnections(offset: 0, limit: 300)
            }, apply: { connections = $0 })
        }
    }

    func beginStorageAnalysis() {
        guard isModuleEnabled, !isAnalyzingStorage else { return }
        guard let storageAnalysisEngine else {
            storageAnalysisError = L10n.string("ui.53cce0f955826240")
            return
        }
        storageAnalysisError = nil
        isAnalyzingStorage = true
        storageAnalysisProgress = StorageAnalysisProgress(
            title: L10n.string("ui.9e316eddfe3b16cd"),
            completed: 0,
            total: 0
        )
        storageAnalysisTask = Task { [weak self] in
            guard let self else { return }
            do {
                let snapshot = try await storageAnalysisEngine.analyze { [weak self] progress in
                    self?.storageAnalysisProgress = progress
                }
                guard !Task.isCancelled else { return }
                storageAnalysis = snapshot
            } catch is CancellationError {
                storageAnalysisError = nil
            } catch let error as AppError {
                storageAnalysisError = error.safeUserMessage
            } catch {
                storageAnalysisError = L10n.string("ui.ebf27fffde487252")
            }
            isAnalyzingStorage = false
            storageAnalysisProgress = nil
            storageAnalysisTask = nil
        }
    }

    func cancelStorageAnalysis() {
        storageAnalysisTask?.cancel()
        storageAnalysisTask = nil
        isAnalyzingStorage = false
        storageAnalysisProgress = nil
    }

    private func applyStorage(_ snapshot: NasStorageSnapshot) {
        storage = snapshot
        let now = Date()
        let points = snapshot.volumes.compactMap { volume -> StorageUsagePoint? in
            guard let used = volume.usedBytes else { return nil }
            return StorageUsagePoint(
                recordedAt: now,
                volumeID: volume.id,
                volumeName: volume.name,
                usedBytes: used
            )
        }
        storageUsageHistory.append(contentsOf: points)
        if storageUsageHistory.count > 120 {
            storageUsageHistory.removeFirst(storageUsageHistory.count - 120)
        }
    }

    func fetchLogs(page: Int? = nil, pageSize: Int? = nil) async {
        if let page { logCurrentPage = max(1, page) }
        if let pageSize { logPageSize = max(10, pageSize) }
        let targetPage = logCurrentPage
        let targetSize = logPageSize
        let offset = (targetPage - 1) * targetSize
        await loadPage(.logs, operation: { [repository] in
            try await repository.loadLogs(offset: offset, limit: targetSize)
        }, apply: { logs = $0 })
    }

    private func fetchConnectionsForOverview() async {
        guard isModuleEnabled else { return }
        if let page = try? await repository.loadConnections(offset: 0, limit: 100) {
            self.connections = page
        }
    }

    func refreshPerformance(force: Bool = false) async {
        guard isModuleEnabled, force || !isLiveUpdatesPaused else { return }
        performanceGeneration += 1
        let generation = performanceGeneration
        performanceIsLoading = performanceHistory.isEmpty
        do {
            let snapshot = try await repository.loadPerformanceSnapshot()
            guard isModuleEnabled, generation == performanceGeneration else { return }
            if performanceHistory.last?.recordedAt != snapshot.recordedAt {
                performanceHistory.append(snapshot)
                if performanceHistory.count > 120 {
                    performanceHistory.removeFirst(performanceHistory.count - 120)
                }
            }
            performanceIsLoading = false
            if overview != nil {
                loadedPages.insert(.overview)
                errors[.overview] = nil
            }
        } catch is CancellationError {
            guard generation == performanceGeneration else { return }
            performanceIsLoading = false
        } catch {
            guard isModuleEnabled, generation == performanceGeneration else { return }
            performanceIsLoading = false
            if overview == nil {
                errors[.overview] = userMessage(for: error, fallback: L10n.string("ui.243c3342118e97c5"))
            }
        }
    }

    private func loadOverview(force: Bool) async {
        if !force, overview != nil { return }
        await loadPage(.overview, operation: { [repository] in
            try await repository.loadSystemOverview()
        }, apply: { overview = $0 })
    }

    private func loadPage<Value: Sendable>(
        _ page: NasSettingsPage,
        operation: @escaping @Sendable () async throws -> Value,
        apply: (Value) -> Void
    ) async {
        requestGenerations[page, default: 0] += 1
        let generation = requestGenerations[page, default: 0]
        loadingPages.insert(page)
        errors[page] = nil
        do {
            let value = try await operation()
            guard isCurrent(page, generation) else { return }
            apply(value)
            loadedPages.insert(page)
            loadingPages.remove(page)
        } catch is CancellationError {
            guard isCurrent(page, generation) else { return }
            loadingPages.remove(page)
        } catch {
            guard isCurrent(page, generation) else { return }
            loadingPages.remove(page)
            errors[page] = userMessage(for: error, fallback: L10n.string("ui.f1217f463299df23"))
        }
    }

    private func isCurrent(_ page: NasSettingsPage, _ generation: Int) -> Bool {
        isModuleEnabled && requestGenerations[page] == generation
    }

    @discardableResult
    func loadDiskTestStatus(diskID: String) async throws -> NasDiskTestStatus {
        let status = try await repository.loadDiskTestStatus(diskID: diskID)
        guard isModuleEnabled else { throw CancellationError() }
        diskTestStatuses[diskID] = status
        return status
    }

    func startDiskTest(diskID: String, type: NasDiskTestType) async throws {
        guard diskOperationIDs.insert(diskID).inserted else {
            throw AppError(
                category: .serverBusy,
                isRetryable: true,
                safeUserMessage: L10n.string("ui.15311c0dd9419f7e")
            )
        }
        defer { diskOperationIDs.remove(diskID) }
        guard let disk = storage?.disks.first(where: { $0.id == diskID }) else {
            throw AppError(
                category: .notFound,
                isRetryable: true,
                safeUserMessage: L10n.string("ui.75f623dd62397b99")
            )
        }
        guard disk.supportsSmartTest else {
            throw AppError(
                category: .apiUnavailable,
                isRetryable: false,
                safeUserMessage: L10n.string("ui.edb18b7e9cd3b114")
            )
        }

        let status = try await repository.startDiskTest(diskID: diskID, type: type)
        guard status.isRunning else {
            throw AppError(
                category: .invalidResponse,
                isRetryable: true,
                safeUserMessage: L10n.string("ui.ddef2b60c5d885df")
            )
        }
        diskTestStatuses[diskID] = status
    }

    func stopDiskTest(diskID: String) async throws {
        guard diskOperationIDs.insert(diskID).inserted else {
            throw AppError(
                category: .serverBusy,
                isRetryable: true,
                safeUserMessage: L10n.string("ui.15311c0dd9419f7e")
            )
        }
        defer { diskOperationIDs.remove(diskID) }
        guard diskTestStatuses[diskID]?.isRunning == true else {
            throw AppError(
                category: .conflict,
                isRetryable: true,
                safeUserMessage: L10n.string("ui.1022d6b5423a7d10")
            )
        }
        let status = try await repository.stopDiskTest(diskID: diskID)
        guard !status.isRunning else {
            throw AppError(
                category: .invalidResponse,
                isRetryable: true,
                safeUserMessage: L10n.string("ui.9681fb468adf10c2")
            )
        }
        diskTestStatuses[diskID] = status
    }

    func controlPackage(id: String, action: NasPackageAction) async throws {
        guard packageOperationIDs.insert(id).inserted else {
            throw AppError(
                category: .serverBusy,
                isRetryable: true,
                safeUserMessage: L10n.string("ui.313fb64bd1a8f846")
            )
        }
        defer { packageOperationIDs.remove(id) }

        guard let package = packages.first(where: { $0.id == id }) else {
            throw AppError(
                category: .notFound,
                isRetryable: true,
                safeUserMessage: L10n.string("ui.86d86e549eb9d8ba")
            )
        }
        switch action {
        case .start where !package.canStart:
            throw unavailablePackageAction(L10n.string("ui.8763bd51641c4851"))
        case .stop where !package.canStop:
            throw unavailablePackageAction(L10n.string("ui.377e24aef22f6f7c"))
        case .uninstall where !package.canUninstall:
            throw unavailablePackageAction(L10n.string("ui.8e3cf87f70acf631"))
        case .upgrade where !package.canUpgrade:
            throw unavailablePackageAction(L10n.string("ui.40a27587a6302b95"))
        default:
            break
        }

        try await repository.controlPackage(id: id, action: action)
        for attempt in 0..<10 {
            await activate(.packages, force: true)
            if packageActionIsVerified(id: id, action: action) {
                return
            }
            if attempt < 9 {
                try await Task.sleep(for: .seconds(1))
            }
        }
        throw AppError(
            category: .invalidResponse,
            isRetryable: true,
            safeUserMessage: L10n.string("ui.3b66d9f42d866bf0")
        )
    }

    func performPowerAction(_ action: NasPowerAction) async throws {
        try await repository.performPowerAction(action)
    }

    func disconnectConnection(_ connection: NasConnection) async throws {
        guard connectionOperationIDs.insert(connection.id).inserted else {
            throw AppError(
                category: .serverBusy,
                isRetryable: true,
                safeUserMessage: L10n.string("ui.8f73f45bdcbee2b3")
            )
        }
        defer { connectionOperationIDs.remove(connection.id) }

        try await repository.disconnectConnection(connection)
        for attempt in 0..<4 {
            await activate(.connections, force: true)
            if connections?.connections.contains(where: { $0.id == connection.id }) == false {
                return
            }
            if attempt < 3 {
                try await Task.sleep(for: .milliseconds(500))
            }
        }
        throw AppError(
            category: .invalidResponse,
            isRetryable: true,
            safeUserMessage: L10n.string("ui.f0b77bcbb861e723")
        )
    }

    func loadTaskDraft(_ task: NasScheduledTask?) async throws -> NasScheduledTaskDraft {
        let id = task.flatMap { Int($0.id) }
        if task != nil, id == nil {
            throw AppError(
                category: .invalidResponse,
                isRetryable: true,
                safeUserMessage: L10n.string("ui.06669846e8a043c1")
            )
        }
        return try await repository.loadScheduledTaskDraft(
            id: id,
            realOwner: task?.realOwner ?? task?.owner
        )
    }

    func loadTaskResults(_ task: NasScheduledTask) async throws -> [NasScheduledTaskResult] {
        try await repository.loadScheduledTaskResults(taskName: task.name)
    }

    func loadTaskResultOutput(
        task: NasScheduledTask,
        resultID: String
    ) async throws -> NasScheduledTaskResultOutput {
        try await repository.loadScheduledTaskResultOutput(
            taskName: task.name,
            resultID: resultID
        )
    }

    func saveTask(_ draft: NasScheduledTaskDraft) async throws {
        let operationID = draft.id.map(String.init) ?? "new"
        try beginTaskOperation(operationID)
        defer { taskOperationIDs.remove(operationID) }
        try await repository.saveScheduledTask(draft)
        await activate(.tasks, force: true)
        let matched = tasks.contains {
            if let id = draft.id { return $0.id == String(id) }
            return $0.name == draft.name && $0.owner == draft.owner
        }
        guard matched else {
            throw taskVerificationError()
        }
    }

    func setTaskEnabled(_ task: NasScheduledTask, enabled: Bool) async throws {
        let id = try taskNumericID(task)
        try beginTaskOperation(task.id)
        defer { taskOperationIDs.remove(task.id) }
        try await repository.setScheduledTaskEnabled(
            id: id,
            realOwner: task.realOwner ?? task.owner,
            enabled: enabled
        )
        await activate(.tasks, force: true)
        guard tasks.first(where: { $0.id == task.id })?.isEnabled == enabled else {
            throw taskVerificationError()
        }
    }

    func runTask(_ task: NasScheduledTask) async throws {
        let id = try taskNumericID(task)
        try beginTaskOperation(task.id)
        defer { taskOperationIDs.remove(task.id) }
        try await repository.runScheduledTask(
            id: id,
            realOwner: task.realOwner ?? task.owner
        )
    }

    func deleteTask(_ task: NasScheduledTask) async throws {
        let id = try taskNumericID(task)
        try beginTaskOperation(task.id)
        defer { taskOperationIDs.remove(task.id) }
        try await repository.deleteScheduledTask(
            id: id,
            realOwner: task.realOwner ?? task.owner
        )
        await activate(.tasks, force: true)
        guard !tasks.contains(where: { $0.id == task.id }) else {
            throw taskVerificationError()
        }
    }

    func saveAccount(_ draft: NasAccountDraft) async throws {
        let operationID = draft.originalName ?? "new"
        guard accountOperationIDs.insert(operationID).inserted else {
            throw busyAccountError()
        }
        defer { accountOperationIDs.remove(operationID) }
        try await repository.saveAccount(draft)
        await activate(.accounts, force: true)
        guard accounts?.users.contains(where: { $0.name == draft.name }) == true else {
            throw accountVerificationError()
        }
    }

    func deleteAccount(_ account: NasAccount) async throws {
        guard account.kind == .user, account.canDelete else {
            throw AppError(
                category: .permissionDenied,
                isRetryable: false,
                safeUserMessage: L10n.string("ui.917cb22bc73cc211")
            )
        }
        guard accountOperationIDs.insert(account.id).inserted else {
            throw busyAccountError()
        }
        defer { accountOperationIDs.remove(account.id) }
        try await repository.deleteAccount(name: account.name)
        await activate(.accounts, force: true)
        guard accounts?.users.contains(where: { $0.id == account.id }) == false else {
            throw accountVerificationError()
        }
    }

    func saveGroup(_ draft: NasGroupDraft) async throws {
        let operationID = draft.originalName.map { "group:\($0)" } ?? "new-group"
        guard accountOperationIDs.insert(operationID).inserted else {
            throw busyAccountError()
        }
        defer { accountOperationIDs.remove(operationID) }
        try await repository.saveGroup(draft)
        await activate(.accounts, force: true)
        guard accounts?.groups.contains(where: { $0.name == draft.name }) == true else {
            throw accountVerificationError()
        }
    }

    func deleteGroup(_ group: NasAccount) async throws {
        guard group.kind == .group, group.canDelete else {
            throw AppError(
                category: .permissionDenied,
                isRetryable: false,
                safeUserMessage: L10n.string("ui.966bbfaa2a0d098a")
            )
        }
        guard accountOperationIDs.insert(group.id).inserted else {
            throw busyAccountError()
        }
        defer { accountOperationIDs.remove(group.id) }
        try await repository.deleteGroup(name: group.name)
        await activate(.accounts, force: true)
        guard accounts?.groups.contains(where: { $0.id == group.id }) == false else {
            throw accountVerificationError()
        }
    }

    private func busyAccountError() -> AppError {
        AppError(
            category: .serverBusy,
            isRetryable: true,
            safeUserMessage: L10n.string("ui.588822329fcd7bbd")
        )
    }

    private func accountVerificationError() -> AppError {
        AppError(
            category: .invalidResponse,
            isRetryable: true,
            safeUserMessage: L10n.string("ui.188f52a0f8ffb8c9")
        )
    }

    private func beginTaskOperation(_ id: String) throws {
        guard taskOperationIDs.insert(id).inserted else {
            throw AppError(
                category: .serverBusy,
                isRetryable: true,
                safeUserMessage: L10n.string("ui.7fc7c12d022f5692")
            )
        }
    }

    private func taskNumericID(_ task: NasScheduledTask) throws -> Int {
        guard let id = Int(task.id) else {
            throw AppError(
                category: .invalidResponse,
                isRetryable: true,
                safeUserMessage: L10n.string("ui.06669846e8a043c1")
            )
        }
        return id
    }

    private func taskVerificationError() -> AppError {
        AppError(
            category: .invalidResponse,
            isRetryable: true,
            safeUserMessage: L10n.string("ui.ca959824992ffae0")
        )
    }

    func checkSystemUpdate() async throws -> NasSystemUpdateInfo {
        try await repository.checkSystemUpdate()
    }

    func saveFileServices(_ settings: NasFileServiceSettings) async throws {
        guard !isSavingServiceSettings else { throw settingsBusyError() }
        isSavingServiceSettings = true
        defer { isSavingServiceSettings = false }
        try await repository.saveFileServiceSettings(settings)
        await activate(.fileServices, force: true)
        guard fileServices == settings else {
            throw settingsVerificationError()
        }
    }

    func saveTerminal(_ settings: NasTerminalSettings) async throws {
        guard !isSavingServiceSettings else { throw settingsBusyError() }
        isSavingServiceSettings = true
        defer { isSavingServiceSettings = false }
        try await repository.saveTerminalSettings(settings)
        await activate(.terminal, force: true)
        guard terminal == settings else {
            throw settingsVerificationError()
        }
    }

    func saveProxy(_ settings: NasProxySettings) async throws {
        guard !isSavingServiceSettings else { throw settingsBusyError() }
        isSavingServiceSettings = true
        defer { isSavingServiceSettings = false }
        try await repository.saveProxySettings(settings)
        await activate(.network, force: true)
        guard proxy?.isEnabled == settings.isEnabled,
              !settings.isEnabled
                || (proxy?.host == settings.host.trimmingCharacters(in: .whitespacesAndNewlines)
                    && proxy?.port == settings.port) else {
            throw settingsVerificationError()
        }
    }

    func saveEthernetInterface(_ interface: NasEthernetInterface) async throws {
        let operationID = "network:\(interface.id)"
        guard networkOperationIDs.insert(operationID).inserted else { throw settingsBusyError() }
        defer { networkOperationIDs.remove(operationID) }
        try await repository.saveEthernetInterface(interface)
        await activate(.interfaces, force: true)
        guard ethernetInterfaces.contains(where: {
            $0.id == interface.id
                && $0.usesDHCP == interface.usesDHCP
                && $0.mtu == interface.mtu
                && $0.isVLANEnabled == interface.isVLANEnabled
        }) else {
            throw settingsVerificationError()
        }
    }

    func saveHardware(_ settings: NasHardwareSettings) async throws {
        guard !isSavingServiceSettings else { throw settingsBusyError() }
        isSavingServiceSettings = true
        defer { isSavingServiceSettings = false }
        try await repository.saveHardwareSettings(settings)
        await activate(.hardware, force: true)
        guard hardware == settings else {
            throw settingsVerificationError()
        }
    }

    func saveRemoteAccess(_ settings: NasRemoteAccessSettings) async throws {
        guard !isSavingServiceSettings else { throw settingsBusyError() }
        isSavingServiceSettings = true
        defer { isSavingServiceSettings = false }
        try await repository.saveRemoteAccessSettings(settings)
        await activate(.remoteAccess, force: true)
        guard remoteAccess?.isRelayEnabled == settings.isRelayEnabled,
              remoteAccess?.isRouterConfigurationEnabled
                == settings.isRouterConfigurationEnabled else {
            throw settingsVerificationError()
        }
    }

    func saveSecurity(_ settings: NasSecuritySettings) async throws {
        guard !isSavingServiceSettings else { throw settingsBusyError() }
        isSavingServiceSettings = true
        defer { isSavingServiceSettings = false }
        try await repository.saveSecuritySettings(settings)
        await activate(.security, force: true)
        guard security == settings else {
            throw settingsVerificationError()
        }
    }

    func saveRegion(_ settings: NasRegionSettings) async throws {
        guard !isSavingServiceSettings else { throw settingsBusyError() }
        isSavingServiceSettings = true
        defer { isSavingServiceSettings = false }
        try await repository.saveRegionSettings(settings)
        await activate(.region, force: true)
        guard region?.dateFormat == settings.dateFormat.trimmingCharacters(
            in: .whitespacesAndNewlines
        ),
        region?.timeFormat == settings.timeFormat.trimmingCharacters(
            in: .whitespacesAndNewlines
        ),
        region?.timeZone == settings.timeZone,
        region?.isNetworkTimeEnabled == settings.isNetworkTimeEnabled else {
            throw settingsVerificationError()
        }
    }

    func saveDDNS(_ draft: NasDDNSDraft) async throws {
        let operationID = draft.originalProviderID ?? "new:\(draft.providerID)"
        guard ddnsOperationIDs.insert(operationID).inserted else { throw settingsBusyError() }
        defer { ddnsOperationIDs.remove(operationID) }
        try await repository.saveDDNS(draft)
        await activate(.ddns, force: true)
        guard ddns?.records.contains(where: {
            $0.providerID == draft.providerID
                && $0.hostname == draft.hostname.trimmingCharacters(in: .whitespacesAndNewlines)
        }) == true else {
            throw settingsVerificationError()
        }
    }

    func deleteDDNS(_ record: NasDDNSRecord) async throws {
        guard ddnsOperationIDs.insert(record.id).inserted else { throw settingsBusyError() }
        defer { ddnsOperationIDs.remove(record.id) }
        try await repository.deleteDDNS(providerID: record.providerID)
        await activate(.ddns, force: true)
        guard ddns?.records.contains(where: { $0.providerID == record.providerID }) == false else {
            throw settingsVerificationError()
        }
    }

    func refreshDDNS() async throws {
        guard ddnsOperationIDs.insert("refresh").inserted else { throw settingsBusyError() }
        defer { ddnsOperationIDs.remove("refresh") }
        try await repository.refreshDDNS()
        await activate(.ddns, force: true)
    }

    private func settingsBusyError() -> AppError {
        AppError(
            category: .serverBusy,
            isRetryable: true,
            safeUserMessage: L10n.string("ui.ba90314384daf833")
        )
    }

    private func settingsVerificationError() -> AppError {
        AppError(
            category: .invalidResponse,
            isRetryable: true,
            safeUserMessage: L10n.string("ui.981825780cae2565")
        )
    }

    private func packageActionIsVerified(id: String, action: NasPackageAction) -> Bool {
        guard let package = packages.first(where: { $0.id == id }) else {
            return action == .uninstall
        }
        let status = package.status?.lowercased() ?? ""
        switch action {
        case .start:
            return status == "running" || status == "active"
        case .stop:
            return status != "running" && status != "active"
        case .uninstall:
            return false
        case .upgrade:
            return true
        }
    }

    private func unavailablePackageAction(_ message: String) -> AppError {
        AppError(
            category: .permissionDenied,
            isRetryable: false,
            safeUserMessage: message
        )
    }
}

@MainActor
func userMessage(for error: Error, fallback: String) -> String {
    (error as? AppError)?.safeUserMessage ?? fallback
}
