import SwiftUI

struct LoginView: View {
    @State private var model = LoginViewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 6) {
                Text("brand.name")
                    .font(.largeTitle.weight(.semibold))
                Text("M0 · API 能力发现与安全登录")
                    .foregroundStyle(.secondary)
            }

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 12) {
                formRow("设备名称") {
                    TextField("我的 NAS", text: $model.displayName)
                }
                formRow("主机") {
                    TextField("nas.example.invalid", text: $model.host)
                        .textContentType(.URL)
                }
                formRow("HTTPS 端口") {
                    TextField("5001", text: $model.port)
                        .frame(maxWidth: 120)
                }
                formRow("账号") {
                    TextField("DSM 账号", text: $model.account)
                        .textContentType(.username)
                }
                formRow("密码") {
                    SecureField("密码不会持久化", text: $model.password)
                        .textContentType(.password)
                }
                if model.requiresOTP {
                    formRow("验证码") {
                        SecureField("双重验证验证码", text: $model.otpCode)
                            .textContentType(.oneTimeCode)
                    }
                }
            }
            .textFieldStyle(.roundedBorder)
            .disabled(model.isBusy)

            HStack(spacing: 12) {
                Button {
                    Task {
                        await model.connect()
                    }
                } label: {
                    if model.isBusy {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text(model.requiresOTP ? "提交验证码" : "发现能力并登录")
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(
                    model.isBusy || model.host.isEmpty || model.account.isEmpty || model.password.isEmpty
                        || (model.requiresOTP && model.otpCode.isEmpty)
                )

                if model.isAuthenticated {
                    Label("已认证", systemImage: "checkmark.shield.fill")
                        .foregroundStyle(.green)
                }
            }

            Text(model.statusMessage)
                .foregroundStyle(model.statusIsError ? Color.red : Color.secondary)
                .textSelection(.enabled)

            Divider()

            Label(
                "当前版本仅接受系统信任的 HTTPS 证书；自签名证书首次信任尚未开放。",
                systemImage: "lock.shield"
            )
            .font(.callout)
            .foregroundStyle(.secondary)
        }
        .padding(28)
        .frame(minWidth: 560, minHeight: 520)
    }

    private func formRow<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        GridRow {
            Text(title)
                .frame(width: 90, alignment: .trailing)
            content()
                .frame(maxWidth: .infinity)
        }
    }
}
