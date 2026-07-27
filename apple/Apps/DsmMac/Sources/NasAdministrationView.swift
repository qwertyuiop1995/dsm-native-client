import Charts
import DsmCore
import SwiftUI

struct NasSettingsView: View {
    @Bindable var model: NasSettingsModel

    var body: some View {
        NasAdministrationSplitView(
            pages: NasSettingsPage.allCases,
            selection: $model.selectedPage,
            label: pageLabel
        ) {
            settingsPage
        }
        .task(id: model.selectedPage) {
            await model.activate(model.selectedPage)
        }
        .task(id: "\(model.selectedPage.rawValue)-\(model.isLiveUpdatesPaused)") {
            let refreshablePages: Set<NasSettingsPage> = [.overview, .logs, .connections]
            guard refreshablePages.contains(model.selectedPage) else { return }
            if model.selectedPage == .overview, model.isLiveUpdatesPaused { return }
            while !Task.isCancelled, model.isModuleEnabled {
                do {
                    try await Task.sleep(for: .seconds(model.selectedPage == .overview ? 2 : 15))
                } catch {
                    return
                }
                if model.selectedPage == .overview {
                    await model.refreshPerformance()
                } else {
                    await model.activate(force: true)
                }
            }
        }
    }

    @ViewBuilder
    private var settingsPage: some View {
        switch model.selectedPage {
        case .overview:
            AdministrationPageContainer(
                isLoading: model.isLoading(.overview) || model.performanceIsLoading,
                hasLoaded: model.hasLoaded(.overview),
                hasContent: model.overview != nil,
                errorMessage: model.errorMessage(for: .overview),
                emptyTitle: "没有系统信息",
                emptyDescription: "这台 NAS 暂未返回系统概况。",
                retry: { await model.activate(.overview, force: true) }
            ) {
                PerformanceDashboard(
                    overview: model.overview,
                    history: model.performanceHistory,
                    connections: model.connections,
                    isPaused: $model.isLiveUpdatesPaused,
                    refresh: { await model.activate(.overview, force: true) },
                    onNavigateToConnections: { model.selectedPage = .connections },
                    onPerformPowerAction: { action in try await model.performPowerAction(action) },
                    onCheckSystemUpdate: { try await model.checkSystemUpdate() }
                )
            }
        case .storage:
            AdministrationPageContainer(
                isLoading: model.isLoading(.storage),
                hasLoaded: model.hasLoaded(.storage),
                hasContent: model.storage != nil,
                errorMessage: model.errorMessage(for: .storage),
                emptyTitle: "没有存储设备",
                emptyDescription: "这台 NAS 暂未返回存储池、空间或硬盘信息。",
                retry: { await model.activate(.storage, force: true) }
            ) {
                UnifiedStorageView(
                    snapshot: model.storage,
                    usageHistory: model.storageUsageHistory,
                    analysis: model.storageAnalysis,
                    analysisProgress: model.storageAnalysisProgress,
                    analysisError: model.storageAnalysisError,
                    isAnalyzing: model.isAnalyzingStorage,
                    testStatuses: model.diskTestStatuses,
                    busyDiskIDs: model.diskOperationIDs,
                    refresh: { await model.activate(.storage, force: true) },
                    beginAnalysis: model.beginStorageAnalysis,
                    cancelAnalysis: model.cancelStorageAnalysis,
                    loadTestStatus: { diskID in
                        _ = try await model.loadDiskTestStatus(diskID: diskID)
                    },
                    startTest: { diskID, type in
                        try await model.startDiskTest(diskID: diskID, type: type)
                    },
                    stopTest: { diskID in
                        try await model.stopDiskTest(diskID: diskID)
                    }
                )
            }
        case .fileServices:
            AdministrationPageContainer(
                isLoading: model.isLoading(.fileServices),
                hasLoaded: model.hasLoaded(.fileServices),
                hasContent: model.fileServices != nil,
                errorMessage: model.errorMessage(for: .fileServices),
                emptyTitle: "没有可管理的文件服务",
                emptyDescription: "这台 NAS 未提供兼容的文件共享设置，或当前账号没有管理权限。",
                retry: { await model.activate(.fileServices, force: true) }
            ) {
                if let settings = model.fileServices {
                    FileServiceSettingsView(
                        settings: settings,
                        isSaving: model.isSavingServiceSettings,
                        onSave: { try await model.saveFileServices($0) }
                    )
                    .id(settings)
                }
            }
        case .terminal:
            AdministrationPageContainer(
                isLoading: model.isLoading(.terminal),
                hasLoaded: model.hasLoaded(.terminal),
                hasContent: model.terminal != nil,
                errorMessage: model.errorMessage(for: .terminal),
                emptyTitle: "没有可管理的远程连接",
                emptyDescription: "这台 NAS 未提供兼容的远程连接设置，或当前账号没有管理权限。",
                retry: { await model.activate(.terminal, force: true) }
            ) {
                if let settings = model.terminal {
                    TerminalSettingsView(
                        settings: settings,
                        isSaving: model.isSavingServiceSettings,
                        onSave: { try await model.saveTerminal($0) }
                    )
                    .id(settings)
                }
            }
        case .network:
            AdministrationPageContainer(
                isLoading: model.isLoading(.network),
                hasLoaded: model.hasLoaded(.network),
                hasContent: model.proxy != nil,
                errorMessage: model.errorMessage(for: .network),
                emptyTitle: "没有可管理的网络设置",
                emptyDescription: "这台 NAS 未提供兼容的网络设置，或当前账号没有管理权限。",
                retry: { await model.activate(.network, force: true) }
            ) {
                if let settings = model.proxy {
                    ProxySettingsView(
                        settings: settings,
                        isSaving: model.isSavingServiceSettings,
                        onSave: { try await model.saveProxy($0) }
                    )
                    .id(settings)
                }
            }
        case .interfaces:
            AdministrationPageContainer(
                isLoading: model.isLoading(.interfaces),
                hasLoaded: model.hasLoaded(.interfaces),
                hasContent: !model.ethernetInterfaces.isEmpty,
                errorMessage: model.errorMessage(for: .interfaces),
                emptyTitle: "没有可管理的网卡",
                emptyDescription: "这台 NAS 未提供兼容的网卡设置，或当前账号没有管理权限。",
                retry: { await model.activate(.interfaces, force: true) }
            ) {
                EthernetInterfacesView(
                    interfaces: model.ethernetInterfaces,
                    busyIDs: model.networkOperationIDs,
                    onSave: { try await model.saveEthernetInterface($0) }
                )
            }
        case .hardware:
            AdministrationPageContainer(
                isLoading: model.isLoading(.hardware),
                hasLoaded: model.hasLoaded(.hardware),
                hasContent: model.hardware != nil,
                errorMessage: model.errorMessage(for: .hardware),
                emptyTitle: "没有可管理的硬件设置",
                emptyDescription: "这台 NAS 未提供兼容的硬件设置，或当前账号没有管理权限。",
                retry: { await model.activate(.hardware, force: true) }
            ) {
                if let settings = model.hardware {
                    HardwareSettingsView(
                        settings: settings,
                        isSaving: model.isSavingServiceSettings,
                        onSave: { try await model.saveHardware($0) }
                    )
                    .id(settings)
                }
            }
        case .remoteAccess:
            AdministrationPageContainer(
                isLoading: model.isLoading(.remoteAccess),
                hasLoaded: model.hasLoaded(.remoteAccess),
                hasContent: model.remoteAccess != nil,
                errorMessage: model.errorMessage(for: .remoteAccess),
                emptyTitle: "没有可管理的远程访问设置",
                emptyDescription: "这台 NAS 未提供兼容的远程访问设置，或当前账号没有管理权限。",
                retry: { await model.activate(.remoteAccess, force: true) }
            ) {
                if let settings = model.remoteAccess {
                    RemoteAccessSettingsView(
                        settings: settings,
                        isSaving: model.isSavingServiceSettings,
                        onSave: { try await model.saveRemoteAccess($0) }
                    )
                    .id(settings)
                }
            }
        case .security:
            AdministrationPageContainer(
                isLoading: model.isLoading(.security),
                hasLoaded: model.hasLoaded(.security),
                hasContent: model.security != nil,
                errorMessage: model.errorMessage(for: .security),
                emptyTitle: "没有可管理的安全设置",
                emptyDescription: "这台 NAS 未提供兼容的安全设置，或当前账号没有管理权限。",
                retry: { await model.activate(.security, force: true) }
            ) {
                if let settings = model.security {
                    SecuritySettingsView(
                        settings: settings,
                        isSaving: model.isSavingServiceSettings,
                        onSave: { try await model.saveSecurity($0) }
                    )
                    .id(settings)
                }
            }
        case .region:
            AdministrationPageContainer(
                isLoading: model.isLoading(.region),
                hasLoaded: model.hasLoaded(.region),
                hasContent: model.region != nil,
                errorMessage: model.errorMessage(for: .region),
                emptyTitle: "没有可管理的区域与时间设置",
                emptyDescription: "这台 NAS 未提供兼容的区域与时间设置，或当前账号没有管理权限。",
                retry: { await model.activate(.region, force: true) }
            ) {
                if let settings = model.region {
                    RegionSettingsView(
                        settings: settings,
                        isSaving: model.isSavingServiceSettings,
                        onSave: { try await model.saveRegion($0) }
                    )
                    .id(settings)
                }
            }
        case .ddns:
            AdministrationPageContainer(
                isLoading: model.isLoading(.ddns),
                hasLoaded: model.hasLoaded(.ddns),
                hasContent: model.ddns != nil,
                errorMessage: model.errorMessage(for: .ddns),
                emptyTitle: "没有可管理的 DDNS 设置",
                emptyDescription: "这台 NAS 未提供兼容的动态域名设置，或当前账号没有管理权限。",
                retry: { await model.activate(.ddns, force: true) }
            ) {
                if let directory = model.ddns {
                    DDNSSettingsView(
                        directory: directory,
                        busyIDs: model.ddnsOperationIDs,
                        onSave: { try await model.saveDDNS($0) },
                        onDelete: { try await model.deleteDDNS($0) },
                        onRefresh: { try await model.refreshDDNS() }
                    )
                    .id(directory)
                }
            }
        case .packages:
            AdministrationPageContainer(
                isLoading: model.isLoading(.packages),
                hasLoaded: model.hasLoaded(.packages),
                hasContent: !model.packages.isEmpty,
                errorMessage: model.errorMessage(for: .packages),
                emptyTitle: "没有已安装套件",
                emptyDescription: "这台 NAS 没有返回可查看的套件。",
                retry: { await model.activate(.packages, force: true) }
            ) {
                PackageList(
                    packages: model.packages,
                    title: "已安装套件",
                    busyPackageIDs: model.packageOperationIDs,
                    onControlPackage: { id, action in try await model.controlPackage(id: id, action: action) }
                )
            }
        case .tasks:
            AdministrationPageContainer(
                isLoading: model.isLoading(.tasks),
                hasLoaded: model.hasLoaded(.tasks),
                hasContent: !model.tasks.isEmpty,
                errorMessage: model.errorMessage(for: .tasks),
                emptyTitle: "没有计划任务",
                emptyDescription: "当前账号没有可查看的任务，或尚未创建计划任务。",
                retry: { await model.activate(.tasks, force: true) }
            ) {
                ScheduledTaskList(
                    tasks: model.tasks,
                    busyTaskIDs: model.taskOperationIDs,
                    loadDraft: { task in try await model.loadTaskDraft(task) },
                    loadResults: { task in try await model.loadTaskResults(task) },
                    loadResultOutput: { task, resultID in
                        try await model.loadTaskResultOutput(task: task, resultID: resultID)
                    },
                    onSave: { draft in try await model.saveTask(draft) },
                    onSetEnabled: { task, enabled in
                        try await model.setTaskEnabled(task, enabled: enabled)
                    },
                    onRun: { task in try await model.runTask(task) },
                    onDelete: { task in try await model.deleteTask(task) }
                )
            }
        case .accounts:
            AdministrationPageContainer(
                isLoading: model.isLoading(.accounts),
                hasLoaded: model.hasLoaded(.accounts),
                hasContent: model.accounts.map { !$0.users.isEmpty || !$0.groups.isEmpty } ?? false,
                errorMessage: model.errorMessage(for: .accounts),
                emptyTitle: "没有可查看的账号或群组",
                emptyDescription: "当前账号没有查看权限，或这台 NAS 尚未配置账号目录。",
                retry: { await model.activate(.accounts, force: true) }
            ) {
                AccountDirectoryView(
                    directory: model.accounts,
                    busyAccountIDs: model.accountOperationIDs,
                    onSave: { draft in try await model.saveAccount(draft) },
                    onDelete: { account in try await model.deleteAccount(account) },
                    onSaveGroup: { draft in try await model.saveGroup(draft) },
                    onDeleteGroup: { group in try await model.deleteGroup(group) }
                )
            }
        case .logs:
            AdministrationPageContainer(
                isLoading: model.isLoading(.logs),
                hasLoaded: model.hasLoaded(.logs),
                hasContent: !(model.logs?.entries.isEmpty ?? true),
                errorMessage: model.errorMessage(for: .logs),
                emptyTitle: "没有系统日志",
                emptyDescription: "当前范围内没有日志，或当前账号无权查看。",
                retry: { await model.activate(.logs, force: true) }
            ) {
                LogEntryList(
                    page: model.logs,
                    currentPage: model.logCurrentPage,
                    pageSize: model.logPageSize,
                    onFetchPage: { page, size in
                        await model.fetchLogs(page: page, pageSize: size)
                    }
                )
            }
        case .connections:
            AdministrationPageContainer(
                isLoading: model.isLoading(.connections),
                hasLoaded: model.hasLoaded(.connections),
                hasContent: !(model.connections?.connections.isEmpty ?? true),
                errorMessage: model.errorMessage(for: .connections),
                emptyTitle: "当前没有活动连接",
                emptyDescription: "没有其他设备或服务正在使用这台 NAS。",
                retry: { await model.activate(.connections, force: true) }
            ) {
                ConnectionList(
                    page: model.connections,
                    busyConnectionIDs: model.connectionOperationIDs,
                    onDisconnect: { connection in
                        try await model.disconnectConnection(connection)
                    }
                )
            }
        }
    }

    private func pageLabel(_ page: NasSettingsPage) -> (String, String) {
        switch page {
        case .overview: ("总览与性能", "gauge.with.dots.needle.67percent")
        case .storage: ("存储管理", "internaldrive")
        case .fileServices: ("文件服务", "folder.badge.gearshape")
        case .terminal: ("远程连接", "terminal")
        case .network: ("网络与代理", "network")
        case .interfaces: ("网络接口", "cable.connector")
        case .hardware: ("硬件与电源", "powerplug")
        case .remoteAccess: ("远程访问", "network.badge.shield.half.filled")
        case .security: ("安全防护", "lock.shield")
        case .region: ("区域与时间", "clock.badge.checkmark")
        case .ddns: ("动态域名", "globe.badge.chevron.backward")
        case .packages: ("套件", "shippingbox")
        case .tasks: ("计划任务", "calendar.badge.clock")
        case .accounts: ("账号与权限", "person.2")
        case .logs: ("系统日志", "doc.text.magnifyingglass")
        case .connections: ("当前连接", "network")
        }
    }
}

private struct EthernetInterfacesView: View {
    let interfaces: [NasEthernetInterface]
    let busyIDs: Set<String>
    let onSave: (NasEthernetInterface) async throws -> Void
    @State private var editing: NasEthernetInterface?

    var body: some View {
        List(interfaces) { interface in
            HStack(spacing: 14) {
                Image(systemName: "cable.connector")
                    .font(.title3)
                    .foregroundStyle(interface.status == "connected" ? .green : .secondary)
                VStack(alignment: .leading, spacing: 4) {
                    Text(interface.displayName)
                        .font(.headline)
                    Text(interface.usesDHCP
                        ? "自动获取地址 · \(interface.address.isEmpty ? "尚未分配" : interface.address)"
                        : "\(interface.address) · \(interface.subnetMask)")
                        .foregroundStyle(.secondary)
                    Text("MTU \(interface.mtu)"
                        + (interface.isVLANEnabled ? " · VLAN \(interface.vlanID ?? 0)" : ""))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                ProgressView()
                    .controlSize(.small)
                    .opacity(busyIDs.contains("network:\(interface.id)") ? 1 : 0)
                Button("编辑") { editing = interface }
                    .disabled(busyIDs.contains("network:\(interface.id)"))
            }
            .padding(.vertical, 5)
        }
        .sheet(isPresented: Binding(
            get: { editing != nil },
            set: { if !$0 { editing = nil } }
        )) {
            if let interface = editing {
                EthernetInterfaceEditor(
                    interface: interface,
                    onCancel: { editing = nil },
                    onSave: {
                        try await onSave($0)
                        editing = nil
                    }
                )
            }
        }
    }
}

private struct EthernetInterfaceEditor: View {
    @State private var draft: NasEthernetInterface
    @State private var isSaving = false
    @State private var isConfirming = false
    @State private var errorMessage: String?
    let original: NasEthernetInterface
    let onCancel: () -> Void
    let onSave: (NasEthernetInterface) async throws -> Void

    init(
        interface: NasEthernetInterface,
        onCancel: @escaping () -> Void,
        onSave: @escaping (NasEthernetInterface) async throws -> Void
    ) {
        _draft = State(initialValue: interface)
        original = interface
        self.onCancel = onCancel
        self.onSave = onSave
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section(draft.displayName) {
                    Toggle("自动获取网络设置", isOn: $draft.usesDHCP)
                    TextField("IP 地址", text: $draft.address)
                        .disabled(draft.usesDHCP)
                    TextField("子网掩码", text: $draft.subnetMask)
                        .disabled(draft.usesDHCP)
                    TextField("网关", text: $draft.gateway)
                        .disabled(draft.usesDHCP)
                    TextField("DNS 服务器", text: $draft.dnsServers)
                        .disabled(draft.usesDHCP)
                    Toggle("作为默认网关", isOn: $draft.isDefaultGateway)
                    TextField("MTU", value: $draft.mtu, format: .number)
                    Toggle("启用 VLAN", isOn: $draft.isVLANEnabled)
                    if draft.isVLANEnabled {
                        TextField(
                            "VLAN ID",
                            value: Binding(
                                get: { draft.vlanID ?? 1 },
                                set: { draft.vlanID = $0 }
                            ),
                            format: .number
                        )
                    }
                }
                Section {
                    Text("更改正在使用的网卡可能立即中断当前连接。保存后应用会重新读取网卡状态；如果地址发生变化，请用新地址重新连接。")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            .formStyle(.grouped)
            Divider()
            HStack {
                Spacer()
                Button("取消", action: onCancel)
                Button("应用网络设置") { isConfirming = true }
                    .buttonStyle(.borderedProminent)
                    .disabled(draft == original || isSaving)
            }
            .padding()
        }
        .frame(minWidth: 560, minHeight: 520)
        .confirmationDialog(
            "应用这张网卡的设置？",
            isPresented: $isConfirming,
            titleVisibility: .visible
        ) {
            Button("应用并可能断开连接", role: .destructive) { save() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("如果 IP 地址、网关或 VLAN 改变，当前连接可能立即中断。请先确认你知道新的连接地址。")
        }
        .alert("无法保存网络设置", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("好") {}
        } message: {
            Text(errorMessage ?? "请检查填写内容后重试。")
        }
    }

    private func save() {
        guard !isSaving else { return }
        isSaving = true
        Task {
            defer { isSaving = false }
            do {
                try await onSave(draft)
            } catch {
                errorMessage = userMessage(
                    for: error,
                    fallback: "网络设置未保存。请检查 NAS 是否仍可连接。"
                )
            }
        }
    }
}

private struct DDNSSettingsView: View {
    let directory: NasDDNSDirectory
    let busyIDs: Set<String>
    let onSave: (NasDDNSDraft) async throws -> Void
    let onDelete: (NasDDNSRecord) async throws -> Void
    let onRefresh: () async throws -> Void
    @State private var presentedDraft: NasDDNSDraft?
    @State private var deleteTarget: NasDDNSRecord?
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("动态域名")
                    .font(.title2.weight(.semibold))
                Spacer()
                Button {
                    refresh()
                } label: {
                    Label("立即更新", systemImage: "arrow.clockwise")
                }
                .disabled(busyIDs.contains("refresh"))
                Button {
                    guard let provider = availableProviders.first else { return }
                    presentedDraft = NasDDNSDraft(
                        providerID: provider.id,
                        hostname: "",
                        username: ""
                    )
                } label: {
                    Label("新建", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .disabled(availableProviders.isEmpty)
            }
            .padding()

            if directory.records.isEmpty {
                ContentUnavailableView(
                    "没有 DDNS 记录",
                    systemImage: "globe",
                    description: Text(
                        availableProviders.isEmpty
                            ? "这台 NAS 没有返回可用的动态域名服务商。"
                            : "可新建记录，让域名随公网地址变化自动更新。"
                    )
                )
            } else {
                List(directory.records) { record in
                    HStack(spacing: 14) {
                        Image(systemName: record.isEnabled ? "globe.badge.checkmark" : "globe")
                            .foregroundStyle(record.isEnabled ? .green : .secondary)
                            .font(.title3)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(record.hostname)
                                .font(.headline)
                            Text([record.providerName, record.address, record.status]
                                .compactMap { $0 }
                                .joined(separator: " · "))
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                            if let updated = record.lastUpdated, !updated.isEmpty {
                                Text("上次更新：\(updated)")
                                    .font(.caption)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        Spacer()
                        ProgressView()
                            .controlSize(.small)
                            .opacity(busyIDs.contains(record.id) ? 1 : 0)
                        Button("编辑") {
                            presentedDraft = draft(from: record)
                        }
                        .disabled(busyIDs.contains(record.id))
                        Button("删除", role: .destructive) {
                            deleteTarget = record
                        }
                        .disabled(busyIDs.contains(record.id))
                    }
                    .padding(.vertical, 5)
                }
            }
        }
        .sheet(isPresented: draftPresentation) {
            if let draft = presentedDraft {
                DDNSRecordEditor(
                    draft: draft,
                    providers: directory.providers,
                    onCancel: { presentedDraft = nil },
                    onSave: { value in
                        try await onSave(value)
                        presentedDraft = nil
                    }
                )
            }
        }
        .confirmationDialog(
            "删除这条动态域名记录？",
            isPresented: Binding(
                get: { deleteTarget != nil },
                set: { if !$0 { deleteTarget = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("删除记录", role: .destructive) {
                guard let target = deleteTarget else { return }
                deleteTarget = nil
                Task {
                    do {
                        try await onDelete(target)
                    } catch {
                        errorMessage = userMessage(
                            for: error,
                            fallback: "记录未删除，请稍后重试。"
                        )
                    }
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("删除后，NAS 将不再自动更新这个域名。")
        }
        .alert("无法完成操作", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("好") {}
        } message: {
            Text(errorMessage ?? "请稍后重试。")
        }
    }

    private var availableProviders: [NasDDNSProvider] {
        let used = Set(directory.records.map(\.providerID))
        return directory.providers.filter { !used.contains($0.id) }
    }

    private var draftPresentation: Binding<Bool> {
        Binding(
            get: { presentedDraft != nil },
            set: { if !$0 { presentedDraft = nil } }
        )
    }

    private func draft(from record: NasDDNSRecord) -> NasDDNSDraft {
        NasDDNSDraft(
            originalProviderID: record.providerID,
            providerID: record.providerID,
            hostname: record.hostname,
            username: record.username ?? "",
            isEnabled: record.isEnabled,
            networkType: record.networkType ?? "auto",
            ipv4: record.ipv4 ?? "0.0.0.0",
            ipv6: record.ipv6 ?? "0:0:0:0:0:0:0:0",
            interfaceV4: record.interfaceV4 ?? "",
            interfaceV6: record.interfaceV6 ?? "",
            heartbeat: record.heartbeat
        )
    }

    private func refresh() {
        Task {
            do {
                try await onRefresh()
            } catch {
                errorMessage = userMessage(for: error, fallback: "暂时无法更新，请稍后重试。")
            }
        }
    }
}

private struct DDNSRecordEditor: View {
    @State private var draft: NasDDNSDraft
    @State private var isSaving = false
    @State private var errorMessage: String?
    let providers: [NasDDNSProvider]
    let onCancel: () -> Void
    let onSave: (NasDDNSDraft) async throws -> Void

    init(
        draft: NasDDNSDraft,
        providers: [NasDDNSProvider],
        onCancel: @escaping () -> Void,
        onSave: @escaping (NasDDNSDraft) async throws -> Void
    ) {
        _draft = State(initialValue: draft)
        self.providers = providers
        self.onCancel = onCancel
        self.onSave = onSave
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("动态域名记录") {
                    Toggle("启用自动更新", isOn: $draft.isEnabled)
                    Picker("服务商", selection: $draft.providerID) {
                        ForEach(providers) { provider in
                            Text(provider.displayName).tag(provider.id)
                        }
                    }
                    .disabled(draft.originalProviderID != nil)
                    TextField("主机名称", text: $draft.hostname)
                    TextField("账号", text: $draft.username)
                    if draft.providerID != "Synology" {
                        SecureField(
                            draft.originalProviderID == nil ? "密码或密钥" : "新密码或密钥（不更改可留空）",
                            text: $draft.password
                        )
                    } else {
                        Text("使用 NAS 已登录的 Synology 账号。")
                            .foregroundStyle(.secondary)
                    }
                    Toggle("定期保持连接", isOn: $draft.heartbeat)
                }
                Section {
                    Text("密码或密钥只用于本次提交，不会保存在 Mac 客户端。保存前会先由 NAS 验证连接，再重新读取记录确认结果。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
            Divider()
            HStack {
                Spacer()
                Button("取消", action: onCancel)
                Button("保存") { save() }
                    .buttonStyle(.borderedProminent)
                    .disabled(
                        isSaving
                            || draft.hostname.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || draft.username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || (draft.originalProviderID == nil
                                && draft.providerID != "Synology"
                                && draft.password.isEmpty)
                    )
            }
            .padding()
        }
        .frame(minWidth: 520, minHeight: 420)
        .alert("无法保存记录", isPresented: Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )) {
            Button("好") {}
        } message: {
            Text(errorMessage ?? "请检查填写内容后重试。")
        }
    }

    private func save() {
        guard !isSaving else { return }
        isSaving = true
        Task {
            defer { isSaving = false }
            do {
                try await onSave(draft)
            } catch {
                errorMessage = userMessage(for: error, fallback: "记录未保存，请稍后重试。")
            }
        }
    }
}

private struct RegionSettingsView: View {
    @State private var draft: NasRegionSettings
    @State private var serverText: String
    @State private var isConfirming = false
    @State private var errorMessage: String?
    let original: NasRegionSettings
    let isSaving: Bool
    let onSave: (NasRegionSettings) async throws -> Void

    init(
        settings: NasRegionSettings,
        isSaving: Bool,
        onSave: @escaping (NasRegionSettings) async throws -> Void
    ) {
        _draft = State(initialValue: settings)
        _serverText = State(initialValue: settings.timeServers.joined(separator: ", "))
        original = settings
        self.isSaving = isSaving
        self.onSave = onSave
    }

    var body: some View {
        Form {
            Section("显示格式") {
                TextField("日期格式", text: $draft.dateFormat)
                TextField("时间格式", text: $draft.timeFormat)
                Picker("时区", selection: $draft.timeZone) {
                    ForEach(draft.timeZones) { zone in
                        Text(zone.displayName).tag(zone.id)
                    }
                }
            }
            Section("日期与时间") {
                Toggle("自动与时间服务器同步", isOn: $draft.isNetworkTimeEnabled)
                if draft.isNetworkTimeEnabled {
                    TextField("时间服务器", text: $serverText)
                    Text("最多填写 3 个地址，并用逗号分隔。保存前会先确认服务器可以正常校时。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    DatePicker(
                        "设置日期与时间",
                        selection: Binding(
                            get: { draft.manualDate ?? Date() },
                            set: { draft.manualDate = $0 }
                        )
                    )
                    Text("手动更改系统时间可能使当前登录失效，并影响验证码、证书和计划任务。")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            Section {
                HStack {
                    Spacer()
                    Button("恢复") {
                        draft = original
                        serverText = original.timeServers.joined(separator: ", ")
                    }
                    .disabled(!hasChanges || isSaving)
                    Button("应用更改") { isConfirming = true }
                        .buttonStyle(.borderedProminent)
                        .disabled(!hasChanges || isSaving)
                }
            }
        }
        .formStyle(.grouped)
        .confirmationDialog(
            draft.isNetworkTimeEnabled ? "应用区域与时间设置？" : "手动更改 NAS 系统时间？",
            isPresented: $isConfirming,
            titleVisibility: .visible
        ) {
            Button(draft.isNetworkTimeEnabled ? "应用更改" : "更改系统时间", role: .destructive) {
                save()
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text(
                draft.isNetworkTimeEnabled
                    ? "保存后将重新读取 NAS，确认时区、格式和校时方式确实生效。"
                    : "当前登录可能失效，计划任务的执行时间也可能改变。请确认日期、时间和时区无误。"
            )
        }
        .alert("无法保存设置", isPresented: errorBinding) {
            Button("好") {}
        } message: {
            Text(errorMessage ?? "请稍后重试。")
        }
    }

    private var normalizedServers: [String] {
        serverText
            .split(separator: ",", omittingEmptySubsequences: true)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private var hasChanges: Bool {
        var candidate = draft
        candidate.timeServers = normalizedServers
        return candidate != original
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    private func save() {
        Task {
            do {
                draft.timeServers = normalizedServers
                try await onSave(draft)
            } catch {
                errorMessage = userMessage(for: error, fallback: "设置未保存，请稍后重试。")
            }
        }
    }
}

private struct SecuritySettingsView: View {
    @State private var draft: NasSecuritySettings
    @State private var expiresAutomatically: Bool
    @State private var isConfirming = false
    @State private var errorMessage: String?
    let original: NasSecuritySettings
    let isSaving: Bool
    let onSave: (NasSecuritySettings) async throws -> Void

    init(
        settings: NasSecuritySettings,
        isSaving: Bool,
        onSave: @escaping (NasSecuritySettings) async throws -> Void
    ) {
        _draft = State(initialValue: settings)
        _expiresAutomatically = State(initialValue: settings.expirationDays != nil)
        original = settings
        self.isSaving = isSaving
        self.onSave = onSave
    }

    var body: some View {
        Form {
            Section("登录保护") {
                Toggle("自动封锁多次登录失败的地址", isOn: $draft.isAutoBlockEnabled)
                Stepper(
                    "允许失败次数：\(draft.failedAttempts)",
                    value: $draft.failedAttempts,
                    in: 1...9_999
                )
                .disabled(!draft.isAutoBlockEnabled)
                Stepper(
                    "统计时间：\(draft.withinMinutes) 分钟",
                    value: $draft.withinMinutes,
                    in: 1...9_999_999
                )
                .disabled(!draft.isAutoBlockEnabled)
                Toggle("自动解除封锁", isOn: $expiresAutomatically)
                    .disabled(!draft.isAutoBlockEnabled)
                    .onChange(of: expiresAutomatically) { _, enabled in
                        draft.expirationDays = enabled ? max(1, draft.expirationDays ?? 1) : nil
                    }
                if expiresAutomatically {
                    Stepper(
                        "封锁期限：\(draft.expirationDays ?? 1) 天",
                        value: Binding(
                            get: { draft.expirationDays ?? 1 },
                            set: { draft.expirationDays = $0 }
                        ),
                        in: 1...999
                    )
                    .disabled(!draft.isAutoBlockEnabled)
                }
            }
            if !draft.dosProtection.isEmpty {
                Section("网络攻击防护") {
                    ForEach(draft.dosProtection.indices, id: \.self) { index in
                        Toggle(
                            "保护 \(draft.dosProtection[index].displayName)",
                            isOn: $draft.dosProtection[index].isEnabled
                        )
                    }
                    Text("按网卡开启后，NAS 会检测并缓解常见的拒绝服务攻击流量。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            if draft.isFirewallEnabled != nil
                || draft.isPortScanProtectionEnabled != nil {
                Section("防火墙") {
                    if draft.isFirewallEnabled != nil {
                        Toggle(
                            "启用防火墙",
                            isOn: Binding(
                                get: { draft.isFirewallEnabled ?? false },
                                set: { draft.isFirewallEnabled = $0 }
                            )
                        )
                        if let profile = draft.firewallProfileName, !profile.isEmpty {
                            LabeledContent("当前配置", value: profile)
                        }
                    }
                    if draft.isPortScanProtectionEnabled != nil {
                        Toggle(
                            "检测可疑端口扫描",
                            isOn: Binding(
                                get: { draft.isPortScanProtectionEnabled ?? false },
                                set: { draft.isPortScanProtectionEnabled = $0 }
                            )
                        )
                        .disabled(draft.isFirewallEnabled == false)
                    }
                    Text("启用时会应用 NAS 当前选定的防火墙配置。若该配置没有允许当前连接，连接可能中断。")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            Section {
                Text("启用后，短时间内多次登录失败的来源会被自动封锁。设置过宽会降低保护效果，设置过严可能误封正常用户。")
                    .foregroundStyle(.secondary)
                HStack {
                    Spacer()
                    Button("恢复") {
                        draft = original
                        expiresAutomatically = original.expirationDays != nil
                    }
                    .disabled(draft == original || isSaving)
                    Button("应用更改") { isConfirming = true }
                        .buttonStyle(.borderedProminent)
                        .disabled(draft == original || isSaving)
                }
            }
        }
        .formStyle(.grouped)
        .confirmationDialog(
            "应用安全防护设置？",
            isPresented: $isConfirming,
            titleVisibility: .visible
        ) {
            Button("应用更改") { save() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("更改会影响后续登录和网络连接。启用防火墙前请确认当前配置允许你的管理连接；保存后将重新读取 NAS 确认结果。")
        }
        .alert("无法保存设置", isPresented: errorBinding) {
            Button("好") {}
        } message: {
            Text(errorMessage ?? "请稍后重试。")
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    private func save() {
        Task {
            do {
                try await onSave(draft)
            } catch {
                errorMessage = userMessage(for: error, fallback: "设置未保存，请稍后重试。")
            }
        }
    }
}

private struct RemoteAccessSettingsView: View {
    @State private var draft: NasRemoteAccessSettings
    @State private var isConfirming = false
    @State private var errorMessage: String?
    let original: NasRemoteAccessSettings
    let isSaving: Bool
    let onSave: (NasRemoteAccessSettings) async throws -> Void

    init(
        settings: NasRemoteAccessSettings,
        isSaving: Bool,
        onSave: @escaping (NasRemoteAccessSettings) async throws -> Void
    ) {
        _draft = State(initialValue: settings)
        original = settings
        self.isSaving = isSaving
        self.onSave = onSave
    }

    var body: some View {
        Form {
            Section("QuickConnect") {
                if draft.isRelayEnabled != nil {
                    Toggle(
                        "无法直连时使用远程中继",
                        isOn: Binding(
                            get: { draft.isRelayEnabled ?? false },
                            set: { draft.isRelayEnabled = $0 }
                        )
                    )
                    .disabled(!draft.canDisableRelay && draft.isRelayEnabled == true)
                    if !draft.canDisableRelay {
                        Text("当前连接正在使用远程中继。请先改用局域网或直连地址，再关闭此选项。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if draft.isRouterConfigurationEnabled != nil {
                    Toggle(
                        "允许自动配置路由器",
                        isOn: Binding(
                            get: { draft.isRouterConfigurationEnabled ?? false },
                            set: { draft.isRouterConfigurationEnabled = $0 }
                        )
                    )
                }
            }
            Section {
                Text("远程中继可在无法直接连接时提供访问路径；自动配置路由器会尝试开放所需连接。")
                    .foregroundStyle(.secondary)
                HStack {
                    Spacer()
                    Button("恢复") { draft = original }
                        .disabled(draft == original || isSaving)
                    Button("应用更改") { isConfirming = true }
                        .buttonStyle(.borderedProminent)
                        .disabled(draft == original || isSaving)
                }
            }
        }
        .formStyle(.grouped)
        .confirmationDialog(
            "应用远程访问设置？",
            isPresented: $isConfirming,
            titleVisibility: .visible
        ) {
            Button("应用更改") { save() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("更改可能影响外部设备连接。保存后将重新读取 NAS，确认设置确实生效。")
        }
        .alert("无法保存设置", isPresented: errorBinding) {
            Button("好") {}
        } message: {
            Text(errorMessage ?? "请稍后重试。")
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    private func save() {
        Task {
            do {
                try await onSave(draft)
            } catch {
                errorMessage = userMessage(for: error, fallback: "设置未保存，请稍后重试。")
            }
        }
    }
}

private struct HardwareSettingsView: View {
    @State private var draft: NasHardwareSettings
    @State private var isConfirming = false
    @State private var errorMessage: String?
    let original: NasHardwareSettings
    let isSaving: Bool
    let onSave: (NasHardwareSettings) async throws -> Void

    init(
        settings: NasHardwareSettings,
        isSaving: Bool,
        onSave: @escaping (NasHardwareSettings) async throws -> Void
    ) {
        _draft = State(initialValue: settings)
        original = settings
        self.isSaving = isSaving
        self.onSave = onSave
    }

    var body: some View {
        Form {
            if draft.restartsAfterPowerFailure != nil {
                Section("断电恢复") {
                    Toggle(
                        "恢复供电后自动启动",
                        isOn: Binding(
                            get: { draft.restartsAfterPowerFailure ?? false },
                            set: { draft.restartsAfterPowerFailure = $0 }
                        )
                    )
                }
            }
            if let range = draft.ledBrightnessRange,
               draft.ledBrightness != nil {
                Section("设备灯光") {
                    Stepper(
                        "亮度 \(draft.ledBrightness ?? range.lowerBound)",
                        value: Binding(
                            get: { draft.ledBrightness ?? range.lowerBound },
                            set: { draft.ledBrightness = $0 }
                        ),
                        in: range
                    )
                }
            }
            if draft.fanMode != nil {
                Section("散热") {
                    Picker(
                        "风扇模式",
                        selection: Binding(
                            get: { draft.fanMode ?? "coolfan" },
                            set: { draft.fanMode = $0 }
                        )
                    ) {
                        Text("散热优先").tag("highfan")
                        Text("低速").tag("lowfan")
                        Text("全速").tag("fullfan")
                        Text("凉爽模式").tag("coolfan")
                        Text("安静模式").tag("quietfan")
                        Text("低功耗安静模式").tag("quietstopfan")
                    }
                }
            }
            if draft.isFanFailureAlertEnabled != nil
                || draft.isVolumeFailureAlertEnabled != nil
                || draft.isPowerOnSoundEnabled != nil
                || draft.isPowerOffSoundEnabled != nil
                || draft.isResetSoundEnabled != nil {
                Section("提示音") {
                    optionalHardwareToggle(
                        "风扇异常时发出提示音",
                        value: $draft.isFanFailureAlertEnabled
                    )
                    optionalHardwareToggle(
                        "存储空间异常时发出提示音",
                        value: $draft.isVolumeFailureAlertEnabled
                    )
                    optionalHardwareToggle(
                        "启动时发出提示音",
                        value: $draft.isPowerOnSoundEnabled
                    )
                    optionalHardwareToggle(
                        "关机时发出提示音",
                        value: $draft.isPowerOffSoundEnabled
                    )
                    optionalHardwareToggle(
                        "重置时发出提示音",
                        value: $draft.isResetSoundEnabled
                    )
                }
            }
            if draft.isExternalDriveDeepSleepEnabled != nil
                || draft.isWakeUpLogEnabled != nil
                || draft.isSATASleepEnabled != nil
                || draft.ignoresNetworkDiscoveryDuringSleep != nil
                || draft.isAutomaticPowerOffEnabled != nil {
                Section("休眠与节能") {
                    optionalHardwareToggle(
                        "允许外接存储进入深度休眠",
                        value: $draft.isExternalDriveDeepSleepEnabled
                    )
                    optionalHardwareToggle(
                        "记录硬盘唤醒事件",
                        value: $draft.isWakeUpLogEnabled
                    )
                    optionalHardwareToggle(
                        "允许 SATA 设备深度休眠",
                        value: $draft.isSATASleepEnabled
                    )
                    optionalHardwareToggle(
                        "休眠时忽略局域网发现流量",
                        value: $draft.ignoresNetworkDiscoveryDuringSleep
                    )
                    optionalHardwareToggle(
                        "长时间闲置后自动关机",
                        value: $draft.isAutomaticPowerOffEnabled
                    )
                }
            }
            if draft.ups != nil {
                Section("不间断电源") {
                    Toggle(
                        "启用 UPS 支持",
                        isOn: Binding(
                            get: { draft.ups?.isEnabled ?? false },
                            set: { draft.ups?.isEnabled = $0 }
                        )
                    )
                    Picker(
                        "连接方式",
                        selection: Binding(
                            get: { draft.ups?.mode ?? "USB" },
                            set: { draft.ups?.mode = $0 }
                        )
                    ) {
                        Text("USB").tag("USB")
                        Text("网络 UPS 服务器").tag("SLAVE")
                        Text("SNMP UPS").tag("SNMP")
                    }
                    .disabled(draft.ups?.isEnabled != true)
                    if draft.ups?.mode == "SLAVE" {
                        TextField(
                            "UPS 服务器地址",
                            text: Binding(
                                get: { draft.ups?.networkServerAddress ?? "" },
                                set: { draft.ups?.networkServerAddress = $0 }
                            )
                        )
                        .disabled(draft.ups?.isEnabled != true)
                    }
                    if draft.ups?.mode == "SNMP" {
                        TextField(
                            "SNMP UPS 地址",
                            text: Binding(
                                get: { draft.ups?.snmpServerAddress ?? "" },
                                set: { draft.ups?.snmpServerAddress = $0 }
                            )
                        )
                        .disabled(draft.ups?.isEnabled != true)
                    }
                    if draft.ups?.waitsUntilLowBattery != nil {
                        Toggle(
                            "电池电量低时进入安全模式",
                            isOn: Binding(
                                get: { draft.ups?.waitsUntilLowBattery ?? false },
                                set: { draft.ups?.waitsUntilLowBattery = $0 }
                            )
                        )
                        .disabled(draft.ups?.isEnabled != true)
                    }
                    if draft.ups?.safeModeDelaySeconds != nil,
                       draft.ups?.waitsUntilLowBattery != true {
                        TextField(
                            "进入安全模式前等待（秒）",
                            value: Binding(
                                get: { draft.ups?.safeModeDelaySeconds ?? 0 },
                                set: { draft.ups?.safeModeDelaySeconds = $0 }
                            ),
                            format: .number
                        )
                        .disabled(draft.ups?.isEnabled != true)
                    }
                    if draft.ups?.shutsDownUPSAfterSafeMode != nil {
                        Toggle(
                            "NAS 进入安全模式后关闭 UPS",
                            isOn: Binding(
                                get: { draft.ups?.shutsDownUPSAfterSafeMode ?? false },
                                set: { draft.ups?.shutsDownUPSAfterSafeMode = $0 }
                            )
                        )
                        .disabled(draft.ups?.isEnabled != true)
                    }
                    Text("设置错误可能使停电时无法安全关机。连接方式和服务器地址必须与实际 UPS 部署一致。")
                        .font(.caption)
                        .foregroundStyle(.orange)
                }
            }
            Section {
                Text("灯光设置会立即反映在设备上；断电恢复设置会在下一次供电恢复时生效。")
                    .foregroundStyle(.secondary)
                HStack {
                    Spacer()
                    Button("恢复") { draft = original }
                        .disabled(draft == original || isSaving)
                    Button("应用更改") { isConfirming = true }
                        .buttonStyle(.borderedProminent)
                        .disabled(draft == original || isSaving)
                }
            }
        }
        .formStyle(.grouped)
        .confirmationDialog(
            "应用硬件设置？",
            isPresented: $isConfirming,
            titleVisibility: .visible
        ) {
            Button("应用更改") { save() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("保存后将重新读取 NAS，确认设置确实生效。UPS 设置错误可能影响停电时的安全关机。")
        }
        .alert("无法保存设置", isPresented: errorBinding) {
            Button("好") {}
        } message: {
            Text(errorMessage ?? "请稍后重试。")
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    @ViewBuilder
    private func optionalHardwareToggle(_ title: String, value: Binding<Bool?>) -> some View {
        if value.wrappedValue != nil {
            Toggle(
                title,
                isOn: Binding(
                    get: { value.wrappedValue ?? false },
                    set: { value.wrappedValue = $0 }
                )
            )
        }
    }

    private func save() {
        Task {
            do {
                try await onSave(draft)
            } catch {
                errorMessage = userMessage(for: error, fallback: "设置未保存，请稍后重试。")
            }
        }
    }
}

private struct ProxySettingsView: View {
    @State private var draft: NasProxySettings
    @State private var isConfirming = false
    @State private var errorMessage: String?
    let original: NasProxySettings
    let isSaving: Bool
    let onSave: (NasProxySettings) async throws -> Void

    init(
        settings: NasProxySettings,
        isSaving: Bool,
        onSave: @escaping (NasProxySettings) async throws -> Void
    ) {
        _draft = State(initialValue: settings)
        original = settings
        self.isSaving = isSaving
        self.onSave = onSave
    }

    var body: some View {
        Form {
            Section("互联网代理") {
                Toggle("通过代理服务器连接互联网", isOn: $draft.isEnabled)
                TextField("服务器地址", text: $draft.host)
                    .disabled(!draft.isEnabled)
                if draft.port != nil {
                    TextField("端口", value: Binding(
                        get: { draft.port ?? 0 },
                        set: { draft.port = $0 }
                    ), format: .number)
                    .disabled(!draft.isEnabled)
                }
            }
            Section {
                Text("代理设置会影响套件下载、系统更新和其他需要访问互联网的功能。保存前请确认服务器地址可用。")
                    .foregroundStyle(.secondary)
                HStack {
                    Spacer()
                    Button("恢复") { draft = original }
                        .disabled(draft == original || isSaving)
                    Button("应用更改") { isConfirming = true }
                        .buttonStyle(.borderedProminent)
                        .disabled(draft == original || isSaving)
                }
            }
        }
        .formStyle(.grouped)
        .confirmationDialog(
            "应用代理设置？",
            isPresented: $isConfirming,
            titleVisibility: .visible
        ) {
            Button("应用更改") { save() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("错误的设置可能使 NAS 无法访问互联网。保存后将重新读取 NAS，确认设置确实生效。")
        }
        .alert("无法保存设置", isPresented: errorBinding) {
            Button("好") {}
        } message: {
            Text(errorMessage ?? "请稍后重试。")
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    private func save() {
        Task {
            do {
                try await onSave(draft)
            } catch {
                errorMessage = userMessage(for: error, fallback: "设置未保存，请稍后重试。")
            }
        }
    }
}

private struct FileServiceSettingsView: View {
    @State private var draft: NasFileServiceSettings
    @State private var isConfirming = false
    @State private var errorMessage: String?
    let original: NasFileServiceSettings
    let isSaving: Bool
    let onSave: (NasFileServiceSettings) async throws -> Void

    init(
        settings: NasFileServiceSettings,
        isSaving: Bool,
        onSave: @escaping (NasFileServiceSettings) async throws -> Void
    ) {
        _draft = State(initialValue: settings)
        original = settings
        self.isSaving = isSaving
        self.onSave = onSave
    }

    var body: some View {
        Form {
            Section("局域网共享") {
                optionalToggle("SMB 文件共享", value: $draft.isSMBEnabled)
                optionalToggle("NFS 文件共享", value: $draft.isNFSEnabled)
            }
            Section("文件传输") {
                optionalToggle("FTP", value: $draft.isFTPEnabled)
                optionalToggle("加密 FTP", value: $draft.isFTPSEnabled)
                optionalPort("FTP 端口", value: $draft.ftpPort)
                optionalToggle("SFTP", value: $draft.isSFTPEnabled)
                optionalPort("SFTP 端口", value: $draft.sftpPort)
            }
            if draft.isSSDPEnabled != nil
                || draft.isBonjourEnabled != nil
                || draft.isSMBTimeMachineEnabled != nil {
                Section("局域网发现") {
                    optionalToggle("允许媒体设备发现 NAS", value: $draft.isSSDPEnabled)
                    optionalToggle("允许 Apple 设备发现 NAS", value: $draft.isBonjourEnabled)
                    optionalToggle(
                        "通过 SMB 提供 Time Machine",
                        value: $draft.isSMBTimeMachineEnabled
                    )
                }
            }
            Section {
                Text("开启服务会允许其他设备连接这台 NAS。请只启用确实需要的服务，并确认路由器和防火墙设置安全。")
                    .foregroundStyle(.secondary)
                HStack {
                    Spacer()
                    Button("恢复") { draft = original }
                        .disabled(draft == original || isSaving)
                    Button("应用更改") { isConfirming = true }
                        .buttonStyle(.borderedProminent)
                        .disabled(draft == original || isSaving)
                }
            }
        }
        .formStyle(.grouped)
        .confirmationDialog(
            "应用文件服务更改？",
            isPresented: $isConfirming,
            titleVisibility: .visible
        ) {
            Button("应用更改") { save() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("连接中的设备可能会短暂断开。保存后将重新读取 NAS，确认设置确实生效。")
        }
        .alert("无法保存设置", isPresented: errorBinding) {
            Button("好") {}
        } message: {
            Text(errorMessage ?? "请稍后重试。")
        }
    }

    @ViewBuilder
    private func optionalToggle(_ title: String, value: Binding<Bool?>) -> some View {
        if value.wrappedValue != nil {
            Toggle(title, isOn: Binding(
                get: { value.wrappedValue ?? false },
                set: { value.wrappedValue = $0 }
            ))
        }
    }

    @ViewBuilder
    private func optionalPort(_ title: String, value: Binding<Int?>) -> some View {
        if value.wrappedValue != nil {
            TextField(title, value: Binding(
                get: { value.wrappedValue ?? 0 },
                set: { value.wrappedValue = $0 }
            ), format: .number)
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    private func save() {
        Task {
            do {
                try await onSave(draft)
            } catch {
                errorMessage = userMessage(for: error, fallback: "设置未保存，请稍后重试。")
            }
        }
    }
}

private struct TerminalSettingsView: View {
    @State private var draft: NasTerminalSettings
    @State private var isConfirming = false
    @State private var errorMessage: String?
    let original: NasTerminalSettings
    let isSaving: Bool
    let onSave: (NasTerminalSettings) async throws -> Void

    init(
        settings: NasTerminalSettings,
        isSaving: Bool,
        onSave: @escaping (NasTerminalSettings) async throws -> Void
    ) {
        _draft = State(initialValue: settings)
        original = settings
        self.isSaving = isSaving
        self.onSave = onSave
    }

    var body: some View {
        Form {
            Section("远程连接") {
                Toggle("允许 SSH 连接", isOn: $draft.isSSHEnabled)
                Toggle("允许 Telnet 连接", isOn: $draft.isTelnetEnabled)
                if draft.sshPort != nil {
                    TextField("SSH 端口", value: Binding(
                        get: { draft.sshPort ?? 0 },
                        set: { draft.sshPort = $0 }
                    ), format: .number)
                }
            }
            Section {
                Text("Telnet 不会加密传输内容，除非旧设备确实需要，否则建议保持关闭。更改 SSH 端口可能会断开现有连接。")
                    .foregroundStyle(.secondary)
                HStack {
                    Spacer()
                    Button("恢复") { draft = original }
                        .disabled(draft == original || isSaving)
                    Button("应用更改") { isConfirming = true }
                        .buttonStyle(.borderedProminent)
                        .disabled(draft == original || isSaving)
                }
            }
        }
        .formStyle(.grouped)
        .confirmationDialog(
            "应用远程连接更改？",
            isPresented: $isConfirming,
            titleVisibility: .visible
        ) {
            Button("应用更改") { save() }
            Button("取消", role: .cancel) {}
        } message: {
            Text("现有远程连接可能会断开。保存后将重新读取 NAS，确认设置确实生效。")
        }
        .alert("无法保存设置", isPresented: errorBinding) {
            Button("好") {}
        } message: {
            Text(errorMessage ?? "请稍后重试。")
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    private func save() {
        Task {
            do {
                try await onSave(draft)
            } catch {
                errorMessage = userMessage(for: error, fallback: "设置未保存，请稍后重试。")
            }
        }
    }
}

private struct NasAdministrationSplitView<Page: Hashable, Content: View>: View {
    let pages: [Page]
    @Binding var selection: Page
    let label: (Page) -> (String, String)
    @ViewBuilder let content: () -> Content

    var body: some View {
        HSplitView {
            VStack(alignment: .leading, spacing: 0) {
                List(pages, id: \.self, selection: $selection) { page in
                    let item = label(page)
                    Label(item.0, systemImage: item.1)
                        .tag(page)
                        .padding(.vertical, 3)
                }
                .listStyle(.sidebar)
            }
            .frame(minWidth: 190, idealWidth: 220, maxWidth: 260)

            content()
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

private struct AdministrationPageContainer<Content: View>: View {
    let isLoading: Bool
    let hasLoaded: Bool
    let hasContent: Bool
    let errorMessage: String?
    let emptyTitle: String
    let emptyDescription: String
    let retry: () async -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        ZStack(alignment: .top) {
            if hasContent {
                content()
            } else if isLoading || !hasLoaded, errorMessage == nil {
                LoadingAdministrationView()
            } else if let errorMessage {
                AdministrationErrorView(message: errorMessage) {
                    Task { await retry() }
                }
            } else {
                ContentUnavailableView(
                    emptyTitle,
                    systemImage: "tray",
                    description: Text(emptyDescription)
                )
            }

            if isLoading, hasContent {
                ProgressView()
                    .controlSize(.small)
                    .padding(8)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.top, 10)
                    .accessibilityLabel("正在更新")
            }
        }
    }
}



private struct SystemInfoBadge: View {
    let icon: String
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(label + ":")
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.primary)
        }
    }
}

private struct PerformanceChartCard<ChartContent: View>: View {
    let title: String
    let subtitle: String
    let unit: String
    let chart: ChartContent

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.headline)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Text(unit)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.primary.opacity(0.05), in: Capsule())
            }
            chart.frame(height: 140)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 215, maxHeight: 215, alignment: .topLeading)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.8), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }
}

private struct MetricCard: View {
    let title: String
    let value: String
    let icon: String
    var progress: Double?
    var tint: Color = .blue

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(tint)
                Text(title)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(value)
                .font(.title3.weight(.bold))
                .contentTransition(.numericText())
                .monospacedDigit()
                .foregroundStyle(.primary)

            Spacer(minLength: 0)

            if let progress {
                ProgressView(value: min(100, max(0, progress)), total: 100)
                    .tint(tint)
                    .controlSize(.small)
                    .accessibilityLabel(title)
                    .accessibilityValue(value)
            } else {
                Color.clear.frame(height: 6)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 76, maxHeight: 76, alignment: .topLeading)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.8), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }
}

private enum UnifiedStorageSection: String, CaseIterable, Identifiable {
    case overview = "总览"
    case analysis = "空间分析"
    case hardware = "存储池与硬盘"

    var id: Self { self }
}

private enum StorageReportSection: String, CaseIterable, Identifiable {
    case shares = "共享文件夹"
    case types = "文件类型"
    case largeFiles = "大文件"
    case duplicates = "重复文件"
    case owners = "所有者"
    case activity = "文件时间"

    var id: Self { self }
}

private struct UnifiedStorageView: View {
    let snapshot: NasStorageSnapshot?
    let usageHistory: [StorageUsagePoint]
    let analysis: StorageAnalysisSnapshot?
    let analysisProgress: StorageAnalysisProgress?
    let analysisError: String?
    let isAnalyzing: Bool
    let testStatuses: [String: NasDiskTestStatus]
    let busyDiskIDs: Set<String>
    let refresh: () async -> Void
    let beginAnalysis: () -> Void
    let cancelAnalysis: () -> Void
    let loadTestStatus: (String) async throws -> Void
    let startTest: (String, NasDiskTestType) async throws -> Void
    let stopTest: (String) async throws -> Void

    @State private var section: UnifiedStorageSection = .overview

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Picker("存储管理内容", selection: $section) {
                    ForEach(UnifiedStorageSection.allCases) { item in
                        Text(item.rawValue).tag(item)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 520)

                Spacer()

                Button {
                    Task { await refresh() }
                } label: {
                    Label("刷新", systemImage: "arrow.clockwise")
                }
                .help("刷新容量和硬盘状态")
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 14)

            Divider()

            switch section {
            case .overview:
                StorageOverviewDashboard(
                    snapshot: snapshot,
                    usageHistory: usageHistory,
                    analysis: analysis,
                    showAnalysis: { section = .analysis },
                    showHardware: { section = .hardware }
                )
            case .analysis:
                StorageAnalysisView(
                    snapshot: analysis,
                    progress: analysisProgress,
                    errorMessage: analysisError,
                    isAnalyzing: isAnalyzing,
                    beginAnalysis: beginAnalysis,
                    cancelAnalysis: cancelAnalysis
                )
            case .hardware:
                StorageView(
                    snapshot: snapshot,
                    testStatuses: testStatuses,
                    busyDiskIDs: busyDiskIDs,
                    loadTestStatus: loadTestStatus,
                    startTest: startTest,
                    stopTest: stopTest
                )
            }
        }
    }
}

private struct StorageOverviewDashboard: View {
    let snapshot: NasStorageSnapshot?
    let usageHistory: [StorageUsagePoint]
    let analysis: StorageAnalysisSnapshot?
    let showAnalysis: () -> Void
    let showHardware: () -> Void

    private var totalBytes: Int64 {
        snapshot?.volumes.reduce(Int64(0)) { $0 + max($1.totalBytes ?? 0, 0) } ?? 0
    }

    private var usedBytes: Int64 {
        snapshot?.volumes.reduce(Int64(0)) { $0 + max($1.usedBytes ?? 0, 0) } ?? 0
    }

    private var availableBytes: Int64 {
        max(totalBytes - usedBytes, 0)
    }

    private var hasWarning: Bool {
        isWarning(snapshot?.overallStatus)
            || (snapshot?.disks.contains { isWarning($0.status) || isWarning($0.smartStatus) } ?? false)
            || (snapshot?.pools.contains { isWarning($0.status) } ?? false)
            || (snapshot?.volumes.contains { isWarning($0.status) } ?? false)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Label(
                    "统一存储管理合并了“存储管理器”和“存储空间分析器”的常用功能。",
                    systemImage: "square.grid.2x2"
                )
                .font(.callout)
                .foregroundStyle(.secondary)

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 12)], spacing: 12) {
                    StorageMetricCard(
                        title: "总容量",
                        value: byteCount(totalBytes),
                        detail: "\(snapshot?.volumes.count ?? 0) 个存储空间",
                        icon: "externaldrive.fill",
                        tint: .blue
                    )
                    StorageMetricCard(
                        title: "已使用",
                        value: byteCount(usedBytes),
                        detail: totalBytes > 0
                            ? "\((Double(usedBytes) / Double(totalBytes) * 100).formatted(.number.precision(.fractionLength(1))))%"
                            : "尚无容量数据",
                        icon: "chart.pie.fill",
                        tint: .indigo
                    )
                    StorageMetricCard(
                        title: "可用空间",
                        value: byteCount(availableBytes),
                        detail: "当前可写容量",
                        icon: "internaldrive",
                        tint: .teal
                    )
                    StorageMetricCard(
                        title: "整体状态",
                        value: hasWarning ? "需要关注" : "良好",
                        detail: "\(snapshot?.pools.count ?? 0) 个存储池 · \(snapshot?.disks.count ?? 0) 块硬盘",
                        icon: hasWarning ? "exclamationmark.triangle.fill" : "checkmark.circle.fill",
                        tint: hasWarning ? .orange : .green
                    )
                }

                if !usageHistory.isEmpty {
                    GroupBox("容量趋势") {
                        Chart(usageHistory) { point in
                            LineMark(
                                x: .value("时间", point.recordedAt),
                                y: .value("已使用", point.usedBytes)
                            )
                            .foregroundStyle(by: .value("存储空间", point.volumeName))
                            PointMark(
                                x: .value("时间", point.recordedAt),
                                y: .value("已使用", point.usedBytes)
                            )
                            .foregroundStyle(by: .value("存储空间", point.volumeName))
                        }
                        .chartYAxis {
                            AxisMarks(format: .byteCount(style: .file))
                        }
                        .frame(height: 220)
                        .padding(.top, 8)
                        .accessibilityLabel("各存储空间已使用容量趋势")
                    }
                }

                HStack(alignment: .top, spacing: 12) {
                    StorageOverviewActionCard(
                        title: "空间分析",
                        description: analysis.map {
                            "上次分析 \($0.generatedAt.formatted(date: .abbreviated, time: .shortened))，共 \($0.scannedFileCount.formatted()) 个文件。"
                        } ?? "查看共享文件夹、文件类型、大文件、重复文件和所有者占用。",
                        icon: "chart.bar.xaxis",
                        actionTitle: analysis == nil ? "开始查看" : "查看报告",
                        action: showAnalysis
                    )
                    StorageOverviewActionCard(
                        title: "存储池与硬盘",
                        description: "查看 RAID、文件系统、硬盘温度、健康状态和 S.M.A.R.T. 检测。",
                        icon: "internaldrive",
                        actionTitle: "查看硬件",
                        action: showHardware
                    )
                }
            }
            .padding(24)
        }
    }
}

private struct StorageMetricCard: View {
    let title: String
    let value: String
    let detail: String
    let icon: String
    let tint: Color

    var body: some View {
        GroupBox {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(tint)
                    .frame(width: 34, height: 34)
                    .background(tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 9))
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(value)
                        .font(.title3.weight(.semibold))
                        .monospacedDigit()
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(4)
        }
    }
}

private struct StorageOverviewActionCard: View {
    let title: String
    let description: String
    let icon: String
    let actionTitle: String
    let action: () -> Void

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Label(title, systemImage: icon)
                    .font(.headline)
                Text(description)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 42, alignment: .topLeading)
                Button(actionTitle, action: action)
            }
            .padding(4)
        }
        .frame(maxWidth: .infinity)
    }
}

private struct StorageAnalysisView: View {
    let snapshot: StorageAnalysisSnapshot?
    let progress: StorageAnalysisProgress?
    let errorMessage: String?
    let isAnalyzing: Bool
    let beginAnalysis: () -> Void
    let cancelAnalysis: () -> Void

    @State private var reportSection: StorageReportSection = .shares

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("空间分析")
                            .font(.title2.weight(.semibold))
                        Text("按当前账号可见的共享文件夹生成报告；分析只读取文件信息，不会修改或删除内容。")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if isAnalyzing {
                        Button("停止分析", role: .cancel, action: cancelAnalysis)
                    } else {
                        Button {
                            beginAnalysis()
                        } label: {
                            Label(snapshot == nil ? "开始分析" : "重新分析", systemImage: "play.fill")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }

                if isAnalyzing {
                    GroupBox {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(progress?.title ?? "正在分析")
                                .font(.headline)
                            if let fraction = progress?.fraction {
                                ProgressView(value: fraction)
                            } else {
                                ProgressView()
                                    .controlSize(.small)
                            }
                            if let progress, progress.total > 0 {
                                Text("\(min(progress.completed + 1, progress.total)) / \(progress.total)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(4)
                    }
                }

                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
                }

                if let snapshot {
                    analysisContent(snapshot)
                } else if !isAnalyzing {
                    ContentUnavailableView {
                        Label("还没有分析报告", systemImage: "chart.bar.doc.horizontal")
                    } description: {
                        Text("开始分析后，可查看共享文件夹占用、文件类型、大文件、重复文件和所有者分布。")
                    } actions: {
                        Button("开始分析", action: beginAnalysis)
                    }
                    .frame(maxWidth: .infinity, minHeight: 320)
                }
            }
            .padding(24)
        }
    }

    @ViewBuilder
    private func analysisContent(_ snapshot: StorageAnalysisSnapshot) -> some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 12)], spacing: 12) {
            StorageMetricCard(
                title: "已分析文件",
                value: snapshot.scannedFileCount.formatted(),
                detail: "本次报告",
                icon: "doc.on.doc",
                tint: .blue
            )
            StorageMetricCard(
                title: "文件占用",
                value: byteCount(snapshot.scannedBytes),
                detail: "不含套件数据和快照",
                icon: "chart.pie.fill",
                tint: .indigo
            )
            StorageMetricCard(
                title: "共享文件夹",
                value: snapshot.shares.count.formatted(),
                detail: "当前账号可见",
                icon: "folder.fill",
                tint: .teal
            )
            StorageMetricCard(
                title: "可整理重复内容",
                value: byteCount(snapshot.duplicateGroups.reduce(Int64(0)) { $0 + $1.reclaimableBytes }),
                detail: "\(snapshot.duplicateGroups.count) 组内容相同的文件",
                icon: "square.on.square",
                tint: .orange
            )
        }

        HStack {
            Picker("报告内容", selection: $reportSection) {
                ForEach(StorageReportSection.allCases) { item in
                    Text(item.rawValue).tag(item)
                }
            }
            .pickerStyle(.segmented)
            Spacer()
            Text(snapshot.generatedAt.formatted(date: .abbreviated, time: .shortened))
                .font(.caption)
                .foregroundStyle(.secondary)
        }

        switch reportSection {
        case .shares:
            StorageUsageBars(
                title: "共享文件夹占用",
                rows: snapshot.shares.map { ($0.name, $0.usedBytes, $0.fileCount) }
            )
        case .types:
            StorageUsageBars(
                title: "文件类型分布",
                rows: snapshot.categories.map { ($0.name, $0.usedBytes, $0.fileCount) }
            )
        case .largeFiles:
            StorageFileList(title: "最大的 200 个文件", files: snapshot.largeFiles, dateKind: nil)
        case .duplicates:
            StorageDuplicateList(snapshot: snapshot)
        case .owners:
            StorageUsageBars(
                title: "所有者占用",
                rows: snapshot.owners.map { ($0.name, $0.usedBytes, $0.fileCount) }
            )
        case .activity:
            VStack(alignment: .leading, spacing: 16) {
                StorageFileList(
                    title: "最近修改",
                    files: snapshot.recentlyModifiedFiles,
                    dateKind: .modified
                )
                StorageFileList(
                    title: "最久未访问",
                    files: snapshot.leastRecentlyAccessedFiles,
                    dateKind: .accessed
                )
            }
        }
    }
}

private struct StorageUsageBars: View {
    let title: String
    let rows: [(name: String, bytes: Int64, count: Int)]

    var body: some View {
        GroupBox(title) {
            VStack(alignment: .leading, spacing: 14) {
                if rows.isEmpty {
                    Text("没有可显示的数据")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 120)
                } else {
                    Chart(Array(rows.prefix(12)), id: \.name) { row in
                        BarMark(
                            x: .value("占用", row.bytes),
                            y: .value("项目", row.name)
                        )
                        .foregroundStyle(.blue.gradient)
                    }
                    .chartXAxis {
                        AxisMarks(format: .byteCount(style: .file))
                    }
                    .frame(height: max(220, CGFloat(min(rows.count, 12)) * 30))
                    .accessibilityLabel(title)

                    Divider()

                    ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                        HStack {
                            Text(row.name)
                                .lineLimit(1)
                            Spacer()
                            Text("\(row.count.formatted()) 个文件")
                                .foregroundStyle(.secondary)
                            Text(byteCount(row.bytes))
                                .monospacedDigit()
                                .frame(minWidth: 90, alignment: .trailing)
                        }
                        .font(.callout)
                    }
                }
            }
            .padding(6)
        }
    }
}

private enum StorageFileDateKind {
    case modified
    case accessed
}

private struct StorageFileList: View {
    let title: String
    let files: [FileItem]
    let dateKind: StorageFileDateKind?

    var body: some View {
        GroupBox(title) {
            LazyVStack(spacing: 0) {
                if files.isEmpty {
                    Text("没有可显示的文件")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 120)
                } else {
                    ForEach(files) { file in
                        HStack(spacing: 10) {
                            Image(systemName: "doc")
                                .foregroundStyle(.secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(file.name)
                                    .lineLimit(1)
                                Text(file.path)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .textSelection(.enabled)
                            }
                            Spacer()
                            if let date = date(for: file) {
                                Text(date.formatted(date: .abbreviated, time: .shortened))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Text(byteCount(file.sizeBytes))
                                .font(.callout.monospacedDigit())
                                .frame(minWidth: 90, alignment: .trailing)
                        }
                        .padding(.vertical, 8)
                        if file.id != files.last?.id {
                            Divider()
                        }
                    }
                }
            }
            .padding(6)
        }
    }

    private func date(for file: FileItem) -> Date? {
        switch dateKind {
        case .modified: file.times?.modifiedAt
        case .accessed: file.times?.accessedAt
        case nil: nil
        }
    }
}

private struct StorageDuplicateList: View {
    let snapshot: StorageAnalysisSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if snapshot.duplicateCheckUnavailable {
                Label(
                    "这台 NAS 暂不能校验文件内容；其他分析结果不受影响。",
                    systemImage: "info.circle"
                )
                .foregroundStyle(.secondary)
            } else if snapshot.duplicateCheckWasLimited {
                Label(
                    "为避免长时间占用硬盘，本次优先校验了较大的 400 个候选文件。",
                    systemImage: "info.circle"
                )
                .foregroundStyle(.secondary)
            }

            if snapshot.duplicateGroups.isEmpty {
                ContentUnavailableView(
                    "没有发现重复内容",
                    systemImage: "checkmark.circle",
                    description: Text("在本次已校验的文件中，没有发现内容完全相同的文件。")
                )
                .frame(maxWidth: .infinity, minHeight: 220)
            } else {
                ForEach(snapshot.duplicateGroups) { group in
                    GroupBox {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text("\(group.files.count) 个相同文件")
                                    .font(.headline)
                                Spacer()
                                Text("可整理 \(byteCount(group.reclaimableBytes))")
                                    .foregroundStyle(.orange)
                            }
                            ForEach(group.files) { file in
                                HStack {
                                    Text(file.path)
                                        .lineLimit(1)
                                        .textSelection(.enabled)
                                    Spacer()
                                    Text(byteCount(file.sizeBytes))
                                        .foregroundStyle(.secondary)
                                        .monospacedDigit()
                                }
                                .font(.callout)
                            }
                        }
                        .padding(4)
                    }
                }
            }
        }
    }
}

private struct StorageView: View {
    let snapshot: NasStorageSnapshot?
    let testStatuses: [String: NasDiskTestStatus]
    let busyDiskIDs: Set<String>
    let loadTestStatus: (String) async throws -> Void
    let startTest: (String, NasDiskTestType) async throws -> Void
    let stopTest: (String) async throws -> Void

    @State private var selection: StorageDetailSelection?

    var body: some View {
        ScrollView {
            if let snapshot {
                VStack(alignment: .leading, spacing: 22) {
                    SectionHeader(title: "存储空间", count: snapshot.volumes.count)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 12)], spacing: 12) {
                        ForEach(snapshot.volumes) { volume in
                            Button {
                                selection = .volume(volume)
                            } label: {
                                CapacityCard(
                                    title: volume.name,
                                    subtitle: [volume.fileSystem, storageStatusText(volume.status)]
                                        .compactMap { $0 }
                                        .joined(separator: " · "),
                                    used: volume.usedBytes,
                                    total: volume.totalBytes,
                                    icon: "externaldrive"
                                )
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint("查看存储空间详情")
                        }
                    }

                    SectionHeader(title: "存储池", count: snapshot.pools.count)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 12)], spacing: 12) {
                        ForEach(snapshot.pools) { pool in
                            Button {
                                selection = .pool(pool)
                            } label: {
                                CapacityCard(
                                    title: pool.name,
                                    subtitle: [pool.raidType, storageStatusText(pool.status)]
                                        .compactMap { $0 }
                                        .joined(separator: " · "),
                                    used: pool.usedBytes,
                                    total: pool.totalBytes,
                                    icon: "square.stack.3d.up"
                                )
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint("查看存储池详情")
                        }
                    }

                    SectionHeader(title: "硬盘", count: snapshot.disks.count)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 12)], spacing: 12) {
                        ForEach(snapshot.disks) { disk in
                            Button {
                                selection = .disk(disk)
                            } label: {
                                DiskCard(disk: disk, testStatus: testStatuses[disk.id])
                            }
                            .buttonStyle(.plain)
                            .accessibilityHint("查看硬盘详情和检测选项")
                        }
                    }
                }
                .padding(24)
            }
        }
        .sheet(item: $selection) { selection in
            StorageDetailSheet(
                selection: selection,
                snapshot: snapshot,
                testStatus: {
                    guard case .disk(let disk) = selection else { return nil }
                    return testStatuses[disk.id]
                }(),
                isDiskBusy: {
                    guard case .disk(let disk) = selection else { return false }
                    return busyDiskIDs.contains(disk.id)
                }(),
                loadTestStatus: loadTestStatus,
                startTest: startTest,
                stopTest: stopTest
            )
        }
    }
}

private enum DisplayMode: String, CaseIterable, Identifiable {
    case list = "列表"
    case grid = "卡片"
    var id: Self { self }

    var icon: String {
        switch self {
        case .list: "list.bullet"
        case .grid: "square.grid.2x2"
        }
    }
}

private enum StorageDetailSelection: Identifiable {
    case volume(NasVolume)
    case pool(NasStoragePool)
    case disk(NasDisk)

    var id: String {
        switch self {
        case .volume(let volume): "volume:\(volume.id)"
        case .pool(let pool): "pool:\(pool.id)"
        case .disk(let disk): "disk:\(disk.id)"
        }
    }
}

private struct CapacityCard: View {
    let title: String
    let subtitle: String
    let used: Int64?
    let total: Int64?
    let icon: String

    private var ratio: Double? {
        guard let used, let total, total > 0 else { return nil }
        return min(1, max(0, Double(used) / Double(total)))
    }

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center) {
                    Label(title, systemImage: icon)
                        .font(.headline)
                    Spacer()
                    Label("查看详情", systemImage: "chevron.right")
                        .labelStyle(.titleAndIcon)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text(used.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? "未知")
                    Spacer()
                    Text(total.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? "未知")
                        .foregroundStyle(.secondary)
                }
                .font(.caption)
                if let ratio {
                    ProgressView(value: ratio)
                        .accessibilityLabel(title)
                        .accessibilityValue("\((ratio * 100).formatted(.number.precision(.fractionLength(0))))% 已使用")
                }
            }
            .padding(6)
            .contentShape(Rectangle())
        }
    }
}

private struct DiskCard: View {
    let disk: NasDisk
    let testStatus: NasDiskTestStatus?

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center) {
                    Label(disk.name, systemImage: disk.isSSD ? "memorychip" : "internaldrive")
                        .font(.headline)
                    Spacer()
                    HStack(spacing: 8) {
                        StatusPill(
                            text: storageStatusText(disk.status) ?? "状态未知",
                            isWarning: isWarning(disk.status)
                        )
                        Label("查看详情", systemImage: "chevron.right")
                            .labelStyle(.titleAndIcon)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if let model = disk.model {
                    Text([disk.vendor, model].compactMap { $0 }.joined(separator: " "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                VStack(spacing: 6) {
                    HStack {
                        Text("容量").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Text(byteCount(disk.totalBytes)).font(.caption.weight(.medium))
                    }
                    HStack {
                        Text("S.M.A.R.T.").font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Text(
                            testStatus?.isRunning == true
                                ? "正在检测"
                                : storageStatusText(disk.smartStatus)
                                    ?? (disk.supportsSmartTest ? "可检测" : "未提供")
                        ).font(.caption.weight(.medium))
                    }
                    if let temperature = disk.temperatureCelsius {
                        HStack {
                            Text("温度").font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Text("\(temperature.formatted(.number.precision(.fractionLength(0))))℃")
                                .font(.caption.weight(.medium))
                        }
                    }
                }
            }
            .padding(6)
            .contentShape(Rectangle())
        }
    }
}

private struct StorageDetailSheet: View {
    let selection: StorageDetailSelection
    let snapshot: NasStorageSnapshot?
    let testStatus: NasDiskTestStatus?
    let isDiskBusy: Bool
    let loadTestStatus: (String) async throws -> Void
    let startTest: (String, NasDiskTestType) async throws -> Void
    let stopTest: (String) async throws -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var pendingTestType: NasDiskTestType?
    @State private var showStopTestConfirm = false
    @State private var isLoadingStatus = false
    @State private var message: String?
    @State private var testStatusError: String?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    switch selection {
                    case .volume(let volume):
                        volumeDetails(volume)
                    case .pool(let pool):
                        poolDetails(pool)
                    case .disk(let disk):
                        diskDetails(disk)
                    }
                }
                .padding(24)
            }
            .navigationTitle(title)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                        .keyboardShortcut(.cancelAction)
                }
            }
        }
        .frame(minWidth: 560, idealWidth: 600, minHeight: 480, idealHeight: 580)
        .confirmationDialog(
            pendingTestType == .extended ? "开始完整检测？" : "开始快速检测？",
            isPresented: Binding(
                get: { pendingTestType != nil },
                set: { if !$0 { pendingTestType = nil } }
            ),
            titleVisibility: .visible
        ) {
            if let pendingTestType {
                Button(pendingTestType == .extended ? "开始完整检测" : "开始快速检测") {
                    beginTest(pendingTestType)
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text(testConfirmationMessage)
        }
        .confirmationDialog(
            "停止当前硬盘检测？",
            isPresented: $showStopTestConfirm,
            titleVisibility: .visible
        ) {
            Button("继续检测", role: .cancel) {}
            Button("停止检测", role: .destructive) {
                stopCurrentTest()
            }
        } message: {
            Text("停止后，本次检测不会产生完整结果；以后仍可重新开始检测。")
        }
    }

    private var title: String {
        switch selection {
        case .volume(let volume): volume.name
        case .pool(let pool): pool.name
        case .disk(let disk): "\(disk.name) 详情"
        }
    }

    @ViewBuilder
    private func volumeDetails(_ volume: NasVolume) -> some View {
        detailHeader(
            icon: "externaldrive",
            title: volume.name,
            status: volume.status
        )
        DetailSection(title: "容量") {
            DetailValueRow(title: "已使用", value: byteCount(volume.usedBytes))
            Divider().opacity(0.4)
            DetailValueRow(title: "总容量", value: byteCount(volume.totalBytes))
            Divider().opacity(0.4)
            DetailValueRow(
                title: "可用容量",
                value: byteCount(availableBytes(used: volume.usedBytes, total: volume.totalBytes))
            )
        }
        DetailSection(title: "信息") {
            DetailValueRow(title: "文件系统", value: volume.fileSystem ?? "未提供")
            Divider().opacity(0.4)
            DetailValueRow(title: "所在存储池", value: poolName(for: volume.poolID) ?? "未提供")
            Divider().opacity(0.4)
            DetailValueRow(title: "位置", value: volume.path ?? "未提供")
            Divider().opacity(0.4)
            DetailValueRow(title: "加密", value: volume.isEncrypted ? "已加密" : "未加密")
            Divider().opacity(0.4)
            DetailValueRow(title: "访问状态", value: volume.isWritable ? "可读写" : "只读")
        }
    }

    @ViewBuilder
    private func poolDetails(_ pool: NasStoragePool) -> some View {
        detailHeader(
            icon: "square.stack.3d.up",
            title: pool.name,
            status: pool.status
        )
        DetailSection(title: "容量") {
            DetailValueRow(title: "已使用", value: byteCount(pool.usedBytes))
            Divider().opacity(0.4)
            DetailValueRow(title: "总容量", value: byteCount(pool.totalBytes))
            Divider().opacity(0.4)
            DetailValueRow(
                title: "可用容量",
                value: byteCount(availableBytes(used: pool.usedBytes, total: pool.totalBytes))
            )
        }
        DetailSection(title: "配置") {
            DetailValueRow(title: "RAID 类型", value: pool.raidType ?? "未提供")
            Divider().opacity(0.4)
            DetailValueRow(title: "访问状态", value: pool.isWritable ? "可读写" : "只读")
            Divider().opacity(0.4)
            DetailValueRow(
                title: "多个存储空间",
                value: pool.supportsMultipleVolumes.map { $0 ? "支持" : "不支持" } ?? "未提供"
            )
            Divider().opacity(0.4)
            DetailValueRow(title: "硬盘", value: diskNames(for: pool.diskIDs))
            Divider().opacity(0.4)
            DetailValueRow(title: "热备盘", value: diskNames(for: pool.spareDiskIDs))
            if pool.isScrubbing {
                Divider().opacity(0.4)
                DetailValueRow(title: "数据清理", value: "正在进行")
            } else if let date = pool.nextScrubbingDate {
                Divider().opacity(0.4)
                DetailValueRow(
                    title: "下次数据清理",
                    value: date.formatted(date: .abbreviated, time: .shortened)
                )
            }
        }
    }

    @ViewBuilder
    private func diskDetails(_ disk: NasDisk) -> some View {
        detailHeader(
            icon: disk.isSSD ? "memorychip" : "internaldrive",
            title: disk.name,
            status: disk.status
        )

        if let message {
            Label(message, systemImage: "info.circle.fill")
                .font(.callout)
                .foregroundStyle(.primary)
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
                .accessibilityElement(children: .combine)
        }

        DetailSection(title: "硬盘信息") {
            DetailValueRow(
                title: "型号",
                value: diskModelDescription(disk)
            )
            Divider().opacity(0.4)
            DetailValueRow(title: "类型", value: disk.type ?? (disk.isSSD ? "SSD" : "HDD"))
            Divider().opacity(0.4)
            DetailValueRow(title: "容量", value: byteCount(disk.totalBytes))
            Divider().opacity(0.4)
            DetailValueRow(title: "位置", value: disk.location ?? "未提供")
            Divider().opacity(0.4)
            DetailValueRow(title: "配置用途", value: poolName(for: disk.usedBy) ?? "未分配")
            Divider().opacity(0.4)
            DetailValueRow(title: "序列号", value: disk.serialNumber ?? "未提供")
            Divider().opacity(0.4)
            DetailValueRow(title: "固件版本", value: disk.firmwareVersion ?? "未提供")
            Divider().opacity(0.4)
            DetailValueRow(
                title: "4K 原生硬盘",
                value: disk.is4KNative.map { $0 ? "是" : "否" } ?? "未提供"
            )
        }

        DetailSection(title: "健康状态") {
            DetailValueRow(
                title: "S.M.A.R.T.",
                value: storageStatusText(disk.smartStatus) ?? "未提供"
            )
            if let temperature = disk.temperatureCelsius {
                Divider().opacity(0.4)
                DetailValueRow(
                    title: "温度",
                    value: "\(temperature.formatted(.number.precision(.fractionLength(0))))℃"
                )
            }
            if let estimatedLifePercent = disk.estimatedLifePercent {
                Divider().opacity(0.4)
                DetailValueRow(title: "预计寿命", value: "\(estimatedLifePercent)%")
            }
            if let badSectorCount = disk.badSectorCount {
                Divider().opacity(0.4)
                DetailValueRow(title: "坏扇数", value: badSectorCount.formatted())
            }
        }

        smartTestSection(disk)
            .task(id: disk.id) {
                await refreshTestStatus(disk.id, reportsError: true)
            }
            .task(id: testStatus?.isRunning) {
                while testStatus?.isRunning == true, !Task.isCancelled {
                    do {
                        try await Task.sleep(for: .seconds(4))
                    } catch {
                        return
                    }
                    await refreshTestStatus(disk.id, reportsError: false)
                }
            }
    }

    @ViewBuilder
    private func smartTestSection(_ disk: NasDisk) -> some View {
        DetailSection(title: "S.M.A.R.T. 检测") {
            if let testStatusError {
                Label(testStatusError, systemImage: "exclamationmark.triangle.fill")
                    .font(.callout)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            } else if isLoadingStatus, testStatus == nil {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("正在读取检测状态…")
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 8)
            } else if testStatus?.isRunning == true {
                HStack(spacing: 12) {
                    ProgressView().controlSize(.small)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(testStatus?.runningType == .extended ? "正在进行完整检测" : "正在进行硬盘检测")
                            .font(.subheadline.weight(.medium))
                        if let progress = testStatus?.progressDescription, !progress.isEmpty {
                            Text(progress).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                }
                .padding(.vertical, 8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityElement(children: .combine)
            } else if testStatus?.isBusyWithOtherTest == true {
                Label(
                    "这块硬盘正在执行其他检测，完成后即可运行 S.M.A.R.T. 检测。",
                    systemImage: "clock.badge.exclamationmark"
                )
                .font(.callout)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 8)
            }

            if let testStatus {
                if testStatus.isHistoryAvailable {
                    DetailValueRow(
                        title: "上次快速检测",
                        value: smartTestTimeText(testStatus.lastQuickTest)
                    )
                    Divider().opacity(0.4)
                    DetailValueRow(
                        title: "上次完整检测",
                        value: smartTestTimeText(testStatus.lastExtendedTest)
                    )
                } else {
                    Label(
                        "暂时无法读取检测记录，可点击“刷新状态”重试。",
                        systemImage: "exclamationmark.arrow.triangle.2.circlepath"
                    )
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
                }
            }
            if let result = testStatus?.lastResult {
                Divider().opacity(0.4)
                DetailValueRow(title: "最近结果", value: smartResultText(result))
            }

            Divider().opacity(0.4).padding(.vertical, 2)

            HStack(spacing: 10) {
                if testStatus?.isRunning == true {
                    Button("停止检测…", role: .destructive) {
                        showStopTestConfirm = true
                    }
                    .disabled(isLoadingStatus || isDiskBusy)
                    .accessibilityHint("停止当前正在进行的硬盘检测")
                } else {
                    Button("快速检测…") {
                        pendingTestType = .quick
                    }
                    .disabled(!canStartTest(disk))
                    .accessibilityHint("执行基本诊断，检查机械和电气问题")

                    Button("完整检测…") {
                        pendingTestType = .extended
                    }
                    .disabled(!canStartTest(disk))
                    .accessibilityHint("扫描整块硬盘，可能需要数小时")
                }

                Spacer()

                Button {
                    Task { await refreshTestStatus(disk.id, reportsError: true) }
                } label: {
                    Label("刷新状态", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isLoadingStatus || isDiskBusy)
                .accessibilityHint("重新读取当前检测状态和历史记录")
            }
            .padding(.top, 4)

            if !disk.supportsSmartTest {
                Text("这块硬盘没有提供可用的 S.M.A.R.T. 检测功能。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)
            }
        }
    }

    private func detailHeader(icon: String, title: String, status: String?) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundStyle(Color.accentColor)
                .frame(width: 42, height: 42)
                .background(Color.accentColor.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.title2.weight(.bold))
                StatusPill(
                    text: storageStatusText(status) ?? "状态未知",
                    isWarning: isWarning(status)
                )
            }
            Spacer()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.5))
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                )
        )
    }

    private func poolName(for id: String?) -> String? {
        guard let id else { return nil }
        return snapshot?.pools.first(where: { $0.id == id })?.name
    }

    private func diskNames(for ids: [String]) -> String {
        guard !ids.isEmpty else { return "无" }
        let names = ids.map { id in
            snapshot?.disks.first(where: { $0.id == id })?.name ?? id
        }
        return names.joined(separator: "、")
    }

    private func diskModelDescription(_ disk: NasDisk) -> String {
        let value = [disk.vendor, disk.model].compactMap { $0 }.joined(separator: " ")
        return value.isEmpty ? "未提供" : value
    }

    private func smartTestTimeText(_ value: String?) -> String {
        guard let value, !value.isEmpty else { return "暂无记录" }
        let date: Date?
        if let timestamp = Double(value) {
            date = Date(
                timeIntervalSince1970: timestamp > 10_000_000_000
                    ? timestamp / 1_000
                    : timestamp
            )
        } else {
            date = ISO8601DateFormatter().date(from: value)
        }
        return date?.formatted(date: .abbreviated, time: .standard) ?? value
    }

    private func canStartTest(_ disk: NasDisk) -> Bool {
        disk.supportsSmartTest
            && testStatus != nil
            && testStatusError == nil
            && testStatus?.isRunning != true
            && testStatus?.isBusyWithOtherTest != true
            && !isLoadingStatus
            && !isDiskBusy
    }

    private var testConfirmationMessage: String {
        if pendingTestType == .extended {
            return "完整检测会扫描整块硬盘，可能需要数小时，并可能暂时影响存储性能。建议在使用较少的时段运行。"
        }
        return "快速检测会检查硬盘的基本机械和电气状态，运行期间请勿移除硬盘。"
    }

    private func beginTest(_ type: NasDiskTestType) {
        guard case .disk(let disk) = selection else { return }
        pendingTestType = nil
        message = nil
        Task {
            do {
                try await startTest(disk.id, type)
                message = type == .extended ? "完整检测已开始。" : "快速检测已开始。"
            } catch {
                message = (error as? AppError)?.safeUserMessage
                    ?? "无法开始检测，请确认硬盘空闲后重试。"
            }
        }
    }

    private func stopCurrentTest() {
        guard case .disk(let disk) = selection else { return }
        message = nil
        Task {
            do {
                try await stopTest(disk.id)
                message = "硬盘检测已停止。"
            } catch {
                message = (error as? AppError)?.safeUserMessage
                    ?? "无法停止检测，请稍后刷新状态。"
            }
        }
    }

    private func refreshTestStatus(_ diskID: String, reportsError: Bool) async {
        guard !isLoadingStatus else { return }
        isLoadingStatus = true
        if reportsError {
            testStatusError = nil
        }
        defer { isLoadingStatus = false }
        do {
            try await loadTestStatus(diskID)
            testStatusError = nil
        } catch is CancellationError {
            return
        } catch {
            if reportsError {
                testStatusError = (error as? AppError)?.safeUserMessage
                    ?? "暂时无法读取检测状态，请稍后重试。"
            }
        }
    }
}

private struct DetailSection<Content: View>: View {
    let title: String
    let content: Content

    init(title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)
                .foregroundStyle(.primary)

            VStack(alignment: .leading, spacing: 0) {
                content
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor).opacity(0.6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                    )
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct DetailValueRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(width: 110, alignment: .leading)

            Spacer(minLength: 16)

            Text(value)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.trailing)
                .textSelection(.enabled)
        }
        .padding(.vertical, 6)
        .accessibilityElement(children: .combine)
    }
}

private struct PerformanceDashboard: View {
    let overview: NasSystemOverview?
    let history: [NasPerformanceSnapshot]
    let connections: NasConnectionPage?
    @Binding var isPaused: Bool
    let refresh: () async -> Void
    let onNavigateToConnections: () -> Void
    let onPerformPowerAction: ((NasPowerAction) async throws -> Void)?
    let onCheckSystemUpdate: (() async throws -> NasSystemUpdateInfo)?

    @State private var showShutdownConfirm = false
    @State private var showRebootConfirm = false
    @State private var isPerformingPowerAction = false
    @State private var isCheckingSystemUpdate = false
    @State private var actionMessage: String? = nil
    @State private var updateAlertTitle: String = "系统更新"
    @State private var updateAlertMessage: String? = nil
    @State private var showUpdateAlert = false

    private var latest: NasPerformanceSnapshot? { history.last }

    private let mainDashboardColumns = [
        GridItem(.flexible(), spacing: 16),
        GridItem(.flexible(), spacing: 16)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                dashboardHeader

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 140, maximum: 220), spacing: 12)], spacing: 12) {
                    MetricCard(title: "处理器", value: percent(latest?.cpuUsage), icon: "cpu", progress: latest?.cpuUsage, tint: .blue)
                    MetricCard(title: "内存", value: percent(latest?.memoryUsage), icon: "memorychip", progress: latest?.memoryUsage, tint: .purple)
                    MetricCard(title: "网络接收", value: speed(latest?.networkReceivedBytesPerSecond), icon: "arrow.down", tint: .green)
                    MetricCard(title: "网络发送", value: speed(latest?.networkSentBytesPerSecond), icon: "arrow.up", tint: .teal)
                    MetricCard(title: "硬盘读取", value: speed(latest?.diskReadBytesPerSecond), icon: "internaldrive", tint: .orange)
                    MetricCard(title: "硬盘写入", value: speed(latest?.diskWriteBytesPerSecond), icon: "internaldrive.fill", tint: .indigo)
                }

                if history.isEmpty {
                    HStack(spacing: 10) {
                        ProgressView()
                        Text("正在读取实时性能数据…")
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 36)
                } else {
                    LazyVGrid(columns: mainDashboardColumns, spacing: 16) {
                        PerformanceChartCard(
                            title: "资源使用率",
                            subtitle: "处理器与内存",
                            unit: "%",
                            chart: percentageChart
                        )
                        PerformanceChartCard(
                            title: "网络速率",
                            subtitle: "接收与发送",
                            unit: "每秒",
                            chart: networkChart
                        )
                        PerformanceChartCard(
                            title: "存储速率",
                            subtitle: "读取与写入",
                            unit: "每秒",
                            chart: storageChart
                        )
                        ActiveConnectionsCard(
                            connections: connections,
                            onNavigate: onNavigateToConnections
                        )
                    }
                }
            }
            .padding(20)
        }
        .confirmationDialog("确定要关闭这台 NAS 吗？", isPresented: $showShutdownConfirm, titleVisibility: .visible) {
            Button("确认关机", role: .destructive) {
                Task {
                    guard !isPerformingPowerAction else { return }
                    isPerformingPowerAction = true
                    defer { isPerformingPowerAction = false }
                    do {
                        try await onPerformPowerAction?(.shutdown)
                        actionMessage = "NAS 已接受关机请求，连接即将中断。"
                    } catch {
                        actionMessage = "无法关闭 NAS：\(powerActionError(error))"
                    }
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("关机后将中断所有在线服务与文件共享，需人工按下物理按键方可再次开机。")
        }
        .confirmationDialog("确定要重启这台 NAS 吗？", isPresented: $showRebootConfirm, titleVisibility: .visible) {
            Button("确认重启", role: .destructive) {
                Task {
                    guard !isPerformingPowerAction else { return }
                    isPerformingPowerAction = true
                    defer { isPerformingPowerAction = false }
                    do {
                        try await onPerformPowerAction?(.reboot)
                        updateAlertTitle = "电源请求已提交"
                        updateAlertMessage = "NAS 已接受重启请求，连接与服务将暂时中断。"
                        showUpdateAlert = true
                    } catch {
                        updateAlertTitle = "无法重启 NAS"
                        updateAlertMessage = powerActionError(error)
                        showUpdateAlert = true
                    }
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            Text("重启需要数分钟时间，期间网络连接和服务将暂时不可用。")
        }
        .alert(updateAlertTitle, isPresented: $showUpdateAlert) {
            Button("确定", role: .cancel) {}
        } message: {
            if let updateAlertMessage {
                Text(updateAlertMessage)
            }
        }
    }

    private var dashboardHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 8) {
                        Text(overview?.serverName ?? "NAS")
                            .font(.title.weight(.bold))
                            .textSelection(.enabled)

                        if let model = overview?.model {
                            Text(model)
                                .font(.caption.weight(.semibold))
                                .padding(.horizontal, 8)
                                .padding(.vertical, 3)
                                .background(Color.accentColor.opacity(0.12), in: Capsule())
                                .foregroundStyle(Color.accentColor)
                        }

                        if let version = overview?.version {
                            Text(version)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                Spacer()

                HStack(spacing: 8) {
                    Button {
                        checkSystemUpdate()
                    } label: {
                        Label("检查系统更新", systemImage: "arrow.down.circle")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(isCheckingSystemUpdate)

                    Menu {
                        Button(role: .destructive) {
                            showRebootConfirm = true
                        } label: {
                            Label("重启 NAS", systemImage: "arrow.clockwise.circle")
                        }

                        Button(role: .destructive) {
                            showShutdownConfirm = true
                        } label: {
                            Label("关机", systemImage: "power")
                        }
                    } label: {
                        Label("电源操作", systemImage: "power")
                    }
                    .menuStyle(.borderedButton)
                    .controlSize(.small)
                    .disabled(isPerformingPowerAction || isCheckingSystemUpdate)

                    Button {
                        isPaused.toggle()
                    } label: {
                        Label(isPaused ? "继续更新" : "暂停更新", systemImage: isPaused ? "play.fill" : "pause.fill")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help(isPaused ? "继续读取实时数据" : "暂时停止读取实时数据")

                    Button {
                        Task { await refresh() }
                    } label: {
                        Label("刷新", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }

            if let overview {
                HStack(spacing: 16) {
                    SystemInfoBadge(icon: "cpu", label: "处理器", value: [overview.cpuModel, overview.cpuCoreCount.map { "\($0)核" }].compactMap { $0 }.joined(separator: " · "))
                    if let memory = overview.memoryBytes {
                        SystemInfoBadge(icon: "memorychip", label: "内存", value: ByteCountFormatter.string(fromByteCount: memory, countStyle: .memory))
                    }
                    if let temperature = overview.temperatureCelsius {
                        SystemInfoBadge(icon: "thermometer.medium", label: "温度", value: "\(temperature.formatted(.number.precision(.fractionLength(0))))℃")
                    }
                    if let uptime = overview.uptimeSeconds {
                        SystemInfoBadge(icon: "clock", label: "已运行", value: uptimeDescription(uptime))
                    }
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
        }
    }

    private func powerActionError(_ error: Error) -> String {
        (error as? AppError)?.safeUserMessage
            ?? "请求没有完成，请确认当前账号有管理权限后重试。"
    }

    private func checkSystemUpdate() {
        guard !isCheckingSystemUpdate, let onCheckSystemUpdate else { return }
        isCheckingSystemUpdate = true
        Task {
            defer { isCheckingSystemUpdate = false }
            do {
                let info = try await onCheckSystemUpdate()
                if info.isUpdateAvailable {
                    let version = info.latestVersion.map { " \($0)" } ?? ""
                    updateAlertTitle = "发现新版本"
                    updateAlertMessage = "发现可用的系统更新\(version)。\n\n请在 DSM 控制面板中查看说明并安排安装。"
                } else if let current = info.currentVersion {
                    updateAlertTitle = "已是最新版本"
                    updateAlertMessage = "当前系统（\(current)）已是最新版本，没有发现可用的系统更新。"
                } else {
                    updateAlertTitle = "系统更新"
                    updateAlertMessage = "当前没有发现可用的系统更新。"
                }
            } catch {
                updateAlertTitle = "检查更新失败"
                updateAlertMessage = (error as? AppError)?.safeUserMessage
                    ?? "暂时无法检查系统更新，请确认网络与系统状态后重试。"
            }
            showUpdateAlert = true
        }
    }

    private var percentageChart: some View {
        Chart(history) { point in
            AreaMark(
                x: .value("时间", point.recordedAt),
                y: .value("使用率", point.cpuUsage)
            )
            .foregroundStyle(by: .value("指标", "处理器"))

            AreaMark(
                x: .value("时间", point.recordedAt),
                y: .value("使用率", point.memoryUsage)
            )
            .foregroundStyle(by: .value("指标", "内存"))
        }
        .chartYScale(domain: 0...100)
    }

    private var networkChart: some View {
        Chart(history) { point in
            LineMark(
                x: .value("时间", point.recordedAt),
                y: .value("速率", Double(point.networkReceivedBytesPerSecond) / 1_024)
            )
            .foregroundStyle(by: .value("方向", "接收"))

            LineMark(
                x: .value("时间", point.recordedAt),
                y: .value("速率", Double(point.networkSentBytesPerSecond) / 1_024)
            )
            .foregroundStyle(by: .value("方向", "发送"))
        }
    }

    private var storageChart: some View {
        Chart(history) { point in
            LineMark(
                x: .value("时间", point.recordedAt),
                y: .value("速率", Double(point.diskReadBytesPerSecond) / 1_024)
            )
            .foregroundStyle(by: .value("操作", "读取"))

            LineMark(
                x: .value("时间", point.recordedAt),
                y: .value("速率", Double(point.diskWriteBytesPerSecond) / 1_024)
            )
            .foregroundStyle(by: .value("操作", "写入"))
        }
    }
}

private struct PackageList: View {
    let packages: [NasPackage]
    let title: String
    let busyPackageIDs: Set<String>
    let onControlPackage: ((String, NasPackageAction) async throws -> Void)?

    init(
        packages: [NasPackage],
        title: String,
        busyPackageIDs: Set<String> = [],
        onControlPackage: ((String, NasPackageAction) async throws -> Void)? = nil
    ) {
        self.packages = packages
        self.title = title
        self.busyPackageIDs = busyPackageIDs
        self.onControlPackage = onControlPackage
    }

    private enum DisplayMode: String, CaseIterable, Identifiable {
        case grid = "grid"
        case list = "list"

        var id: String { rawValue }
        var icon: String {
            switch self {
            case .grid: return "square.grid.2x2"
            case .list: return "list.bullet"
            }
        }
        var label: String {
            switch self {
            case .grid: return "卡片"
            case .list: return "列表"
            }
        }
    }

    @State private var searchText = ""
    @State private var packageToUninstall: NasPackage? = nil
    @State private var actionError: String? = nil
    @AppStorage("packageDisplayMode") private var displayModeRaw: String = DisplayMode.grid.rawValue

    private var displayMode: DisplayMode {
        get { DisplayMode(rawValue: displayModeRaw) ?? .grid }
        set { displayModeRaw = newValue.rawValue }
    }

    private var filtered: [NasPackage] {
        guard !searchText.isEmpty else { return packages }
        return packages.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
                || $0.id.localizedCaseInsensitiveContains(searchText)
                || ($0.packageDescription?.localizedCaseInsensitiveContains(searchText) ?? false)
        }
    }

    private let columns = [
        GridItem(.adaptive(minimum: 250, maximum: 380), spacing: 14)
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("共 \(filtered.count) 项")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Picker("视图模式", selection: $displayModeRaw) {
                    ForEach(DisplayMode.allCases) { mode in
                        Label(mode.label, systemImage: mode.icon).tag(mode.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 90)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            Divider()

            if filtered.isEmpty {
                ContentUnavailableView("未找到匹配的套件", systemImage: "shippingbox", description: Text("尝试输入其他关键词搜索"))
                    .frame(maxHeight: .infinity)
            } else {
                switch displayMode {
                case .grid:
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 14) {
                            ForEach(filtered) { package in
                                PackageCard(
                                    package: package,
                                    isBusy: busyPackageIDs.contains(package.id),
                                    onControl: { action in
                                        handleAction(package: package, action: action)
                                    }
                                )
                            }
                        }
                        .padding(16)
                    }
                case .list:
                    List(filtered) { package in
                        PackageRow(
                            package: package,
                            isBusy: busyPackageIDs.contains(package.id),
                            onControl: { action in
                                handleAction(package: package, action: action)
                            }
                        )
                    }
                    .listStyle(.inset)
                }
            }
        }
        .navigationTitle(title)
        .searchable(text: $searchText, prompt: "搜索套件名称或说明")
        .alert("确定要卸载此套件吗？", isPresented: Binding(
            get: { packageToUninstall != nil },
            set: { if !$0 { packageToUninstall = nil } }
        )) {
            Button("确认卸载", role: .destructive) {
                if let pkg = packageToUninstall {
                    packageToUninstall = nil
                    Task {
                        do {
                            try await onControlPackage?(pkg.id, .uninstall)
                        } catch {
                            actionError = packageActionError(
                                error,
                                packageName: pkg.name,
                                actionText: "卸载"
                            )
                        }
                    }
                }
            }
            Button("取消", role: .cancel) {}
        } message: {
            if let pkg = packageToUninstall {
                Text("将被卸载的套件：\(pkg.name)\n卸载后相关配置和应用数据可能会被清空。")
            }
        }
        .alert("套件操作提示", isPresented: Binding(
            get: { actionError != nil },
            set: { if !$0 { actionError = nil } }
        )) {
            Button("确定", role: .cancel) {}
        } message: {
            if let actionError {
                Text(actionError)
            }
        }
    }

    private func handleAction(package: NasPackage, action: NasPackageAction) {
        if action == .uninstall {
            packageToUninstall = package
            return
        }
        Task {
            do {
                try await onControlPackage?(package.id, action)
            } catch {
                let actionText = action == .stop ? "暂停" : (action == .start ? "启动" : "更新")
                actionError = packageActionError(
                    error,
                    packageName: package.name,
                    actionText: actionText
                )
            }
        }
    }

    private func packageActionError(
        _ error: Error,
        packageName: String,
        actionText: String
    ) -> String {
        let message = (error as? AppError)?.safeUserMessage
            ?? "操作没有完成，请稍后重试。"
        return "无法\(actionText)套件“\(packageName)”：\(message)"
    }
}

private struct PackageCard: View {
    let package: NasPackage
    let isBusy: Bool
    let onControl: (NasPackageAction) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                PackageIconView(package: package)

                VStack(alignment: .leading, spacing: 2) {
                    Text(package.name)
                        .font(.body.weight(.semibold))
                        .lineLimit(1)
                    Text([package.version, package.installType].compactMap { $0 }.joined(separator: " · "))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }

            if let description = package.packageDescription, !description.isEmpty {
                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, minHeight: 32, alignment: .topLeading)
            } else {
                Spacer()
                    .frame(height: 32)
            }

            HStack(alignment: .center) {
                StatusPill(
                    text: package.statusDescription ?? package.status ?? "常规",
                    isWarning: isWarning(package.status)
                )

                Spacer()

                if isBusy {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    HStack(spacing: 6) {
                        if package.canUpgrade {
                            Button {
                                triggerAction(.upgrade)
                            } label: {
                                Image(systemName: "arrow.triangle.2.circlepath")
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .help("更新套件")
                        }

                        if package.canStop {
                            Button {
                                triggerAction(.stop)
                            } label: {
                                Label("暂停", systemImage: "pause.fill")
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        } else if package.canStart {
                            Button {
                                triggerAction(.start)
                            } label: {
                                Label("启动", systemImage: "play.fill")
                            }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                        }
                    }
                }
            }
        }
        .padding(12)
        .background(Color(NSColor.controlBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
        )
        .contextMenu {
            if package.canStart {
                Button { triggerAction(.start) } label: {
                    Label("启动套件", systemImage: "play.fill")
                }
            }
            if package.canStop {
                Button { triggerAction(.stop) } label: {
                    Label("暂停套件", systemImage: "pause.fill")
                }
            }
            if package.canUpgrade {
                Button { triggerAction(.upgrade) } label: {
                    Label("更新套件", systemImage: "arrow.triangle.2.circlepath")
                }
            }
            if package.canUninstall {
                Divider()
                Button(role: .destructive) { triggerAction(.uninstall) } label: {
                    Label("卸载套件…", systemImage: "trash")
                }
            }
        }
        .disabled(isBusy)
        .accessibilityElement(children: .combine)
    }

    private func triggerAction(_ action: NasPackageAction) {
        guard !isBusy else { return }
        onControl(action)
    }
}

private struct PackageRow: View {
    let package: NasPackage
    let isBusy: Bool
    let onControl: (NasPackageAction) -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            PackageIconView(package: package, size: 34)

            VStack(alignment: .leading, spacing: 3) {
                Text(package.name).font(.body.weight(.medium))
                if let description = package.packageDescription, !description.isEmpty {
                    Text(description).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Text([package.version, package.installType].compactMap { $0 }.joined(separator: " · "))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer()

            StatusPill(
                text: package.statusDescription ?? package.status ?? "常规",
                isWarning: isWarning(package.status)
            )

            if isBusy {
                ProgressView().controlSize(.small)
            } else {
                HStack(spacing: 6) {
                    if package.canUpgrade {
                        Button {
                            triggerAction(.upgrade)
                        } label: {
                            Image(systemName: "arrow.triangle.2.circlepath")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .help("更新套件")
                    }

                    if package.canStop {
                        Button("暂停") { triggerAction(.stop) }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                    } else if package.canStart {
                        Button("启动") { triggerAction(.start) }
                            .buttonStyle(.borderedProminent)
                            .controlSize(.small)
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .contextMenu {
            if package.canStart {
                Button { triggerAction(.start) } label: {
                    Label("启动套件", systemImage: "play.fill")
                }
            }
            if package.canStop {
                Button { triggerAction(.stop) } label: {
                    Label("暂停套件", systemImage: "pause.fill")
                }
            }
            if package.canUpgrade {
                Button { triggerAction(.upgrade) } label: {
                    Label("更新套件", systemImage: "arrow.triangle.2.circlepath")
                }
            }
            if package.canUninstall {
                Divider()
                Button(role: .destructive) { triggerAction(.uninstall) } label: {
                    Label("卸载套件…", systemImage: "trash")
                }
            }
        }
        .disabled(isBusy)
        .accessibilityElement(children: .combine)
    }

    private func triggerAction(_ action: NasPackageAction) {
        guard !isBusy else { return }
        onControl(action)
    }
}

private struct PackageIconView: View {
    let package: NasPackage
    var size: CGFloat = 40

    var body: some View {
        if let iconData = package.iconData,
           let image = NSImage(data: iconData) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: size, height: size)
                .clipShape(RoundedRectangle(cornerRadius: size > 36 ? 10 : 8, style: .continuous))
                .shadow(color: .black.opacity(0.06), radius: 2, x: 0, y: 1)
                .accessibilityHidden(true)
        } else {
            fallbackIcon
        }
    }

    private var fallbackIcon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size > 36 ? 10 : 8, style: .continuous)
                .fill(Color.accentColor.opacity(0.12))
                .frame(width: size, height: size)
            Image(systemName: serviceIcon(package))
                .font(size > 36 ? .title3 : .body)
                .foregroundStyle(Color.accentColor)
        }
        .accessibilityHidden(true)
    }
}


private struct ScheduledTaskList: View {
    let tasks: [NasScheduledTask]
    let busyTaskIDs: Set<String>
    let loadDraft: (NasScheduledTask?) async throws -> NasScheduledTaskDraft
    let loadResults: (NasScheduledTask) async throws -> [NasScheduledTaskResult]
    let loadResultOutput: (
        NasScheduledTask,
        String
    ) async throws -> NasScheduledTaskResultOutput
    let onSave: (NasScheduledTaskDraft) async throws -> Void
    let onSetEnabled: (NasScheduledTask, Bool) async throws -> Void
    let onRun: (NasScheduledTask) async throws -> Void
    let onDelete: (NasScheduledTask) async throws -> Void
    @State private var displayMode: DisplayMode = .list
    @State private var editorDraft: NasScheduledTaskDraft?
    @State private var editorIsReadOnly = false
    @State private var resultsTask: NasScheduledTask?
    @State private var pendingRun: NasScheduledTask?
    @State private var pendingDelete: NasScheduledTask?
    @State private var operationError: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("\(tasks.count) 个任务")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()

                Picker("展示方式", selection: $displayMode) {
                    ForEach(DisplayMode.allCases) { mode in
                        Label(mode.rawValue, systemImage: mode.icon).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()

                Button {
                    openEditor(for: nil, readOnly: false)
                } label: {
                    Label("新建任务", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(busyTaskIDs.contains("new"))
            }
            .padding()

            if displayMode == .list {
                listContent
            } else {
                gridContent
            }
        }
        .sheet(
            isPresented: Binding(
                get: { editorDraft != nil },
                set: { if !$0 { editorDraft = nil } }
            )
        ) {
            if let editorDraft {
                ScheduledTaskEditor(
                    initialDraft: editorDraft,
                    isReadOnly: editorIsReadOnly,
                    onCancel: { self.editorDraft = nil },
                    onSave: { draft in
                        do {
                            try await onSave(draft)
                            self.editorDraft = nil
                            return nil
                        } catch {
                            return userMessage(
                                for: error,
                                fallback: "没有保存这个任务，请检查内容后重试。"
                            )
                        }
                    }
                )
            }
        }
        .sheet(item: $resultsTask) { task in
            ScheduledTaskResultsSheet(
                task: task,
                loadResults: { try await loadResults(task) },
                loadOutput: { resultID in
                    try await loadResultOutput(task, resultID)
                }
            )
        }
        .confirmationDialog(
            "立即运行“\(pendingRun?.name ?? "")”？",
            isPresented: Binding(
                get: { pendingRun != nil },
                set: { if !$0 { pendingRun = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("取消", role: .cancel) { pendingRun = nil }
            Button("立即运行") {
                guard let task = pendingRun else { return }
                pendingRun = nil
                perform { try await onRun(task) }
            }
        } message: {
            Text("任务会在 NAS 上立即执行，可能影响正在使用的服务。")
        }
        .confirmationDialog(
            "删除“\(pendingDelete?.name ?? "")”？",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("取消", role: .cancel) { pendingDelete = nil }
            Button("删除任务", role: .destructive) {
                guard let task = pendingDelete else { return }
                pendingDelete = nil
                perform { try await onDelete(task) }
            }
        } message: {
            Text("删除后，这个任务不会再自动运行。")
        }
        .alert(
            "操作没有完成",
            isPresented: Binding(
                get: { operationError != nil },
                set: { if !$0 { operationError = nil } }
            )
        ) {
            Button("确定") { operationError = nil }
        } message: {
            Text(operationError ?? "请刷新后重试。")
        }
    }

    private var listContent: some View {
        List(tasks) { task in
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: task.isEnabled ? "checkmark.circle.fill" : "pause.circle")
                    .foregroundStyle(task.isEnabled ? .green : .secondary)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(task.name).font(.body.weight(.medium))
                    Text([task.owner, task.type].compactMap { $0 }.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let action = task.action, !action.isEmpty {
                        Text(action).font(.caption2).foregroundStyle(.tertiary).lineLimit(2)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 4) {
                    StatusPill(text: task.isEnabled ? "已启用" : "已停用", isWarning: false)
                    if let next = task.nextTriggerDescription {
                        Text(next).font(.caption2).foregroundStyle(.secondary)
                    }
                }
                if busyTaskIDs.contains(task.id) {
                    ProgressView().controlSize(.small)
                } else {
                    Menu {
                        taskMenu(for: task)
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .accessibilityLabel("\(task.name)的更多操作")
                }
            }
            .padding(.vertical, 5)
            .contentShape(Rectangle())
            .contextMenu {
                taskMenu(for: task)
            }
            .accessibilityElement(children: .contain)
        }
    }

    private var gridContent: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 14)], spacing: 14) {
                ForEach(tasks) { task in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Image(systemName: task.isEnabled ? "checkmark.circle.fill" : "pause.circle")
                                .foregroundStyle(task.isEnabled ? .green : .secondary)
                                .font(.headline)
                            Text(task.name)
                                .font(.body.weight(.medium))
                                .lineLimit(1)
                            Spacer()
                            StatusPill(text: task.isEnabled ? "已启用" : "已停用", isWarning: false)
                        }

                        Text([task.owner, task.type].compactMap { $0 }.joined(separator: " · "))
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if let action = task.action, !action.isEmpty {
                            Text(action)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .lineLimit(2)
                        }

                        Divider().padding(.vertical, 2)

                        HStack {
                            if let next = task.nextTriggerDescription {
                                Text(next)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if busyTaskIDs.contains(task.id) {
                                ProgressView().controlSize(.small)
                            } else {
                                Menu {
                                    taskMenu(for: task)
                                } label: {
                                    Image(systemName: "ellipsis.circle")
                                }
                                .menuStyle(.borderlessButton)
                                .fixedSize()
                            }
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color(nsColor: .controlBackgroundColor).opacity(0.6))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                            )
                    )
                    .contentShape(Rectangle())
                    .contextMenu {
                        taskMenu(for: task)
                    }
                }
            }
            .padding(20)
        }
    }

    @ViewBuilder
    private func taskMenu(for task: NasScheduledTask) -> some View {
        Button("查看详情") {
            openEditor(for: task, readOnly: true)
        }
        Button("运行记录") {
            resultsTask = task
        }
        if task.canEdit {
            Button("修改…") {
                openEditor(for: task, readOnly: false)
            }
            Button(task.isEnabled ? "停用" : "启用") {
                perform {
                    try await onSetEnabled(task, !task.isEnabled)
                }
            }
        }
        if task.canRun {
            Divider()
            Button("立即运行…") { pendingRun = task }
        }
        if task.canEdit {
            Divider()
            Button("删除…", role: .destructive) {
                pendingDelete = task
            }
        }
    }

    private func openEditor(for task: NasScheduledTask?, readOnly: Bool) {
        Task {
            do {
                let draft = try await loadDraft(task)
                editorIsReadOnly = readOnly || (task != nil && task?.canEdit == false)
                editorDraft = draft
            } catch {
                operationError = userMessage(
                    for: error,
                    fallback: "暂时无法读取任务详情，请刷新后重试。"
                )
            }
        }
    }

    private func perform(_ operation: @escaping () async throws -> Void) {
        Task {
            do {
                try await operation()
            } catch {
                operationError = userMessage(
                    for: error,
                    fallback: "操作没有完成，请刷新后重试。"
                )
            }
        }
    }
}

private struct ScheduledTaskResultsSheet: View {
    let task: NasScheduledTask
    let loadResults: () async throws -> [NasScheduledTaskResult]
    let loadOutput: (String) async throws -> NasScheduledTaskResultOutput

    @Environment(\.dismiss) private var dismiss
    @State private var results: [NasScheduledTaskResult] = []
    @State private var selectedResultID: String?
    @State private var output: NasScheduledTaskResultOutput?
    @State private var isLoading = false
    @State private var isLoadingOutput = false
    @State private var errorMessage: String?

    private var selectedResult: NasScheduledTaskResult? {
        results.first { $0.id == selectedResultID }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header 模态顶栏
            HStack(alignment: .center) {
                Image(systemName: "clock.arrow.circlepath")
                    .font(.title2)
                    .foregroundStyle(Color.accentColor)

                VStack(alignment: .leading, spacing: 2) {
                    Text("“\(task.name)”运行记录")
                        .font(.title3.weight(.bold))
                    Text("查看任务在 NAS 上的历史执行状态与控制台输出")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()

                Button {
                    Task { await refreshResults() }
                } label: {
                    Label("刷新", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isLoading || isLoadingOutput)

                Button("关闭") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .controlSize(.small)
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 16)

            Divider()

            // 内容展示区
            Group {
                if isLoading, results.isEmpty {
                    VStack(spacing: 12) {
                        ProgressView().controlSize(.large)
                        Text("正在读取运行记录…")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if results.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "clock.badge.questionmark")
                            .font(.system(size: 44))
                            .foregroundStyle(.secondary.opacity(0.6))

                        VStack(spacing: 6) {
                            Text("还没有运行记录")
                                .font(.headline)
                            Text(errorMessage ?? "这个任务尚未被自动或手动触发运行，或 NAS 当前没有保留历史结果。")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: 400)
                        }

                        Button {
                            Task { await refreshResults() }
                        } label: {
                            Label("重新读取", systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                    }
                    .padding(32)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(nsColor: .controlBackgroundColor).opacity(0.4))
                    )
                    .padding(24)
                } else {
                    HSplitView {
                        List(results, selection: $selectedResultID) { result in
                            VStack(alignment: .leading, spacing: 6) {
                                HStack {
                                    Image(systemName: result.exitCode == 0 ? "checkmark.circle.fill" : "xmark.circle.fill")
                                        .foregroundStyle(result.exitCode == 0 ? .green : .red)
                                        .accessibilityHidden(true)
                                    Text(result.startedAt?.formatted(date: .abbreviated, time: .standard) ?? "时间未知")
                                        .font(.body.weight(.medium))
                                }
                                HStack {
                                    StatusPill(text: result.exitCode == 0 ? "执行成功" : "执行失败", isWarning: result.exitCode != 0)
                                    if let code = result.exitCode {
                                        Text("代码: \(code)").font(.caption2).foregroundStyle(.tertiary).monospacedDigit()
                                    }
                                }
                            }
                            .tag(result.id)
                            .padding(.vertical, 4)
                        }
                        .frame(minWidth: 230, idealWidth: 250, maxWidth: 290)

                        resultDetails
                            .frame(minWidth: 430, maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
            }
        }
        .frame(minWidth: 720, idealWidth: 800, minHeight: 480, maxHeight: 680)
        .task {
            await refreshResults()
        }
        .task(id: selectedResultID) {
            await refreshOutput()
        }
    }

    @ViewBuilder
    private var resultDetails: some View {
        if let result = selectedResult {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    DetailSection(title: "运行信息") {
                        DetailValueRow(
                            title: "开始时间",
                            value: result.startedAt?.formatted(date: .long, time: .standard) ?? "未提供"
                        )
                        Divider().opacity(0.4)
                        DetailValueRow(
                            title: "结束时间",
                            value: result.stoppedAt?.formatted(date: .long, time: .standard) ?? "未提供"
                        )
                        Divider().opacity(0.4)
                        DetailValueRow(
                            title: "退出状态",
                            value: result.exitCode.map(String.init) ?? result.exitType ?? "未提供"
                        )
                        if let trigger = result.triggerEvent, !trigger.isEmpty {
                            Divider().opacity(0.4)
                            DetailValueRow(title: "触发方式", value: trigger)
                        }
                    }

                    if isLoadingOutput {
                        ProgressView("正在读取详细结果…")
                    } else if let errorMessage {
                        Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    } else {
                        TaskOutputSection(title: "执行内容", text: output?.command)
                        TaskOutputSection(title: "运行输出", text: output?.output)
                    }
                }
                .padding(20)
            }
        } else {
            VStack(spacing: 12) {
                Image(systemName: "list.bullet.rectangle")
                    .font(.system(size: 36))
                    .foregroundStyle(.secondary.opacity(0.5))
                Text("选择一次运行记录")
                    .font(.headline)
                Text("可以在左侧选择不同时间的执行记录，查看开始时间、退出码和完整输出。")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 320)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func refreshResults() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let loaded = try await loadResults()
            results = loaded
            if selectedResultID == nil || !loaded.contains(where: { $0.id == selectedResultID }) {
                selectedResultID = loaded.first?.id
            }
        } catch is CancellationError {
            return
        } catch {
            results = []
            errorMessage = userMessage(
                for: error,
                fallback: "暂时无法读取运行记录，请稍后重试。"
            )
        }
    }

    private func refreshOutput() async {
        guard let selectedResultID, !isLoadingOutput else {
            output = nil
            return
        }
        isLoadingOutput = true
        output = nil
        errorMessage = nil
        defer { isLoadingOutput = false }
        do {
            output = try await loadOutput(selectedResultID)
        } catch is CancellationError {
            return
        } catch {
            errorMessage = userMessage(
                for: error,
                fallback: "暂时无法读取这次运行的详细结果。"
            )
        }
    }
}

private struct TaskOutputSection: View {
    let title: String
    let text: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Spacer()
                if let text, !text.isEmpty {
                    Text("\(text.components(separatedBy: .newlines).count) 行")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            VStack(alignment: .leading, spacing: 0) {
                ScrollView([.horizontal, .vertical]) {
                    Text(text.flatMap { $0.isEmpty ? nil : $0 } ?? "暂无输出日志内容")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(text?.isEmpty == false ? Color.primary : Color.secondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                }
            }
            .frame(minHeight: 80, maxHeight: 180)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color(nsColor: .textBackgroundColor))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(Color.primary.opacity(0.12), lineWidth: 1)
                    )
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ScheduledTaskEditor: View {
    @State private var draft: NasScheduledTaskDraft
    @State private var isSaving = false
    @State private var saveError: String?
    let isReadOnly: Bool
    let onCancel: () -> Void
    let onSave: (NasScheduledTaskDraft) async -> String?

    init(
        initialDraft: NasScheduledTaskDraft,
        isReadOnly: Bool,
        onCancel: @escaping () -> Void,
        onSave: @escaping (NasScheduledTaskDraft) async -> String?
    ) {
        _draft = State(initialValue: initialDraft)
        self.isReadOnly = isReadOnly
        self.onCancel = onCancel
        self.onSave = onSave
    }

    var body: some View {
        VStack(spacing: 0) {
            // 顶栏 Header
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(isReadOnly ? "任务详情" : (draft.id == nil ? "新建任务" : "修改任务"))
                        .font(.title3.weight(.bold))
                    Text(isReadOnly ? "查看 NAS 计划任务配置" : "配置定期自动执行的系统脚本")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if !isReadOnly {
                    Toggle("启用", isOn: $draft.isEnabled)
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 16)

            Divider()

            // 内容区 ScrollView
            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 20) {
                    // 卡片1：基础配置
                    VStack(alignment: .leading, spacing: 12) {
                        Text("常规设置")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)

                        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 12) {
                            GridRow {
                                Text("任务名称")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .gridColumnAlignment(.trailing)
                                TextField("如：自动清理临时文件", text: $draft.name)
                                    .textFieldStyle(.roundedBorder)
                            }
                            GridRow {
                                Text("执行账号")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                TextField("root / admin", text: $draft.owner)
                                    .textFieldStyle(.roundedBorder)
                            }
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color(nsColor: .controlBackgroundColor).opacity(0.6))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                            )
                    )

                    // 卡片2：调度策略
                    VStack(alignment: .leading, spacing: 14) {
                        Text("运行调度")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)

                        HStack(spacing: 16) {
                            HStack(spacing: 6) {
                                Image(systemName: "clock")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                Text("执行时间")
                                    .font(.subheadline)
                            }

                            HStack(spacing: 4) {
                                Picker("小时", selection: $draft.schedule.hour) {
                                    ForEach(0..<24, id: \.self) { hour in
                                        Text(String(format: "%02d 点", hour)).tag(hour)
                                    }
                                }
                                .labelsHidden()
                                .fixedSize()

                                Picker("分钟", selection: $draft.schedule.minute) {
                                    ForEach(0..<60, id: \.self) { minute in
                                        Text(String(format: "%02d 分", minute)).tag(minute)
                                    }
                                }
                                .labelsHidden()
                                .fixedSize()
                            }
                        }

                        VStack(alignment: .leading, spacing: 8) {
                            Text("重复运行日")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            WeekdaySelector(selection: $draft.schedule.weekDays)
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color(nsColor: .controlBackgroundColor).opacity(0.6))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                            )
                    )

                    // 卡片3：命令编辑器
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("执行命令")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Label("Shell 脚本", systemImage: "terminal")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }

                        ZStack(alignment: .topLeading) {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color(nsColor: .textBackgroundColor))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.primary.opacity(0.12), lineWidth: 1)
                                )

                            TextEditor(text: $draft.script)
                                .font(.system(.body, design: .monospaced))
                                .scrollContentBackground(.hidden)
                                .padding(8)
                                .frame(minHeight: 120, maxHeight: 200)

                            if draft.script.isEmpty {
                                Text("输入要在 NAS 上运行的 Shell 命令，例如：\n/volume1/scripts/backup.sh")
                                    .font(.system(.body, design: .monospaced))
                                    .foregroundStyle(.tertiary)
                                    .padding(.top, 13)
                                    .padding(.leading, 12)
                                    .allowsHitTesting(false)
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    // 卡片4：高级选项 (通知设置)
                    DisclosureGroup {
                        VStack(alignment: .leading, spacing: 10) {
                            Toggle("只在运行失败时发送通知", isOn: $draft.notifyOnError)
                                .toggleStyle(.checkbox)

                            VStack(alignment: .leading, spacing: 4) {
                                Text("接收邮箱")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                TextField("admin@example.com", text: $draft.notificationEmails)
                                    .textFieldStyle(.roundedBorder)
                            }
                        }
                        .padding(.top, 8)
                    } label: {
                        Label("通知设置", systemImage: "bell")
                            .font(.subheadline.weight(.medium))
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color(nsColor: .controlBackgroundColor).opacity(0.4))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.primary.opacity(0.06), lineWidth: 1)
                            )
                    )

                    // 风险警告 Alert Box
                    if !isReadOnly {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundStyle(.orange)
                                .font(.body)

                            Text("请确认脚本命令安全。任务将以所选账号的高权限在 NAS 设备上全速执行。")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.orange.opacity(0.08))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.orange.opacity(0.25), lineWidth: 1)
                                )
                        )
                    }

                    if let saveError {
                        HStack(spacing: 8) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.red)
                            Text(saveError)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)
                .padding(.bottom, 28)
            }
            .disabled(isReadOnly || isSaving)

            Divider()

            // 底栏 Footer
            HStack {
                Spacer()
                Button(isReadOnly ? "关闭" : "取消", action: onCancel)
                    .keyboardShortcut(.cancelAction)

                if !isReadOnly {
                    Button {
                        isSaving = true
                        Task {
                            saveError = await onSave(draft)
                            isSaving = false
                        }
                    } label: {
                        HStack(spacing: 6) {
                            if isSaving {
                                ProgressView()
                                    .controlSize(.small)
                            }
                            Text("保存")
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(
                        isSaving
                            || draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || draft.owner.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || draft.script.isEmpty
                    )
                }
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(minWidth: 560, idealWidth: 600, minHeight: 520, maxHeight: 720)
    }
}

private struct WeekdaySelector: View {
    @Binding var selection: String
    private let days = [
        (0, "日", "星期日"),
        (1, "一", "星期一"),
        (2, "二", "星期二"),
        (3, "三", "星期三"),
        (4, "四", "星期四"),
        (5, "五", "星期五"),
        (6, "六", "星期六")
    ]

    private var selectedDays: Set<Int> {
        Set(selection.split(separator: ",").compactMap { Int($0) })
    }

    var body: some View {
        HStack(spacing: 8) {
            ForEach(days, id: \.0) { day in
                let isSelected = selectedDays.contains(day.0)
                Button {
                    var updated = selectedDays
                    if isSelected {
                        if updated.count > 1 {
                            updated.remove(day.0)
                        }
                    } else {
                        updated.insert(day.0)
                    }
                    selection = updated.sorted().map(String.init).joined(separator: ",")
                } label: {
                    Text(day.1)
                        .font(.system(size: 13, weight: isSelected ? .bold : .medium))
                        .frame(width: 32, height: 32)
                        .background(
                            Circle()
                                .fill(isSelected ? Color.accentColor : Color.primary.opacity(0.06))
                        )
                        .foregroundColor(isSelected ? .white : .primary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(day.2)
            }
        }
    }
}

private struct AccountDirectoryView: View {
    enum Scope: String, CaseIterable, Identifiable {
        case users = "账号"
        case groups = "群组"
        var id: Self { self }
    }

    enum DisplayMode: String, CaseIterable, Identifiable {
        case list = "列表"
        case grid = "卡片"
        var id: Self { self }
        var icon: String { self == .list ? "list.bullet" : "square.grid.2x2" }
    }

    let directory: NasAccountDirectory?
    let busyAccountIDs: Set<String>
    let onSave: (NasAccountDraft) async throws -> Void
    let onDelete: (NasAccount) async throws -> Void
    let onSaveGroup: (NasGroupDraft) async throws -> Void
    let onDeleteGroup: (NasAccount) async throws -> Void
    @State private var scope: Scope = .users
    @State private var searchText = ""
    @State private var editorDraft: NasAccountDraft?
    @State private var groupEditorDraft: NasGroupDraft?
    @State private var pendingDelete: NasAccount?
    @State private var operationError: String?
    @State private var displayMode: DisplayMode = .list

    private var accounts: [NasAccount] {
        let source = scope == .users ? directory?.users ?? [] : directory?.groups ?? []
        guard !searchText.isEmpty else { return source }
        return source.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
                || ($0.description?.localizedCaseInsensitiveContains(searchText) ?? false)
                || ($0.email?.localizedCaseInsensitiveContains(searchText) ?? false)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Picker("显示内容", selection: $scope) {
                    ForEach(Scope.allCases) { scope in
                        Text("\(scope.rawValue) \(count(scope))").tag(scope)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 320)

                Picker("展示方式", selection: $displayMode) {
                    ForEach(DisplayMode.allCases) { mode in
                        Label(mode.rawValue, systemImage: mode.icon).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()

                Spacer()
                if scope == .users {
                    Button {
                        editorDraft = NasAccountDraft(
                            groups: directory?.groups.contains {
                                $0.name.caseInsensitiveCompare("users") == .orderedSame
                            } == true ? ["users"] : nil
                        )
                    } label: {
                        Label("新建账号", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(busyAccountIDs.contains("new"))
                } else {
                    Button {
                        groupEditorDraft = NasGroupDraft()
                    } label: {
                        Label("新建群组", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(busyAccountIDs.contains("new-group"))
                }
            }
            .padding()

            if displayMode == .list {
                listContent
            } else {
                gridContent
            }
        }
        .sheet(
            isPresented: Binding(
                get: { editorDraft != nil },
                set: { if !$0 { editorDraft = nil } }
            )
        ) {
            if let editorDraft {
                AccountEditor(
                    initialDraft: editorDraft,
                    availableGroups: directory?.groups.map(\.name) ?? [],
                    onCancel: { self.editorDraft = nil },
                    onSave: { draft in
                        do {
                            try await onSave(draft)
                            self.editorDraft = nil
                            return nil
                        } catch {
                            return userMessage(
                                for: error,
                                fallback: "没有保存这个账号，请检查内容后重试。"
                            )
                        }
                    }
                )
            }
        }
        .sheet(
            isPresented: Binding(
                get: { groupEditorDraft != nil },
                set: { if !$0 { groupEditorDraft = nil } }
            )
        ) {
            if let groupEditorDraft {
                GroupEditor(
                    initialDraft: groupEditorDraft,
                    onCancel: { self.groupEditorDraft = nil },
                    onSave: { draft in
                        do {
                            try await onSaveGroup(draft)
                            self.groupEditorDraft = nil
                            return nil
                        } catch {
                            return userMessage(
                                for: error,
                                fallback: "没有保存这个群组，请检查内容后重试。"
                            )
                        }
                    }
                )
            }
        }
        .confirmationDialog(
            "删除\(pendingDelete?.kind == .group ? "群组" : "账号")“\(pendingDelete?.name ?? "")”？",
            isPresented: Binding(
                get: { pendingDelete != nil },
                set: { if !$0 { pendingDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("取消", role: .cancel) { pendingDelete = nil }
            Button(pendingDelete?.kind == .group ? "删除群组" : "删除账号", role: .destructive) {
                guard let item = pendingDelete else { return }
                pendingDelete = nil
                Task {
                    do {
                        if item.kind == .group {
                            try await onDeleteGroup(item)
                        } else {
                            try await onDelete(item)
                        }
                    } catch {
                        operationError = userMessage(
                            for: error,
                            fallback: "没有删除这个账号，请刷新后重试。"
                        )
                    }
                }
            }
        } message: {
            if pendingDelete?.kind == .group {
                Text("群组会从成员的权限设置中移除，账号本身不会被删除。")
            } else {
                Text("这个账号将无法再登录 NAS。账号的个人文件是否保留由 NAS 的现有设置决定。")
            }
        }
        .alert(
            "操作没有完成",
            isPresented: Binding(
                get: { operationError != nil },
                set: { if !$0 { operationError = nil } }
            )
        ) {
            Button("确定") { operationError = nil }
        } message: {
            if let operationError {
                Text(operationError)
            }
        }
    }

    private var listContent: some View {
        List(accounts) { account in
            HStack(spacing: 12) {
                Image(systemName: account.kind == .user ? "person.circle.fill" : "person.2.circle.fill")
                    .font(.title2)
                    .foregroundStyle(account.isExpired ? Color.secondary : Color.accentColor)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 3) {
                    Text(account.name).font(.body.weight(.medium)).textSelection(.enabled)
                    Text([account.email, account.description].compactMap { $0 }.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer()
                if account.isExpired {
                    StatusPill(text: "已停用", isWarning: true)
                }
                if let id = account.numericID {
                    Text("#\(id)").font(.caption2).foregroundStyle(.tertiary).monospacedDigit()
                }
                if busyAccountIDs.contains(account.id) {
                    ProgressView().controlSize(.small)
                } else if account.kind == .user, account.canEdit || account.canDelete {
                    Menu {
                        accountMenu(for: account)
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .accessibilityLabel("\(account.name)的更多操作")
                } else if account.kind == .group, account.canEdit || account.canDelete {
                    Menu {
                        accountMenu(for: account)
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .accessibilityLabel("\(account.name)的更多操作")
                }
            }
            .padding(.vertical, 5)
            .contentShape(Rectangle())
            .contextMenu {
                accountMenu(for: account)
            }
            .accessibilityElement(children: .combine)
        }
        .searchable(text: $searchText, prompt: "搜索\(scope.rawValue)")
    }

    private var gridContent: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 14)], spacing: 14) {
                ForEach(accounts) { account in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Image(systemName: account.kind == .user ? "person.circle.fill" : "person.2.circle.fill")
                                .font(.title2)
                                .foregroundStyle(account.isExpired ? Color.secondary : Color.accentColor)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(account.name)
                                    .font(.body.weight(.medium))
                                    .textSelection(.enabled)
                                    .lineLimit(1)
                                if let id = account.numericID {
                                    Text("#\(id)").font(.caption2).foregroundStyle(.tertiary).monospacedDigit()
                                }
                            }
                            Spacer()
                            if account.isExpired {
                                StatusPill(text: "已停用", isWarning: true)
                            }
                        }

                        let info = [account.email, account.description].compactMap({ $0 }).joined(separator: " · ")
                        if !info.isEmpty {
                            Text(info)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                        }

                        Divider().padding(.vertical, 2)

                        HStack {
                            Spacer()
                            if busyAccountIDs.contains(account.id) {
                                ProgressView().controlSize(.small)
                            } else if account.canEdit || account.canDelete {
                                Menu {
                                    accountMenu(for: account)
                                } label: {
                                    Image(systemName: "ellipsis.circle")
                                }
                                .menuStyle(.borderlessButton)
                                .fixedSize()
                            }
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color(nsColor: .controlBackgroundColor).opacity(0.6))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                            )
                    )
                    .contentShape(Rectangle())
                    .contextMenu {
                        accountMenu(for: account)
                    }
                }
            }
            .padding(20)
        }
        .searchable(text: $searchText, prompt: "搜索\(scope.rawValue)")
    }

    @ViewBuilder
    private func accountMenu(for account: NasAccount) -> some View {
        if account.kind == .user {
            if account.canEdit {
                Button("修改…") {
                    openUserEditor(for: account)
                }
            }
            if account.canDelete {
                Button("删除…", role: .destructive) {
                    pendingDelete = account
                }
            }
        } else {
            if account.canEdit {
                Button("修改…") {
                    openGroupEditor(for: account)
                }
            }
            if account.canDelete {
                Button("删除…", role: .destructive) {
                    pendingDelete = account
                }
            }
        }
    }

    private func openUserEditor(for account: NasAccount) {
        editorDraft = NasAccountDraft(
            originalName: account.name,
            name: account.name,
            description: account.description ?? "",
            email: account.email ?? "",
            isExpired: account.isExpired,
            groups: account.groups
        )
    }

    private func openGroupEditor(for account: NasAccount) {
        groupEditorDraft = NasGroupDraft(
            originalName: account.name,
            name: account.name,
            description: account.description ?? ""
        )
    }

    private func count(_ scope: Scope) -> Int {
        scope == .users ? directory?.users.count ?? 0 : directory?.groups.count ?? 0
    }
}

private struct AccountEditor: View {
    @State private var draft: NasAccountDraft
    @State private var isSaving = false
    @State private var saveError: String?
    let availableGroups: [String]
    let onCancel: () -> Void
    let onSave: (NasAccountDraft) async -> String?

    init(
        initialDraft: NasAccountDraft,
        availableGroups: [String],
        onCancel: @escaping () -> Void,
        onSave: @escaping (NasAccountDraft) async -> String?
    ) {
        _draft = State(initialValue: initialDraft)
        self.availableGroups = availableGroups
        self.onCancel = onCancel
        self.onSave = onSave
    }

    private var passwordMismatch: Bool {
        !draft.password.isEmpty && !draft.passwordConfirmation.isEmpty && draft.password != draft.passwordConfirmation
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(draft.originalName == nil ? "新建账号" : "修改账号")
                        .font(.title3.weight(.bold))
                    Text(draft.originalName == nil ? "创建 NAS 系统访问与权限账号" : "更新现有的账号配置与登录凭证")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 16)

            Divider()

            // Scrollable Content
            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 18) {
                    // 卡片1：常规信息
                    VStack(alignment: .leading, spacing: 12) {
                        Text("常规信息")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)

                        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 12) {
                            GridRow {
                                Text("账号名称")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .gridColumnAlignment(.trailing)
                                VStack(alignment: .leading, spacing: 4) {
                                    TextField("输入账号名称", text: $draft.name)
                                        .textFieldStyle(.roundedBorder)
                                        .disabled(draft.originalName != nil)
                                    if draft.originalName != nil {
                                        Text("已创建账号的名称不可修改")
                                            .font(.caption2)
                                            .foregroundStyle(.tertiary)
                                    }
                                }
                            }
                            GridRow {
                                Text("邮箱 (可选)")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                TextField("user@example.com", text: $draft.email)
                                    .textFieldStyle(.roundedBorder)
                                    .textContentType(.emailAddress)
                            }
                            GridRow {
                                Text("备注 (可选)")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                TextField("填写账号说明或备注", text: $draft.description)
                                    .textFieldStyle(.roundedBorder)
                            }
                        }

                        Divider().padding(.vertical, 4)

                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("暂停账号登录")
                                    .font(.subheadline.weight(.medium))
                                Text("开启后该账号将暂时无法登录 NAS 服务")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Toggle("", isOn: $draft.isExpired)
                                .toggleStyle(.switch)
                                .controlSize(.small)
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color(nsColor: .controlBackgroundColor).opacity(0.6))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                            )
                    )

                    // 卡片2：所属群组
                    if draft.groups != nil, !availableGroups.isEmpty {
                        DisclosureGroup {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(availableGroups, id: \.self) { group in
                                    Toggle(
                                        group,
                                        isOn: Binding(
                                            get: { draft.groups?.contains(group) == true },
                                            set: { isMember in
                                                var groups = draft.groups ?? []
                                                if isMember, !groups.contains(group) {
                                                    groups.append(group)
                                                } else if !isMember {
                                                    groups.removeAll { $0 == group }
                                                }
                                                draft.groups = groups
                                            }
                                        )
                                    )
                                    .toggleStyle(.checkbox)
                                }
                            }
                            .padding(.top, 8)
                        } label: {
                            Label("所属群组", systemImage: "person.3")
                                .font(.subheadline.weight(.medium))
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color(nsColor: .controlBackgroundColor).opacity(0.4))
                                .overlay(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.primary.opacity(0.06), lineWidth: 1)
                                )
                        )
                    }

                    // 卡片3：密码安全
                    VStack(alignment: .leading, spacing: 12) {
                        Text(draft.originalName == nil ? "设置登录密码" : "更改登录密码 (可选)")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)

                        Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 12) {
                            GridRow {
                                Text("登录密码")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .gridColumnAlignment(.trailing)
                                SecureField(draft.originalName == nil ? "输入登录密码" : "留空表示保留原密码", text: $draft.password)
                                    .textFieldStyle(.roundedBorder)
                                    .textContentType(.newPassword)
                            }
                            GridRow {
                                Text("再次输入密码")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                SecureField("再次输入以确认", text: $draft.passwordConfirmation)
                                    .textFieldStyle(.roundedBorder)
                                    .textContentType(.newPassword)
                            }
                        }

                        if passwordMismatch {
                            HStack(spacing: 6) {
                                Image(systemName: "exclamationmark.circle.fill")
                                    .font(.caption)
                                Text("两次输入的密码不一致")
                                    .font(.caption)
                            }
                            .foregroundStyle(.red)
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color(nsColor: .controlBackgroundColor).opacity(0.6))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                            )
                    )

                    if let saveError {
                        HStack(spacing: 8) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.red)
                            Text(saveError)
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                }
                .padding(24)
            }
            .disabled(isSaving)

            Divider()

            // Footer
            HStack {
                Spacer()
                Button("取消", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button {
                    isSaving = true
                    Task {
                        saveError = await onSave(draft)
                        isSaving = false
                    }
                } label: {
                    HStack(spacing: 6) {
                        if isSaving {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Text("保存")
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(
                    isSaving
                        || draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || (draft.originalName == nil && draft.password.isEmpty)
                        || draft.password != draft.passwordConfirmation
                )
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(width: 540, height: 560)
    }
}

private struct GroupEditor: View {
    @State private var draft: NasGroupDraft
    @State private var isSaving = false
    @State private var saveError: String?
    let onCancel: () -> Void
    let onSave: (NasGroupDraft) async -> String?

    init(
        initialDraft: NasGroupDraft,
        onCancel: @escaping () -> Void,
        onSave: @escaping (NasGroupDraft) async -> String?
    ) {
        _draft = State(initialValue: initialDraft)
        self.onCancel = onCancel
        self.onSave = onSave
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(draft.originalName == nil ? "新建群组" : "修改群组")
                        .font(.title3.weight(.bold))
                    Text("管理 NAS 用户群组结构与权限划分")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            .padding(.bottom, 16)

            Divider()

            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("群组参数")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 12) {
                        GridRow {
                            Text("群组名称")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .gridColumnAlignment(.trailing)
                            TextField("输入群组名称", text: $draft.name)
                                .textFieldStyle(.roundedBorder)
                                .disabled(draft.originalName != nil)
                        }
                        GridRow {
                            Text("备注 (可选)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                            TextField("填写群组说明", text: $draft.description)
                                .textFieldStyle(.roundedBorder)
                        }
                    }
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color(nsColor: .controlBackgroundColor).opacity(0.6))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                        )
                )

                if let saveError {
                    HStack(spacing: 8) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.red)
                        Text(saveError)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }

                Spacer()
            }
            .padding(24)
            .disabled(isSaving)

            Divider()

            // Footer
            HStack {
                Spacer()
                Button("取消", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                Button {
                    isSaving = true
                    Task {
                        saveError = await onSave(draft)
                        isSaving = false
                    }
                } label: {
                    HStack(spacing: 6) {
                        if isSaving {
                            ProgressView()
                                .controlSize(.small)
                        }
                        Text("保存")
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(
                    isSaving
                        || draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                )
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .background(Color(nsColor: .windowBackgroundColor))
        }
        .frame(width: 480, height: 320)
    }
}

private struct ActiveConnectionsCard: View {
    let connections: NasConnectionPage?
    let onNavigate: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("当前连接", systemImage: "network")
                    .font(.headline)
                Spacer()
                Button {
                    onNavigate()
                } label: {
                    HStack(spacing: 3) {
                        Text("查看全部")
                        Image(systemName: "chevron.right")
                    }
                    .font(.caption.weight(.medium))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color.accentColor)
            }

            if let page = connections, !page.connections.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(alignment: .firstTextBaseline) {
                        Text("\(page.connections.count)")
                            .font(.title2.weight(.bold))
                            .monospacedDigit()
                        Text("个活动连接")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(Array(page.connections.prefix(3))) { item in
                            HStack(spacing: 8) {
                                Image(systemName: item.isCurrentConnection ? "laptopcomputer.and.arrow.down" : "person.fill")
                                    .font(.caption2)
                                    .foregroundStyle(item.isCurrentConnection ? Color.green : Color.accentColor)
                                Text(item.account)
                                    .font(.caption.weight(.medium))
                                    .lineLimit(1)
                                if let proto = item.protocolName {
                                    Text(proto)
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                        .padding(.horizontal, 4)
                                        .padding(.vertical, 1)
                                        .background(Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 4))
                                }
                                Spacer()
                                if let ip = item.source {
                                    Text(ip)
                                        .font(.caption2)
                                        .foregroundStyle(.tertiary)
                                        .monospacedDigit()
                                }
                            }
                        }
                    }
                }
            } else {
                VStack(spacing: 6) {
                    Text("暂无活动连接数据")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 215, maxHeight: 215, alignment: .topLeading)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.8), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }
}

private struct LogEntryList: View {
    let page: NasLogPage?
    let currentPage: Int
    let pageSize: Int
    let onFetchPage: (Int, Int) async -> Void

    enum LogFilter: String, CaseIterable, Identifiable {
        case all = "全部"
        case error = "错误"
        case warning = "警告"
        case info = "信息"

        var id: Self { self }
    }

    @State private var selectedFilter: LogFilter = .all
    @State private var searchText = ""

    private var filteredEntries: [NasLogEntry] {
        guard let source = page?.entries else { return [] }
        return source.filter { entry in
            let matchesFilter: Bool
            switch selectedFilter {
            case .all: matchesFilter = true
            case .error: matchesFilter = isError(entry.level)
            case .warning: matchesFilter = isWarning(entry.level) && !isError(entry.level)
            case .info: matchesFilter = !isError(entry.level) && !isWarning(entry.level)
            }
            guard matchesFilter else { return false }
            guard !searchText.isEmpty else { return true }
            return entry.message.localizedCaseInsensitiveContains(searchText)
                || (entry.source?.localizedCaseInsensitiveContains(searchText) ?? false)
                || (entry.account?.localizedCaseInsensitiveContains(searchText) ?? false)
        }
    }

    private var totalPages: Int {
        guard let page, page.total > 0 else { return 1 }
        return max(1, Int(ceil(Double(page.total) / Double(pageSize))))
    }

    var body: some View {
        VStack(spacing: 0) {
            filterHeaderBar
            Divider()

            List(filteredEntries) { entry in
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        StatusPill(text: entry.level ?? "信息", isWarning: isWarning(entry.level))
                        Text(entry.source ?? "系统").font(.caption.weight(.semibold))
                        if let account = entry.account { Text(account).font(.caption).foregroundStyle(.secondary) }
                        Spacer()
                        if let date = entry.date {
                            Text(date, format: .dateTime.month().day().hour().minute().second())
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Text(entry.message).textSelection(.enabled)
                }
                .padding(.vertical, 5)
                .accessibilityElement(children: .combine)
            }
            .searchable(text: $searchText, prompt: "搜索日志")

            Divider()
            paginationBar
        }
    }

    private var filterHeaderBar: some View {
        HStack(spacing: 10) {
            FilterChipButton(
                title: "\(page?.total.formatted() ?? "0") 条",
                icon: "doc.text",
                isSelected: selectedFilter == .all,
                badgeColor: .accentColor
            ) {
                selectedFilter = .all
            }

            FilterChipButton(
                title: "\(page?.errorCount ?? 0) 个错误",
                icon: "xmark.octagon.fill",
                isSelected: selectedFilter == .error,
                badgeColor: .red
            ) {
                selectedFilter = .error
            }

            FilterChipButton(
                title: "\(page?.warningCount ?? 0) 个警告",
                icon: "exclamationmark.triangle.fill",
                isSelected: selectedFilter == .warning,
                badgeColor: .orange
            ) {
                selectedFilter = .warning
            }

            FilterChipButton(
                title: "信息",
                icon: "info.circle.fill",
                isSelected: selectedFilter == .info,
                badgeColor: .blue
            ) {
                selectedFilter = .info
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.4))
    }

    private var paginationBar: some View {
        HStack(spacing: 12) {
            Text("每页")
                .font(.caption)
                .foregroundStyle(.secondary)

            Picker("", selection: Binding(
                get: { pageSize },
                set: { newSize in
                    Task { await onFetchPage(1, newSize) }
                }
            )) {
                Text("50 条").tag(50)
                Text("100 条").tag(100)
                Text("200 条").tag(200)
            }
            .pickerStyle(.menu)
            .fixedSize()

            Spacer()

            Text("第 \(currentPage) / \(totalPages) 页 (共 \(page?.total ?? 0) 条)")
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()

            HStack(spacing: 6) {
                Button {
                    guard currentPage > 1 else { return }
                    Task { await onFetchPage(currentPage - 1, pageSize) }
                } label: {
                    Image(systemName: "chevron.left")
                }
                .disabled(currentPage <= 1)
                .help("上一页")

                Button {
                    guard currentPage < totalPages else { return }
                    Task { await onFetchPage(currentPage + 1, pageSize) }
                } label: {
                    Image(systemName: "chevron.right")
                }
                .disabled(currentPage >= totalPages)
                .help("下一页")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.6))
    }

    private func isError(_ level: String?) -> Bool {
        guard let level = level?.lowercased() else { return false }
        return level.contains("err") || level.contains("fatal") || level.contains("critical") || level.contains("error")
    }
}

private struct FilterChipButton: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let badgeColor: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.caption2)
                    .foregroundStyle(isSelected ? .white : badgeColor)
                Text(title)
                    .font(.caption.weight(isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? .white : .primary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(
                isSelected ? badgeColor : Color.primary.opacity(0.05),
                in: Capsule()
            )
        }
        .buttonStyle(.plain)
    }
}

private struct ConnectionList: View {
    let page: NasConnectionPage?
    let busyConnectionIDs: Set<String>
    let onDisconnect: (NasConnection) async throws -> Void
    @State private var displayMode: DisplayMode = .list
    @State private var pendingDisconnect: NasConnection?
    @State private var operationError: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("\(page?.connections.count ?? 0) 个活跃连接")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()

                Picker("展示方式", selection: $displayMode) {
                    ForEach(DisplayMode.allCases) { mode in
                        Label(mode.rawValue, systemImage: mode.icon).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
            }
            .padding()

            if displayMode == .list {
                listContent
            } else {
                gridContent
            }
        }
        .confirmationDialog(
            "断开“\(pendingDisconnect?.account ?? "")”的连接？",
            isPresented: Binding(
                get: { pendingDisconnect != nil },
                set: { if !$0 { pendingDisconnect = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("取消", role: .cancel) { pendingDisconnect = nil }
            Button("断开连接", role: .destructive) {
                guard let connection = pendingDisconnect else { return }
                pendingDisconnect = nil
                Task {
                    do {
                        try await onDisconnect(connection)
                    } catch {
                        operationError = userMessage(
                            for: error,
                            fallback: "没有断开这个连接，请刷新后重试。"
                        )
                    }
                }
            }
        } message: {
            if pendingDisconnect?.isCurrentConnection == true {
                Text("这可能包括岚仓正在使用的会话。断开后，你可能需要重新登录 NAS。")
            } else {
                Text("对方会立即退出当前会话，需要重新登录才能继续使用 NAS。")
            }
        }
        .alert(
            "没有断开连接",
            isPresented: Binding(
                get: { operationError != nil },
                set: { if !$0 { operationError = nil } }
            )
        ) {
            Button("确定") { operationError = nil }
        } message: {
            Text(operationError ?? "请刷新后重试。")
        }
    }

    private var listContent: some View {
        List(page?.connections ?? []) { connection in
            HStack(spacing: 12) {
                Image(systemName: connection.isCurrentConnection ? "laptopcomputer.and.arrow.down" : "network")
                    .foregroundStyle(connection.isCurrentConnection ? Color.green : Color.accentColor)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(connection.account).font(.body.weight(.medium))
                        if connection.isCurrentConnection {
                            Text("当前连接").font(.caption2).foregroundStyle(.green)
                        }
                    }
                    Text([connection.protocolName, connection.source, connection.location].compactMap { $0 }.joined(separator: " · "))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let description = connection.description {
                        Text(description).font(.caption2).foregroundStyle(.tertiary)
                    }
                }
                Spacer()
                if let date = connection.connectedAt {
                    Text(date, format: .dateTime.month().day().hour().minute())
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if busyConnectionIDs.contains(connection.id) {
                    ProgressView()
                        .controlSize(.small)
                        .accessibilityLabel("正在断开连接")
                } else if connection.canDisconnect {
                    Button("断开") {
                        pendingDisconnect = connection
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("让这个设备或服务重新登录")
                }
            }
            .padding(.vertical, 5)
            .contentShape(Rectangle())
            .contextMenu {
                connectionMenu(for: connection)
            }
            .accessibilityElement(children: .combine)
        }
    }

    private var gridContent: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 14)], spacing: 14) {
                ForEach(page?.connections ?? []) { connection in
                    VStack(alignment: .leading, spacing: 10) {
                        HStack {
                            Image(systemName: connection.isCurrentConnection ? "laptopcomputer.and.arrow.down" : "network")
                                .font(.title3)
                                .foregroundStyle(connection.isCurrentConnection ? Color.green : Color.accentColor)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(connection.account)
                                    .font(.body.weight(.medium))
                                    .lineLimit(1)
                                if connection.isCurrentConnection {
                                    Text("当前连接")
                                        .font(.caption2.weight(.semibold))
                                        .foregroundStyle(.green)
                                }
                            }
                            Spacer()
                        }

                        Text([connection.protocolName, connection.source, connection.location].compactMap { $0 }.joined(separator: " · "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)

                        if let description = connection.description {
                            Text(description)
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                        }

                        Divider().padding(.vertical, 2)

                        HStack {
                            if let date = connection.connectedAt {
                                Text(date, format: .dateTime.month().day().hour().minute())
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer()

                            if busyConnectionIDs.contains(connection.id) {
                                ProgressView().controlSize(.small)
                            } else if connection.canDisconnect {
                                Button("断开") {
                                    pendingDisconnect = connection
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                        }
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color(nsColor: .controlBackgroundColor).opacity(0.6))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color.primary.opacity(0.08), lineWidth: 1)
                            )
                    )
                    .contentShape(Rectangle())
                    .contextMenu {
                        connectionMenu(for: connection)
                    }
                }
            }
            .padding(20)
        }
    }

    @ViewBuilder
    private func connectionMenu(for connection: NasConnection) -> some View {
        if connection.canDisconnect {
            Button("断开连接…", role: .destructive) {
                pendingDisconnect = connection
            }
        }
    }
}

private struct SectionHeader: View {
    let title: String
    let count: Int

    var body: some View {
        HStack {
            Text(title).font(.title2.weight(.semibold))
            Text("\(count)").font(.caption).foregroundStyle(.secondary)
        }
    }
}

private struct StatusPill: View {
    let text: String
    let isWarning: Bool

    var body: some View {
        Text(text)
            .font(.caption.weight(.medium))
            .foregroundStyle(isWarning ? .orange : .secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background((isWarning ? Color.orange : Color.secondary).opacity(0.1), in: Capsule())
    }
}

private struct LoadingAdministrationView: View {
    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("正在读取 NAS 信息…")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }
}

private struct AdministrationErrorView: View {
    let message: String
    let retry: () -> Void

    var body: some View {
        ContentUnavailableView {
            Label("暂时无法显示", systemImage: "exclamationmark.triangle")
        } description: {
            Text(message)
        } actions: {
            Button("重新加载", action: retry)
        }
    }
}

private func percent(_ value: Double?) -> String {
    value.map { "\($0.formatted(.number.precision(.fractionLength(0))))%" } ?? "正在读取"
}

private func speed(_ value: Int64?) -> String {
    guard let value else { return "正在读取" }
    return "\(ByteCountFormatter.string(fromByteCount: value, countStyle: .file))/秒"
}

private func byteCount(_ value: Int64?) -> String {
    value.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? "未知"
}

private func availableBytes(used: Int64?, total: Int64?) -> Int64? {
    guard let used, let total else { return nil }
    return max(0, total - used)
}

private func storageStatusText(_ status: String?) -> String? {
    guard let status, !status.isEmpty else { return nil }
    switch status.lowercased() {
    case "normal", "healthy", "good", "smart_complete":
        return "良好"
    case "background":
        return "正在检查"
    case "attention", "warning":
        return "需要注意"
    case "not_use":
        return "未初始化"
    case "sys_partition_normal":
        return "已初始化"
    case "error", "failed", "critical", "abnormal":
        return "异常"
    default:
        return status
    }
}

private func smartResultText(_ result: String) -> String {
    storageStatusText(result) ?? "未提供"
}

private func isWarning(_ status: String?) -> Bool {
    guard let status = status?.lowercased() else { return false }
    return ["error", "warning", "critical", "failed", "abnormal", "crashed", "expired"].contains {
        status.contains($0)
    }
}

private func serviceIcon(_ package: NasPackage) -> String {
    let value = "\(package.id) \(package.name)".lowercased()
    if value.contains("backup") { return "externaldrive.badge.timemachine" }
    if value.contains("surveillance") || value.contains("camera") { return "video" }
    if value.contains("monitor") { return "waveform.path.ecg" }
    if value.contains("drive") || value.contains("cloud") { return "icloud" }
    return "shippingbox"
}

private func uptimeDescription(_ seconds: Int64) -> String {
    let days = seconds / 86_400
    let hours = seconds % 86_400 / 3_600
    let minutes = seconds % 3_600 / 60
    if days > 0 { return "\(days) 天 \(hours) 小时" }
    if hours > 0 { return "\(hours) 小时 \(minutes) 分钟" }
    return "\(minutes) 分钟"
}
