import DsmCore
import SwiftUI

struct RootView: View {
    @Bindable var model: AppModel

    var body: some View {
        Group {
            if let workspace = model.workspace {
                WorkspaceView(
                    model: workspace,
                    profiles: model.profiles,
                    selectedProfileID: model.selectedProfileID,
                    connectedWorkspaces: model.connectedWorkspaces,
                    connectionRoute: model.currentConnectionRoute,
                    onAddNAS: {
                        model.newProfile()
                    },
                    onSelectNAS: { profileID in
                        model.selectProfile(id: profileID)
                    },
                    hasFileClipboard: model.fileClipboard != nil && !model.isPreparingPaste,
                    onCopy: { items in model.placeOnClipboard(items, moveSource: false) },
                    onCut: { items in model.placeOnClipboard(items, moveSource: true) },
                    onPaste: model.pasteClipboardIntoCurrentFolder,
                    onRenameNAS: { name in model.renameCurrentNAS(to: name) },
                    onLogout: {
                        await model.logout()
                    },
                    onSessionExpired: { message in
                        await model.returnToLoginAfterSessionIssue(message: message)
                    }
                )
            } else {
                LoginView(model: model)
            }
        }
        .frame(minWidth: 980, minHeight: 640)
        .alert("发现同名项目", isPresented: Binding(
            get: { model.pendingPasteConflict != nil },
            set: { if !$0 { model.cancelPendingPaste() } }
        )) {
            Button("取消", role: .cancel) {
                model.cancelPendingPaste()
            }
            Button("跳过同名项目") {
                model.resolvePendingPaste(replaceExisting: false)
            }
            Button("替换同名项目", role: .destructive) {
                model.resolvePendingPaste(replaceExisting: true)
            }
        } message: {
            if let prompt = model.pendingPasteConflict {
                Text(pasteConflictMessage(prompt))
            }
        }
    }

    private func pasteConflictMessage(_ prompt: PasteConflictPrompt) -> String {
        let count = prompt.conflictingNames.count
        let examples = prompt.conflictingNames.prefix(3).map { "“\($0)”" }.joined(separator: "、")
        let suffix = count > 3 ? "等，共 \(count) 个项目" : ""
        return "目标文件夹中已有同名项目：\(examples)\(suffix)。你可以跳过这些项目，或用正在粘贴的项目替换它们。"
    }
}

struct LoginView: View {
    enum Field: Hashable {
        case displayName
        case host
        case port
        case account
        case password
        case otp
    }

    @Bindable var model: AppModel
    @FocusState private var focusedField: Field?
    @State private var confirmsProfileDeletion = false
    @State private var showsAdvancedConnectionSettings = false

    var body: some View {
        NavigationSplitView {
            profileSidebar
                .navigationSplitViewColumnWidth(min: 220, ideal: 250, max: 300)
        } detail: {
            connectionForm
        }
        .navigationSplitViewStyle(.balanced)
        .sheet(item: $model.pendingCertificate) { prompt in
            CertificateReviewView(
                prompt: prompt,
                onCancel: model.cancelCertificateReview,
                onTrust: {
                    Task { await model.acceptPendingCertificate() }
                }
            )
        }
        .alert("移除这台 NAS？", isPresented: $confirmsProfileDeletion) {
            Button("取消", role: .cancel) {}
            Button("移除", role: .destructive) {
                Task { await model.deleteSelectedProfile() }
            }
        } message: {
            Text("这会删除本机保存的地址和登录信息，不会删除 NAS 上的任何文件。")
        }
        .onChange(of: model.requiresOTP) { _, required in
            if required {
                focusedField = .otp
            }
        }
    }

    private var profileSidebar: some View {
        VStack(spacing: 0) {
            List(selection: $model.selectedProfileID) {
                Section("NAS") {
                    ForEach(model.profiles) { profile in
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(profile.displayName)
                                Text(profile.portOverride.map { "\(profile.host):\($0)" } ?? profile.host)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "externaldrive.connected.to.line.below")
                                .foregroundStyle(.blue)
                        }
                        .tag(profile.id)
                        .contextMenu {
                            Button("移除这台 NAS", role: .destructive) {
                                model.selectedProfileID = profile.id
                                model.selectProfile(id: profile.id)
                                confirmsProfileDeletion = true
                            }
                        }
                    }
                }
            }
            .onChange(of: model.selectedProfileID) { _, id in
                model.selectProfile(id: id)
            }

            Divider()
            HStack {
                Button {
                    model.newProfile()
                    focusedField = .displayName
                } label: {
                    Label("添加 NAS", systemImage: "plus")
                }
                .buttonStyle(.borderless)
                Spacer()
            }
            .padding(12)
        }
    }

    private var connectionForm: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 12) {
                        Image(systemName: "externaldrive.fill.badge.wifi")
                            .font(.system(size: 34, weight: .semibold))
                            .foregroundStyle(.blue)
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("岚仓")
                                .font(.largeTitle.weight(.semibold))
                            Text("安全地浏览和管理 Synology NAS 中的文件")
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 14) {
                        Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 14) {
                            formRow("设备名称") {
                                TextField("例如：家里的 NAS", text: $model.displayName)
                                    .focused($focusedField, equals: .displayName)
                            }
                            formRow("NAS 地址") {
                                TextField(
                                    "使用 QuickConnect 时会自动优先尝试直接连接；也可以粘贴完整的 HTTPS 地址。",
                                    text: $model.host
                                )
                                .textContentType(.URL)
                                .accessibilityLabel("NAS 地址")
                                .accessibilityHint("可以输入 QuickConnect ID、IP、域名或完整的 HTTPS 地址")
                                .focused($focusedField, equals: .host)
                            }
                            formRow("用户名") {
                                TextField("NAS 登录用户名", text: $model.account)
                                    .textContentType(.username)
                                    .focused($focusedField, equals: .account)
                            }
                            formRow("密码") {
                                VStack(alignment: .leading, spacing: 6) {
                                    SecureField(
                                        model.rememberPassword ? "已安全保存在这台 Mac 上" : "密码不会保存",
                                        text: $model.password
                                    )
                                    .textContentType(.password)
                                    .focused($focusedField, equals: .password)
                                    HStack(spacing: 18) {
                                        Toggle(
                                            "在这台 Mac 上记住密码",
                                            isOn: Binding(
                                                get: { model.rememberPassword },
                                                set: { model.setRememberPassword($0) }
                                            )
                                        )
                                        .help("使用应用内加密存储保存密码")

                                        Toggle(
                                            "自动登录",
                                            isOn: Binding(
                                                get: { model.autoLoginEnabled },
                                                set: { model.setAutoLoginEnabled($0) }
                                            )
                                        )
                                        .help("下次打开岚仓时自动连接这台 NAS")
                                    }
                                    .toggleStyle(.checkbox)
                                    .font(.callout)
                                }
                            }
                            if model.requiresOTP {
                                formRow("验证码") {
                                    SecureField("输入 6 位验证码", text: $model.otpCode)
                                        .textContentType(.oneTimeCode)
                                        .focused($focusedField, equals: .otp)
                                }
                            }
                        }

                        Divider()

                        DisclosureGroup(isExpanded: $showsAdvancedConnectionSettings) {
                            Grid(alignment: .leading, horizontalSpacing: 16, verticalSpacing: 8) {
                                formRow("自定义端口") {
                                    VStack(alignment: .leading, spacing: 4) {
                                        TextField("自动", text: $model.port)
                                            .frame(maxWidth: 140)
                                            .focused($focusedField, equals: .port)
                                        Text("留空时由岚仓自动选择；填写后将优先使用这个端口。")
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                            .padding(.top, 10)
                        } label: {
                            Label("高级连接设置", systemImage: "gearshape")
                        }
                    }
                    .textFieldStyle(.roundedBorder)
                    .disabled(model.isBusy)
                    .padding(8)
                } label: {
                    Label("连接到 NAS", systemImage: "lock.shield")
                }

                StatusBanner(
                    message: model.statusMessage,
                    isError: model.statusIsError,
                    isBusy: model.isBusy
                )

                HStack(spacing: 12) {
                    Button {
                        Task { await model.connect() }
                    } label: {
                        Label(
                            model.requiresOTP ? "验证并连接" : "连接",
                            systemImage: "arrow.right.circle.fill"
                        )
                        .frame(minWidth: 112)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
                    .disabled(
                        model.isBusy || model.host.isEmpty || model.account.isEmpty || model.password.isEmpty
                            || (model.requiresOTP && model.otpCode.isEmpty)
                    )

                    Spacer()

                    if model.selectedProfileID != nil {
                        Button("移除这台 NAS", role: .destructive) {
                            confirmsProfileDeletion = true
                        }
                    }
                }

                Label(
                    "首次连接时可能需要核对这台 NAS 的安全信息；如果以后发生变化，岚仓会立即提醒你。",
                    systemImage: "checkmark.shield"
                )
                .font(.callout)
                .foregroundStyle(.secondary)
            }
            .padding(40)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(.background)
    }

    private func formRow<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        GridRow {
            Text(title)
                .frame(width: 96, alignment: .trailing)
            content()
                .frame(maxWidth: .infinity)
        }
    }
}

private struct StatusBanner: View {
    let message: String
    let isError: Bool
    let isBusy: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            if isBusy {
                ProgressView()
                    .controlSize(.small)
            } else {
                Image(systemName: isError ? "exclamationmark.triangle.fill" : "info.circle.fill")
                    .foregroundStyle(isError ? .red : .blue)
                    .accessibilityHidden(true)
            }
            Text(message)
                .textSelection(.enabled)
            Spacer()
        }
        .padding(12)
        .background(isError ? Color.red.opacity(0.08) : Color.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(isBusy ? "连接状态" : isError ? "连接失败" : "提示")：\(message)"
        )
    }
}

private struct CertificateReviewView: View {
    let prompt: CertificatePrompt
    let onCancel: () -> Void
    let onTrust: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 12) {
                Image(systemName: prompt.isCertificateChange ? "exclamationmark.shield.fill" : "checkmark.shield.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(prompt.isCertificateChange ? .red : .orange)
                VStack(alignment: .leading, spacing: 4) {
                    Text(prompt.isCertificateChange ? "安全信息发生变化" : "确认这台 NAS")
                        .font(.title2.weight(.semibold))
                    Text(prompt.review.host)
                        .foregroundStyle(.secondary)
                }
            }

            Text(
                prompt.isCertificateChange
                    ? "这台 NAS 提供的安全信息与上次不同。如果你没有刚刚更新过 NAS 证书，请取消并检查设备。"
                    : "系统无法自动确认这台 NAS 的身份。请在 DSM 控制面板或浏览器中核对下面的安全指纹，一致后再继续。"
            )

            GroupBox("本次连接") {
                LabeledContent("设备地址", value: prompt.review.host)
                LabeledContent("证书名称", value: prompt.review.subjectSummary)
                LabeledContent("安全指纹") {
                    Text(prompt.review.formattedFingerprint)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                }
            }

            if let previous = prompt.formattedPreviousFingerprint, prompt.isCertificateChange {
                GroupBox("上次连接使用的安全指纹") {
                    Text(previous)
                        .font(.system(.callout, design: .monospaced))
                        .textSelection(.enabled)
                }
            }

            if !prompt.review.canBePinned {
                Label("这份证书已过期或无法用于安全连接，请先在 NAS 中更新证书。", systemImage: "xmark.octagon.fill")
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("取消", action: onCancel)
                    .keyboardShortcut(.cancelAction)
                if prompt.review.canBePinned {
                    Button(prompt.isCertificateChange ? "确认更换并继续" : "我已核对，继续连接", action: onTrust)
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding(28)
        .frame(width: 620)
    }
}
