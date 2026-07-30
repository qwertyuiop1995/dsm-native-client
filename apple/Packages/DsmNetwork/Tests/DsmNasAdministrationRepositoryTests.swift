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
            response(#"{"success":true,"data":{"overview_data":{"status_level":"normal"},"disks":[{"id":"disk1","device":"sata1","longName":"硬盘 1","vendor":"VENDOR","model":"MODEL","size_total":1000,"summary_status_key":"normal","smart_status":"normal","temp":35,"serial":"SERIAL-REDACTED","firm":"FW1","container":{"str":"测试机箱"},"is4Kn":true,"remain_life":98,"unc":0}],"storagePools":[{"id":"pool1","desc":"存储池 1","raidType":"raid_1","summary_status":"normal","size":{"used":400,"total":1000},"is_writable":true,"disks":["disk1"],"spares":[]}],"volumes":[{"id":"volume1","vol_desc":"存储空间 1","fs_type":"btrfs","summary_status":"normal","size":{"used":300,"total":800},"is_writable":true,"pool_path":"pool1","vol_path":"/volume1"}]}}"#)
        ])
        let repository = try makeRepository(apiNames: [DsmAPIName.storageOverview], transport: transport)

        let storage = try await repository.loadStorage()

        XCTAssertEqual(storage.disks.first?.smartStatus, "normal")
        XCTAssertEqual(storage.disks.first?.deviceID, "sata1")
        XCTAssertEqual(storage.disks.first?.supportsSmartTest, true)
        XCTAssertEqual(storage.disks.first?.serialNumber, "SERIAL-REDACTED")
        XCTAssertEqual(storage.disks.first?.estimatedLifePercent, 98)
        XCTAssertEqual(storage.pools.first?.usedBytes, 400)
        XCTAssertEqual(storage.pools.first?.diskIDs, ["disk1"])
        XCTAssertEqual(storage.volumes.first?.fileSystem, "btrfs")
        XCTAssertEqual(storage.volumes.first?.poolID, "pool1")
    }

    func test读取硬盘当前检测状态和真实历史记录() async throws {
        let transport = MockHTTPTransport(responses: [
            response(#"{"success":true,"data":{"disks":[{"id":"disk1","device":"sata1","longName":"硬盘 1","smart_status":"normal","smart_test_support":true}],"storagePools":[],"volumes":[]}}"#),
            response(#"{"success":true,"data":{"latest_test_time":"2026-07-25T10:20:30+08:00","testInfo":[{"device":"sata1","testing":false,"ihm_testing":false,"perf_testing":false,"quickTime":"2","extendTime":"500","latest_test_result":"completed"}]}}"#),
            response(#"{"success":true,"data":{"total":3,"testLog":[{"type":"smart","test_type":"extend","result":"completed","time":"2026-07-25T10:20:30+08:00"},{"type":"smart","test_type":"quick","result":"completed","time":"2026-07-24T09:10:20+08:00"},{"type":"ihm","result":"ihm_000","time":"2026-07-23T08:00:00+08:00"}]}}"#)
        ])
        let repository = try makeRepository(
            apiNames: [DsmAPIName.storageOverview, DsmAPIName.coreStorageDisk],
            transport: transport
        )

        let status = try await repository.loadDiskTestStatus(diskID: "disk1")

        XCTAssertFalse(status.isRunning)
        XCTAssertFalse(status.isBusyWithOtherTest)
        XCTAssertTrue(status.isHistoryAvailable)
        XCTAssertEqual(status.lastQuickTest, "2026-07-24T09:10:20+08:00")
        XCTAssertEqual(status.lastExtendedTest, "2026-07-25T10:20:30+08:00")
        XCTAssertEqual(status.lastResult, "completed")
        let requests = await transport.recordedRequests()
        XCTAssertEqual(requestValue("device", in: requests[1]), "sata1")
        XCTAssertEqual(requestValue("method", in: requests[2]), "disk_test_log_get")
        XCTAssertEqual(requestValue("type", in: requests[2]), "smart")
    }

    func test硬盘检测先检查状态再启动并复查运行状态() async throws {
        let transport = MockHTTPTransport(responses: [
            response(#"{"success":true,"data":{"disks":[{"id":"disk1","device":"sata1","longName":"硬盘 1","model":"MODEL","size_total":1000,"summary_status_key":"normal","smart_status":"normal","smart_test_support":true}],"storagePools":[],"volumes":[]}}"#),
            response(#"{"success":true,"data":{"latest_test_time":"2026-01-01 10:00:00","testInfo":[{"device":"sata1","testing":false,"ihm_testing":false,"perf_testing":false,"latest_test_result":"completed"}]}}"#),
            response(#"{"success":true}"#),
            response(#"{"success":true,"data":{"testInfo":[{"device":"sata1","testing":true,"test_type":"quick","remain":"约 2 分钟"}]}}"#)
        ])
        let repository = try makeRepository(
            apiNames: [DsmAPIName.storageOverview, DsmAPIName.coreStorageDisk],
            transport: transport
        )
        _ = try await repository.loadStorage()

        let status = try await repository.startDiskTest(diskID: "disk1", type: .quick)

        XCTAssertTrue(status.isRunning)
        XCTAssertEqual(status.runningType, .quick)
        XCTAssertEqual(status.progressDescription, "约 2 分钟")
        let requests = await transport.recordedRequests()
        XCTAssertEqual(requests.count, 4)
        XCTAssertEqual(requestValue("method", in: requests[1]), "get_smart_test_log")
        XCTAssertEqual(requestValue("device", in: requests[1]), "sata1")
        XCTAssertEqual(requestValue("method", in: requests[2]), "do_smart_test")
        XCTAssertEqual(requestValue("device", in: requests[2]), "sata1")
        XCTAssertEqual(requestValue("type", in: requests[2]), "quick")
        XCTAssertEqual(requestValue("method", in: requests[3]), "get_smart_test_log")
    }

    func test其他硬盘检测占用时不提交SMART写操作() async throws {
        let transport = MockHTTPTransport(responses: [
            response(#"{"success":true,"data":{"disks":[{"id":"disk1","device":"sata1","longName":"硬盘 1","smart_status":"normal","smart_test_support":true}],"storagePools":[],"volumes":[]}}"#),
            response(#"{"success":true,"data":{"testInfo":[{"device":"sata1","testing":false,"ihm_testing":true,"perf_testing":false}]}}"#)
        ])
        let repository = try makeRepository(
            apiNames: [DsmAPIName.storageOverview, DsmAPIName.coreStorageDisk],
            transport: transport
        )
        _ = try await repository.loadStorage()

        do {
            _ = try await repository.startDiskTest(diskID: "disk1", type: .quick)
            XCTFail("其他检测占用时不应启动 S.M.A.R.T. 检测")
        } catch let error as AppError {
            XCTAssertEqual(error.category, .conflict)
            XCTAssertEqual(error.safeUserMessage, "这块硬盘正在执行其他检测，请等待完成后再试。")
        }

        let requests = await transport.recordedRequests()
        XCTAssertEqual(requests.count, 2)
        XCTAssertFalse(requests.contains { requestValue("method", in: $0) == "do_smart_test" })
    }

    func test停止硬盘检测先确认正在运行并复查停止状态() async throws {
        let transport = MockHTTPTransport(responses: [
            response(#"{"success":true,"data":{"disks":[{"id":"disk1","device":"sata1","longName":"硬盘 1","smart_status":"normal","smart_test_support":true}],"storagePools":[],"volumes":[]}}"#),
            response(#"{"success":true,"data":{"testInfo":[{"testing":true,"test_type":"extend","remain":"约 1 小时"}]}}"#),
            response(#"{"success":true}"#),
            response(#"{"success":true,"data":{"testInfo":[{"testing":false,"test_type":"extend","result":"stopped"}]}}"#)
        ])
        let repository = try makeRepository(
            apiNames: [DsmAPIName.storageOverview, DsmAPIName.coreStorageDisk],
            transport: transport
        )
        _ = try await repository.loadStorage()

        let status = try await repository.stopDiskTest(diskID: "disk1")

        XCTAssertFalse(status.isRunning)
        let requests = await transport.recordedRequests()
        XCTAssertEqual(requestValue("method", in: requests[1]), "get_smart_test_log")
        XCTAssertEqual(requestValue("method", in: requests[2]), "do_smart_test")
        XCTAssertEqual(requestValue("device", in: requests[2]), "sata1")
        XCTAssertEqual(requestValue("type", in: requests[2]), "stop")
        XCTAssertEqual(requestValue("method", in: requests[3]), "get_smart_test_log")
    }

    func test硬盘检测启动统一结果回读确认运行状态() async throws {
        let transport = MockHTTPTransport(responses: [
            response(syntheticStorageDisk),
            response(syntheticDiskTestStatus(running: false)),
            response(#"{"success":true}"#),
            response(syntheticDiskTestStatus(running: true, type: "quick"))
        ])
        let repository = try makeRepository(
            apiNames: [DsmAPIName.storageOverview, DsmAPIName.coreStorageDisk],
            transport: transport
        )
        _ = try await repository.loadStorage()

        let result = try await repository.startDiskTestResult(
            diskID: "synthetic-disk",
            type: .quick
        )

        XCTAssertEqual(result.status, .confirmedSuccess)
        XCTAssertEqual(result.counts, try MutationResultCounts(
            succeeded: 1,
            failed: 0,
            unknown: 0
        ))
        let requests = await transport.recordedRequests()
        XCTAssertEqual(requestValue("method", in: requests[2]), "do_smart_test")
        XCTAssertEqual(requestValue("type", in: requests[2]), "quick")
    }

    func test硬盘检测停止统一结果回读确认停止状态() async throws {
        let transport = MockHTTPTransport(responses: [
            response(syntheticStorageDisk),
            response(syntheticDiskTestStatus(running: true, type: "extend")),
            response(#"{"success":true}"#),
            response(syntheticDiskTestStatus(running: false))
        ])
        let repository = try makeRepository(
            apiNames: [DsmAPIName.storageOverview, DsmAPIName.coreStorageDisk],
            transport: transport
        )
        _ = try await repository.loadStorage()

        let result = try await repository.stopDiskTestResult(
            diskID: "synthetic-disk"
        )

        XCTAssertEqual(result.status, .confirmedSuccess)
        let requests = await transport.recordedRequests()
        XCTAssertEqual(requestValue("method", in: requests[2]), "do_smart_test")
        XCTAssertEqual(requestValue("type", in: requests[2]), "stop")
    }

    func test硬盘检测提交断网且状态未变化时不自动重放() async throws {
        let transport = MockHTTPTransport(steps: [
            .response(response(syntheticStorageDisk)),
            .response(response(syntheticDiskTestStatus(running: false))),
            .urlError(.networkConnectionLost),
            .response(response(syntheticDiskTestStatus(running: false)))
        ])
        let repository = try makeRepository(
            apiNames: [DsmAPIName.storageOverview, DsmAPIName.coreStorageDisk],
            transport: transport
        )
        _ = try await repository.loadStorage()

        let result = try await repository.startDiskTestResult(
            diskID: "synthetic-disk",
            type: .extended
        )

        XCTAssertEqual(result.status, .submittedButUnverified)
        XCTAssertTrue(result.requiresRefresh)
        let requests = await transport.recordedRequests()
        XCTAssertEqual(
            requests.filter { requestValue("method", in: $0) == "do_smart_test" }.count,
            1
        )
    }

    func test硬盘检测提交超时但回读目标状态时确认成功() async throws {
        let transport = MockHTTPTransport(steps: [
            .response(response(syntheticStorageDisk)),
            .response(response(syntheticDiskTestStatus(running: false))),
            .urlError(.timedOut),
            .response(response(syntheticDiskTestStatus(running: true, type: "quick")))
        ])
        let repository = try makeRepository(
            apiNames: [DsmAPIName.storageOverview, DsmAPIName.coreStorageDisk],
            transport: transport
        )
        _ = try await repository.loadStorage()

        let result = try await repository.startDiskTestResult(
            diskID: "synthetic-disk",
            type: .quick
        )

        XCTAssertEqual(result.status, .confirmedSuccess)
        XCTAssertEqual(result.diagnosticTag, "storage.disk-test.start.confirmed-after-submit-error")
    }

    func test硬盘检测拒绝同硬盘重复提交并区分提交后取消() async throws {
        let transport = MockHTTPTransport(steps: [
            .response(response(syntheticStorageDisk)),
            .response(response(syntheticDiskTestStatus(running: false))),
            .waitUntilCancelled
        ])
        let repository = try makeRepository(
            apiNames: [DsmAPIName.storageOverview, DsmAPIName.coreStorageDisk],
            transport: transport
        )
        _ = try await repository.loadStorage()
        let firstTask = Task {
            try await repository.startDiskTestResult(
                diskID: "synthetic-disk",
                type: .quick
            )
        }
        while await transport.recordedRequests().count < 3 {
            await Task.yield()
        }

        let duplicate = try await repository.stopDiskTestResult(
            diskID: "synthetic-disk"
        )
        firstTask.cancel()
        let cancelled = try await firstTask.value

        XCTAssertEqual(duplicate.status, .confirmedFailure)
        XCTAssertFalse(duplicate.submitted)
        XCTAssertEqual(duplicate.errorCategory, .conflict)
        XCTAssertEqual(cancelled.status, .cancellationRequestedAfterSubmission)
        XCTAssertTrue(cancelled.requiresRefresh)
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

    func test套件图标通过认证请求头读取且凭据不进入地址() async throws {
        let icon = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        let transport = MockHTTPTransport(responses: [
            response(#"{"success":true,"data":{"packages":[{"id":"Example","name":"示例套件","version":"1.0","additional":{"status":"stopped","startable":true,"install_type":"user","ctl_uninstall":true,"available_operation":["start","uninstall"]}}]}}"#),
            DsmHTTPResponse(
                data: icon,
                statusCode: 200,
                headers: ["Content-Type": "image/png"]
            )
        ])
        let repository = try makeRepository(
            apiNames: [DsmAPIName.corePackage, DsmAPIName.corePackageThumb],
            transport: transport
        )

        let packages = try await repository.loadPackages()

        XCTAssertEqual(packages.first?.iconData, icon)
        XCTAssertEqual(packages.first?.canStart, true)
        XCTAssertEqual(packages.first?.canStop, false)
        XCTAssertEqual(packages.first?.canUninstall, true)
        let requests = await transport.recordedRequests()
        XCTAssertEqual(requests.count, 2)
        XCTAssertEqual(requestValue("api", in: requests[1]), DsmAPIName.corePackageThumb)
        XCTAssertEqual(requestValue("method", in: requests[1]), "get")
        XCTAssertEqual(requestValue("name", in: requests[1]), "Example")
        XCTAssertNotNil(requests[1].value(forHTTPHeaderField: "Cookie"))
        XCTAssertNotNil(requests[1].value(forHTTPHeaderField: "X-SYNO-TOKEN"))
        XCTAssertFalse(requests[1].url?.absoluteString.contains("REDACTED_SESSION") == true)
    }

    func test暂停套件先检查可行性再调用专用控制接口() async throws {
        let transport = MockHTTPTransport(responses: [
            response(#"{"success":true,"data":{"packages":[{"id":"Example","name":"示例套件","version":"1.0","additional":{"status":"running","startable":true,"dsm_apps":"App.One App.Two","install_type":"user","available_operation":["stop","uninstall"]}}]}}"#),
            response(#"{"success":true}"#),
            response(#"{"success":true}"#)
        ])
        let repository = try makeRepository(
            apiNames: [
                DsmAPIName.corePackage,
                DsmAPIName.corePackageControl
            ],
            transport: transport
        )
        _ = try await repository.loadPackages()

        try await repository.controlPackage(id: "Example", action: .stop)

        let requests = await transport.recordedRequests()
        XCTAssertEqual(requests.count, 3)
        XCTAssertEqual(requestValue("api", in: requests[1]), DsmAPIName.corePackage)
        XCTAssertEqual(requestValue("method", in: requests[1]), "feasibility_check")
        XCTAssertEqual(requestValue("type", in: requests[1]), "stop_check")
        XCTAssertEqual(requestValue("api", in: requests[2]), DsmAPIName.corePackageControl)
        XCTAssertEqual(requestValue("method", in: requests[2]), "stop")
        XCTAssertEqual(requestValue("id", in: requests[2]), "Example")
    }

    func test卸载套件使用专用接口并传递桌面应用标识() async throws {
        let transport = MockHTTPTransport(responses: [
            response(#"{"success":true,"data":{"packages":[{"id":"Example","name":"示例套件","version":"1.0","additional":{"status":"stopped","startable":true,"dsm_apps":"App.One App.Two","install_type":"user","ctl_uninstall":true,"available_operation":["uninstall"]}}]}}"#),
            response(#"{"success":true}"#),
            response(#"{"success":true}"#)
        ])
        let repository = try makeRepository(
            apiNames: [
                DsmAPIName.corePackage,
                DsmAPIName.corePackageUninstallation
            ],
            transport: transport
        )
        _ = try await repository.loadPackages()

        try await repository.controlPackage(id: "Example", action: .uninstall)

        let requests = await transport.recordedRequests()
        XCTAssertEqual(requestValue("type", in: requests[1]), "uninstall_check")
        XCTAssertEqual(
            requestValue("api", in: requests[2]),
            DsmAPIName.corePackageUninstallation
        )
        XCTAssertEqual(requestValue("method", in: requests[2]), "uninstall")
        XCTAssertEqual(
            requestValue("dsm_apps", in: requests[2]),
            #"["App.One","App.Two"]"#
        )
    }

    func test套件卸载回读确认目标消失时返回确认成功() async throws {
        let transport = MockHTTPTransport(responses: [
            response(packageListResponse),
            response(#"{"success":true}"#),
            response(#"{"success":true}"#),
            response(#"{"success":true,"data":{"packages":[]}}"#),
        ])
        let repository = try makeRepository(
            apiNames: [
                DsmAPIName.corePackage,
                DsmAPIName.corePackageUninstallation,
            ],
            transport: transport
        )
        _ = try await repository.loadPackages()

        let result = try await repository.uninstallPackageResult(id: "Example")

        XCTAssertEqual(result.status, .confirmedSuccess)
        XCTAssertEqual(result.counts.succeeded, 1)
        XCTAssertFalse(result.requiresRefresh)
        let methods = await transport.recordedRequests().compactMap {
            requestValue("method", in: $0)
        }
        XCTAssertEqual(methods, ["list", "feasibility_check", "uninstall", "list"])
    }

    func test套件卸载提交时断网保留未确认语义() async throws {
        let transport = MockHTTPTransport(steps: [
            .response(response(packageListResponse)),
            .response(response(#"{"success":true}"#)),
            .urlError(.networkConnectionLost),
        ])
        let repository = try makeRepository(
            apiNames: [
                DsmAPIName.corePackage,
                DsmAPIName.corePackageUninstallation,
            ],
            transport: transport
        )
        _ = try await repository.loadPackages()

        let result = try await repository.uninstallPackageResult(id: "Example")

        XCTAssertEqual(result.status, .submittedButUnverified)
        XCTAssertTrue(result.submitted)
        XCTAssertTrue(result.requiresRefresh)
        XCTAssertEqual(result.counts.unknown, 1)
        XCTAssertEqual(result.errorCategory, .network)
    }

    func test套件卸载回读失败时要求刷新且不自动重放() async throws {
        let transport = MockHTTPTransport(steps: [
            .response(response(packageListResponse)),
            .response(response(#"{"success":true}"#)),
            .response(response(#"{"success":true}"#)),
            .urlError(.timedOut),
        ])
        let repository = try makeRepository(
            apiNames: [
                DsmAPIName.corePackage,
                DsmAPIName.corePackageUninstallation,
            ],
            transport: transport
        )
        _ = try await repository.loadPackages()

        let result = try await repository.uninstallPackageResult(id: "Example")

        XCTAssertEqual(result.status, .submittedButUnverified)
        XCTAssertTrue(result.requiresRefresh)
        XCTAssertEqual(result.counts.unknown, 1)
        let requests = await transport.recordedRequests()
        XCTAssertEqual(
            requests.filter { requestValue("method", in: $0) == "uninstall" }.count,
            1
        )
    }

    func test套件卸载被明确拒绝时返回权限不足() async throws {
        let transport = MockHTTPTransport(responses: [
            response(packageListResponse),
            response(#"{"success":true}"#),
            response(#"{"success":false,"error":{"code":105}}"#),
        ])
        let repository = try makeRepository(
            apiNames: [
                DsmAPIName.corePackage,
                DsmAPIName.corePackageUninstallation,
            ],
            transport: transport
        )
        _ = try await repository.loadPackages()

        let result = try await repository.uninstallPackageResult(id: "Example")

        XCTAssertEqual(result.status, .permissionDenied)
        XCTAssertTrue(result.submitted)
        XCTAssertEqual(result.counts.failed, 1)
        XCTAssertEqual(result.errorCategory, .permission)
    }

    func test套件卸载提交前取消时不发送请求() async throws {
        let transport = MockHTTPTransport(responses: [])
        let repository = try makeRepository(
            apiNames: [
                DsmAPIName.corePackage,
                DsmAPIName.corePackageUninstallation,
            ],
            transport: transport
        )

        let task = Task {
            withUnsafeCurrentTask { currentTask in
                currentTask?.cancel()
            }
            return try await repository.uninstallPackageResult(id: "Example")
        }
        let result = try await task.value

        XCTAssertEqual(result.status, .cancelledBeforeSubmission)
        XCTAssertFalse(result.submitted)
        let requests = await transport.recordedRequests()
        XCTAssertTrue(requests.isEmpty)
    }

    func test套件卸载拒绝同一目标重复提交并区分提交后取消() async throws {
        let transport = MockHTTPTransport(steps: [
            .response(response(packageListResponse)),
            .response(response(#"{"success":true}"#)),
            .waitUntilCancelled,
        ])
        let repository = try makeRepository(
            apiNames: [
                DsmAPIName.corePackage,
                DsmAPIName.corePackageUninstallation,
            ],
            transport: transport
        )
        _ = try await repository.loadPackages()
        let firstTask = Task {
            try await repository.uninstallPackageResult(id: "Example")
        }
        while await transport.recordedRequests().count < 3 {
            await Task.yield()
        }

        let duplicate = try await repository.uninstallPackageResult(id: "Example")
        firstTask.cancel()
        let cancelled = try await firstTask.value

        XCTAssertEqual(duplicate.status, .confirmedFailure)
        XCTAssertFalse(duplicate.submitted)
        XCTAssertEqual(duplicate.errorCategory, .conflict)
        XCTAssertEqual(cancelled.status, .cancellationRequestedAfterSubmission)
        XCTAssertTrue(cancelled.requiresRefresh)
    }

    func test计划任务列表固定使用已验证的第三版而详情保存使用第四版() async throws {
        let transport = MockHTTPTransport(responses: [
            response(#"{"success":true,"data":{"tasks":[{"id":12,"name":"示例任务","owner":"operator","real_owner":"operator","type":"script","enable":true,"can_run":true,"can_edit":true}]}}"#),
            response(#"{"success":true,"data":{"id":12,"name":"示例任务","owner":"operator","real_owner":"operator","enable":true,"schedule":{"date_type":0,"week_day":"1,2,3,4,5","repeat_date":1002,"hour":3,"minute":15,"repeat_hour":0,"repeat_min":0,"last_work_hour":3},"extra":{"script":"echo ok","notify_if_error":true,"notify_mail":"ops@example.invalid"}}}"#),
            response(#"{"success":true}"#)
        ])
        let repository = try makeRepository(
            apiNames: [DsmAPIName.coreTaskScheduler],
            transport: transport
        )

        let tasks = try await repository.loadScheduledTasks()
        var draft = try await repository.loadScheduledTaskDraft(
            id: 12,
            realOwner: "operator"
        )
        draft.name = "修改后的任务"
        try await repository.saveScheduledTask(draft)

        XCTAssertEqual(tasks.first?.canRun, true)
        XCTAssertEqual(draft.script, "echo ok")
        let requests = await transport.recordedRequests()
        XCTAssertEqual(requestValue("version", in: requests[0]), "3")
        XCTAssertEqual(requestValue("method", in: requests[1]), "get")
        XCTAssertEqual(requestValue("version", in: requests[1]), "4")
        XCTAssertEqual(requestValue("method", in: requests[2]), "set")
        XCTAssertEqual(requestValue("version", in: requests[2]), "4")
        XCTAssertEqual(requestValue("schedule", in: requests[2])?.contains(#""hour":3"#), true)
        XCTAssertEqual(requestValue("extra", in: requests[2])?.contains(#""script":"echo ok""#), true)
    }

    func test计划任务运行记录和输出使用事件调度接口() async throws {
        let transport = MockHTTPTransport(responses: [
            response(#"{"success":true,"data":[{"task_name":"示例任务","result_id":"result-1","start_time":"2026-07-25 10:00:00","exit_info":{"exit_type":"error","exit_code":1}},{"task_name":"示例任务","result_id":"result-2","start_time":"2026-07-26 10:00:00","stop_time":"2026-07-26 10:00:03","exit_info":{"exit_type":"normal","exit_code":0},"trigger_event":"manual"}]}"#),
            response(#"{"success":true,"data":{"script_in":"echo ok","script_out":"ok\n"}}"#)
        ])
        let repository = try makeRepository(
            apiNames: [DsmAPIName.coreEventScheduler],
            transport: transport
        )

        let results = try await repository.loadScheduledTaskResults(taskName: "示例任务")
        let output = try await repository.loadScheduledTaskResultOutput(
            taskName: "示例任务",
            resultID: "result-2"
        )

        XCTAssertEqual(results.map(\.id), ["result-2", "result-1"])
        XCTAssertEqual(results.first?.exitCode, 0)
        XCTAssertEqual(output.command, "echo ok")
        XCTAssertEqual(output.output, "ok\n")
        let requests = await transport.recordedRequests()
        XCTAssertEqual(requestValue("method", in: requests[0]), "result_list")
        XCTAssertEqual(requestValue("task_name", in: requests[0]), "示例任务")
        XCTAssertEqual(requestValue("method", in: requests[1]), "result_get_file")
        XCTAssertEqual(requestValue("result_id", in: requests[1]), "result-2")
    }

    func test系统更新检查使用实际更新服务且没有更新时不伪造版本() async throws {
        let transport = MockHTTPTransport(responses: [
            response(#"{"success":true,"data":{"firmware_ver":"DSM 7.2.1"}}"#),
            response(#"{"success":true,"data":{"update":{"version":"DSM 7.2.2","release_note":"可靠性改进"},"promotion":null}}"#)
        ])
        let repository = try makeRepository(
            apiNames: [DsmAPIName.coreSystem, DsmAPIName.coreUpgradeServer],
            transport: transport
        )

        let info = try await repository.checkSystemUpdate()

        XCTAssertTrue(info.isUpdateAvailable)
        XCTAssertEqual(info.currentVersion, "DSM 7.2.1")
        XCTAssertEqual(info.latestVersion, "DSM 7.2.2")
        XCTAssertEqual(info.releaseNotes, "可靠性改进")
        let requests = await transport.recordedRequests()
        XCTAssertEqual(requestValue("api", in: requests[1]), DsmAPIName.coreUpgradeServer)
        XCTAssertEqual(requestValue("method", in: requests[1]), "check")
        XCTAssertEqual(requestValue("version", in: requests[1]), "3")
        XCTAssertEqual(requestValue("need_promotion", in: requests[1]), "false")
    }

    func test断开网页连接使用设备标识且写请求允许没有数据正文() async throws {
        let transport = MockHTTPTransport(responses: [
            response(#"{"success":true,"data":{"items":[{"pid":"88","did":"device-token","who":"operator","from":"192.0.2.10","descr":"File Station","type":"HTTP/HTTPS","time":"2026-07-26 10:00:00","can_be_kicked":true}],"total":1}}"#),
            response(#"{"success":true}"#)
        ])
        let repository = try makeRepository(
            apiNames: [DsmAPIName.coreCurrentConnection],
            transport: transport
        )

        let page = try await repository.loadConnections(offset: 0, limit: 10)
        let connection = try XCTUnwrap(page.connections.first)
        try await repository.disconnectConnection(connection)

        let requests = await transport.recordedRequests()
        XCTAssertEqual(requestValue("method", in: requests[1]), "kick_connection")
        XCTAssertEqual(requestValue("service_conn", in: requests[1]), "[]")
        XCTAssertEqual(
            requestValue("http_conn", in: requests[1])?.contains(#""did":"device-token""#),
            true
        )
    }

    func test新建账号只在请求正文传送密码且删除使用账号数组() async throws {
        let transport = MockHTTPTransport(responses: [
            response(#"{"success":true}"#),
            response(#"{"success":true}"#)
        ])
        let repository = try makeRepository(
            apiNames: [DsmAPIName.coreUser],
            transport: transport
        )
        let draft = NasAccountDraft(
            name: "new-user",
            description: "测试",
            email: "new-user@example.invalid",
            password: "REDACTED_PASSWORD",
            passwordConfirmation: "REDACTED_PASSWORD"
        )

        try await repository.saveAccount(draft)
        try await repository.deleteAccount(name: "new-user")

        let requests = await transport.recordedRequests()
        XCTAssertEqual(requestValue("method", in: requests[0]), "create")
        XCTAssertEqual(requestValue("password", in: requests[0]), "REDACTED_PASSWORD")
        XCTAssertFalse(requests[0].url?.absoluteString.contains("REDACTED_PASSWORD") == true)
        XCTAssertEqual(requestValue("method", in: requests[1]), "delete")
        XCTAssertEqual(requestValue("name", in: requests[1]), #"["new-user"]"#)
    }

    func test群组新建修改和删除使用专用群组接口() async throws {
        let transport = MockHTTPTransport(responses: [
            response(#"{"success":true}"#),
            response(#"{"success":true}"#),
            response(#"{"success":true}"#)
        ])
        let repository = try makeRepository(
            apiNames: [DsmAPIName.coreGroup],
            transport: transport
        )

        try await repository.saveGroup(
            NasGroupDraft(name: "media-team", description: "媒体")
        )
        try await repository.saveGroup(
            NasGroupDraft(
                originalName: "media-team",
                name: "media-team",
                description: "媒体与照片"
            )
        )
        try await repository.deleteGroup(name: "media-team")

        let requests = await transport.recordedRequests()
        XCTAssertEqual(requestValue("method", in: requests[0]), "create")
        XCTAssertEqual(requestValue("method", in: requests[1]), "set")
        XCTAssertEqual(requestValue("method", in: requests[2]), "delete")
        XCTAssertEqual(requestValue("name", in: requests[2]), #"["media-team"]"#)
    }

    func test账号删除回读确认目标消失时返回确认成功() async throws {
        let transport = MockHTTPTransport(responses: [
            response(#"{"success":true,"data":{"users":[{"name":"new-user","can_delete":true}]}}"#),
            response(#"{"success":true,"data":{"groups":[]}}"#),
            response(#"{"success":true}"#),
            response(#"{"success":true,"data":{"users":[]}}"#),
            response(#"{"success":true,"data":{"groups":[]}}"#)
        ])
        let repository = try makeRepository(
            apiNames: [DsmAPIName.coreUser, DsmAPIName.coreGroup],
            transport: transport
        )

        let result = try await repository.deleteAccountResult(name: "new-user")

        XCTAssertEqual(result.status, .confirmedSuccess)
        XCTAssertTrue(result.submitted)
        XCTAssertFalse(result.requiresRefresh)
        let requests = await transport.recordedRequests()
        XCTAssertEqual(requests.count, 5)
        XCTAssertEqual(requestValue("method", in: requests[2]), "delete")
    }

    func test账号删除提交时断网保留未确认语义且不重放() async throws {
        let transport = MockHTTPTransport(steps: [
            .response(response(#"{"success":true,"data":{"users":[{"name":"new-user","can_delete":true}]}}"#)),
            .response(response(#"{"success":true,"data":{"groups":[]}}"#)),
            .urlError(.timedOut)
        ])
        let repository = try makeRepository(
            apiNames: [DsmAPIName.coreUser, DsmAPIName.coreGroup],
            transport: transport
        )

        let result = try await repository.deleteAccountResult(name: "new-user")

        XCTAssertEqual(result.status, .submittedButUnverified)
        XCTAssertTrue(result.submitted)
        XCTAssertTrue(result.requiresRefresh)
        XCTAssertEqual(result.localizationKey, "account.delete.unverified")
        let requests = await transport.recordedRequests()
        XCTAssertEqual(requests.count, 3)
        XCTAssertEqual(requestValue("method", in: requests[2]), "delete")
    }

    func test受保护账号删除在提交前被拒绝() async throws {
        let transport = MockHTTPTransport(responses: [])
        let repository = try makeRepository(
            apiNames: [DsmAPIName.coreUser, DsmAPIName.coreGroup],
            transport: transport
        )

        let result = try await repository.deleteAccountResult(name: "admin")

        XCTAssertEqual(result.status, .permissionDenied)
        XCTAssertFalse(result.submitted)
        let requests = await transport.recordedRequests()
        XCTAssertTrue(requests.isEmpty)
    }

    func test群组删除回读确认目标消失时返回确认成功() async throws {
        let transport = MockHTTPTransport(responses: [
            response(#"{"success":true,"data":{"users":[]}}"#),
            response(#"{"success":true,"data":{"groups":[{"name":"media-team","can_delete":true}]}}"#),
            response(#"{"success":true}"#),
            response(#"{"success":true,"data":{"users":[]}}"#),
            response(#"{"success":true,"data":{"groups":[]}}"#)
        ])
        let repository = try makeRepository(
            apiNames: [DsmAPIName.coreUser, DsmAPIName.coreGroup],
            transport: transport
        )

        let result = try await repository.deleteGroupResult(name: "media-team")

        XCTAssertEqual(result.status, .confirmedSuccess)
        XCTAssertTrue(result.submitted)
        let requests = await transport.recordedRequests()
        XCTAssertEqual(requests.count, 5)
        XCTAssertEqual(requestValue("api", in: requests[2]), DsmAPIName.coreGroup)
        XCTAssertEqual(requestValue("method", in: requests[2]), "delete")
    }

    func test文件服务设置只提交真实变化并回读确认() async throws {
        let currentResponses = [
            response(#"{"success":true,"data":{"enable_samba":true}}"#),
            response(#"{"success":true,"data":{"enable_nfs":false}}"#),
            response(#"{"success":true,"data":{"enable_ftp":false,"enable_ftps":false,"portnum":21}}"#),
            response(#"{"success":true,"data":{"enable":false,"portnum":22}}"#)
        ]
        let verifiedResponses = [
            response(#"{"success":true,"data":{"enable_samba":false}}"#),
            response(#"{"success":true,"data":{"enable_nfs":false}}"#),
            response(#"{"success":true,"data":{"enable_ftp":true,"enable_ftps":true,"portnum":2121}}"#),
            response(#"{"success":true,"data":{"enable":false,"portnum":22}}"#)
        ]
        let transport = MockHTTPTransport(
            responses: currentResponses
                + [response(#"{"success":true}"#), response(#"{"success":true}"#)]
                + verifiedResponses
        )
        let repository = try makeRepository(
            apiNames: [
                DsmAPIName.coreFileServiceSMB,
                DsmAPIName.coreFileServiceNFS,
                DsmAPIName.coreFileServiceFTP,
                DsmAPIName.coreFileServiceSFTP
            ],
            transport: transport
        )

        let result = try await repository.saveFileServiceSettingsResult(
            NasFileServiceSettings(
                isSMBEnabled: false,
                isNFSEnabled: false,
                isFTPEnabled: true,
                isFTPSEnabled: true,
                ftpPort: 2121,
                isSFTPEnabled: false,
                sftpPort: 22
            )
        )

        XCTAssertEqual(result.status, .confirmedSuccess)
        XCTAssertEqual(
            result.counts,
            try MutationResultCounts(succeeded: 2, failed: 0, unknown: 0)
        )
        let requests = await transport.recordedRequests()
        XCTAssertEqual(requests.count, 10)
        XCTAssertEqual(requestValue("method", in: requests[4]), "set")
        XCTAssertEqual(requestValue("enable_samba", in: requests[4]), "false")
        XCTAssertEqual(requestValue("method", in: requests[5]), "set")
        XCTAssertEqual(requestValue("enable_ftp", in: requests[5]), "true")
        XCTAssertEqual(requestValue("enable_ftps", in: requests[5]), "true")
        XCTAssertEqual(requestValue("portnum", in: requests[5]), "2121")
        XCTAssertFalse(requests.contains { requestValue("enable_nfs", in: $0) != nil })
    }

    func test文件服务中途超时后整体回读并报告部分成功() async throws {
        let transport = MockHTTPTransport(steps: [
            .response(response(#"{"success":true,"data":{"enable_samba":true}}"#)),
            .response(response(#"{"success":true,"data":{"enable_ftp":false,"enable_ftps":false,"portnum":21}}"#)),
            .response(response(#"{"success":true}"#)),
            .urlError(.timedOut),
            .response(response(#"{"success":true,"data":{"enable_samba":false}}"#)),
            .response(response(#"{"success":true,"data":{"enable_ftp":false,"enable_ftps":false,"portnum":21}}"#))
        ])
        let repository = try makeRepository(
            apiNames: [
                DsmAPIName.coreFileServiceSMB,
                DsmAPIName.coreFileServiceFTP
            ],
            transport: transport
        )

        let result = try await repository.saveFileServiceSettingsResult(
            NasFileServiceSettings(
                isSMBEnabled: false,
                isNFSEnabled: nil,
                isFTPEnabled: true,
                isFTPSEnabled: false,
                ftpPort: 21,
                isSFTPEnabled: nil,
                sftpPort: nil
            )
        )

        XCTAssertEqual(result.status, .partialSuccess)
        XCTAssertTrue(result.requiresRefresh)
        XCTAssertEqual(
            result.counts,
            try MutationResultCounts(succeeded: 1, failed: 0, unknown: 1)
        )
        XCTAssertEqual(result.localizationKey, "file-services.settings.partial")
        let requests = await transport.recordedRequests()
        XCTAssertEqual(requests.count, 6)
        XCTAssertEqual(
            requests.filter { requestValue("enable_ftp", in: $0) == "true" }.count,
            1
        )
    }

    func test文件服务提交断网且回读失败时不自动重放() async throws {
        let transport = MockHTTPTransport(steps: [
            .response(response(#"{"success":true,"data":{"enable_samba":true}}"#)),
            .urlError(.networkConnectionLost),
            .urlError(.notConnectedToInternet)
        ])
        let repository = try makeRepository(
            apiNames: [DsmAPIName.coreFileServiceSMB],
            transport: transport
        )

        let result = try await repository.saveFileServiceSettingsResult(
            NasFileServiceSettings(
                isSMBEnabled: false,
                isNFSEnabled: nil,
                isFTPEnabled: nil,
                isFTPSEnabled: nil,
                ftpPort: nil,
                isSFTPEnabled: nil,
                sftpPort: nil
            )
        )

        XCTAssertEqual(result.status, .submittedButUnverified)
        XCTAssertTrue(result.submitted)
        XCTAssertTrue(result.requiresRefresh)
        XCTAssertEqual(result.counts.unknown, 1)
        let requests = await transport.recordedRequests()
        XCTAssertEqual(requests.count, 3)
        XCTAssertEqual(
            requests.filter { requestValue("enable_samba", in: $0) == "false" }.count,
            1
        )
    }

    func test文件服务拒绝重复提交并区分提交后取消() async throws {
        let transport = MockHTTPTransport(steps: [
            .response(response(#"{"success":true,"data":{"enable_samba":true}}"#)),
            .waitUntilCancelled
        ])
        let repository = try makeRepository(
            apiNames: [DsmAPIName.coreFileServiceSMB],
            transport: transport
        )
        let settings = NasFileServiceSettings(
            isSMBEnabled: false,
            isNFSEnabled: nil,
            isFTPEnabled: nil,
            isFTPSEnabled: nil,
            ftpPort: nil,
            isSFTPEnabled: nil,
            sftpPort: nil
        )
        let firstTask = Task {
            try await repository.saveFileServiceSettingsResult(settings)
        }
        while await transport.recordedRequests().count < 2 {
            await Task.yield()
        }

        let duplicate = try await repository.saveFileServiceSettingsResult(settings)
        firstTask.cancel()
        let cancelled = try await firstTask.value

        XCTAssertEqual(duplicate.status, .confirmedFailure)
        XCTAssertFalse(duplicate.submitted)
        XCTAssertEqual(duplicate.errorCategory, .conflict)
        XCTAssertEqual(cancelled.status, .cancellationRequestedAfterSubmission)
        XCTAssertTrue(cancelled.requiresRefresh)
    }

    func test文件服务预检拒绝冲突端口且不提交() async throws {
        let transport = MockHTTPTransport(responses: [
            response(#"{"success":true,"data":{"enable_ftp":false,"enable_ftps":false,"portnum":21}}"#),
            response(#"{"success":true,"data":{"enable":false,"portnum":22}}"#)
        ])
        let repository = try makeRepository(
            apiNames: [
                DsmAPIName.coreFileServiceFTP,
                DsmAPIName.coreFileServiceSFTP
            ],
            transport: transport
        )

        let result = try await repository.saveFileServiceSettingsResult(
            NasFileServiceSettings(
                isSMBEnabled: nil,
                isNFSEnabled: nil,
                isFTPEnabled: true,
                isFTPSEnabled: false,
                ftpPort: 2_222,
                isSFTPEnabled: true,
                sftpPort: 2_222
            )
        )

        XCTAssertEqual(result.status, .confirmedFailure)
        XCTAssertFalse(result.submitted)
        XCTAssertEqual(result.errorCategory, .validation)
        XCTAssertEqual(result.localizationKey, "file-services.settings.invalid")
        let requests = await transport.recordedRequests()
        XCTAssertEqual(requests.count, 2)
        XCTAssertFalse(requests.contains {
            requestValue("method", in: $0) == "set"
        })
    }

    func test文件服务预检拒绝关闭TimeMachine依赖的SMB() async throws {
        let transport = MockHTTPTransport(responses: [
            response(#"{"success":true,"data":{"enable_samba":true}}"#),
            response(#"{"success":true,"data":{"enable_smb_time_machine":true}}"#)
        ])
        let repository = try makeRepository(
            apiNames: [
                DsmAPIName.coreFileServiceSMB,
                DsmAPIName.coreFileServiceDiscovery
            ],
            transport: transport
        )

        let result = try await repository.saveFileServiceSettingsResult(
            NasFileServiceSettings(
                isSMBEnabled: false,
                isNFSEnabled: nil,
                isFTPEnabled: nil,
                isFTPSEnabled: nil,
                ftpPort: nil,
                isSFTPEnabled: nil,
                sftpPort: nil,
                isSMBTimeMachineEnabled: true
            )
        )

        XCTAssertEqual(result.status, .confirmedFailure)
        XCTAssertFalse(result.submitted)
        XCTAssertEqual(result.errorCategory, .validation)
        XCTAssertEqual(result.localizationKey, "file-services.settings.invalid")
        let requests = await transport.recordedRequests()
        XCTAssertEqual(requests.count, 2)
        XCTAssertFalse(requests.contains {
            requestValue("method", in: $0) == "set"
        })
    }

    func test文件服务一次性能力预检避免先写后发现不支持() async throws {
        let transport = MockHTTPTransport(responses: [
            response(#"{"success":true,"data":{"enable_samba":true}}"#)
        ])
        let repository = try makeRepository(
            apiNames: [DsmAPIName.coreFileServiceSMB],
            transport: transport
        )

        let result = try await repository.saveFileServiceSettingsResult(
            NasFileServiceSettings(
                isSMBEnabled: false,
                isNFSEnabled: nil,
                isFTPEnabled: true,
                isFTPSEnabled: nil,
                ftpPort: nil,
                isSFTPEnabled: nil,
                sftpPort: nil
            )
        )

        XCTAssertEqual(result.status, .unsupported)
        XCTAssertFalse(result.submitted)
        XCTAssertEqual(result.counts.failed, 2)
        let requests = await transport.recordedRequests()
        XCTAssertEqual(requests.count, 1)
        XCTAssertFalse(requests.contains {
            requestValue("method", in: $0) == "set"
        })
    }

    func test远程连接设置写入后回读确认() async throws {
        let transport = MockHTTPTransport(responses: [
            response(#"{"success":true,"data":{"enable_ssh":false,"enable_telnet":false,"ssh_port":22}}"#),
            response(#"{"success":true}"#),
            response(#"{"success":true,"data":{"enable_ssh":true,"enable_telnet":false,"ssh_port":2222}}"#)
        ])
        let repository = try makeRepository(
            apiNames: [DsmAPIName.coreTerminal],
            transport: transport
        )

        let result = try await repository.saveTerminalSettingsResult(
            NasTerminalSettings(isSSHEnabled: true, isTelnetEnabled: false, sshPort: 2222)
        )

        XCTAssertEqual(result.status, .confirmedSuccess)
        XCTAssertEqual(
            result.counts,
            try MutationResultCounts(succeeded: 2, failed: 0, unknown: 0)
        )
        let requests = await transport.recordedRequests()
        XCTAssertEqual(requests.count, 3)
        XCTAssertEqual(requestValue("method", in: requests[1]), "set")
        XCTAssertEqual(requestValue("enable_ssh", in: requests[1]), "true")
        XCTAssertEqual(requestValue("enable_telnet", in: requests[1]), "false")
        XCTAssertEqual(requestValue("ssh_port", in: requests[1]), "2222")
        XCTAssertEqual(requestValue("method", in: requests[2]), "get")
    }

    func test远程连接回读不一致时不报告成功() async throws {
        let transport = MockHTTPTransport(responses: [
            response(#"{"success":true,"data":{"enable_ssh":false,"enable_telnet":false,"ssh_port":22}}"#),
            response(#"{"success":true}"#),
            response(#"{"success":true,"data":{"enable_ssh":false,"enable_telnet":false,"ssh_port":22}}"#)
        ])
        let repository = try makeRepository(
            apiNames: [DsmAPIName.coreTerminal],
            transport: transport
        )

        let result = try await repository.saveTerminalSettingsResult(
            NasTerminalSettings(isSSHEnabled: true, isTelnetEnabled: false, sshPort: 22)
        )

        XCTAssertEqual(result.status, .confirmedFailure)
        XCTAssertTrue(result.submitted)
        XCTAssertFalse(result.requiresRefresh)
        XCTAssertEqual(result.counts.failed, 1)
        XCTAssertEqual(result.localizationKey, "terminal.settings.failed")
    }

    func test远程终端提交超时后逐字段回读并报告部分成功() async throws {
        let transport = MockHTTPTransport(steps: [
            .response(response(#"{"success":true,"data":{"enable_ssh":false,"enable_telnet":false,"ssh_port":22}}"#)),
            .urlError(.timedOut),
            .response(response(#"{"success":true,"data":{"enable_ssh":true,"enable_telnet":false,"ssh_port":22}}"#))
        ])
        let repository = try makeRepository(
            apiNames: [DsmAPIName.coreTerminal],
            transport: transport
        )

        let result = try await repository.saveTerminalSettingsResult(
            NasTerminalSettings(
                isSSHEnabled: true,
                isTelnetEnabled: true,
                sshPort: 2_222
            )
        )

        XCTAssertEqual(result.status, .partialSuccess)
        XCTAssertTrue(result.requiresRefresh)
        XCTAssertEqual(
            result.counts,
            try MutationResultCounts(succeeded: 1, failed: 0, unknown: 2)
        )
        XCTAssertEqual(result.localizationKey, "terminal.settings.partial")
        let requests = await transport.recordedRequests()
        XCTAssertEqual(requests.count, 3)
        XCTAssertEqual(
            requests.filter { requestValue("method", in: $0) == "set" }.count,
            1
        )
    }

    func test远程终端提交断网且回读失败时不自动重放() async throws {
        let transport = MockHTTPTransport(steps: [
            .response(response(#"{"success":true,"data":{"enable_ssh":false,"enable_telnet":false,"ssh_port":22}}"#)),
            .urlError(.networkConnectionLost),
            .urlError(.notConnectedToInternet)
        ])
        let repository = try makeRepository(
            apiNames: [DsmAPIName.coreTerminal],
            transport: transport
        )

        let result = try await repository.saveTerminalSettingsResult(
            NasTerminalSettings(
                isSSHEnabled: true,
                isTelnetEnabled: false,
                sshPort: 2_222
            )
        )

        XCTAssertEqual(result.status, .submittedButUnverified)
        XCTAssertTrue(result.submitted)
        XCTAssertTrue(result.requiresRefresh)
        XCTAssertEqual(result.counts.unknown, 2)
        let requests = await transport.recordedRequests()
        XCTAssertEqual(requests.count, 3)
        XCTAssertEqual(
            requests.filter { requestValue("method", in: $0) == "set" }.count,
            1
        )
    }

    func test远程终端拒绝重复提交并区分提交后取消() async throws {
        let transport = MockHTTPTransport(steps: [
            .response(response(#"{"success":true,"data":{"enable_ssh":false,"enable_telnet":false,"ssh_port":22}}"#)),
            .waitUntilCancelled
        ])
        let repository = try makeRepository(
            apiNames: [DsmAPIName.coreTerminal],
            transport: transport
        )
        let settings = NasTerminalSettings(
            isSSHEnabled: true,
            isTelnetEnabled: false,
            sshPort: 22
        )
        let firstTask = Task {
            try await repository.saveTerminalSettingsResult(settings)
        }
        while await transport.recordedRequests().count < 2 {
            await Task.yield()
        }

        let duplicate = try await repository.saveTerminalSettingsResult(settings)
        firstTask.cancel()
        let cancelled = try await firstTask.value

        XCTAssertEqual(duplicate.status, .confirmedFailure)
        XCTAssertFalse(duplicate.submitted)
        XCTAssertEqual(duplicate.errorCategory, .conflict)
        XCTAssertEqual(cancelled.status, .cancellationRequestedAfterSubmission)
        XCTAssertTrue(cancelled.requiresRefresh)
    }

    func test远程终端预检拒绝无效端口且不发送请求() async throws {
        let transport = MockHTTPTransport(responses: [])
        let repository = try makeRepository(
            apiNames: [DsmAPIName.coreTerminal],
            transport: transport
        )

        let result = try await repository.saveTerminalSettingsResult(
            NasTerminalSettings(
                isSSHEnabled: true,
                isTelnetEnabled: false,
                sshPort: 65_536
            )
        )

        XCTAssertEqual(result.status, .confirmedFailure)
        XCTAssertFalse(result.submitted)
        XCTAssertEqual(result.errorCategory, .validation)
        XCTAssertEqual(result.localizationKey, "terminal.settings.invalid")
        let requests = await transport.recordedRequests()
        XCTAssertTrue(requests.isEmpty)
    }

    func test远程终端能力缺失时不发送请求() async throws {
        let transport = MockHTTPTransport(responses: [])
        let repository = try makeRepository(
            apiNames: [],
            transport: transport
        )

        let result = try await repository.saveTerminalSettingsResult(
            NasTerminalSettings(
                isSSHEnabled: true,
                isTelnetEnabled: false,
                sshPort: 22
            )
        )

        XCTAssertEqual(result.status, .unsupported)
        XCTAssertFalse(result.submitted)
        XCTAssertEqual(result.errorCategory, .unsupported)
        let requests = await transport.recordedRequests()
        XCTAssertTrue(requests.isEmpty)
    }

    func test代理设置写入后回读确认且不传入地址栏() async throws {
        let transport = MockHTTPTransport(responses: [
            response(#"{"success":true,"data":{"enable":false,"http_host":"","http_port":8080}}"#),
            response(#"{"success":true}"#),
            response(#"{"success":true,"data":{"enable":true,"http_host":"proxy.example.invalid","http_port":3128}}"#)
        ])
        let repository = try makeRepository(
            apiNames: [DsmAPIName.coreNetworkProxy],
            transport: transport
        )

        let result = try await repository.saveProxySettingsResult(
            NasProxySettings(
                isEnabled: true,
                host: " proxy.example.invalid ",
                port: 3128
            )
        )

        XCTAssertEqual(result.status, .confirmedSuccess)
        XCTAssertEqual(
            result.counts,
            try MutationResultCounts(succeeded: 3, failed: 0, unknown: 0)
        )
        let requests = await transport.recordedRequests()
        XCTAssertEqual(requestValue("method", in: requests[1]), "set")
        XCTAssertEqual(requestValue("http_host", in: requests[1]), "proxy.example.invalid")
        XCTAssertEqual(requestValue("http_port", in: requests[1]), "3128")
        XCTAssertFalse(requests[1].url?.absoluteString.contains("proxy.example.invalid") == true)
    }

    func test代理设置提交超时后逐字段回读并报告部分成功() async throws {
        let transport = MockHTTPTransport(steps: [
            .response(response(#"{"success":true,"data":{"enable":false,"http_host":"","http_port":8080}}"#)),
            .urlError(.timedOut),
            .response(response(#"{"success":true,"data":{"enable":true,"http_host":"","http_port":8080}}"#))
        ])
        let repository = try makeRepository(
            apiNames: [DsmAPIName.coreNetworkProxy],
            transport: transport
        )

        let result = try await repository.saveProxySettingsResult(
            NasProxySettings(
                isEnabled: true,
                host: "proxy.example.invalid",
                port: 3_128
            )
        )

        XCTAssertEqual(result.status, .partialSuccess)
        XCTAssertTrue(result.requiresRefresh)
        XCTAssertEqual(
            result.counts,
            try MutationResultCounts(succeeded: 1, failed: 0, unknown: 2)
        )
        XCTAssertEqual(result.localizationKey, "proxy.settings.partial")
        let requests = await transport.recordedRequests()
        XCTAssertEqual(requests.count, 3)
        XCTAssertEqual(
            requests.filter { requestValue("method", in: $0) == "set" }.count,
            1
        )
    }

    func test代理设置提交断网且回读失败时不自动重放() async throws {
        let transport = MockHTTPTransport(steps: [
            .response(response(#"{"success":true,"data":{"enable":false,"http_host":"","http_port":8080}}"#)),
            .urlError(.networkConnectionLost),
            .urlError(.notConnectedToInternet)
        ])
        let repository = try makeRepository(
            apiNames: [DsmAPIName.coreNetworkProxy],
            transport: transport
        )

        let result = try await repository.saveProxySettingsResult(
            NasProxySettings(
                isEnabled: true,
                host: "proxy.example.invalid",
                port: 3_128
            )
        )

        XCTAssertEqual(result.status, .submittedButUnverified)
        XCTAssertTrue(result.submitted)
        XCTAssertTrue(result.requiresRefresh)
        XCTAssertEqual(result.counts.unknown, 3)
        let requests = await transport.recordedRequests()
        XCTAssertEqual(requests.count, 3)
        XCTAssertEqual(
            requests.filter { requestValue("method", in: $0) == "set" }.count,
            1
        )
    }

    func test代理设置拒绝重复提交并区分提交后取消() async throws {
        let transport = MockHTTPTransport(steps: [
            .response(response(#"{"success":true,"data":{"enable":false,"http_host":"","http_port":8080}}"#)),
            .waitUntilCancelled
        ])
        let repository = try makeRepository(
            apiNames: [DsmAPIName.coreNetworkProxy],
            transport: transport
        )
        let settings = NasProxySettings(
            isEnabled: true,
            host: "proxy.example.invalid",
            port: 3_128
        )
        let firstTask = Task {
            try await repository.saveProxySettingsResult(settings)
        }
        while await transport.recordedRequests().count < 2 {
            await Task.yield()
        }

        let duplicate = try await repository.saveProxySettingsResult(settings)
        firstTask.cancel()
        let cancelled = try await firstTask.value

        XCTAssertEqual(duplicate.status, .confirmedFailure)
        XCTAssertFalse(duplicate.submitted)
        XCTAssertEqual(duplicate.errorCategory, .conflict)
        XCTAssertEqual(cancelled.status, .cancellationRequestedAfterSubmission)
        XCTAssertTrue(cancelled.requiresRefresh)
    }

    func test代理设置预检拒绝无效地址和端口且不发送请求() async throws {
        for settings in [
            NasProxySettings(
                isEnabled: true,
                host: "https://proxy.example.invalid/path",
                port: 3_128
            ),
            NasProxySettings(
                isEnabled: true,
                host: "proxy.example.invalid",
                port: 65_536
            ),
            NasProxySettings(
                isEnabled: true,
                host: " ",
                port: nil
            )
        ] {
            let transport = MockHTTPTransport(responses: [])
            let repository = try makeRepository(
                apiNames: [DsmAPIName.coreNetworkProxy],
                transport: transport
            )

            let result = try await repository.saveProxySettingsResult(settings)

            XCTAssertEqual(result.status, .confirmedFailure)
            XCTAssertFalse(result.submitted)
            XCTAssertEqual(result.errorCategory, .validation)
            XCTAssertEqual(result.localizationKey, "proxy.settings.invalid")
            let requests = await transport.recordedRequests()
            XCTAssertTrue(requests.isEmpty)
        }
    }

    func test代理设置能力缺失时不发送请求() async throws {
        let transport = MockHTTPTransport(responses: [])
        let repository = try makeRepository(
            apiNames: [],
            transport: transport
        )

        let result = try await repository.saveProxySettingsResult(
            NasProxySettings(
                isEnabled: true,
                host: "proxy.example.invalid",
                port: 3_128
            )
        )

        XCTAssertEqual(result.status, .unsupported)
        XCTAssertFalse(result.submitted)
        XCTAssertEqual(result.errorCategory, .unsupported)
        let requests = await transport.recordedRequests()
        XCTAssertTrue(requests.isEmpty)
    }

    func test硬件设置使用设备范围并在提交后回读确认() async throws {
        let transport = MockHTTPTransport(responses: [
            response(#"{"success":true,"data":{"rc_power_config":false}}"#),
            response(#"{"success":true,"data":{"led_brightness":3}}"#),
            response(#"{"success":true,"data":{"min":0,"max":7}}"#),
            response(#"{"success":true}"#),
            response(#"{"success":true}"#),
            response(#"{"success":true}"#),
            response(#"{"success":true,"data":{"rc_power_config":true}}"#),
            response(#"{"success":true,"data":{"led_brightness":5}}"#),
            response(#"{"success":true,"data":{"min":0,"max":7}}"#)
        ])
        let repository = try makeRepository(
            apiNames: [
                DsmAPIName.coreHardwarePowerRecovery,
                DsmAPIName.coreHardwareLEDBrightness
            ],
            transport: transport
        )

        let result = try await repository.saveHardwareSettingsResult(
            NasHardwareSettings(
                restartsAfterPowerFailure: true,
                ledBrightness: 5,
                ledBrightnessRange: 0...7
            )
        )

        XCTAssertEqual(result.status, .confirmedSuccess)
        XCTAssertEqual(
            result.counts,
            try MutationResultCounts(succeeded: 2, failed: 0, unknown: 0)
        )
        let requests = await transport.recordedRequests()
        XCTAssertEqual(requests.count, 9)
        XCTAssertEqual(requestValue("method", in: requests[3]), "set")
        XCTAssertEqual(requestValue("rc_power_config", in: requests[3]), "true")
        XCTAssertEqual(requestValue("method", in: requests[4]), "set_current_brightness")
        XCTAssertEqual(requestValue("led_brightness", in: requests[4]), "5")
        XCTAssertEqual(requestValue("method", in: requests[5]), "update")
    }

    func test硬件设置中途超时后回读并报告部分成功() async throws {
        let transport = MockHTTPTransport(steps: [
            .response(response(#"{"success":true,"data":{"rc_power_config":false}}"#)),
            .response(response(#"{"success":true,"data":{"dual_fan_speed":"quietfan"}}"#)),
            .response(response(#"{"success":true}"#)),
            .urlError(.timedOut),
            .response(response(#"{"success":true,"data":{"rc_power_config":true}}"#)),
            .response(response(#"{"success":true,"data":{"dual_fan_speed":"quietfan"}}"#))
        ])
        let repository = try makeRepository(
            apiNames: [
                DsmAPIName.coreHardwarePowerRecovery,
                DsmAPIName.coreHardwareFanSpeed
            ],
            transport: transport
        )

        let result = try await repository.saveHardwareSettingsResult(
            NasHardwareSettings(
                restartsAfterPowerFailure: true,
                ledBrightness: nil,
                ledBrightnessRange: nil,
                fanMode: "coolfan"
            )
        )

        XCTAssertEqual(result.status, .partialSuccess)
        XCTAssertTrue(result.requiresRefresh)
        XCTAssertEqual(
            result.counts,
            try MutationResultCounts(succeeded: 1, failed: 0, unknown: 1)
        )
        XCTAssertEqual(result.localizationKey, "hardware.settings.partial")
        let requests = await transport.recordedRequests()
        XCTAssertEqual(requests.count, 6)
        XCTAssertEqual(
            requests.filter { requestValue("dual_fan_speed", in: $0) == "coolfan" }.count,
            1
        )
    }

    func test硬件设置提交断网且回读失败时不自动重放() async throws {
        let transport = MockHTTPTransport(steps: [
            .response(response(#"{"success":true,"data":{"rc_power_config":false}}"#)),
            .urlError(.networkConnectionLost),
            .urlError(.notConnectedToInternet)
        ])
        let repository = try makeRepository(
            apiNames: [DsmAPIName.coreHardwarePowerRecovery],
            transport: transport
        )

        let result = try await repository.saveHardwareSettingsResult(
            NasHardwareSettings(
                restartsAfterPowerFailure: true,
                ledBrightness: nil,
                ledBrightnessRange: nil
            )
        )

        XCTAssertEqual(result.status, .submittedButUnverified)
        XCTAssertTrue(result.submitted)
        XCTAssertTrue(result.requiresRefresh)
        XCTAssertEqual(result.counts.unknown, 1)
        let requests = await transport.recordedRequests()
        XCTAssertEqual(requests.count, 3)
        XCTAssertEqual(
            requests.filter { requestValue("method", in: $0) == "set" }.count,
            1
        )
    }

    func test硬件设置预检拒绝越界亮度且不提交() async throws {
        let transport = MockHTTPTransport(responses: [
            response(#"{"success":true,"data":{"led_brightness":3}}"#),
            response(#"{"success":true,"data":{"min":0,"max":7}}"#)
        ])
        let repository = try makeRepository(
            apiNames: [DsmAPIName.coreHardwareLEDBrightness],
            transport: transport
        )

        let result = try await repository.saveHardwareSettingsResult(
            NasHardwareSettings(
                restartsAfterPowerFailure: nil,
                ledBrightness: 8,
                ledBrightnessRange: 0...7
            )
        )

        XCTAssertEqual(result.status, .confirmedFailure)
        XCTAssertFalse(result.submitted)
        XCTAssertEqual(result.errorCategory, .validation)
        let requests = await transport.recordedRequests()
        XCTAssertEqual(requests.count, 2)
        XCTAssertFalse(requests.contains {
            ["set_current_brightness", "update"].contains(
                requestValue("method", in: $0)
            )
        })
    }

    func test硬件设置拒绝重复提交并区分提交后取消() async throws {
        let transport = MockHTTPTransport(steps: [
            .response(response(#"{"success":true,"data":{"rc_power_config":false}}"#)),
            .waitUntilCancelled
        ])
        let repository = try makeRepository(
            apiNames: [DsmAPIName.coreHardwarePowerRecovery],
            transport: transport
        )
        let settings = NasHardwareSettings(
            restartsAfterPowerFailure: true,
            ledBrightness: nil,
            ledBrightnessRange: nil
        )
        let firstTask = Task {
            try await repository.saveHardwareSettingsResult(settings)
        }
        while await transport.recordedRequests().count < 2 {
            await Task.yield()
        }

        let duplicate = try await repository.saveHardwareSettingsResult(settings)
        firstTask.cancel()
        let cancelled = try await firstTask.value

        XCTAssertEqual(duplicate.status, .confirmedFailure)
        XCTAssertFalse(duplicate.submitted)
        XCTAssertEqual(duplicate.errorCategory, .conflict)
        XCTAssertEqual(cancelled.status, .cancellationRequestedAfterSubmission)
        XCTAssertTrue(cancelled.requiresRefresh)
    }

    func test远程访问设置分别写入并回读确认() async throws {
        let transport = MockHTTPTransport(responses: [
            response(#"{"success":true,"data":{"relay_enabled":true}}"#),
            response(#"{"success":true,"data":{"enabled":false}}"#),
            response(#"{"success":true}"#),
            response(#"{"success":true}"#),
            response(#"{"success":true,"data":{"relay_enabled":false}}"#),
            response(#"{"success":true,"data":{"enabled":true}}"#)
        ])
        let repository = try makeRepository(
            apiNames: [
                DsmAPIName.coreQuickConnect,
                DsmAPIName.coreQuickConnectUPnP
            ],
            transport: transport
        )

        let result = try await repository.saveRemoteAccessSettingsResult(
            NasRemoteAccessSettings(
                isRelayEnabled: false,
                isRouterConfigurationEnabled: true,
                canDisableRelay: true
            )
        )

        XCTAssertEqual(result.status, .confirmedSuccess)
        XCTAssertEqual(
            result.counts,
            try MutationResultCounts(succeeded: 2, failed: 0, unknown: 0)
        )
        let requests = await transport.recordedRequests()
        XCTAssertEqual(requests.count, 6)
        XCTAssertEqual(requestValue("method", in: requests[2]), "set_misc_config")
        XCTAssertEqual(requestValue("version", in: requests[2]), "3")
        XCTAssertEqual(requestValue("relay_enabled", in: requests[2]), "false")
        XCTAssertEqual(requestValue("method", in: requests[3]), "set")
        XCTAssertEqual(requestValue("enabled", in: requests[3]), "true")
    }

    func test远程访问中途超时后回读并报告部分成功() async throws {
        let transport = MockHTTPTransport(steps: [
            .response(response(#"{"success":true,"data":{"relay_enabled":true}}"#)),
            .response(response(#"{"success":true,"data":{"enabled":false}}"#)),
            .response(response(#"{"success":true}"#)),
            .urlError(.timedOut),
            .response(response(#"{"success":true,"data":{"relay_enabled":false}}"#)),
            .response(response(#"{"success":true,"data":{"enabled":false}}"#))
        ])
        let repository = try makeRepository(
            apiNames: [
                DsmAPIName.coreQuickConnect,
                DsmAPIName.coreQuickConnectUPnP
            ],
            transport: transport
        )

        let result = try await repository.saveRemoteAccessSettingsResult(
            NasRemoteAccessSettings(
                isRelayEnabled: false,
                isRouterConfigurationEnabled: true,
                canDisableRelay: true
            )
        )

        XCTAssertEqual(result.status, .partialSuccess)
        XCTAssertTrue(result.requiresRefresh)
        XCTAssertEqual(
            result.counts,
            try MutationResultCounts(succeeded: 1, failed: 0, unknown: 1)
        )
        XCTAssertEqual(result.localizationKey, "remote-access.settings.partial")
        let requests = await transport.recordedRequests()
        XCTAssertEqual(requests.count, 6)
        XCTAssertEqual(
            requests.filter { requestValue("enabled", in: $0) == "true" }.count,
            1
        )
    }

    func test远程访问提交断网且回读失败时不自动重放() async throws {
        let transport = MockHTTPTransport(steps: [
            .response(response(#"{"success":true,"data":{"relay_enabled":true}}"#)),
            .urlError(.networkConnectionLost),
            .urlError(.notConnectedToInternet)
        ])
        let repository = try makeRepository(
            apiNames: [DsmAPIName.coreQuickConnect],
            transport: transport
        )

        let result = try await repository.saveRemoteAccessSettingsResult(
            NasRemoteAccessSettings(
                isRelayEnabled: false,
                isRouterConfigurationEnabled: nil,
                canDisableRelay: true
            )
        )

        XCTAssertEqual(result.status, .submittedButUnverified)
        XCTAssertTrue(result.submitted)
        XCTAssertTrue(result.requiresRefresh)
        XCTAssertEqual(result.counts.unknown, 1)
        let requests = await transport.recordedRequests()
        XCTAssertEqual(requests.count, 3)
        XCTAssertEqual(
            requests.filter {
                requestValue("method", in: $0) == "set_misc_config"
            }.count,
            1
        )
    }

    func test远程访问拒绝重复提交并区分提交后取消() async throws {
        let transport = MockHTTPTransport(steps: [
            .response(response(#"{"success":true,"data":{"enabled":false}}"#)),
            .waitUntilCancelled
        ])
        let repository = try makeRepository(
            apiNames: [DsmAPIName.coreQuickConnectUPnP],
            transport: transport
        )
        let settings = NasRemoteAccessSettings(
            isRelayEnabled: nil,
            isRouterConfigurationEnabled: true,
            canDisableRelay: true
        )
        let firstTask = Task {
            try await repository.saveRemoteAccessSettingsResult(settings)
        }
        while await transport.recordedRequests().count < 2 {
            await Task.yield()
        }

        let duplicate = try await repository.saveRemoteAccessSettingsResult(settings)
        firstTask.cancel()
        let cancelled = try await firstTask.value

        XCTAssertEqual(duplicate.status, .confirmedFailure)
        XCTAssertFalse(duplicate.submitted)
        XCTAssertEqual(duplicate.errorCategory, .conflict)
        XCTAssertEqual(cancelled.status, .cancellationRequestedAfterSubmission)
        XCTAssertTrue(cancelled.requiresRefresh)
    }

    func test当前使用中继连接时预检拒绝关闭中继() async throws {
        let transport = MockHTTPTransport(responses: [
            response(#"{"success":true,"data":{"relay_enabled":true}}"#)
        ])
        let repository = try makeRepository(
            apiNames: [DsmAPIName.coreQuickConnect],
            transport: transport,
            host: "alpha.beta.quickconnect.to"
        )

        let result = try await repository.saveRemoteAccessSettingsResult(
            NasRemoteAccessSettings(
                isRelayEnabled: false,
                isRouterConfigurationEnabled: nil,
                canDisableRelay: false
            )
        )

        XCTAssertEqual(result.status, .confirmedFailure)
        XCTAssertFalse(result.submitted)
        XCTAssertEqual(result.errorCategory, .conflict)
        let requests = await transport.recordedRequests()
        XCTAssertEqual(requests.count, 1)
    }

    func test安全防护设置写入完整规则并回读确认() async throws {
        let transport = MockHTTPTransport(responses: [
            response(#"{"success":true,"data":{"enable":false,"attempts":10,"within_mins":5,"expire_day":0}}"#),
            response(#"{"success":true}"#),
            response(#"{"success":true,"data":{"enable":true,"attempts":5,"within_mins":10,"expire_day":7}}"#)
        ])
        let repository = try makeRepository(
            apiNames: [DsmAPIName.coreSecurityAutoBlock],
            transport: transport
        )

        try await repository.saveSecuritySettings(
            NasSecuritySettings(
                isAutoBlockEnabled: true,
                failedAttempts: 5,
                withinMinutes: 10,
                expirationDays: 7
            )
        )

        let requests = await transport.recordedRequests()
        XCTAssertEqual(requestValue("method", in: requests[1]), "set")
        XCTAssertEqual(requestValue("enable", in: requests[1]), "true")
        XCTAssertEqual(requestValue("attempts", in: requests[1]), "5")
        XCTAssertEqual(requestValue("within_mins", in: requests[1]), "10")
        XCTAssertEqual(requestValue("expire_day", in: requests[1]), "7")
    }

    func test局域网发现设置分别写入并回读确认() async throws {
        let transport = MockHTTPTransport(responses: [
            response(#"{"success":true,"data":{"enable_ssdp":false,"enable_avahi":true}}"#),
            response(#"{"success":true,"data":{"enable_smb_time_machine":false}}"#),
            response(#"{"success":true}"#),
            response(#"{"success":true}"#),
            response(#"{"success":true,"data":{"enable_ssdp":true,"enable_avahi":true}}"#),
            response(#"{"success":true,"data":{"enable_smb_time_machine":true}}"#)
        ])
        let repository = try makeRepository(
            apiNames: [DsmAPIName.coreWebDSM, DsmAPIName.coreFileServiceDiscovery],
            transport: transport
        )

        try await repository.saveFileServiceSettings(
            NasFileServiceSettings(
                isSMBEnabled: nil,
                isNFSEnabled: nil,
                isFTPEnabled: nil,
                isFTPSEnabled: nil,
                ftpPort: nil,
                isSFTPEnabled: nil,
                sftpPort: nil,
                isSSDPEnabled: true,
                isBonjourEnabled: true,
                isSMBTimeMachineEnabled: true
            )
        )

        let requests = await transport.recordedRequests()
        XCTAssertEqual(requestValue("method", in: requests[2]), "set")
        XCTAssertEqual(requestValue("version", in: requests[2]), "2")
        XCTAssertEqual(requestValue("enable_ssdp", in: requests[2]), "true")
        XCTAssertEqual(requestValue("enable_avahi", in: requests[2]), "true")
        XCTAssertEqual(requestValue("method", in: requests[3]), "set")
        XCTAssertEqual(requestValue("enable_smb_time_machine", in: requests[3]), "true")
    }

    func test风扇和提示音设置只提交变化并回读确认() async throws {
        let transport = MockHTTPTransport(responses: [
            response(#"{"success":true,"data":{"dual_fan_speed":"quietfan"}}"#),
            response(#"{"success":true,"data":{"fan_fail":true,"volume_or_cache_crash":true,"poweron_beep":false,"poweroff_beep":false,"reset_beep":true}}"#),
            response(#"{"success":true}"#),
            response(#"{"success":true}"#),
            response(#"{"success":true,"data":{"dual_fan_speed":"coolfan"}}"#),
            response(#"{"success":true,"data":{"fan_fail":true,"volume_or_cache_crash":true,"poweron_beep":true,"poweroff_beep":false,"reset_beep":true}}"#)
        ])
        let repository = try makeRepository(
            apiNames: [
                DsmAPIName.coreHardwareFanSpeed,
                DsmAPIName.coreHardwareBeepControl
            ],
            transport: transport
        )

        try await repository.saveHardwareSettings(
            NasHardwareSettings(
                restartsAfterPowerFailure: nil,
                ledBrightness: nil,
                ledBrightnessRange: nil,
                fanMode: "coolfan",
                isFanFailureAlertEnabled: true,
                isVolumeFailureAlertEnabled: true,
                isPowerOnSoundEnabled: true,
                isPowerOffSoundEnabled: false,
                isResetSoundEnabled: true
            )
        )

        let requests = await transport.recordedRequests()
        XCTAssertEqual(requestValue("dual_fan_speed", in: requests[2]), "coolfan")
        XCTAssertEqual(requestValue("poweron_beep", in: requests[3]), "true")
        XCTAssertNil(requestValue("fan_fail", in: requests[3]))
    }

    func test拒绝服务攻击防护按真实网卡提交并回读确认() async throws {
        let transport = MockHTTPTransport(responses: [
            response(#"{"success":true,"data":{"enable":true,"attempts":5,"within_mins":10,"expire_day":7}}"#),
            response(#"{"success":true,"data":{"interfaces":[{"id":"eth0","display":"局域网 1"},{"id":"eth1","display":"局域网 2"}]}}"#),
            response(#"{"success":true,"data":{"configs":[{"adapter":"eth0","dos_protect_enable":false},{"adapter":"eth1","dos_protect_enable":true}]}}"#),
            response(#"{"success":true}"#),
            response(#"{"success":true,"data":{"enable":true,"attempts":5,"within_mins":10,"expire_day":7}}"#),
            response(#"{"success":true,"data":{"interfaces":[{"id":"eth0","display":"局域网 1"},{"id":"eth1","display":"局域网 2"}]}}"#),
            response(#"{"success":true,"data":{"configs":[{"adapter":"eth0","dos_protect_enable":true},{"adapter":"eth1","dos_protect_enable":true}]}}"#)
        ])
        let repository = try makeRepository(
            apiNames: [
                DsmAPIName.coreSecurityAutoBlock,
                DsmAPIName.coreNetworkEthernet,
                DsmAPIName.coreSecurityDoS
            ],
            transport: transport
        )

        try await repository.saveSecuritySettings(
            NasSecuritySettings(
                isAutoBlockEnabled: true,
                failedAttempts: 5,
                withinMinutes: 10,
                expirationDays: 7,
                dosProtection: [
                    NasDoSProtectionSetting(
                        id: "eth0",
                        displayName: "局域网 1",
                        isEnabled: true
                    ),
                    NasDoSProtectionSetting(
                        id: "eth1",
                        displayName: "局域网 2",
                        isEnabled: true
                    )
                ]
            )
        )

        let requests = await transport.recordedRequests()
        XCTAssertEqual(requestValue("method", in: requests[3]), "set")
        XCTAssertEqual(requestValue("version", in: requests[3]), "2")
        XCTAssertTrue(requestValue("configs", in: requests[3])?.contains("eth0") == true)
        XCTAssertFalse(requests.contains {
            requestValue("method", in: $0) == "set"
                && requestValue("enable", in: $0) != nil
        })
    }

    func test休眠设置只提交设备返回的可修改字段并回读确认() async throws {
        let transport = MockHTTPTransport(responses: [
            response(#"{"success":true,"data":{"eunit_deep_sleep":false,"enable_log":true,"sata_deep_sleep":true,"ignore_netbios_broadcast":false,"auto_poweroff_enable":false}}"#),
            response(#"{"success":true}"#),
            response(#"{"success":true,"data":{"eunit_deep_sleep":true,"enable_log":true,"sata_deep_sleep":true,"ignore_netbios_broadcast":true,"auto_poweroff_enable":false}}"#)
        ])
        let repository = try makeRepository(
            apiNames: [DsmAPIName.coreHardwareHibernation],
            transport: transport
        )

        try await repository.saveHardwareSettings(
            NasHardwareSettings(
                restartsAfterPowerFailure: nil,
                ledBrightness: nil,
                ledBrightnessRange: nil,
                isExternalDriveDeepSleepEnabled: true,
                isWakeUpLogEnabled: true,
                isSATASleepEnabled: true,
                ignoresNetworkDiscoveryDuringSleep: true,
                isAutomaticPowerOffEnabled: false
            )
        )

        let requests = await transport.recordedRequests()
        XCTAssertEqual(requestValue("method", in: requests[1]), "set")
        XCTAssertEqual(requestValue("eunit_deep_sleep", in: requests[1]), "true")
        XCTAssertEqual(requestValue("ignore_netbios_broadcast", in: requests[1]), "true")
        XCTAssertNil(requestValue("enable_log", in: requests[1]))
        XCTAssertNil(requestValue("sata_deep_sleep", in: requests[1]))
    }

    func test读取区域时区和网络校时设置() async throws {
        let transport = MockHTTPTransport(responses: [
            response(#"{"success":true,"data":{"date_format":"Y-m-d","time_format":"H:i","timezone":"Asia/Shanghai","enable_ntp":"ntp","server":"time.example.invalid,pool.example.invalid","date":"2026/7/26","hour":18,"minute":30,"second":10}}"#),
            response(#"{"success":true,"data":{"zonedata":[{"value":"Asia/Shanghai","display":"北京、上海"},{"value":"UTC","display":"协调世界时"}]}}"#)
        ])
        let repository = try makeRepository(
            apiNames: [DsmAPIName.coreRegionNTP],
            transport: transport
        )

        let settings = try await repository.loadRegionSettings()

        XCTAssertEqual(settings.dateFormat, "Y-m-d")
        XCTAssertEqual(settings.timeFormat, "H:i")
        XCTAssertEqual(settings.timeZone, "Asia/Shanghai")
        XCTAssertTrue(settings.isNetworkTimeEnabled)
        XCTAssertEqual(
            settings.timeServers,
            ["time.example.invalid", "pool.example.invalid"]
        )
        XCTAssertEqual(settings.timeZones.map(\.id), ["Asia/Shanghai", "UTC"])
        XCTAssertNotNil(settings.manualDate)
    }

    func test网络校时先验证服务器再保存并回读确认() async throws {
        let current = #"{"success":true,"data":{"date_format":"Y-m-d","time_format":"H:i","timezone":"Asia/Shanghai","enable_ntp":"manual","server":"","date":"2026/7/26","hour":18,"minute":30,"second":10}}"#
        let zones = #"{"success":true,"data":{"zonedata":[{"value":"Asia/Shanghai","display":"北京、上海"},{"value":"UTC","display":"协调世界时"}]}}"#
        let transport = MockHTTPTransport(responses: [
            response(current),
            response(zones),
            response(current),
            response(zones),
            response(#"{"success":true}"#),
            response(#"{"success":true}"#),
            response(#"{"success":true,"data":{"date_format":"Y/m/d","time_format":"H:i","timezone":"UTC","enable_ntp":"ntp","server":"time.example.invalid"}}"#),
            response(zones)
        ])
        let repository = try makeRepository(
            apiNames: [DsmAPIName.coreRegionNTP],
            transport: transport
        )
        let original = try await repository.loadRegionSettings()

        try await repository.saveRegionSettings(
            NasRegionSettings(
                dateFormat: "Y/m/d",
                timeFormat: "H:i",
                timeZone: "UTC",
                isNetworkTimeEnabled: true,
                timeServers: ["time.example.invalid"],
                manualDate: original.manualDate,
                timeZones: original.timeZones
            )
        )

        let requests = await transport.recordedRequests()
        XCTAssertEqual(requestValue("method", in: requests[4]), "sync")
        XCTAssertEqual(requestValue("servers", in: requests[4]), #"["time.example.invalid"]"#)
        XCTAssertEqual(requestValue("method", in: requests[5]), "set")
        XCTAssertEqual(requestValue("enable_ntp", in: requests[5]), "ntp")
        XCTAssertEqual(requestValue("timezone", in: requests[5]), "UTC")
    }

    func test新建DDNS先验证连接再保存更新并回读确认() async throws {
        let providers = #"{"success":true,"data":{"providers":[{"id":"Example","display":"示例服务"}]}}"#
        let transport = MockHTTPTransport(responses: [
            response(providers),
            response(#"{"success":true,"data":{"records":[]}}"#),
            response(#"{"success":true}"#),
            response(#"{"success":true}"#),
            response(#"{"success":true}"#),
            response(providers),
            response(#"{"success":true,"data":{"records":[{"provider":"Example","hostname":"nas.example.invalid","username":"owner","enable":true,"ip":"192.0.2.10","status":"service_ddns_normal"}]}}"#)
        ])
        let repository = try makeRepository(
            apiNames: [DsmAPIName.coreDDNSProvider, DsmAPIName.coreDDNSRecord],
            transport: transport
        )

        try await repository.saveDDNS(
            NasDDNSDraft(
                providerID: "Example",
                hostname: "nas.example.invalid",
                username: "owner",
                password: "REDACTED_PASSWORD"
            )
        )

        let requests = await transport.recordedRequests()
        XCTAssertEqual(requestValue("method", in: requests[2]), "test")
        XCTAssertEqual(requestValue("method", in: requests[3]), "create")
        XCTAssertEqual(requestValue("method", in: requests[4]), "update_ip_address")
        XCTAssertEqual(requestValue("id", in: requests[4]), "Example")
        XCTAssertFalse(requests[3].url?.absoluteString.contains("REDACTED_PASSWORD") == true)
    }

    func test读取DDNS时合并重复服务商并忽略无效项() async throws {
        let transport = MockHTTPTransport(responses: [
            response(#"{"success":true,"data":{"providers":[{"id":"Synology"},{"id":"Synology","display":"Synology"},{"provider":"Example","name":"示例服务"},{"id":"","display":"无效项"}]}}"#),
            response(#"{"success":true,"data":{"records":[{"provider":"Synology","hostname":"nas.example.invalid","enable":true,"ip":"192.0.2.10"}]}}"#)
        ])
        let repository = try makeRepository(
            apiNames: [DsmAPIName.coreDDNSProvider, DsmAPIName.coreDDNSRecord],
            transport: transport
        )

        let directory = try await repository.loadDDNS()

        XCTAssertEqual(directory.providers.map(\.id), ["Synology", "Example"])
        XCTAssertEqual(directory.providers.map(\.displayName), ["Synology", "示例服务"])
        XCTAssertEqual(directory.records.count, 1)
        XCTAssertEqual(directory.records.first?.providerName, "Synology")
    }

    func testUPS设置提交连接方式和安全关机参数并回读确认() async throws {
        let transport = MockHTTPTransport(responses: [
            response(#"{"success":true,"data":{"enable":false,"mode":"USB","delay_time":60,"ups_set_safemode_until_lowbatt":false,"shutdown_device":false,"net_server_ip":"","snmp_server_ip":""}}"#),
            response(#"{"success":true}"#),
            response(#"{"success":true,"data":{"enable":true,"mode":"SLAVE","delay_time":120,"ups_set_safemode_until_lowbatt":false,"shutdown_device":true,"net_server_ip":"192.0.2.2","snmp_server_ip":""}}"#)
        ])
        let repository = try makeRepository(
            apiNames: [DsmAPIName.coreExternalDeviceUPS],
            transport: transport
        )

        try await repository.saveHardwareSettings(
            NasHardwareSettings(
                restartsAfterPowerFailure: nil,
                ledBrightness: nil,
                ledBrightnessRange: nil,
                ups: NasUPSSettings(
                    isEnabled: true,
                    mode: "SLAVE",
                    safeModeDelaySeconds: 120,
                    waitsUntilLowBattery: false,
                    shutsDownUPSAfterSafeMode: true,
                    networkServerAddress: "192.0.2.2",
                    snmpServerAddress: ""
                )
            )
        )

        let requests = await transport.recordedRequests()
        XCTAssertEqual(requestValue("method", in: requests[1]), "set")
        XCTAssertEqual(requestValue("mode", in: requests[1]), "SLAVE")
        XCTAssertEqual(requestValue("delay_time", in: requests[1]), "120")
        XCTAssertEqual(requestValue("net_server_ip", in: requests[1]), "192.0.2.2")
        XCTAssertEqual(requestValue("shutdown_device", in: requests[1]), "true")
    }

    func test网卡设置使用单张网卡配置并在提交后回读() async throws {
        let transport = MockHTTPTransport(responses: [
            response(#"{"success":true,"data":{"interfaces":[{"ifname":"eth0","title":"局域网 1","status":"connected"}]}}"#),
            response(#"{"success":true,"data":{"ifname":"eth0","title":"局域网 1","status":"connected","use_dhcp":true,"ip":"192.0.2.10","mask":"255.255.255.0","gateway":"192.0.2.1","dns":"192.0.2.1","is_default_gateway":true,"mtu":1500,"enable_vlan":false,"vlan_id":0}}"#),
            response(#"{"success":true}"#),
            response(#"{"success":true,"data":{"ifname":"eth0","title":"局域网 1","status":"connected","use_dhcp":false,"ip":"192.0.2.20","mask":"255.255.255.0","gateway":"192.0.2.1","dns":"192.0.2.1","is_default_gateway":true,"mtu":1500,"enable_vlan":true,"vlan_id":20}}"#)
        ])
        let repository = try makeRepository(
            apiNames: [DsmAPIName.coreNetworkEthernet],
            transport: transport
        )

        try await repository.saveEthernetInterface(
            NasEthernetInterface(
                id: "eth0",
                displayName: "局域网 1",
                status: "connected",
                usesDHCP: false,
                address: "192.0.2.20",
                subnetMask: "255.255.255.0",
                gateway: "192.0.2.1",
                dnsServers: "192.0.2.1",
                isDefaultGateway: true,
                mtu: 1_500,
                isVLANEnabled: true,
                vlanID: 20
            )
        )

        let requests = await transport.recordedRequests()
        XCTAssertEqual(requestValue("method", in: requests[2]), "set")
        XCTAssertEqual(requestValue("version", in: requests[2]), "1")
        XCTAssertTrue(requestValue("configs", in: requests[2])?.contains(#""ifname":"eth0""#) == true)
        XCTAssertTrue(requestValue("configs", in: requests[2])?.contains(#""vlan_id":20"#) == true)
    }

    func test网卡设置回读一致时返回确认成功() async throws {
        let transport = MockHTTPTransport(responses: [
            response(ethernetListResponse),
            response(ethernetCurrentResponse),
            response(#"{"success":true}"#),
            response(ethernetUpdatedResponse)
        ])
        let repository = try makeRepository(
            apiNames: [DsmAPIName.coreNetworkEthernet],
            transport: transport
        )

        let result = try await repository.saveEthernetInterfaceResult(
            ethernetUpdate
        )

        XCTAssertEqual(result.status, .confirmedSuccess)
        XCTAssertTrue(result.submitted)
        XCTAssertFalse(result.requiresRefresh)
        XCTAssertEqual(result.counts.succeeded, 1)
    }

    func test网卡设置提交时断网保留未确认语义且不重放() async throws {
        let transport = MockHTTPTransport(steps: [
            .response(response(ethernetListResponse)),
            .response(response(ethernetCurrentResponse)),
            .urlError(.networkConnectionLost)
        ])
        let repository = try makeRepository(
            apiNames: [DsmAPIName.coreNetworkEthernet],
            transport: transport
        )

        let result = try await repository.saveEthernetInterfaceResult(
            ethernetUpdate
        )

        XCTAssertEqual(result.status, .submittedButUnverified)
        XCTAssertTrue(result.submitted)
        XCTAssertTrue(result.requiresRefresh)
        XCTAssertEqual(result.errorCategory, .network)
        XCTAssertEqual(result.localizationKey, "network.ethernet.unverified")
        let requests = await transport.recordedRequests()
        XCTAssertEqual(
            requests.filter { requestValue("method", in: $0) == "set" }.count,
            1
        )
    }

    func test网卡设置回读失败时要求重新连接核对() async throws {
        let transport = MockHTTPTransport(steps: [
            .response(response(ethernetListResponse)),
            .response(response(ethernetCurrentResponse)),
            .response(response(#"{"success":true}"#)),
            .urlError(.timedOut)
        ])
        let repository = try makeRepository(
            apiNames: [DsmAPIName.coreNetworkEthernet],
            transport: transport
        )

        let result = try await repository.saveEthernetInterfaceResult(
            ethernetUpdate
        )

        XCTAssertEqual(result.status, .submittedButUnverified)
        XCTAssertTrue(result.requiresRefresh)
        XCTAssertEqual(result.counts.unknown, 1)
        let requests = await transport.recordedRequests()
        XCTAssertEqual(
            requests.filter { requestValue("method", in: $0) == "set" }.count,
            1
        )
    }

    func test网卡设置拒绝同一目标重复提交并区分提交后取消() async throws {
        let transport = MockHTTPTransport(steps: [
            .response(response(ethernetListResponse)),
            .response(response(ethernetCurrentResponse)),
            .waitUntilCancelled
        ])
        let repository = try makeRepository(
            apiNames: [DsmAPIName.coreNetworkEthernet],
            transport: transport
        )
        let update = ethernetUpdate
        let firstTask = Task {
            try await repository.saveEthernetInterfaceResult(update)
        }
        while await transport.recordedRequests().count < 3 {
            await Task.yield()
        }

        let duplicate = try await repository.saveEthernetInterfaceResult(
            update
        )
        firstTask.cancel()
        let cancelled = try await firstTask.value

        XCTAssertEqual(duplicate.status, .confirmedFailure)
        XCTAssertFalse(duplicate.submitted)
        XCTAssertEqual(duplicate.errorCategory, .conflict)
        XCTAssertEqual(cancelled.status, .cancellationRequestedAfterSubmission)
        XCTAssertTrue(cancelled.requiresRefresh)
    }

    func test关闭防火墙使用专用停用动作并回读确认() async throws {
        let autoBlock = #"{"success":true,"data":{"enable":true,"attempts":5,"within_mins":10,"expire_day":0}}"#
        let transport = MockHTTPTransport(responses: [
            response(autoBlock),
            response(#"{"success":true,"data":{"enable_firewall":true,"profile_name":"default"}}"#),
            response(#"{"success":true,"data":{"enable_port_check":true}}"#),
            response(#"{"success":true}"#),
            response(autoBlock),
            response(#"{"success":true,"data":{"enable_firewall":false,"profile_name":"default"}}"#),
            response(#"{"success":true,"data":{"enable_port_check":true}}"#)
        ])
        let repository = try makeRepository(
            apiNames: [
                DsmAPIName.coreSecurityAutoBlock,
                DsmAPIName.coreSecurityFirewall,
                DsmAPIName.coreSecurityFirewallConf
            ],
            transport: transport
        )

        try await repository.saveSecuritySettings(
            NasSecuritySettings(
                isAutoBlockEnabled: true,
                failedAttempts: 5,
                withinMinutes: 10,
                expirationDays: nil,
                isFirewallEnabled: false,
                firewallProfileName: "default",
                isPortScanProtectionEnabled: true
            )
        )

        let requests = await transport.recordedRequests()
        XCTAssertEqual(requestValue("method", in: requests[3]), "set")
        XCTAssertEqual(requestValue("set_type", in: requests[3]), "disable")
    }

    func test安全设置统一结果逐项提交并回读确认() async throws {
        let transport = MockHTTPTransport(responses: [
            response(securityAutoBlock(enabled: false, attempts: 10, within: 5, expiration: 0)),
            response(securityFirewall(enabled: true)),
            response(securityFirewallConf(enabled: false)),
            response(securityEthernet),
            response(securityDoS(enabled: false)),
            response(#"{"success":true}"#),
            response(#"{"success":true}"#),
            response(#"{"success":true}"#),
            response(#"{"success":true}"#),
            response(securityAutoBlock(enabled: true, attempts: 5, within: 10, expiration: 7)),
            response(securityFirewall(enabled: false)),
            response(securityFirewallConf(enabled: true)),
            response(securityEthernet),
            response(securityDoS(enabled: true))
        ])
        let repository = try makeRepository(
            apiNames: securityAPINameSet,
            transport: transport
        )

        let result = try await repository.saveSecuritySettingsResult(
            securityUpdate
        )

        XCTAssertEqual(result.status, .confirmedSuccess)
        XCTAssertEqual(result.counts, try MutationResultCounts(
            succeeded: 4,
            failed: 0,
            unknown: 0
        ))
        let requests = await transport.recordedRequests()
        XCTAssertEqual(requestValue("method", in: requests[5]), "set")
        XCTAssertEqual(requestValue("method", in: requests[6]), "set")
        XCTAssertEqual(requestValue("version", in: requests[6]), "2")
        XCTAssertEqual(requestValue("method", in: requests[7]), "set")
        XCTAssertEqual(requestValue("set_type", in: requests[8]), "disable")
    }

    func test安全设置中途失败后回读并报告部分成功() async throws {
        let transport = MockHTTPTransport(steps: [
            .response(response(securityAutoBlock(
                enabled: false,
                attempts: 10,
                within: 5,
                expiration: 0
            ))),
            .response(response(securityFirewallConf(enabled: false))),
            .response(response(#"{"success":true}"#)),
            .urlError(.timedOut),
            .response(response(securityAutoBlock(
                enabled: true,
                attempts: 5,
                within: 10,
                expiration: 7
            ))),
            .response(response(securityFirewallConf(enabled: false)))
        ])
        let repository = try makeRepository(
            apiNames: [
                DsmAPIName.coreSecurityAutoBlock,
                DsmAPIName.coreSecurityFirewallConf
            ],
            transport: transport
        )
        let settings = NasSecuritySettings(
            isAutoBlockEnabled: true,
            failedAttempts: 5,
            withinMinutes: 10,
            expirationDays: 7,
            isPortScanProtectionEnabled: true
        )

        let result = try await repository.saveSecuritySettingsResult(settings)

        XCTAssertEqual(result.status, .partialSuccess)
        XCTAssertTrue(result.requiresRefresh)
        XCTAssertEqual(result.counts, try MutationResultCounts(
            succeeded: 1,
            failed: 1,
            unknown: 0
        ))
        XCTAssertEqual(result.localizationKey, "security.settings.partial")
        let requests = await transport.recordedRequests()
        XCTAssertEqual(requests.count, 6)
    }

    func test安全设置提交断网且回读失败时不自动重放() async throws {
        let transport = MockHTTPTransport(steps: [
            .response(response(securityAutoBlock(
                enabled: false,
                attempts: 10,
                within: 5,
                expiration: 0
            ))),
            .urlError(.networkConnectionLost),
            .urlError(.notConnectedToInternet)
        ])
        let repository = try makeRepository(
            apiNames: [DsmAPIName.coreSecurityAutoBlock],
            transport: transport
        )
        let settings = NasSecuritySettings(
            isAutoBlockEnabled: true,
            failedAttempts: 5,
            withinMinutes: 10,
            expirationDays: 7
        )

        let result = try await repository.saveSecuritySettingsResult(settings)

        XCTAssertEqual(result.status, .submittedButUnverified)
        XCTAssertTrue(result.submitted)
        XCTAssertTrue(result.requiresRefresh)
        XCTAssertEqual(result.counts.unknown, 1)
        let requests = await transport.recordedRequests()
        XCTAssertEqual(requests.count, 3)
    }

    func test安全设置拒绝重复提交并区分提交后取消() async throws {
        let transport = MockHTTPTransport(steps: [
            .response(response(securityAutoBlock(
                enabled: false,
                attempts: 10,
                within: 5,
                expiration: 0
            ))),
            .waitUntilCancelled
        ])
        let repository = try makeRepository(
            apiNames: [DsmAPIName.coreSecurityAutoBlock],
            transport: transport
        )
        let settings = NasSecuritySettings(
            isAutoBlockEnabled: true,
            failedAttempts: 5,
            withinMinutes: 10,
            expirationDays: 7
        )
        let firstTask = Task {
            try await repository.saveSecuritySettingsResult(settings)
        }
        while await transport.recordedRequests().count < 2 {
            await Task.yield()
        }

        let duplicate = try await repository.saveSecuritySettingsResult(settings)
        firstTask.cancel()
        let cancelled = try await firstTask.value

        XCTAssertEqual(duplicate.status, .confirmedFailure)
        XCTAssertFalse(duplicate.submitted)
        XCTAssertEqual(duplicate.errorCategory, .conflict)
        XCTAssertEqual(cancelled.status, .cancellationRequestedAfterSubmission)
        XCTAssertTrue(cancelled.requiresRefresh)
    }

    func test开启防火墙轮询配置档任务并回读确认() async throws {
        let autoBlock = securityAutoBlock(
            enabled: true,
            attempts: 5,
            within: 10,
            expiration: 0
        )
        let transport = MockHTTPTransport(responses: [
            response(autoBlock),
            response(securityFirewall(enabled: false)),
            response(#"{"success":true,"data":{"task_id":"synthetic-task"}}"#),
            response(#"{"success":true,"data":{"success":true}}"#),
            response(#"{"success":true}"#),
            response(autoBlock),
            response(securityFirewall(enabled: true))
        ])
        let repository = try makeRepository(
            apiNames: [
                DsmAPIName.coreSecurityAutoBlock,
                DsmAPIName.coreSecurityFirewall,
                DsmAPIName.coreSecurityFirewallProfileApply
            ],
            transport: transport
        )

        let result = try await repository.saveSecuritySettingsResult(
            NasSecuritySettings(
                isAutoBlockEnabled: true,
                failedAttempts: 5,
                withinMinutes: 10,
                expirationDays: nil,
                isFirewallEnabled: true,
                firewallProfileName: "synthetic-profile"
            )
        )

        XCTAssertEqual(result.status, .confirmedSuccess)
        let requests = await transport.recordedRequests()
        XCTAssertEqual(requestValue("method", in: requests[2]), "start")
        XCTAssertEqual(requestValue("name", in: requests[2]), "synthetic-profile")
        XCTAssertEqual(requestValue("method", in: requests[3]), "status")
        XCTAssertEqual(requestValue("task_id", in: requests[3]), "synthetic-task")
        XCTAssertEqual(requestValue("method", in: requests[4]), "stop")
    }

    private func makeRepository(
        apiNames: [String],
        transport: MockHTTPTransport,
        host: String = "nas.example.invalid"
    ) throws -> DsmNasAdministrationRepository {
        let capabilities = Dictionary(uniqueKeysWithValues: apiNames.map { name in
            (
                name,
                ApiCapability(
                    name: name,
                    path: "entry.cgi",
                    minVersion: 1,
                    maxVersion: name == DsmAPIName.coreTaskScheduler ? 4 : 3,
                    requestFormat: .form,
                    selectedVersion: name == DsmAPIName.coreTaskScheduler
                        ? 4
                        : (name == DsmAPIName.coreRegionNTP ? 3 : 1)
                )
            )
        })
        return try DsmNasAdministrationRepository(
            profile: NasProfile(
                displayName: "测试设备",
                host: host,
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

    private var packageListResponse: String {
        #"{"success":true,"data":{"packages":[{"id":"Example","name":"示例套件","version":"1.0","additional":{"status":"stopped","startable":true,"dsm_apps":"App.One App.Two","install_type":"user","ctl_uninstall":true,"available_operation":["uninstall"]}}]}}"#
    }

    private var ethernetListResponse: String {
        #"{"success":true,"data":{"interfaces":[{"ifname":"eth0","title":"局域网 1","status":"connected"}]}}"#
    }

    private var ethernetCurrentResponse: String {
        #"{"success":true,"data":{"ifname":"eth0","title":"局域网 1","status":"connected","use_dhcp":true,"ip":"192.0.2.10","mask":"255.255.255.0","gateway":"192.0.2.1","dns":"192.0.2.1","is_default_gateway":true,"mtu":1500,"enable_vlan":false,"vlan_id":0}}"#
    }

    private var ethernetUpdatedResponse: String {
        #"{"success":true,"data":{"ifname":"eth0","title":"局域网 1","status":"connected","use_dhcp":false,"ip":"192.0.2.20","mask":"255.255.255.0","gateway":"192.0.2.1","dns":"192.0.2.1","is_default_gateway":true,"mtu":1500,"enable_vlan":true,"vlan_id":20}}"#
    }

    private var ethernetUpdate: NasEthernetInterface {
        NasEthernetInterface(
            id: "eth0",
            displayName: "局域网 1",
            status: "connected",
            usesDHCP: false,
            address: "192.0.2.20",
            subnetMask: "255.255.255.0",
            gateway: "192.0.2.1",
            dnsServers: "192.0.2.1",
            isDefaultGateway: true,
            mtu: 1_500,
            isVLANEnabled: true,
            vlanID: 20
        )
    }

    private var securityAPINameSet: [String] {
        [
            DsmAPIName.coreSecurityAutoBlock,
            DsmAPIName.coreNetworkEthernet,
            DsmAPIName.coreSecurityDoS,
            DsmAPIName.coreSecurityFirewall,
            DsmAPIName.coreSecurityFirewallConf
        ]
    }

    private var securityEthernet: String {
        #"{"success":true,"data":{"interfaces":[{"id":"eth-synthetic","display":"Synthetic LAN"}]}}"#
    }

    private func securityAutoBlock(
        enabled: Bool,
        attempts: Int,
        within: Int,
        expiration: Int
    ) -> String {
        #"{"success":true,"data":{"enable":\#(enabled),"attempts":\#(attempts),"within_mins":\#(within),"expire_day":\#(expiration)}}"#
    }

    private func securityFirewall(enabled: Bool) -> String {
        #"{"success":true,"data":{"enable_firewall":\#(enabled),"profile_name":"synthetic-profile"}}"#
    }

    private func securityFirewallConf(enabled: Bool) -> String {
        #"{"success":true,"data":{"enable_port_check":\#(enabled)}}"#
    }

    private func securityDoS(enabled: Bool) -> String {
        #"{"success":true,"data":{"configs":[{"adapter":"eth-synthetic","dos_protect_enable":\#(enabled)}]}}"#
    }

    private var securityUpdate: NasSecuritySettings {
        NasSecuritySettings(
            isAutoBlockEnabled: true,
            failedAttempts: 5,
            withinMinutes: 10,
            expirationDays: 7,
            dosProtection: [
                NasDoSProtectionSetting(
                    id: "eth-synthetic",
                    displayName: "Synthetic LAN",
                    isEnabled: true
                )
            ],
            isFirewallEnabled: false,
            firewallProfileName: "synthetic-profile",
            isPortScanProtectionEnabled: true
        )
    }

    private var syntheticStorageDisk: String {
        #"{"success":true,"data":{"disks":[{"id":"synthetic-disk","device":"synthetic-device","longName":"Synthetic Disk","smart_status":"normal","smart_test_support":true}],"storagePools":[],"volumes":[]}}"#
    }

    private func syntheticDiskTestStatus(
        running: Bool,
        type: String? = nil
    ) -> String {
        var item = #"{"device":"synthetic-device","testing":\#(running),"ihm_testing":false,"perf_testing":false"#
        if let type {
            item += #","test_type":"\#(type)""#
        }
        item += "}"
        return #"{"success":true,"data":{"testInfo":[\#(item)]}}"#
    }

    private func requestValue(_ name: String, in request: URLRequest) -> String? {
        if let value = URLComponents(
            url: request.url ?? URL(fileURLWithPath: "/"),
            resolvingAgainstBaseURL: false
        )?.queryItems?.first(where: { $0.name == name })?.value {
            return value
        }
        guard let body = request.httpBody,
              let fields = String(data: body, encoding: .utf8) else {
            return nil
        }
        return URLComponents(string: "https://example.invalid/?\(fields)")?
            .queryItems?
            .first(where: { $0.name == name })?
            .value
    }
}
