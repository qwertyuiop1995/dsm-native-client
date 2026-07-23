import DsmCore
import Foundation
import XCTest
@testable import DsmNetwork

final class DsmNasAdministrationRepositoryTests: XCTestCase {
    func test读取系统总览并把会话凭据留在请求正文() async throws {
        let transport = MockHTTPTransport(responses: [
            response(#"{"success":true,"data":{"model":"DS923+","firmware_ver":"DSM 7.2","up_time":"3600","cpu_series":"AMD Ryzen","cpu_cores":"4","cpu_clock_speed":2200,"ram_size":4096,"sys_temp":42}}"#)
        ])
        let repository = try makeRepository(apiNames: [DsmAPIName.coreSystem], transport: transport)

        let overview = try await repository.loadSystemOverview()

        XCTAssertEqual(overview.serverName, "测试设备")
        XCTAssertEqual(overview.model, "DS923+")
        XCTAssertEqual(overview.cpuCoreCount, 4)
        XCTAssertEqual(overview.memoryBytes, 4_294_967_296)
        let requests = await transport.recordedRequests()
        XCTAssertEqual(requests.count, 1)
        XCTAssertFalse(requests.contains { $0.url?.absoluteString.contains("REDACTED_SESSION") == true })
    }

    func test按实际嵌套结构读取性能数据() async throws {
        let transport = MockHTTPTransport(responses: [
            response(#"{"success":true,"data":{"time":100,"cpu":{"user_load":12,"system_load":5,"other_load":3},"memory":{"real_usage":46,"swap_usage":2},"network":[{"device":"eth0","rx":1,"tx":2},{"device":"total","rx":1024,"tx":2048}],"disk":{"total":{"read_byte":4096,"write_byte":8192,"utilization":15}},"space":{"total":{"read_byte":3000,"write_byte":4000}},"nfs":[{"read_OPS":4,"write_OPS":5}]}}"#)
        ])
        let repository = try makeRepository(
            apiNames: [DsmAPIName.coreSystemUtilization],
            transport: transport
        )

        let snapshot = try await repository.loadPerformanceSnapshot()

        XCTAssertEqual(snapshot.cpuUsage, 20)
        XCTAssertEqual(snapshot.memoryUsage, 46)
        XCTAssertEqual(snapshot.networkReceivedBytesPerSecond, 1_024)
        XCTAssertEqual(snapshot.diskWriteBytesPerSecond, 8_192)
        XCTAssertEqual(snapshot.nfsReadOperationsPerSecond, 4)
    }

    func test读取真实存储池空间和硬盘结构() async throws {
        let transport = MockHTTPTransport(responses: [
            response(#"{"success":true,"data":{"overview_data":{"status_level":"normal"},"disks":[{"id":"disk1","longName":"硬盘 1","model":"MODEL","size_total":1000,"summary_status_key":"normal","smart_status":"normal","temp":35,"smart_test_support":true}],"storagePools":[{"id":"pool1","desc":"存储池 1","raidType":"raid_1","summary_status":"normal","size":{"used":400,"total":1000},"is_writable":true}],"volumes":[{"id":"volume1","vol_desc":"存储空间 1","fs_type":"btrfs","summary_status":"normal","size":{"used":300,"total":800},"is_writable":true}]}}"#)
        ])
        let repository = try makeRepository(apiNames: [DsmAPIName.storageOverview], transport: transport)

        let storage = try await repository.loadStorage()

        XCTAssertEqual(storage.disks.first?.smartStatus, "normal")
        XCTAssertEqual(storage.pools.first?.usedBytes, 400)
        XCTAssertEqual(storage.volumes.first?.fileSystem, "btrfs")
    }

    func test套件列表读取附加状态和说明() async throws {
        let transport = MockHTTPTransport(responses: [
            response(#"{"success":true,"data":{"packages":[{"id":"HyperBackup","name":"Hyper Backup","version":"4.1","timestamp":100,"additional":{"status":"running","status_description":"运行中","description":"备份服务","install_type":"system"}}]}}"#)
        ])
        let repository = try makeRepository(apiNames: [DsmAPIName.corePackage], transport: transport)

        let packages = try await repository.loadPackages()

        XCTAssertEqual(packages.map(\.name), ["Hyper Backup"])
        XCTAssertEqual(packages.first?.status, "running")
        XCTAssertEqual(packages.first?.packageDescription, "备份服务")
    }

    private func makeRepository(
        apiNames: [String],
        transport: MockHTTPTransport
    ) throws -> DsmNasAdministrationRepository {
        let capabilities = Dictionary(uniqueKeysWithValues: apiNames.map { name in
            (
                name,
                ApiCapability(
                    name: name,
                    path: "entry.cgi",
                    minVersion: 1,
                    maxVersion: 3,
                    requestFormat: .form,
                    selectedVersion: name == DsmAPIName.coreTaskScheduler ? 3 : 1
                )
            )
        })
        return try DsmNasAdministrationRepository(
            profile: NasProfile(
                displayName: "测试设备",
                host: "nas.example.invalid",
                port: 5_001
            ),
            capabilities: CapabilitySet(capabilities),
            session: AuthSession(
                sid: "REDACTED_SESSION",
                synoToken: "REDACTED_SESSION",
                did: nil,
                isPortalPort: false
            ),
            transport: transport
        )
    }

    private func response(_ json: String) -> DsmHTTPResponse {
        DsmHTTPResponse(data: Data(json.utf8), statusCode: 200)
    }
}
