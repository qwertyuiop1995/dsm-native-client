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
}

private actor NasAdministrationRepositoryStub: NasSettingsRepository {
    private var systemRequests = 0
    private let delayNanoseconds: UInt64

    init(delayNanoseconds: UInt64 = 0) {
        self.delayNanoseconds = delayNanoseconds
    }

    func systemRequestCount() -> Int { systemRequests }

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
        NasStorageSnapshot(overallStatus: "normal", disks: [], pools: [], volumes: [])
    }

    func loadPackages() async throws -> [NasPackage] { [] }
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

    func loadInstalledServices() async throws -> [NasPackage] { [] }
}
