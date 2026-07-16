import DsmCore
import DsmNetwork
import Foundation
import Observation

@MainActor
@Observable
final class LoginViewModel {
    var displayName = "我的 NAS"
    var host = ""
    var port = "5001"
    var account = ""
    var password = ""
    var otpCode = ""
    var requiresOTP = false
    var isBusy = false
    var isAuthenticated = false
    var statusMessage = "请输入使用系统信任 HTTPS 证书的 DSM 地址。"
    var statusIsError = false

    private let profileID = UUID()
    private let repository: any AuthRepository

    init(repository: any AuthRepository = DsmAuthRepository()) {
        self.repository = repository
    }

    func connect() async {
        guard !isBusy else {
            return
        }
        isBusy = true
        statusIsError = false
        statusMessage = "正在发现 DSM API 能力…"
        defer { isBusy = false }

        do {
            guard let parsedPort = Int(port) else {
                throw NasProfileValidationError.invalidPort
            }
            let profile = try NasProfile(
                id: profileID,
                displayName: displayName,
                host: host,
                port: parsedPort
            )
            let capabilities = try await repository.discover(profile: profile)
            statusMessage = "能力发现完成，正在登录…"

            _ = try await repository.login(
                profile: profile,
                capabilities: capabilities,
                account: account,
                password: password,
                otpCode: requiresOTP ? otpCode : nil
            )

            password = ""
            otpCode = ""
            requiresOTP = false
            isAuthenticated = true
            statusMessage = "登录成功，已发现 \(capabilities.count) 项 API 能力。"
        } catch let error as AppError {
            statusIsError = true
            statusMessage = error.safeUserMessage
            isAuthenticated = false

            if error.category == .otpRequired {
                requiresOTP = true
                otpCode = ""
            } else {
                password = ""
                otpCode = ""
            }
        } catch {
            statusIsError = true
            statusMessage = error.localizedDescription
            isAuthenticated = false
            password = ""
            otpCode = ""
        }
    }
}
