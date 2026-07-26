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

        try await repository.saveFileServiceSettings(
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

        try await repository.saveTerminalSettings(
            NasTerminalSettings(isSSHEnabled: true, isTelnetEnabled: false, sshPort: 2222)
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

        do {
            try await repository.saveTerminalSettings(
                NasTerminalSettings(isSSHEnabled: true, isTelnetEnabled: false, sshPort: 22)
            )
            XCTFail("回读状态不一致时不应报告成功")
        } catch let error as AppError {
            XCTAssertEqual(error.category, .invalidResponse)
            XCTAssertTrue(error.isRetryable)
        }
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

        try await repository.saveProxySettings(
            NasProxySettings(
                isEnabled: true,
                host: " proxy.example.invalid ",
                port: 3128
            )
        )

        let requests = await transport.recordedRequests()
        XCTAssertEqual(requestValue("method", in: requests[1]), "set")
        XCTAssertEqual(requestValue("http_host", in: requests[1]), "proxy.example.invalid")
        XCTAssertEqual(requestValue("http_port", in: requests[1]), "3128")
        XCTAssertFalse(requests[1].url?.absoluteString.contains("proxy.example.invalid") == true)
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

        try await repository.saveHardwareSettings(
            NasHardwareSettings(
                restartsAfterPowerFailure: true,
                ledBrightness: 5,
                ledBrightnessRange: 0...7
            )
        )

        let requests = await transport.recordedRequests()
        XCTAssertEqual(requests.count, 9)
        XCTAssertEqual(requestValue("method", in: requests[3]), "set")
        XCTAssertEqual(requestValue("rc_power_config", in: requests[3]), "true")
        XCTAssertEqual(requestValue("method", in: requests[4]), "set_current_brightness")
        XCTAssertEqual(requestValue("led_brightness", in: requests[4]), "5")
        XCTAssertEqual(requestValue("method", in: requests[5]), "update")
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

        try await repository.saveRemoteAccessSettings(
            NasRemoteAccessSettings(
                isRelayEnabled: false,
                isRouterConfigurationEnabled: true,
                canDisableRelay: true
            )
        )

        let requests = await transport.recordedRequests()
        XCTAssertEqual(requests.count, 6)
        XCTAssertEqual(requestValue("method", in: requests[2]), "set_misc_config")
        XCTAssertEqual(requestValue("version", in: requests[2]), "3")
        XCTAssertEqual(requestValue("relay_enabled", in: requests[2]), "false")
        XCTAssertEqual(requestValue("method", in: requests[3]), "set")
        XCTAssertEqual(requestValue("enabled", in: requests[3]), "true")
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
