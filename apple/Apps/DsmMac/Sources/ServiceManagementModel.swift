import DsmCore
import Foundation
import Observation

actor UnavailableServiceManagementRepository: ServiceManagementRepository {
    private func unavailable() -> AppError {
        AppError(
            category: .apiUnavailable,
            isRetryable: false,
            safeUserMessage: "这台 NAS 当前无法使用此功能，请确认对应套件已安装并允许当前账号访问。"
        )
    }

    func loadDownloadStation() async throws -> DownloadStationSnapshot { throw unavailable() }
    func createDownloadTask(uri: String, destination: String?) async throws { throw unavailable() }
    func createDownloadTask(
        fileURL: URL,
        destination: String?,
        unzipPassword: String?
    ) async throws {
        throw unavailable()
    }
    func loadDownloadStationSettings() async throws -> DownloadStationSettings {
        throw unavailable()
    }
    func saveDownloadStationSettings(_ settings: DownloadStationSettings) async throws {
        throw unavailable()
    }
    func controlDownloadTasks(ids: [String], action: DownloadStationTaskAction) async throws {
        throw unavailable()
    }
    func deleteDownloadTasks(ids: [String], removeData: Bool) async throws { throw unavailable() }
    func loadContainerManager() async throws -> ContainerManagerSnapshot { throw unavailable() }
    func controlContainers(ids: [String], action: ContainerAction) async throws {
        throw unavailable()
    }
    func deleteContainers(ids: [String]) async throws { throw unavailable() }
    func searchContainerImages(query: String) async throws -> [ContainerRegistryImage] {
        throw unavailable()
    }
    func loadContainerImageTags(repository: String) async throws -> [String] {
        throw unavailable()
    }
    func pullContainerImage(repository: String, tag: String) async throws { throw unavailable() }
    func deleteContainerImages(ids: [String]) async throws { throw unavailable() }
    func createContainerNetwork(name: String, driver: String) async throws { throw unavailable() }
    func deleteContainerNetworks(ids: [String]) async throws { throw unavailable() }
    func loadVirtualMachineManager() async throws -> VirtualMachineManagerSnapshot {
        throw unavailable()
    }
    func createVirtualMachine(_ configuration: VirtualMachineCreation) async throws {
        throw unavailable()
    }
    func updateVirtualMachine(
        id: String,
        configuration: VirtualMachineUpdate
    ) async throws {
        throw unavailable()
    }
    func openVirtualMachineConsole(id: String) async throws -> VirtualMachineConsoleSession {
        throw unavailable()
    }
    func controlVirtualMachines(ids: [String], action: VirtualMachinePowerAction) async throws {
        throw unavailable()
    }
    func deleteVirtualMachines(ids: [String]) async throws { throw unavailable() }
    func updateVirtualMachineNetwork(
        id: String,
        configuration: VirtualMachineNetworkUpdate
    ) async throws {
        throw unavailable()
    }
    func deleteVirtualMachineNetworks(ids: [String]) async throws { throw unavailable() }
    func deleteVirtualMachineImages(ids: [String]) async throws { throw unavailable() }
}

@MainActor
@Observable
final class ServiceManagementModel {
    enum Module: Hashable {
        case downloads
        case containers
        case virtualMachines
    }

    private(set) var downloads: DownloadStationSnapshot?
    private(set) var containers: ContainerManagerSnapshot?
    private(set) var virtualMachines: VirtualMachineManagerSnapshot?
    private(set) var isLoading = false
    private(set) var isPerformingAction = false
    var message: String?
    var messageIsError = false
    var downloadSelection: Set<String> = []
    var containerSelection: Set<String> = []
    var imageSelection: Set<String> = []
    var networkSelection: Set<String> = []
    var virtualMachineSelection: Set<String> = []
    var virtualMachineNetworkSelection: Set<String> = []
    var virtualMachineImageSelection: Set<String> = []

    @ObservationIgnored private let repository: any ServiceManagementRepository
    @ObservationIgnored private let fileRepository: (any FileRepository)?
    @ObservationIgnored private var loadedModules: Set<Module> = []

    init(
        repository: any ServiceManagementRepository = UnavailableServiceManagementRepository(),
        fileRepository: (any FileRepository)? = nil
    ) {
        self.repository = repository
        self.fileRepository = fileRepository
    }

    func activate(_ module: Module, force: Bool = false) async {
        message = nil
        guard force || !loadedModules.contains(module) else { return }
        isLoading = true
        do {
            switch module {
            case .downloads:
                downloads = try await repository.loadDownloadStation()
            case .containers:
                containers = try await repository.loadContainerManager()
            case .virtualMachines:
                virtualMachines = try await repository.loadVirtualMachineManager()
            }
            loadedModules.insert(module)
            isLoading = false
        } catch {
            isLoading = false
            show(error)
        }
    }

    func createDownload(uri: String, destination: String?) async -> Bool {
        await perform(module: .downloads, success: "下载任务已添加。") {
            try await self.repository.createDownloadTask(uri: uri, destination: destination)
        }
    }

    func createDownload(
        fileURL: URL,
        destination: String?,
        unzipPassword: String?
    ) async -> Bool {
        await perform(module: .downloads, success: "下载任务已添加。") {
            try await self.repository.createDownloadTask(
                fileURL: fileURL,
                destination: destination,
                unzipPassword: unzipPassword
            )
        }
    }

    func loadDownloadSettings() async throws -> DownloadStationSettings {
        try await repository.loadDownloadStationSettings()
    }

    func saveDownloadSettings(_ settings: DownloadStationSettings) async -> Bool {
        await perform(module: .downloads, success: "下载设置已保存。") {
            try await self.repository.saveDownloadStationSettings(settings)
        }
    }

    func loadDownloadDestinationFolders(in path: String?) async throws -> [FileItem] {
        guard let fileRepository else {
            throw AppError(
                category: .apiUnavailable,
                isRetryable: false,
                safeUserMessage: "暂时无法浏览 NAS 文件夹，请重新连接后再试。"
            )
        }

        var folders: [FileItem] = []
        var offset = 0
        while true {
            let page = if let path {
                try await fileRepository.listFolder(path: path, offset: offset, limit: 500)
            } else {
                try await fileRepository.listShares(offset: offset, limit: 500)
            }
            folders.append(contentsOf: page.items.filter(\.isDirectory))
            guard page.hasMore else { break }
            let nextOffset = page.offset + page.items.count
            guard nextOffset > offset else { break }
            offset = nextOffset
        }

        return folders.sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
    }

    func controlDownloads(_ action: DownloadStationTaskAction) async -> Bool {
        let ids = Array(downloadSelection)
        return await perform(module: .downloads, success: downloadActionMessage(action)) {
            try await self.repository.controlDownloadTasks(ids: ids, action: action)
        }
    }

    func deleteDownloads(removeData: Bool) async -> Bool {
        let ids = Array(downloadSelection)
        return await perform(module: .downloads, success: "下载任务已删除。") {
            try await self.repository.deleteDownloadTasks(ids: ids, removeData: removeData)
        }
    }

    func controlContainers(_ action: ContainerAction) async -> Bool {
        let ids = Array(containerSelection)
        return await perform(module: .containers, success: containerActionMessage(action)) {
            try await self.repository.controlContainers(ids: ids, action: action)
        }
    }

    func deleteContainers() async -> Bool {
        let ids = Array(containerSelection)
        return await perform(module: .containers, success: "容器已删除。") {
            try await self.repository.deleteContainers(ids: ids)
        }
    }

    func searchImages(query: String) async throws -> [ContainerRegistryImage] {
        try await repository.searchContainerImages(query: query)
    }

    func loadImageTags(repositoryName: String) async throws -> [String] {
        try await repository.loadContainerImageTags(repository: repositoryName)
    }

    func pullImage(repositoryName: String, tag: String) async -> Bool {
        await perform(module: .containers, success: "已开始下载映像。") {
            try await self.repository.pullContainerImage(repository: repositoryName, tag: tag)
        }
    }

    func clearMessage() {
        message = nil
        messageIsError = false
    }

    func deleteImages() async -> Bool {
        let ids = Array(imageSelection)
        return await perform(module: .containers, success: "映像已删除。") {
            try await self.repository.deleteContainerImages(ids: ids)
        }
    }

    func createNetwork(name: String, driver: String) async -> Bool {
        await perform(module: .containers, success: "网络已创建。") {
            try await self.repository.createContainerNetwork(name: name, driver: driver)
        }
    }

    func deleteNetworks() async -> Bool {
        let ids = Array(networkSelection)
        return await perform(module: .containers, success: "网络已删除。") {
            try await self.repository.deleteContainerNetworks(ids: ids)
        }
    }

    func controlVirtualMachines(_ action: VirtualMachinePowerAction) async -> Bool {
        let ids = Array(virtualMachineSelection)
        return await perform(module: .virtualMachines, success: virtualMachineActionMessage(action)) {
            try await self.repository.controlVirtualMachines(ids: ids, action: action)
        }
    }

    func createVirtualMachine(_ configuration: VirtualMachineCreation) async -> Bool {
        await perform(module: .virtualMachines, success: "虚拟机已创建。") {
            try await self.repository.createVirtualMachine(configuration)
        }
    }

    func updateVirtualMachine(
        id: String,
        configuration: VirtualMachineUpdate
    ) async -> Bool {
        await perform(module: .virtualMachines, success: "虚拟机设置已保存。") {
            try await self.repository.updateVirtualMachine(id: id, configuration: configuration)
        }
    }

    func openVirtualMachineConsole(id: String) async -> VirtualMachineConsoleSession? {
        guard !isPerformingAction else { return nil }
        isPerformingAction = true
        message = nil
        do {
            let session = try await repository.openVirtualMachineConsole(id: id)
            isPerformingAction = false
            return session
        } catch {
            isPerformingAction = false
            show(error)
            return nil
        }
    }

    func deleteVirtualMachines() async -> Bool {
        let ids = Array(virtualMachineSelection)
        return await perform(module: .virtualMachines, success: "虚拟机已删除。") {
            try await self.repository.deleteVirtualMachines(ids: ids)
        }
    }

    func updateVirtualMachineNetwork(
        id: String,
        configuration: VirtualMachineNetworkUpdate
    ) async -> Bool {
        await perform(module: .virtualMachines, success: "网络设置已保存。") {
            try await self.repository.updateVirtualMachineNetwork(
                id: id,
                configuration: configuration
            )
        }
    }

    func deleteVirtualMachineNetworks() async -> Bool {
        let ids = Array(virtualMachineNetworkSelection)
        let succeeded = await perform(module: .virtualMachines, success: "网络已删除。") {
            try await self.repository.deleteVirtualMachineNetworks(ids: ids)
        }
        if succeeded { virtualMachineNetworkSelection.removeAll() }
        return succeeded
    }

    func deleteVirtualMachineImages() async -> Bool {
        let ids = Array(virtualMachineImageSelection)
        let succeeded = await perform(module: .virtualMachines, success: "映像已删除。") {
            try await self.repository.deleteVirtualMachineImages(ids: ids)
        }
        if succeeded { virtualMachineImageSelection.removeAll() }
        return succeeded
    }

    private func perform(
        module: Module,
        success: String,
        operation: () async throws -> Void
    ) async -> Bool {
        guard !isPerformingAction else { return false }
        isPerformingAction = true
        message = nil
        do {
            try await operation()
            await activate(module, force: true)
            isPerformingAction = false
            message = success
            messageIsError = false
            return true
        } catch {
            isPerformingAction = false
            show(error)
            return false
        }
    }

    private func show(_ error: Error) {
        if let error = error as? AppError {
            message = error.safeUserMessage
        } else {
            message = "操作未完成，请检查连接后重试。"
        }
        messageIsError = true
    }

    private func downloadActionMessage(_ action: DownloadStationTaskAction) -> String {
        switch action {
        case .pause: "下载已暂停。"
        case .resume: "下载已继续。"
        case .finish: "已请求结束下载。"
        }
    }

    private func containerActionMessage(_ action: ContainerAction) -> String {
        switch action {
        case .start: "容器已启动。"
        case .stop: "容器已停止。"
        case .restart: "容器已重新启动。"
        }
    }

    private func virtualMachineActionMessage(_ action: VirtualMachinePowerAction) -> String {
        switch action {
        case .powerOn: "虚拟机已启动。"
        case .shutdown: "已请求虚拟机正常关机。"
        case .powerOff: "虚拟机已强制断电。"
        case .restart: "虚拟机已重新启动。"
        }
    }
}
