import DsmCore
import Foundation

enum DsmErrorContext {
    case general
    case authentication(otpWasSubmitted: Bool)
}

enum DsmErrorMapper {
    static func map(_ error: DsmNetworkError, context: DsmErrorContext = .general) -> AppError {
        switch error {
        case .invalidRequest(let requestID):
            return AppError(
                category: .invalidResponse,
                isRetryable: false,
                safeUserMessage: "请求参数无效。",
                requestID: requestID
            )
        case .httpStatus(let code, let requestID):
            return mapHTTPStatus(code, requestID: requestID)
        case .responseTooLarge(let requestID), .invalidResponse(let requestID):
            return AppError(
                category: .invalidResponse,
                isRetryable: false,
                safeUserMessage: "DSM 返回了无法识别的响应。",
                requestID: requestID
            )
        case .api(let code, let requestID):
            return mapDSMCode(code, requestID: requestID, context: context)
        case .transport(let code, let requestID):
            return mapTransportCode(code, requestID: requestID)
        case .cancelled(let requestID):
            return AppError(
                category: .cancelled,
                isRetryable: false,
                safeUserMessage: "操作已取消。",
                requestID: requestID
            )
        }
    }

    private static func mapHTTPStatus(_ code: Int, requestID: UUID) -> AppError {
        if code == 401 || code == 403 {
            return AppError(
                category: .authenticationRequired,
                isRetryable: false,
                safeUserMessage: "DSM 拒绝了认证请求。",
                httpStatus: code,
                requestID: requestID
            )
        }

        return AppError(
            category: code >= 500 ? .serverBusy : .invalidResponse,
            isRetryable: code >= 500,
            safeUserMessage: code >= 500 ? "DSM 暂时不可用，请稍后重试。" : "DSM 返回了异常的 HTTP 状态。",
            httpStatus: code,
            requestID: requestID
        )
    }

    private static func mapDSMCode(
        _ code: Int,
        requestID: UUID,
        context: DsmErrorContext
    ) -> AppError {
        if case .authentication(let otpWasSubmitted) = context {
            switch code {
            case 400:
                return apiError(.authenticationRequired, false, "账号或密码错误。", code, requestID)
            case 401:
                return apiError(.authenticationRequired, false, "账号已被停用。", code, requestID)
            case 402:
                return apiError(.permissionDenied, false, "当前账号没有登录权限。", code, requestID)
            case 403, 406:
                return apiError(.otpRequired, false, "需要输入双重验证验证码。", code, requestID)
            case 404 where otpWasSubmitted:
                return apiError(.otpRequired, false, "验证码不正确，请重新输入。", code, requestID)
            case 407:
                return apiError(.permissionDenied, false, "当前网络来源已被 DSM 阻止。", code, requestID)
            case 408:
                return apiError(.authenticationRequired, false, "密码已过期，请联系管理员处理。", code, requestID)
            case 409, 410:
                return apiError(.authenticationRequired, false, "请先在 DSM 官方界面修改密码。", code, requestID)
            default:
                break
            }
        }

        switch code {
        case 102, 103:
            return apiError(.apiUnavailable, false, "此 DSM 不提供所需 API。", code, requestID)
        case 104:
            return apiError(.versionUnsupported, false, "DSM API 版本与客户端不兼容。", code, requestID)
        case 105:
            return apiError(.permissionDenied, false, "当前账号没有执行此操作的权限。", code, requestID)
        case 106, 107, 119:
            return apiError(.authenticationRequired, false, "DSM 会话已失效，请重新登录。", code, requestID)
        case 109, 110, 111, 117, 118:
            return apiError(.serverBusy, true, "DSM 暂时繁忙，请稍后重试。", code, requestID)
        case 150:
            return apiError(.networkUnavailable, false, "登录后的网络来源发生变化，请重新连接。", code, requestID)
        default:
            return apiError(.unknown, false, "DSM 无法完成请求。", code, requestID)
        }
    }

    private static func mapTransportCode(_ code: Int, requestID: UUID) -> AppError {
        let urlErrorCode = URLError.Code(rawValue: code)
        switch urlErrorCode {
        case .timedOut:
            return AppError(
                category: .timeout,
                isRetryable: true,
                safeUserMessage: "连接 DSM 超时。",
                requestID: requestID
            )
        case .notConnectedToInternet, .networkConnectionLost, .cannotConnectToHost, .cannotFindHost:
            return AppError(
                category: .networkUnavailable,
                isRetryable: true,
                safeUserMessage: "无法连接到 DSM，请检查网络和地址。",
                requestID: requestID
            )
        case .serverCertificateUntrusted,
             .serverCertificateHasBadDate,
             .serverCertificateHasUnknownRoot,
             .serverCertificateNotYetValid,
             .secureConnectionFailed:
            return AppError(
                category: .tlsUntrusted,
                isRetryable: false,
                safeUserMessage: "DSM 的 HTTPS 证书当前不受信任。",
                requestID: requestID
            )
        case .cancelled:
            return AppError(
                category: .cancelled,
                isRetryable: false,
                safeUserMessage: "操作已取消。",
                requestID: requestID
            )
        default:
            return AppError(
                category: .networkUnavailable,
                isRetryable: true,
                safeUserMessage: "连接 DSM 时发生网络错误。",
                requestID: requestID
            )
        }
    }

    private static func apiError(
        _ category: AppErrorCategory,
        _ isRetryable: Bool,
        _ message: String,
        _ code: Int,
        _ requestID: UUID
    ) -> AppError {
        AppError(
            category: category,
            isRetryable: isRetryable,
            safeUserMessage: message,
            dsmCode: code,
            requestID: requestID
        )
    }
}
