import DsmCore
import XCTest
@testable import DsmMacExecutable

@MainActor
final class NasAdministrationModelTests: XCTestCase {
    func test关闭NAS设置后不会发起请求且开启后可以读取() async {
        let repository = NasAdministrationRepositoryStub()
        let model = NasSettingsModel(repository: repository)

        model.setModuleEnabled(false)
        await model.activate()
        let disabledRequestCount = await repository.systemRequestCount()
        XCTAssertEqual(disabledRequestCount, 0)

        model.setModuleEnabled(true)
        await model.activate()
        let enabledRequestCount = await repository.systemRequestCount()
        XCTAssertEqual(enabledRequestCount, 1)
        XCTAssertEqual(model.overview?.serverName, "测试 NAS")
        XCTAssertEqual(model.performanceHistory.last?.cpuUsage, 25)
    }

    func test关闭NAS设置后停止接受迟到结果() async {
        let repository = NasAdministrationRepositoryStub(delayNanoseconds: 50_000_000)
        let model = NasSettingsModel(repository: repository)
        model.setModuleEnabled(true)

        let task = Task { await model.activate() }
        await Task.yield()
        model.setModuleEnabled(false)
        await task.value

        XCTAssertNil(model.overview)
        XCTAssertFalse(model.isLoading(.overview))
    }

    func test页面切换不会清空已经读取的账号目录() async {
        let repository = NasAdministrationRepositoryStub()
        let model = NasSettingsModel(repository: repository)
        model.setModuleEnabled(true)

        await model.activate(.accounts)
        XCTAssertEqual(model.accounts?.users.map(\.name), ["user"])

        await model.activate(.overview)
        XCTAssertEqual(model.accounts?.users.map(\.name), ["user"])
        XCTAssertTrue(model.hasLoaded(.accounts))
    }

    func test空结果仅在请求完成后进入已加载状态() async {
        let repository = NasAdministrationRepositoryStub()
        let model = NasSettingsModel(repository: repository)
        model.setModuleEnabled(true)

        XCTAssertFalse(model.hasLoaded(.connections))
        await model.activate(.connections)

        XCTAssertTrue(model.hasLoaded(.connections))
        XCTAssertEqual(model.connections?.connections, [])
    }

    func test暂停套件后刷新并确认最终状态() async throws {
        let repository = NasAdministrationRepositoryStub(packages: [
            package(status: "running", canStart: false, canStop: true, canUninstall: true)
        ])
        let model = NasSettingsModel(repository: repository)
        model.setModuleEnabled(true)
        await model.activate(.packages)

        try await model.controlPackage(id: "Example", action: .stop)

        XCTAssertEqual(model.packages.first?.status, "stopped")
        XCTAssertFalse(model.packageOperationIDs.contains("Example"))
        let requestCount = await repository.packageControlRequestCount()
        XCTAssertEqual(requestCount, 1)
    }

    func test系统套件不会提交卸载请求() async {
        let repository = NasAdministrationRepositoryStub(packages: [
            package(status: "running", canStart: false, canStop: true, canUninstall: false)
        ])
        let model = NasSettingsModel(repository: repository)
        model.setModuleEnabled(true)
        await model.activate(.packages)

        do {
            try await model.controlPackage(id: "Example", action: .uninstall)
            XCTFail("系统套件应拒绝卸载")
        } catch let error as AppError {
            XCTAssertEqual(error.category, .permissionDenied)
        } catch {
            XCTFail("返回了非统一错误：\(error)")
        }
        let requestCount = await repository.packageControlRequestCount()
        XCTAssertEqual(requestCount, 0)
    }

    func test启动硬盘检测后保存已确认的运行状态() async throws {
        let repository = NasAdministrationRepositoryStub()
        let model = NasSettingsModel(repository: repository)
        model.setModuleEnabled(true)
        await model.activate(.storage)

        try await model.startDiskTest(diskID: "disk1", type: .extended)

        XCTAssertEqual(model.diskTestStatuses["disk1"]?.isRunning, true)
        XCTAssertEqual(model.diskTestStatuses["disk1"]?.runningType, .extended)
        XCTAssertFalse(model.diskOperationIDs.contains("disk1"))
        let requestCount = await repository.diskTestRequestCount()
        XCTAssertEqual(requestCount, 1)
    }

    func test停止硬盘检测后保存已确认的停止状态() async throws {
        let repository = NasAdministrationRepositoryStub()
        let model = NasSettingsModel(repository: repository)
        model.setModuleEnabled(true)
        await model.activate(.storage)
        try await model.startDiskTest(diskID: "disk1", type: .quick)

        try await model.stopDiskTest(diskID: "disk1")

        XCTAssertEqual(model.diskTestStatuses["disk1"]?.isRunning, false)
        XCTAssertFalse(model.diskOperationIDs.contains("disk1"))
        let requestCount = await repository.diskTestRequestCount()
        XCTAssertEqual(requestCount, 2)
    }

    private func package(
        status: String,
        canStart: Bool,
        canStop: Bool,
        canUninstall: Bool
    ) -> NasPackage {
        NasPackage(
            id: "Example",
            name: "示例套件",
            version: "1.0",
            status: status,
            statusDescription: nil,
            packageDescription: nil,
            installType: canUninstall ? "user" : "system",
            installedAt: nil,
            canStart: canStart,
            canStop: canStop,
            canUninstall: canUninstall
        )
    }
}

private actor NasAdministrationRepositoryStub: NasSettingsRepository {
    private var systemRequests = 0
    private var packageControlRequests = 0
    private var diskTestRequests = 0
    private var diskTestStatus = NasDiskTestStatus(diskID: "disk1", isRunning: false)
    private var packages: [NasPackage]
    private let delayNanoseconds: UInt64

    init(
        delayNanoseconds: UInt64 = 0,
        packages: [NasPackage] = []
    ) {
        self.delayNanoseconds = delayNanoseconds
        self.packages = packages
    }

    func systemRequestCount() -> Int { systemRequests }
    func packageControlRequestCount() -> Int { packageControlRequests }
    func diskTestRequestCount() -> Int { diskTestRequests }

    func loadSystemOverview() async throws -> NasSystemOverview {
        systemRequests += 1
        if delayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: delayNanoseconds)
        }
        return NasSystemOverview(serverName: "测试 NAS", model: "DS")
    }

    func loadPerformanceSnapshot() async throws -> NasPerformanceSnapshot {
        NasPerformanceSnapshot(
            recordedAt: Date(timeIntervalSince1970: 1),
            cpuUsage: 25,
            cpuUserUsage: 15,
            cpuSystemUsage: 8,
            cpuOtherUsage: 2,
            memoryUsage: 50,
            swapUsage: 0,
            networkReceivedBytesPerSecond: 1_024,
            networkSentBytesPerSecond: 2_048,
            diskReadBytesPerSecond: 4_096,
            diskWriteBytesPerSecond: 8_192,
            volumeReadBytesPerSecond: 4_096,
            volumeWriteBytesPerSecond: 8_192,
            diskUtilization: 10,
            nfsReadOperationsPerSecond: 0,
            nfsWriteOperationsPerSecond: 0
        )
    }

    func loadStorage() async throws -> NasStorageSnapshot {
        NasStorageSnapshot(
            overallStatus: "normal",
            disks: [
                NasDisk(
                    id: "disk1",
                    name: "硬盘 1",
                    model: "MODEL",
                    type: "HDD",
                    totalBytes: 1_000,
                    status: "normal",
                    smartStatus: "normal",
                    temperatureCelsius: 35,
                    isSSD: false,
                    usedBy: nil,
                    supportsSmartTest: true
                )
            ],
            pools: [],
            volumes: []
        )
    }

    func loadDiskTestStatus(diskID: String) async throws -> NasDiskTestStatus {
        diskTestStatus
    }

    func startDiskTest(
        diskID: String,
        type: NasDiskTestType
    ) async throws -> NasDiskTestStatus {
        diskTestRequests += 1
        diskTestStatus = NasDiskTestStatus(
            diskID: diskID,
            isRunning: true,
            runningType: type,
            progressDescription: "已开始"
        )
        return diskTestStatus
    }

    func stopDiskTest(diskID: String) async throws -> NasDiskTestStatus {
        diskTestRequests += 1
        diskTestStatus = NasDiskTestStatus(diskID: diskID, isRunning: false)
        return diskTestStatus
    }

    func loadPackages() async throws -> [NasPackage] { packages }
    func loadScheduledTasks() async throws -> [NasScheduledTask] { [] }

    func loadAccountsAndGroups() async throws -> NasAccountDirectory {
        NasAccountDirectory(
            users: [
                NasAccount(
                    id: "user:user",
                    name: "user",
                    kind: .user,
                    numericID: 1,
                    description: nil
                )
            ],
            groups: []
        )
    }

    func loadLogs(offset: Int, limit: Int) async throws -> NasLogPage {
        NasLogPage(entries: [], total: 0, infoCount: 0, warningCount: 0, errorCount: 0)
    }

    func loadConnections(offset: Int, limit: Int) async throws -> NasConnectionPage {
        NasConnectionPage(connections: [], total: 0)
    }


    func controlPackage(id: String, action: NasPackageAction) async throws {
        packageControlRequests += 1
        switch action {
        case .uninstall:
            packages.removeAll { $0.id == id }
        case .start, .stop:
            guard let index = packages.firstIndex(where: { $0.id == id }) else { return }
            let package = packages[index]
            let isStarting = action == .start
            packages[index] = NasPackage(
                id: package.id,
                name: package.name,
                version: package.version,
                status: isStarting ? "running" : "stopped",
                statusDescription: nil,
                packageDescription: package.packageDescription,
                installType: package.installType,
                installedAt: package.installedAt,
                iconData: package.iconData,
                canStart: !isStarting,
                canStop: isStarting,
                canUninstall: package.canUninstall
            )
        case .upgrade:
            break
        }
    }
}
