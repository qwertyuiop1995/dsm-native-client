import DsmCore
import Foundation
import Observation

enum NasSettingsPage: String, CaseIterable, Identifiable {
    case overview
    case storage
    case packages
    case tasks
    case accounts
    case logs
    case connections
    case services

    var id: Self { self }
}

actor UnavailableNasAdministrationRepository: NasSettingsRepository {
    private func unavailable() -> AppError {
        AppError(
            category: .apiUnavailable,
            isRetryable: false,
            safeUserMessage: "这台 NAS 暂不提供此项信息。"
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
    func loadInstalledServices() async throws -> [NasPackage] { throw unavailable() }
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
    private(set) var packages: [NasPackage] = []
    private(set) var tasks: [NasScheduledTask] = []
    private(set) var accounts: NasAccountDirectory?
    private(set) var logs: NasLogPage?
    private(set) var connections: NasConnectionPage?
    private(set) var services: [NasPackage] = []
    private(set) var performanceIsLoading = false
    private(set) var isModuleEnabled = false
    private var loadingPages: Set<NasSettingsPage> = []
    private var loadedPages: Set<NasSettingsPage> = []
    private var errors: [NasSettingsPage: String] = [:]

    @ObservationIgnored private let repository: any NasSettingsRepository
    @ObservationIgnored private var requestGenerations: [NasSettingsPage: Int] = [:]
    @ObservationIgnored private var performanceGeneration = 0

    init(repository: any NasSettingsRepository = UnavailableNasAdministrationRepository()) {
        self.repository = repository
    }

    func setModuleEnabled(_ enabled: Bool) {
        isModuleEnabled = enabled
        guard !enabled else { return }
        performanceGeneration += 1
        for page in NasSettingsPage.allCases {
            requestGenerations[page, default: 0] += 1
        }
        loadingPages.removeAll()
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
            }, apply: { storage = $0 })
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
        case .services:
            await loadPage(.services, operation: { [repository] in
                try await repository.loadInstalledServices()
            }, apply: { services = $0 })
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
                errors[.overview] = userMessage(for: error, fallback: "暂时无法读取运行状态，请稍后重试。")
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
            errors[page] = userMessage(for: error, fallback: "暂时无法读取 NAS 信息，请稍后重试。")
        }
    }

    private func isCurrent(_ page: NasSettingsPage, _ generation: Int) -> Bool {
        isModuleEnabled && requestGenerations[page] == generation
    }
}

@MainActor
private func userMessage(for error: Error, fallback: String) -> String {
    (error as? AppError)?.safeUserMessage ?? fallback
}
