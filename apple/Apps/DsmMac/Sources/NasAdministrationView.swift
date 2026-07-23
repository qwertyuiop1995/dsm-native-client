import Charts
import DsmCore
import SwiftUI

struct NasSettingsView: View {
    @Bindable var model: NasSettingsModel

    var body: some View {
        NasAdministrationSplitView(
            title: "NAS 设置",
            subtitle: "查看系统、存储、账号、日志、连接与服务",
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
                    onNavigateToConnections: { model.selectedPage = .connections }
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
                StorageView(snapshot: model.storage)
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
                PackageList(packages: model.packages, title: "已安装套件")
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
                ScheduledTaskList(tasks: model.tasks)
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
                AccountDirectoryView(directory: model.accounts)
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
                ConnectionList(page: model.connections)
            }
        case .services:
            AdministrationPageContainer(
                isLoading: model.isLoading(.services),
                hasLoaded: model.hasLoaded(.services),
                hasContent: !model.services.isEmpty,
                errorMessage: model.errorMessage(for: .services),
                emptyTitle: "没有可查看的服务",
                emptyDescription: "已安装的备份、监控和其他服务会显示在这里。",
                retry: { await model.activate(.services, force: true) }
            ) {
                PackageList(packages: model.services, title: "已安装服务")
            }
        }
    }

    private func pageLabel(_ page: NasSettingsPage) -> (String, String) {
        switch page {
        case .overview: ("总览与性能", "gauge.with.dots.needle.67percent")
        case .storage: ("存储与硬盘", "internaldrive")
        case .packages: ("套件", "shippingbox")
        case .tasks: ("计划任务", "calendar.badge.clock")
        case .accounts: ("账号与权限", "person.2")
        case .logs: ("系统日志", "doc.text.magnifyingglass")
        case .connections: ("当前连接", "network")
        case .services: ("已安装服务", "square.stack.3d.up")
        }
    }
}

private struct NasAdministrationSplitView<Page: Hashable, Content: View>: View {
    let title: String
    let subtitle: String
    let pages: [Page]
    @Binding var selection: Page
    let label: (Page) -> (String, String)
    @ViewBuilder let content: () -> Content

    var body: some View {
        HSplitView {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.title2.weight(.semibold))
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(16)

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

private struct PerformanceDashboard: View {
    let overview: NasSystemOverview?
    let history: [NasPerformanceSnapshot]
    let connections: NasConnectionPage?
    @Binding var isPaused: Bool
    let refresh: () async -> Void
    let onNavigateToConnections: () -> Void

    private var latest: NasPerformanceSnapshot? { history.last }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                dashboardHeader

                LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 10)], spacing: 10) {
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
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 330), spacing: 14)], spacing: 14) {
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

    private var percentageChart: some View {
        Chart(history) { point in
            AreaMark(
                x: .value("时间", point.recordedAt),
                y: .value("使用率", point.cpuUsage),
                series: .value("项目", "处理器")
            )
            .foregroundStyle(by: .value("项目", "处理器"))
            .opacity(0.08)
            .interpolationMethod(.catmullRom)

            LineMark(
                x: .value("时间", point.recordedAt),
                y: .value("使用率", point.cpuUsage),
                series: .value("项目", "处理器")
            )
            .foregroundStyle(by: .value("项目", "处理器"))
            .interpolationMethod(.catmullRom)

            AreaMark(
                x: .value("时间", point.recordedAt),
                y: .value("使用率", point.memoryUsage),
                series: .value("项目", "内存")
            )
            .foregroundStyle(by: .value("项目", "内存"))
            .opacity(0.08)
            .interpolationMethod(.catmullRom)

            LineMark(
                x: .value("时间", point.recordedAt),
                y: .value("使用率", point.memoryUsage),
                series: .value("项目", "内存")
            )
            .foregroundStyle(by: .value("项目", "内存"))
            .interpolationMethod(.catmullRom)
        }
        .chartYScale(domain: 0...100)
        .chartYAxis {
            AxisMarks(position: .leading) {
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4, 4]))
                AxisValueLabel()
            }
        }
        .chartXAxis {
            AxisMarks {
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4, 4]))
                AxisValueLabel(format: .dateTime.hour().minute().second())
            }
        }
        .accessibilityLabel("处理器与内存使用率趋势")
    }

    private var networkChart: some View {
        Chart(history) { point in
            AreaMark(
                x: .value("时间", point.recordedAt),
                y: .value("字节每秒", point.networkReceivedBytesPerSecond),
                series: .value("方向", "接收")
            )
            .foregroundStyle(by: .value("方向", "接收"))
            .opacity(0.08)

            LineMark(
                x: .value("时间", point.recordedAt),
                y: .value("字节每秒", point.networkReceivedBytesPerSecond),
                series: .value("方向", "接收")
            )
            .foregroundStyle(by: .value("方向", "接收"))

            AreaMark(
                x: .value("时间", point.recordedAt),
                y: .value("字节每秒", point.networkSentBytesPerSecond),
                series: .value("方向", "发送")
            )
            .foregroundStyle(by: .value("方向", "发送"))
            .opacity(0.08)

            LineMark(
                x: .value("时间", point.recordedAt),
                y: .value("字节每秒", point.networkSentBytesPerSecond),
                series: .value("方向", "发送")
            )
            .foregroundStyle(by: .value("方向", "发送"))
        }
        .chartYAxis {
            AxisMarks(position: .leading) {
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4, 4]))
                AxisValueLabel(format: .byteCount(style: .file))
            }
        }
        .chartXAxis {
            AxisMarks {
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4, 4]))
                AxisValueLabel(format: .dateTime.hour().minute().second())
            }
        }
        .accessibilityLabel("网络接收与发送速率趋势")
    }

    private var storageChart: some View {
        Chart(history) { point in
            AreaMark(
                x: .value("时间", point.recordedAt),
                y: .value("字节每秒", point.diskReadBytesPerSecond),
                series: .value("操作", "读取")
            )
            .foregroundStyle(by: .value("操作", "读取"))
            .opacity(0.08)

            LineMark(
                x: .value("时间", point.recordedAt),
                y: .value("字节每秒", point.diskReadBytesPerSecond),
                series: .value("操作", "读取")
            )
            .foregroundStyle(by: .value("操作", "读取"))

            AreaMark(
                x: .value("时间", point.recordedAt),
                y: .value("字节每秒", point.diskWriteBytesPerSecond),
                series: .value("操作", "写入")
            )
            .foregroundStyle(by: .value("操作", "写入"))
            .opacity(0.08)

            LineMark(
                x: .value("时间", point.recordedAt),
                y: .value("字节每秒", point.diskWriteBytesPerSecond),
                series: .value("操作", "写入")
            )
            .foregroundStyle(by: .value("操作", "写入"))
        }
        .chartYAxis {
            AxisMarks(position: .leading) {
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4, 4]))
                AxisValueLabel(format: .byteCount(style: .file))
            }
        }
        .chartXAxis {
            AxisMarks {
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.5, dash: [4, 4]))
                AxisValueLabel(format: .dateTime.hour().minute().second())
            }
        }
        .accessibilityLabel("硬盘读取与写入速率趋势")
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
            chart.frame(height: 150)
        }
        .padding(14)
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
        VStack(alignment: .leading, spacing: 8) {
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

            if let progress {
                ProgressView(value: min(100, max(0, progress)), total: 100)
                    .tint(tint)
                    .controlSize(.small)
                    .accessibilityLabel(title)
                    .accessibilityValue(value)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor).opacity(0.8), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(Color.primary.opacity(0.06), lineWidth: 1)
        )
    }
}

private struct StorageView: View {
    let snapshot: NasStorageSnapshot?

    var body: some View {
        ScrollView {
            if let snapshot {
                VStack(alignment: .leading, spacing: 22) {
                    SectionHeader(title: "存储空间", count: snapshot.volumes.count)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 12)], spacing: 12) {
                        ForEach(snapshot.volumes) { volume in
                            CapacityCard(
                                title: volume.name,
                                subtitle: [volume.fileSystem, volume.status].compactMap { $0 }.joined(separator: " · "),
                                used: volume.usedBytes,
                                total: volume.totalBytes,
                                icon: "externaldrive"
                            )
                        }
                    }

                    SectionHeader(title: "存储池", count: snapshot.pools.count)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 12)], spacing: 12) {
                        ForEach(snapshot.pools) { pool in
                            CapacityCard(
                                title: pool.name,
                                subtitle: [pool.raidType, pool.status].compactMap { $0 }.joined(separator: " · "),
                                used: pool.usedBytes,
                                total: pool.totalBytes,
                                icon: "square.stack.3d.up"
                            )
                        }
                    }

                    SectionHeader(title: "硬盘", count: snapshot.disks.count)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 300), spacing: 12)], spacing: 12) {
                        ForEach(snapshot.disks) { disk in
                            GroupBox {
                                VStack(alignment: .leading, spacing: 9) {
                                    HStack {
                                        Label(disk.name, systemImage: disk.isSSD ? "memorychip" : "internaldrive")
                                            .font(.headline)
                                        Spacer()
                                        StatusPill(text: disk.status ?? "状态未知", isWarning: isWarning(disk.status))
                                    }
                                    if let model = disk.model {
                                        Text(model).font(.caption).foregroundStyle(.secondary)
                                    }
                                    LabeledContent("容量", value: byteCount(disk.totalBytes))
                                    LabeledContent("S.M.A.R.T.", value: disk.smartStatus ?? (disk.supportsSmartTest ? "支持检测" : "未提供"))
                                    if let temperature = disk.temperatureCelsius {
                                        LabeledContent("温度", value: "\(temperature.formatted(.number.precision(.fractionLength(0))))℃")
                                    }
                                }
                                .padding(4)
                            }
                        }
                    }
                }
                .padding(24)
            }
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
                Label(title, systemImage: icon).font(.headline)
                if !subtitle.isEmpty {
                    Text(subtitle).font(.caption).foregroundStyle(.secondary)
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
            .padding(4)
        }
    }
}

private struct PackageList: View {
    let packages: [NasPackage]
    let title: String
    @State private var searchText = ""

    private var filtered: [NasPackage] {
        guard !searchText.isEmpty else { return packages }
        return packages.filter {
            $0.name.localizedCaseInsensitiveContains(searchText)
                || $0.id.localizedCaseInsensitiveContains(searchText)
                || ($0.packageDescription?.localizedCaseInsensitiveContains(searchText) ?? false)
        }
    }

    var body: some View {
        List(filtered) { package in
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: serviceIcon(package))
                    .font(.title3)
                    .foregroundStyle(.tint)
                    .frame(width: 28)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text(package.name).font(.body.weight(.medium))
                    if let description = package.packageDescription, !description.isEmpty {
                        Text(description).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    }
                    Text([package.version, package.installType].compactMap { $0 }.joined(separator: " · "))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                StatusPill(
                    text: package.statusDescription ?? package.status ?? "状态未知",
                    isWarning: isWarning(package.status)
                )
            }
            .padding(.vertical, 5)
            .accessibilityElement(children: .combine)
        }
        .navigationTitle(title)
        .searchable(text: $searchText, prompt: "搜索名称或说明")
    }
}

private struct ScheduledTaskList: View {
    let tasks: [NasScheduledTask]

    var body: some View {
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
            }
            .padding(.vertical, 5)
            .accessibilityElement(children: .combine)
        }
    }
}

private struct AccountDirectoryView: View {
    enum Scope: String, CaseIterable, Identifiable {
        case users = "账号"
        case groups = "群组"
        var id: Self { self }
    }

    let directory: NasAccountDirectory?
    @State private var scope: Scope = .users
    @State private var searchText = ""

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
                Spacer()
                Text("这里只显示当前账号有权查看的目录信息")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()

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
                }
                .padding(.vertical, 5)
                .accessibilityElement(children: .combine)
            }
            .searchable(text: $searchText, prompt: "搜索\(scope.rawValue)")
        }
    }

    private func count(_ scope: Scope) -> Int {
        scope == .users ? directory?.users.count ?? 0 : directory?.groups.count ?? 0
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
                .frame(maxWidth: .infinity, minHeight: 70)
            }
        }
        .padding(14)
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

    var body: some View {
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
            }
            .padding(.vertical, 5)
            .accessibilityElement(children: .combine)
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
