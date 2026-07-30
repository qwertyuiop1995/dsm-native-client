import DsmCore
import DsmLocalization
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

    func test套件卸载只有回读确认后才从列表移除() async throws {
        let repository = NasAdministrationRepositoryStub(packages: [
            package(status: "stopped", canStart: true, canStop: false, canUninstall: true)
        ])
        let model = NasSettingsModel(repository: repository)
        model.setModuleEnabled(true)
        await model.activate(.packages)

        try await model.controlPackage(id: "Example", action: .uninstall)

        XCTAssertTrue(model.packages.isEmpty)
        XCTAssertFalse(model.packageOperationIDs.contains("Example"))
        let requestCount = await repository.packageControlRequestCount()
        XCTAssertEqual(requestCount, 1)
    }

    func test套件卸载未确认时提示先刷新且不建议立即重试() async {
        let repository = NasAdministrationRepositoryStub(
            packages: [
                package(
                    status: "stopped",
                    canStart: true,
                    canStop: false,
                    canUninstall: true
                )
            ],
            packageUninstallStatus: .submittedButUnverified
        )
        let model = NasSettingsModel(repository: repository)
        model.setModuleEnabled(true)
        await model.activate(.packages)

        do {
            try await model.controlPackage(id: "Example", action: .uninstall)
            XCTFail("未确认的卸载不应显示为完成")
        } catch let error as AppError {
            XCTAssertEqual(error.category, .unknown)
            XCTAssertEqual(
                error.safeUserMessage,
                L10n.string("package.uninstall.unverified")
            )
            XCTAssertFalse(error.isRetryable)
        } catch {
            XCTFail("返回了非统一错误：\(error)")
        }
        XCTAssertEqual(model.packages.map(\.id), ["Example"])
    }

    func test套件卸载反馈覆盖权限和不支持状态() {
        let permission = NasSettingsModel.packageUninstallFeedback(
            for: .permissionDenied
        )
        let unsupported = NasSettingsModel.packageUninstallFeedback(
            for: .unsupported
        )

        XCTAssertEqual(
            permission.resourceKey,
            "package.uninstall.permission-denied"
        )
        XCTAssertEqual(permission.category, .permissionDenied)
        XCTAssertEqual(
            unsupported.resourceKey,
            "package.uninstall.unsupported"
        )
        XCTAssertEqual(unsupported.category, .apiUnavailable)
    }

    func test账号删除只有回读确认后才从目录移除() async throws {
        let repository = NasAdministrationRepositoryStub()
        let model = NasSettingsModel(repository: repository)
        model.setModuleEnabled(true)
        await model.activate(.accounts)
        let account = try XCTUnwrap(model.accounts?.users.first)

        try await model.deleteAccount(account)

        XCTAssertTrue(model.accounts?.users.isEmpty == true)
        XCTAssertFalse(model.accountOperationIDs.contains(account.id))
    }

    func test账号删除未确认时提示先刷新且不建议立即重试() async throws {
        let repository = NasAdministrationRepositoryStub(
            accountDeleteStatus: .submittedButUnverified
        )
        let model = NasSettingsModel(repository: repository)
        model.setModuleEnabled(true)
        await model.activate(.accounts)
        let account = try XCTUnwrap(model.accounts?.users.first)

        do {
            try await model.deleteAccount(account)
            XCTFail("未确认的删除不应显示为完成")
        } catch let error as AppError {
            XCTAssertEqual(error.category, .unknown)
            XCTAssertEqual(
                error.safeUserMessage,
                L10n.string("account.delete.unverified")
            )
            XCTAssertFalse(error.isRetryable)
        } catch {
            XCTFail("返回了非统一错误：\(error)")
        }
        XCTAssertEqual(model.accounts?.users.map(\.name), ["user"])
    }

    func test账号与群组删除反馈覆盖权限和不支持状态() {
        let accountPermission = NasSettingsModel.directoryDeletionFeedback(
            for: .permissionDenied,
            kind: .user
        )
        let groupUnsupported = NasSettingsModel.directoryDeletionFeedback(
            for: .unsupported,
            kind: .group
        )

        XCTAssertEqual(
            accountPermission.resourceKey,
            "account.delete.permission-denied"
        )
        XCTAssertEqual(accountPermission.category, .permissionDenied)
        XCTAssertEqual(
            groupUnsupported.resourceKey,
            "group.delete.unsupported"
        )
        XCTAssertEqual(groupUnsupported.category, .apiUnavailable)
    }

    func test网卡设置只有确认成功后才更新当前配置() async throws {
        let repository = NasAdministrationRepositoryStub()
        let model = NasSettingsModel(repository: repository)
        model.setModuleEnabled(true)
        await model.activate(.interfaces)
        let updated = ethernetUpdate

        try await model.saveEthernetInterface(updated)

        XCTAssertEqual(model.ethernetInterfaces.first?.address, updated.address)
        XCTAssertEqual(model.ethernetInterfaces.first?.vlanID, updated.vlanID)
        XCTAssertFalse(model.networkOperationIDs.contains("network:eth0"))
    }

    func test网卡设置未确认时提示重新连接且不建议立即重试() async {
        let repository = NasAdministrationRepositoryStub(
            ethernetUpdateStatus: .submittedButUnverified
        )
        let model = NasSettingsModel(repository: repository)
        model.setModuleEnabled(true)
        await model.activate(.interfaces)

        do {
            try await model.saveEthernetInterface(ethernetUpdate)
            XCTFail("未确认的网卡设置不应显示为完成")
        } catch let error as AppError {
            XCTAssertEqual(error.category, .unknown)
            XCTAssertEqual(
                error.safeUserMessage,
                L10n.string("network.ethernet.unverified")
            )
            XCTAssertFalse(error.isRetryable)
        } catch {
            XCTFail("返回了非统一错误：\(error)")
        }
        XCTAssertEqual(model.ethernetInterfaces.first?.usesDHCP, true)
    }

    func test网卡设置反馈覆盖权限和不支持状态() {
        let permission = NasSettingsModel.ethernetUpdateFeedback(
            for: .permissionDenied
        )
        let unsupported = NasSettingsModel.ethernetUpdateFeedback(
            for: .unsupported
        )

        XCTAssertEqual(
            permission.resourceKey,
            "network.ethernet.permission-denied"
        )
        XCTAssertEqual(permission.category, .permissionDenied)
        XCTAssertEqual(
            unsupported.resourceKey,
            "network.ethernet.unsupported"
        )
        XCTAssertEqual(unsupported.category, .apiUnavailable)
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

    func test启动硬盘检测未确认时保留当前状态并提示刷新() async {
        let repository = NasAdministrationRepositoryStub(
            diskTestStartStatus: .submittedButUnverified
        )
        let model = NasSettingsModel(repository: repository)
        model.setModuleEnabled(true)
        await model.activate(.storage)

        do {
            try await model.startDiskTest(diskID: "disk1", type: .quick)
            XCTFail("未确认结果不应显示为检测已开始")
        } catch let error as AppError {
            XCTAssertEqual(error.category, .unknown)
            XCTAssertFalse(error.isRetryable)
            XCTAssertEqual(
                error.safeUserMessage,
                L10n.string("storage.disk-test.start.unverified")
            )
        } catch {
            XCTFail("返回了非统一错误：\(error)")
        }
        XCTAssertEqual(model.diskTestStatuses["disk1"]?.isRunning, false)
    }

    func test停止硬盘检测未确认时保留运行状态并提示刷新() async throws {
        let repository = NasAdministrationRepositoryStub(
            diskTestStopStatus: .submittedButUnverified
        )
        let model = NasSettingsModel(repository: repository)
        model.setModuleEnabled(true)
        await model.activate(.storage)
        try await model.startDiskTest(diskID: "disk1", type: .extended)

        do {
            try await model.stopDiskTest(diskID: "disk1")
            XCTFail("未确认结果不应显示为检测已停止")
        } catch let error as AppError {
            XCTAssertEqual(error.category, .unknown)
            XCTAssertFalse(error.isRetryable)
            XCTAssertEqual(
                error.safeUserMessage,
                L10n.string("storage.disk-test.stop.unverified")
            )
        }
        XCTAssertEqual(model.diskTestStatuses["disk1"]?.isRunning, true)
    }

    func test硬盘检测反馈覆盖权限和不支持状态() {
        XCTAssertEqual(
            NasSettingsModel.diskTestFeedback(
                for: .permissionDenied,
                isStarting: true
            ),
            NasSettingsModel.DiskTestFeedback(
                resourceKey: "storage.disk-test.start.permission-denied",
                category: .permissionDenied
            )
        )
        XCTAssertEqual(
            NasSettingsModel.diskTestFeedback(
                for: .unsupported,
                isStarting: false
            ),
            NasSettingsModel.DiskTestFeedback(
                resourceKey: "storage.disk-test.stop.unsupported",
                category: .apiUnavailable
            )
        )
    }

    func test文件服务设置确认成功后刷新模型状态() async throws {
        let repository = NasAdministrationRepositoryStub()
        let model = NasSettingsModel(repository: repository)
        model.setModuleEnabled(true)
        await model.activate(.fileServices)
        let expected = fileServiceUpdate

        try await model.saveFileServices(expected)

        XCTAssertEqual(model.fileServices, expected)
        XCTAssertFalse(model.isSavingServiceSettings)
    }

    func test文件服务部分成功时刷新并提示逐项核对() async {
        let repository = NasAdministrationRepositoryStub(
            fileServiceUpdateStatus: .partialSuccess
        )
        let model = NasSettingsModel(repository: repository)
        model.setModuleEnabled(true)
        await model.activate(.fileServices)

        do {
            try await model.saveFileServices(fileServiceUpdate)
            XCTFail("部分成功不应显示为全部保存")
        } catch let error as AppError {
            XCTAssertEqual(error.category, .partialFailure)
            XCTAssertFalse(error.isRetryable)
            XCTAssertEqual(
                error.safeUserMessage,
                L10n.string("file-services.settings.partial")
            )
        } catch {
            XCTFail("返回了非统一错误：\(error)")
        }
        XCTAssertEqual(model.fileServices?.isSMBEnabled, true)
        XCTAssertEqual(model.fileServices?.isFTPEnabled, false)
    }

    func test文件服务未确认时提示先读取且不建议立即重试() async {
        let repository = NasAdministrationRepositoryStub(
            fileServiceUpdateStatus: .submittedButUnverified
        )
        let model = NasSettingsModel(repository: repository)
        model.setModuleEnabled(true)
        await model.activate(.fileServices)

        do {
            try await model.saveFileServices(fileServiceUpdate)
            XCTFail("未确认结果不应显示为保存成功")
        } catch let error as AppError {
            XCTAssertEqual(error.category, .unknown)
            XCTAssertFalse(error.isRetryable)
            XCTAssertEqual(
                error.safeUserMessage,
                L10n.string("file-services.settings.unverified")
            )
        } catch {
            XCTFail("返回了非统一错误：\(error)")
        }
        XCTAssertEqual(model.fileServices?.isSMBEnabled, false)
        XCTAssertEqual(model.fileServices?.isFTPEnabled, false)
    }

    func test文件服务反馈覆盖权限和不支持状态() {
        XCTAssertEqual(
            NasSettingsModel.fileServiceSettingsFeedback(for: .permissionDenied),
            NasSettingsModel.FileServiceSettingsFeedback(
                resourceKey: "file-services.settings.permission-denied",
                category: .permissionDenied
            )
        )
        XCTAssertEqual(
            NasSettingsModel.fileServiceSettingsFeedback(for: .unsupported),
            NasSettingsModel.FileServiceSettingsFeedback(
                resourceKey: "file-services.settings.unsupported",
                category: .apiUnavailable
            )
        )
    }

    func test远程终端设置确认成功后刷新模型状态() async throws {
        let repository = NasAdministrationRepositoryStub()
        let model = NasSettingsModel(repository: repository)
        model.setModuleEnabled(true)
        await model.activate(.terminal)
        let expected = terminalUpdate

        try await model.saveTerminal(expected)

        XCTAssertEqual(model.terminal, expected)
        XCTAssertFalse(model.isSavingServiceSettings)
    }

    func test远程终端部分成功时刷新并提示逐项核对() async {
        let repository = NasAdministrationRepositoryStub(
            terminalUpdateStatus: .partialSuccess
        )
        let model = NasSettingsModel(repository: repository)
        model.setModuleEnabled(true)
        await model.activate(.terminal)

        do {
            try await model.saveTerminal(terminalUpdate)
            XCTFail("部分成功不应显示为全部保存")
        } catch let error as AppError {
            XCTAssertEqual(error.category, .partialFailure)
            XCTAssertFalse(error.isRetryable)
            XCTAssertEqual(
                error.safeUserMessage,
                L10n.string("terminal.settings.partial")
            )
        } catch {
            XCTFail("返回了非统一错误：\(error)")
        }
        XCTAssertEqual(model.terminal?.isSSHEnabled, true)
        XCTAssertEqual(model.terminal?.isTelnetEnabled, false)
        XCTAssertEqual(model.terminal?.sshPort, 22)
    }

    func test远程终端未确认时提示先读取且不建议立即重试() async {
        let repository = NasAdministrationRepositoryStub(
            terminalUpdateStatus: .submittedButUnverified
        )
        let model = NasSettingsModel(repository: repository)
        model.setModuleEnabled(true)
        await model.activate(.terminal)

        do {
            try await model.saveTerminal(terminalUpdate)
            XCTFail("未确认结果不应显示为保存成功")
        } catch let error as AppError {
            XCTAssertEqual(error.category, .unknown)
            XCTAssertFalse(error.isRetryable)
            XCTAssertEqual(
                error.safeUserMessage,
                L10n.string("terminal.settings.unverified")
            )
        } catch {
            XCTFail("返回了非统一错误：\(error)")
        }
        XCTAssertEqual(model.terminal?.isSSHEnabled, false)
        XCTAssertEqual(model.terminal?.isTelnetEnabled, false)
        XCTAssertEqual(model.terminal?.sshPort, 22)
    }

    func test远程终端反馈覆盖权限和不支持状态() {
        XCTAssertEqual(
            NasSettingsModel.terminalSettingsFeedback(for: .permissionDenied),
            NasSettingsModel.TerminalSettingsFeedback(
                resourceKey: "terminal.settings.permission-denied",
                category: .permissionDenied
            )
        )
        XCTAssertEqual(
            NasSettingsModel.terminalSettingsFeedback(for: .unsupported),
            NasSettingsModel.TerminalSettingsFeedback(
                resourceKey: "terminal.settings.unsupported",
                category: .apiUnavailable
            )
        )
    }

    func test互联网代理设置确认成功后刷新模型状态() async throws {
        let repository = NasAdministrationRepositoryStub()
        let model = NasSettingsModel(repository: repository)
        model.setModuleEnabled(true)
        await model.activate(.network)
        let expected = NasProxySettings(
            isEnabled: true,
            host: "proxy.example.invalid",
            port: 3_128
        )

        try await model.saveProxy(expected)

        XCTAssertEqual(model.proxy, expected)
        XCTAssertFalse(model.isSavingServiceSettings)
    }

    func test互联网代理部分成功时刷新并提示逐项核对() async {
        let repository = NasAdministrationRepositoryStub(
            proxyUpdateStatus: .partialSuccess
        )
        let model = NasSettingsModel(repository: repository)
        model.setModuleEnabled(true)
        await model.activate(.network)

        do {
            try await model.saveProxy(
                NasProxySettings(
                    isEnabled: true,
                    host: "proxy.example.invalid",
                    port: 3_128
                )
            )
            XCTFail("部分成功不应显示为全部保存")
        } catch let error as AppError {
            XCTAssertEqual(error.category, .partialFailure)
            XCTAssertFalse(error.isRetryable)
            XCTAssertEqual(
                error.safeUserMessage,
                L10n.string("proxy.settings.partial")
            )
        } catch {
            XCTFail("返回了非统一错误：\(error)")
        }
        XCTAssertEqual(model.proxy?.isEnabled, true)
        XCTAssertEqual(model.proxy?.host, "")
    }

    func test互联网代理未确认时提示先读取且不建议立即重试() async {
        let repository = NasAdministrationRepositoryStub(
            proxyUpdateStatus: .submittedButUnverified
        )
        let model = NasSettingsModel(repository: repository)
        model.setModuleEnabled(true)
        await model.activate(.network)

        do {
            try await model.saveProxy(
                NasProxySettings(
                    isEnabled: true,
                    host: "proxy.example.invalid",
                    port: 3_128
                )
            )
            XCTFail("未确认结果不应显示为保存成功")
        } catch let error as AppError {
            XCTAssertEqual(error.category, .unknown)
            XCTAssertFalse(error.isRetryable)
            XCTAssertEqual(
                error.safeUserMessage,
                L10n.string("proxy.settings.unverified")
            )
        } catch {
            XCTFail("返回了非统一错误：\(error)")
        }
        XCTAssertEqual(model.proxy?.isEnabled, false)
    }

    func test互联网代理反馈覆盖权限和不支持状态() {
        XCTAssertEqual(
            NasSettingsModel.proxySettingsFeedback(for: .permissionDenied),
            NasSettingsModel.ProxySettingsFeedback(
                resourceKey: "proxy.settings.permission-denied",
                category: .permissionDenied
            )
        )
        XCTAssertEqual(
            NasSettingsModel.proxySettingsFeedback(for: .unsupported),
            NasSettingsModel.ProxySettingsFeedback(
                resourceKey: "proxy.settings.unsupported",
                category: .apiUnavailable
            )
        )
    }

    func test硬件设置确认成功后刷新模型状态() async throws {
        let repository = NasAdministrationRepositoryStub()
        let model = NasSettingsModel(repository: repository)
        model.setModuleEnabled(true)
        await model.activate(.hardware)
        let expected = hardwareUpdate

        try await model.saveHardware(expected)

        XCTAssertEqual(model.hardware, expected)
        XCTAssertFalse(model.isSavingServiceSettings)
    }

    func test硬件设置部分成功时刷新并提示逐项核对() async {
        let repository = NasAdministrationRepositoryStub(
            hardwareUpdateStatus: .partialSuccess
        )
        let model = NasSettingsModel(repository: repository)
        model.setModuleEnabled(true)
        await model.activate(.hardware)

        do {
            try await model.saveHardware(hardwareUpdate)
            XCTFail("部分成功不应显示为全部保存")
        } catch let error as AppError {
            XCTAssertEqual(error.category, .partialFailure)
            XCTAssertFalse(error.isRetryable)
            XCTAssertEqual(
                error.safeUserMessage,
                L10n.string("hardware.settings.partial")
            )
        } catch {
            XCTFail("返回了非统一错误：\(error)")
        }
        XCTAssertEqual(model.hardware?.restartsAfterPowerFailure, true)
        XCTAssertEqual(model.hardware?.fanMode, "quietfan")
    }

    func test硬件设置未确认时提示先读取且不建议立即重试() async {
        let repository = NasAdministrationRepositoryStub(
            hardwareUpdateStatus: .submittedButUnverified
        )
        let model = NasSettingsModel(repository: repository)
        model.setModuleEnabled(true)
        await model.activate(.hardware)

        do {
            try await model.saveHardware(hardwareUpdate)
            XCTFail("未确认结果不应显示为保存成功")
        } catch let error as AppError {
            XCTAssertEqual(error.category, .unknown)
            XCTAssertFalse(error.isRetryable)
            XCTAssertEqual(
                error.safeUserMessage,
                L10n.string("hardware.settings.unverified")
            )
        } catch {
            XCTFail("返回了非统一错误：\(error)")
        }
        XCTAssertEqual(model.hardware?.restartsAfterPowerFailure, false)
        XCTAssertEqual(model.hardware?.fanMode, "quietfan")
    }

    func test硬件设置反馈覆盖权限和不支持状态() {
        XCTAssertEqual(
            NasSettingsModel.hardwareSettingsFeedback(for: .permissionDenied),
            NasSettingsModel.HardwareSettingsFeedback(
                resourceKey: "hardware.settings.permission-denied",
                category: .permissionDenied
            )
        )
        XCTAssertEqual(
            NasSettingsModel.hardwareSettingsFeedback(for: .unsupported),
            NasSettingsModel.HardwareSettingsFeedback(
                resourceKey: "hardware.settings.unsupported",
                category: .apiUnavailable
            )
        )
    }

    func test远程访问设置确认成功后刷新模型状态() async throws {
        let repository = NasAdministrationRepositoryStub()
        let model = NasSettingsModel(repository: repository)
        model.setModuleEnabled(true)
        await model.activate(.remoteAccess)
        let expected = remoteAccessUpdate

        try await model.saveRemoteAccess(expected)

        XCTAssertEqual(model.remoteAccess, expected)
        XCTAssertFalse(model.isSavingServiceSettings)
    }

    func test远程访问部分成功时刷新并提示重新连接核对() async {
        let repository = NasAdministrationRepositoryStub(
            remoteAccessUpdateStatus: .partialSuccess
        )
        let model = NasSettingsModel(repository: repository)
        model.setModuleEnabled(true)
        await model.activate(.remoteAccess)

        do {
            try await model.saveRemoteAccess(remoteAccessUpdate)
            XCTFail("部分成功不应显示为全部保存")
        } catch let error as AppError {
            XCTAssertEqual(error.category, .partialFailure)
            XCTAssertFalse(error.isRetryable)
            XCTAssertEqual(
                error.safeUserMessage,
                L10n.string("remote-access.settings.partial")
            )
        } catch {
            XCTFail("返回了非统一错误：\(error)")
        }
        XCTAssertEqual(model.remoteAccess?.isRelayEnabled, false)
        XCTAssertEqual(model.remoteAccess?.isRouterConfigurationEnabled, false)
    }

    func test远程访问未确认时提示重连且禁止立即重试() async {
        let repository = NasAdministrationRepositoryStub(
            remoteAccessUpdateStatus: .submittedButUnverified
        )
        let model = NasSettingsModel(repository: repository)
        model.setModuleEnabled(true)
        await model.activate(.remoteAccess)

        do {
            try await model.saveRemoteAccess(remoteAccessUpdate)
            XCTFail("未确认结果不应显示为保存成功")
        } catch let error as AppError {
            XCTAssertEqual(error.category, .unknown)
            XCTAssertFalse(error.isRetryable)
            XCTAssertEqual(
                error.safeUserMessage,
                L10n.string("remote-access.settings.unverified")
            )
        } catch {
            XCTFail("返回了非统一错误：\(error)")
        }
        XCTAssertEqual(model.remoteAccess?.isRelayEnabled, true)
        XCTAssertEqual(model.remoteAccess?.isRouterConfigurationEnabled, false)
    }

    func test远程访问反馈覆盖权限和不支持状态() {
        XCTAssertEqual(
            NasSettingsModel.remoteAccessSettingsFeedback(for: .permissionDenied),
            NasSettingsModel.RemoteAccessSettingsFeedback(
                resourceKey: "remote-access.settings.permission-denied",
                category: .permissionDenied
            )
        )
        XCTAssertEqual(
            NasSettingsModel.remoteAccessSettingsFeedback(for: .unsupported),
            NasSettingsModel.RemoteAccessSettingsFeedback(
                resourceKey: "remote-access.settings.unsupported",
                category: .apiUnavailable
            )
        )
    }

    func test安全设置确认成功后刷新模型状态() async throws {
        let repository = NasAdministrationRepositoryStub()
        let model = NasSettingsModel(repository: repository)
        model.setModuleEnabled(true)
        await model.activate(.security)
        let expected = securityUpdate

        try await model.saveSecurity(expected)

        XCTAssertEqual(model.security, expected)
        XCTAssertFalse(model.isSavingServiceSettings)
    }

    func test安全设置部分成功时刷新并提示逐项核对() async {
        let repository = NasAdministrationRepositoryStub(
            securityUpdateStatus: .partialSuccess
        )
        let model = NasSettingsModel(repository: repository)
        model.setModuleEnabled(true)
        await model.activate(.security)

        do {
            try await model.saveSecurity(securityUpdate)
            XCTFail("部分成功不应显示为全部保存")
        } catch let error as AppError {
            XCTAssertEqual(error.category, .partialFailure)
            XCTAssertFalse(error.isRetryable)
            XCTAssertEqual(
                error.safeUserMessage,
                L10n.string("security.settings.partial")
            )
        } catch {
            XCTFail("返回了非统一错误：\(error)")
        }
        XCTAssertEqual(model.security?.isAutoBlockEnabled, true)
        XCTAssertEqual(model.security?.isPortScanProtectionEnabled, false)
    }

    func test安全设置未确认时提示先回读且不建议立即重试() async {
        let repository = NasAdministrationRepositoryStub(
            securityUpdateStatus: .submittedButUnverified
        )
        let model = NasSettingsModel(repository: repository)
        model.setModuleEnabled(true)
        await model.activate(.security)

        do {
            try await model.saveSecurity(securityUpdate)
            XCTFail("未确认结果不应显示为保存成功")
        } catch let error as AppError {
            XCTAssertEqual(error.category, .unknown)
            XCTAssertFalse(error.isRetryable)
            XCTAssertEqual(
                error.safeUserMessage,
                L10n.string("security.settings.unverified")
            )
        } catch {
            XCTFail("返回了非统一错误：\(error)")
        }
    }

    func test安全设置权限与不支持反馈映射() {
        XCTAssertEqual(
            NasSettingsModel.securitySettingsFeedback(for: .permissionDenied),
            NasSettingsModel.SecuritySettingsFeedback(
                resourceKey: "security.settings.permission-denied",
                category: .permissionDenied
            )
        )
        XCTAssertEqual(
            NasSettingsModel.securitySettingsFeedback(for: .unsupported),
            NasSettingsModel.SecuritySettingsFeedback(
                resourceKey: "security.settings.unsupported",
                category: .apiUnavailable
            )
        )
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

    private var securityUpdate: NasSecuritySettings {
        NasSecuritySettings(
            isAutoBlockEnabled: true,
            failedAttempts: 5,
            withinMinutes: 10,
            expirationDays: 7,
            isFirewallEnabled: false,
            firewallProfileName: "synthetic-profile",
            isPortScanProtectionEnabled: true
        )
    }

    private var fileServiceUpdate: NasFileServiceSettings {
        NasFileServiceSettings(
            isSMBEnabled: true,
            isNFSEnabled: true,
            isFTPEnabled: true,
            isFTPSEnabled: true,
            ftpPort: 2_121,
            isSFTPEnabled: true,
            sftpPort: 2_222,
            isSSDPEnabled: true,
            isBonjourEnabled: true,
            isSMBTimeMachineEnabled: true
        )
    }

    private var terminalUpdate: NasTerminalSettings {
        NasTerminalSettings(
            isSSHEnabled: true,
            isTelnetEnabled: true,
            sshPort: 2_222
        )
    }

    private var hardwareUpdate: NasHardwareSettings {
        NasHardwareSettings(
            restartsAfterPowerFailure: true,
            ledBrightness: 5,
            ledBrightnessRange: 0...7,
            fanMode: "coolfan"
        )
    }

    private var remoteAccessUpdate: NasRemoteAccessSettings {
        NasRemoteAccessSettings(
            isRelayEnabled: false,
            isRouterConfigurationEnabled: true,
            canDisableRelay: true
        )
    }
}

private actor NasAdministrationRepositoryStub: NasSettingsRepository {
    private var systemRequests = 0
    private var packageControlRequests = 0
    private var diskTestRequests = 0
    private var diskTestStatus = NasDiskTestStatus(diskID: "disk1", isRunning: false)
    private let diskTestStartStatus: MutationResultStatus
    private let diskTestStopStatus: MutationResultStatus
    private var packages: [NasPackage]
    private let packageUninstallStatus: MutationResultStatus
    private var accountDirectory = NasAccountDirectory(
        users: [
            NasAccount(
                id: "user:user",
                name: "user",
                kind: .user,
                numericID: 1,
                description: nil,
                canDelete: true
            )
        ],
        groups: []
    )
    private let accountDeleteStatus: MutationResultStatus
    private var ethernetInterfaces = [
        NasEthernetInterface(
            id: "eth0",
            displayName: "局域网 1",
            status: "connected",
            usesDHCP: true,
            address: "192.0.2.10",
            subnetMask: "255.255.255.0",
            gateway: "192.0.2.1",
            dnsServers: "192.0.2.1",
            isDefaultGateway: true,
            mtu: 1_500,
            isVLANEnabled: false,
            vlanID: nil
        )
    ]
    private let ethernetUpdateStatus: MutationResultStatus
    private var securitySettings = NasSecuritySettings(
        isAutoBlockEnabled: false,
        failedAttempts: 10,
        withinMinutes: 5,
        expirationDays: nil,
        isFirewallEnabled: true,
        firewallProfileName: "synthetic-profile",
        isPortScanProtectionEnabled: false
    )
    private var hardwareSettings = NasHardwareSettings(
        restartsAfterPowerFailure: false,
        ledBrightness: 3,
        ledBrightnessRange: 0...7,
        fanMode: "quietfan"
    )
    private var remoteAccessSettings = NasRemoteAccessSettings(
        isRelayEnabled: true,
        isRouterConfigurationEnabled: false,
        canDisableRelay: true
    )
    private let securityUpdateStatus: MutationResultStatus
    private var fileServiceSettings = NasFileServiceSettings(
        isSMBEnabled: false,
        isNFSEnabled: false,
        isFTPEnabled: false,
        isFTPSEnabled: false,
        ftpPort: 21,
        isSFTPEnabled: false,
        sftpPort: 22,
        isSSDPEnabled: false,
        isBonjourEnabled: false,
        isSMBTimeMachineEnabled: false
    )
    private let fileServiceUpdateStatus: MutationResultStatus
    private var terminalSettings = NasTerminalSettings(
        isSSHEnabled: false,
        isTelnetEnabled: false,
        sshPort: 22
    )
    private let terminalUpdateStatus: MutationResultStatus
    private var proxySettings = NasProxySettings(
        isEnabled: false,
        host: "",
        port: 3_128
    )
    private let proxyUpdateStatus: MutationResultStatus
    private let hardwareUpdateStatus: MutationResultStatus
    private let remoteAccessUpdateStatus: MutationResultStatus
    private let delayNanoseconds: UInt64

    init(
        delayNanoseconds: UInt64 = 0,
        packages: [NasPackage] = [],
        packageUninstallStatus: MutationResultStatus = .confirmedSuccess,
        accountDeleteStatus: MutationResultStatus = .confirmedSuccess,
        ethernetUpdateStatus: MutationResultStatus = .confirmedSuccess,
        securityUpdateStatus: MutationResultStatus = .confirmedSuccess,
        fileServiceUpdateStatus: MutationResultStatus = .confirmedSuccess,
        terminalUpdateStatus: MutationResultStatus = .confirmedSuccess,
        proxyUpdateStatus: MutationResultStatus = .confirmedSuccess,
        hardwareUpdateStatus: MutationResultStatus = .confirmedSuccess,
        remoteAccessUpdateStatus: MutationResultStatus = .confirmedSuccess,
        diskTestStartStatus: MutationResultStatus = .confirmedSuccess,
        diskTestStopStatus: MutationResultStatus = .confirmedSuccess
    ) {
        self.delayNanoseconds = delayNanoseconds
        self.packages = packages
        self.packageUninstallStatus = packageUninstallStatus
        self.accountDeleteStatus = accountDeleteStatus
        self.ethernetUpdateStatus = ethernetUpdateStatus
        self.securityUpdateStatus = securityUpdateStatus
        self.fileServiceUpdateStatus = fileServiceUpdateStatus
        self.terminalUpdateStatus = terminalUpdateStatus
        self.proxyUpdateStatus = proxyUpdateStatus
        self.hardwareUpdateStatus = hardwareUpdateStatus
        self.remoteAccessUpdateStatus = remoteAccessUpdateStatus
        self.diskTestStartStatus = diskTestStartStatus
        self.diskTestStopStatus = diskTestStopStatus
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

    func startDiskTestResult(
        diskID: String,
        type: NasDiskTestType
    ) async throws -> MutationResult {
        diskTestRequests += 1
        if diskTestStartStatus == .confirmedSuccess {
            diskTestStatus = NasDiskTestStatus(
                diskID: diskID,
                isRunning: true,
                runningType: type,
                progressDescription: "已开始"
            )
        }
        return try diskMutationResult(
            status: diskTestStartStatus,
            operation: "diskTestStart",
            prefix: "storage.disk-test.start"
        )
    }

    func stopDiskTestResult(diskID: String) async throws -> MutationResult {
        diskTestRequests += 1
        if diskTestStopStatus == .confirmedSuccess {
            diskTestStatus = NasDiskTestStatus(diskID: diskID, isRunning: false)
        }
        return try diskMutationResult(
            status: diskTestStopStatus,
            operation: "diskTestStop",
            prefix: "storage.disk-test.stop"
        )
    }

    private func diskMutationResult(
        status: MutationResultStatus,
        operation: String,
        prefix: String
    ) throws -> MutationResult {
        let isUnknown = status == .submittedButUnverified
            || status == .cancellationRequestedAfterSubmission
        let isPartial = status == .partialSuccess
        let submitted = status != .cancelledBeforeSubmission
            && status != .permissionDenied
            && status != .unsupported
        return try MutationResult(
            status: status,
            operation: operation,
            submitted: submitted,
            requiresRefresh: isUnknown || isPartial,
            counts: MutationResultCounts(
                succeeded: status == .confirmedSuccess || isPartial ? 1 : 0,
                failed: isPartial
                    || status == .permissionDenied
                    || status == .unsupported
                    || status == .confirmedFailure ? 1 : 0,
                unknown: isUnknown ? 1 : 0
            ),
            localizationKey: isUnknown ? "\(prefix).unverified" : nil,
            diagnosticTag: "\(prefix).test"
        )
    }

    func loadPackages() async throws -> [NasPackage] { packages }
    func loadScheduledTasks() async throws -> [NasScheduledTask] { [] }

    func loadAccountsAndGroups() async throws -> NasAccountDirectory {
        accountDirectory
    }

    func deleteAccountResult(name: String) async throws -> MutationResult {
        if accountDeleteStatus == .confirmedSuccess {
            accountDirectory = NasAccountDirectory(
                users: accountDirectory.users.filter { $0.name != name },
                groups: accountDirectory.groups
            )
        }
        return try deletionResult(
            status: accountDeleteStatus,
            operation: "accountDelete",
            prefix: "account.delete"
        )
    }

    func loadLogs(offset: Int, limit: Int) async throws -> NasLogPage {
        NasLogPage(entries: [], total: 0, infoCount: 0, warningCount: 0, errorCount: 0)
    }

    func loadConnections(offset: Int, limit: Int) async throws -> NasConnectionPage {
        NasConnectionPage(connections: [], total: 0)
    }

    func loadEthernetInterfaces() async throws -> [NasEthernetInterface] {
        ethernetInterfaces
    }

    func loadFileServiceSettings() async throws -> NasFileServiceSettings {
        fileServiceSettings
    }

    func saveFileServiceSettingsResult(
        _ settings: NasFileServiceSettings
    ) async throws -> MutationResult {
        switch fileServiceUpdateStatus {
        case .confirmedSuccess:
            fileServiceSettings = settings
        case .partialSuccess:
            fileServiceSettings.isSMBEnabled = settings.isSMBEnabled
        default:
            break
        }
        let isUnknown = fileServiceUpdateStatus == .submittedButUnverified
            || fileServiceUpdateStatus == .cancellationRequestedAfterSubmission
        let isPartial = fileServiceUpdateStatus == .partialSuccess
        let submitted = fileServiceUpdateStatus != .cancelledBeforeSubmission
            && fileServiceUpdateStatus != .permissionDenied
            && fileServiceUpdateStatus != .unsupported
        return try MutationResult(
            status: fileServiceUpdateStatus,
            operation: "fileServiceSettingsUpdate",
            submitted: submitted,
            requiresRefresh: isUnknown || isPartial,
            counts: MutationResultCounts(
                succeeded: fileServiceUpdateStatus == .confirmedSuccess
                    || isPartial ? 1 : 0,
                failed: isPartial
                    || fileServiceUpdateStatus == .permissionDenied
                    || fileServiceUpdateStatus == .unsupported
                    || fileServiceUpdateStatus == .confirmedFailure ? 1 : 0,
                unknown: isUnknown ? 1 : 0
            ),
            localizationKey: isPartial
                ? "file-services.settings.partial"
                : (isUnknown ? "file-services.settings.unverified" : nil),
            diagnosticTag: "file-services.settings.test"
        )
    }

    func loadTerminalSettings() async throws -> NasTerminalSettings {
        terminalSettings
    }

    func saveTerminalSettingsResult(
        _ settings: NasTerminalSettings
    ) async throws -> MutationResult {
        switch terminalUpdateStatus {
        case .confirmedSuccess:
            terminalSettings = settings
        case .partialSuccess:
            terminalSettings.isSSHEnabled = settings.isSSHEnabled
        default:
            break
        }
        let isUnknown = terminalUpdateStatus == .submittedButUnverified
            || terminalUpdateStatus == .cancellationRequestedAfterSubmission
        let isPartial = terminalUpdateStatus == .partialSuccess
        let submitted = terminalUpdateStatus != .cancelledBeforeSubmission
            && terminalUpdateStatus != .permissionDenied
            && terminalUpdateStatus != .unsupported
        return try MutationResult(
            status: terminalUpdateStatus,
            operation: "terminalSettingsUpdate",
            submitted: submitted,
            requiresRefresh: isUnknown || isPartial,
            counts: MutationResultCounts(
                succeeded: terminalUpdateStatus == .confirmedSuccess
                    || isPartial ? 1 : 0,
                failed: isPartial
                    || terminalUpdateStatus == .permissionDenied
                    || terminalUpdateStatus == .unsupported
                    || terminalUpdateStatus == .confirmedFailure ? 1 : 0,
                unknown: isUnknown ? 1 : 0
            ),
            localizationKey: isPartial
                ? "terminal.settings.partial"
                : (isUnknown ? "terminal.settings.unverified" : nil),
            diagnosticTag: "terminal.settings.test"
        )
    }

    func loadProxySettings() async throws -> NasProxySettings {
        proxySettings
    }

    func saveProxySettingsResult(
        _ settings: NasProxySettings
    ) async throws -> MutationResult {
        switch proxyUpdateStatus {
        case .confirmedSuccess:
            proxySettings = settings
        case .partialSuccess:
            proxySettings.isEnabled = settings.isEnabled
        default:
            break
        }
        let isUnknown = proxyUpdateStatus == .submittedButUnverified
            || proxyUpdateStatus == .cancellationRequestedAfterSubmission
        let isPartial = proxyUpdateStatus == .partialSuccess
        let submitted = proxyUpdateStatus != .cancelledBeforeSubmission
            && proxyUpdateStatus != .permissionDenied
            && proxyUpdateStatus != .unsupported
        return try MutationResult(
            status: proxyUpdateStatus,
            operation: "proxySettingsUpdate",
            submitted: submitted,
            requiresRefresh: isUnknown || isPartial,
            counts: MutationResultCounts(
                succeeded: proxyUpdateStatus == .confirmedSuccess
                    || isPartial ? 1 : 0,
                failed: isPartial
                    || proxyUpdateStatus == .permissionDenied
                    || proxyUpdateStatus == .unsupported
                    || proxyUpdateStatus == .confirmedFailure ? 1 : 0,
                unknown: isUnknown ? 1 : 0
            ),
            localizationKey: isPartial
                ? "proxy.settings.partial"
                : (isUnknown ? "proxy.settings.unverified" : nil),
            diagnosticTag: "proxy.settings.test"
        )
    }

    func saveEthernetInterfaceResult(
        _ interface: NasEthernetInterface
    ) async throws -> MutationResult {
        if ethernetUpdateStatus == .confirmedSuccess {
            ethernetInterfaces = [interface]
        }
        return try deletionResult(
            status: ethernetUpdateStatus,
            operation: "ethernetUpdate",
            prefix: "network.ethernet"
        )
    }

    func loadHardwareSettings() async throws -> NasHardwareSettings {
        hardwareSettings
    }

    func saveHardwareSettingsResult(
        _ settings: NasHardwareSettings
    ) async throws -> MutationResult {
        switch hardwareUpdateStatus {
        case .confirmedSuccess:
            hardwareSettings = settings
        case .partialSuccess:
            hardwareSettings.restartsAfterPowerFailure =
                settings.restartsAfterPowerFailure
        default:
            break
        }
        let isUnknown = hardwareUpdateStatus == .submittedButUnverified
            || hardwareUpdateStatus == .cancellationRequestedAfterSubmission
        let isPartial = hardwareUpdateStatus == .partialSuccess
        let submitted = hardwareUpdateStatus != .cancelledBeforeSubmission
            && hardwareUpdateStatus != .permissionDenied
            && hardwareUpdateStatus != .unsupported
        return try MutationResult(
            status: hardwareUpdateStatus,
            operation: "hardwareSettingsUpdate",
            submitted: submitted,
            requiresRefresh: isUnknown || isPartial,
            counts: MutationResultCounts(
                succeeded: hardwareUpdateStatus == .confirmedSuccess || isPartial ? 1 : 0,
                failed: isPartial
                    || hardwareUpdateStatus == .permissionDenied
                    || hardwareUpdateStatus == .unsupported
                    || hardwareUpdateStatus == .confirmedFailure ? 1 : 0,
                unknown: isUnknown ? 1 : 0
            ),
            localizationKey: isPartial
                ? "hardware.settings.partial"
                : (isUnknown ? "hardware.settings.unverified" : nil),
            diagnosticTag: "hardware.settings.test"
        )
    }

    func loadRemoteAccessSettings() async throws -> NasRemoteAccessSettings {
        remoteAccessSettings
    }

    func saveRemoteAccessSettingsResult(
        _ settings: NasRemoteAccessSettings
    ) async throws -> MutationResult {
        switch remoteAccessUpdateStatus {
        case .confirmedSuccess:
            remoteAccessSettings = settings
        case .partialSuccess:
            remoteAccessSettings.isRelayEnabled = settings.isRelayEnabled
        default:
            break
        }
        let isUnknown = remoteAccessUpdateStatus == .submittedButUnverified
            || remoteAccessUpdateStatus == .cancellationRequestedAfterSubmission
        let isPartial = remoteAccessUpdateStatus == .partialSuccess
        let submitted = remoteAccessUpdateStatus != .cancelledBeforeSubmission
            && remoteAccessUpdateStatus != .permissionDenied
            && remoteAccessUpdateStatus != .unsupported
        return try MutationResult(
            status: remoteAccessUpdateStatus,
            operation: "remoteAccessSettingsUpdate",
            submitted: submitted,
            requiresRefresh: isUnknown || isPartial,
            counts: MutationResultCounts(
                succeeded: remoteAccessUpdateStatus == .confirmedSuccess || isPartial ? 1 : 0,
                failed: isPartial
                    || remoteAccessUpdateStatus == .permissionDenied
                    || remoteAccessUpdateStatus == .unsupported
                    || remoteAccessUpdateStatus == .confirmedFailure ? 1 : 0,
                unknown: isUnknown ? 1 : 0
            ),
            localizationKey: isPartial
                ? "remote-access.settings.partial"
                : (isUnknown ? "remote-access.settings.unverified" : nil),
            diagnosticTag: "remote-access.settings.test"
        )
    }

    func loadSecuritySettings() async throws -> NasSecuritySettings {
        securitySettings
    }

    func saveSecuritySettingsResult(
        _ settings: NasSecuritySettings
    ) async throws -> MutationResult {
        switch securityUpdateStatus {
        case .confirmedSuccess:
            securitySettings = settings
        case .partialSuccess:
            securitySettings.isAutoBlockEnabled = settings.isAutoBlockEnabled
            securitySettings.failedAttempts = settings.failedAttempts
            securitySettings.withinMinutes = settings.withinMinutes
            securitySettings.expirationDays = settings.expirationDays
        default:
            break
        }
        let isUnknown = securityUpdateStatus == .submittedButUnverified
            || securityUpdateStatus == .cancellationRequestedAfterSubmission
        let isPartial = securityUpdateStatus == .partialSuccess
        let submitted = securityUpdateStatus != .cancelledBeforeSubmission
            && securityUpdateStatus != .permissionDenied
            && securityUpdateStatus != .unsupported
        return try MutationResult(
            status: securityUpdateStatus,
            operation: "securitySettingsUpdate",
            submitted: submitted,
            requiresRefresh: isUnknown || isPartial,
            counts: MutationResultCounts(
                succeeded: securityUpdateStatus == .confirmedSuccess || isPartial ? 1 : 0,
                failed: isPartial
                    || securityUpdateStatus == .permissionDenied
                    || securityUpdateStatus == .unsupported
                    || securityUpdateStatus == .confirmedFailure ? 1 : 0,
                unknown: isUnknown ? 1 : 0
            ),
            localizationKey: isPartial
                ? "security.settings.partial"
                : (isUnknown ? "security.settings.unverified" : nil),
            diagnosticTag: "security.settings.test"
        )
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

    func uninstallPackageResult(id: String) async throws -> MutationResult {
        packageControlRequests += 1
        switch packageUninstallStatus {
        case .confirmedSuccess:
            packages.removeAll { $0.id == id }
            return try MutationResult(
                status: .confirmedSuccess,
                operation: "packageUninstall",
                submitted: true,
                requiresRefresh: false,
                counts: MutationResultCounts(succeeded: 1, failed: 0, unknown: 0)
            )
        case .submittedButUnverified:
            return try MutationResult(
                status: .submittedButUnverified,
                operation: "packageUninstall",
                submitted: true,
                requiresRefresh: true,
                counts: MutationResultCounts(succeeded: 0, failed: 0, unknown: 1)
            )
        default:
            return try MutationResult(
                status: packageUninstallStatus,
                operation: "packageUninstall",
                submitted: false,
                requiresRefresh: false,
                counts: MutationResultCounts(succeeded: 0, failed: 1, unknown: 0)
            )
        }
    }

    private func deletionResult(
        status: MutationResultStatus,
        operation: String,
        prefix: String
    ) throws -> MutationResult {
        let submitted = status != .cancelledBeforeSubmission
            && status != .permissionDenied
            && status != .unsupported
        let isUnknown = status == .submittedButUnverified
            || status == .cancellationRequestedAfterSubmission
        return try MutationResult(
            status: status,
            operation: operation,
            submitted: submitted,
            requiresRefresh: isUnknown,
            counts: MutationResultCounts(
                succeeded: status == .confirmedSuccess ? 1 : 0,
                failed: status == .permissionDenied
                    || status == .unsupported
                    || status == .confirmedFailure ? 1 : 0,
                unknown: isUnknown ? 1 : 0
            ),
            localizationKey: isUnknown ? "\(prefix).unverified" : nil,
            diagnosticTag: "\(prefix).test"
        )
    }
}
