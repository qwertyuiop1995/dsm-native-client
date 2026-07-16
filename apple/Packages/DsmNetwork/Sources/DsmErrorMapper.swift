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
                safeUserMessage: "无法开始此操作，请重试。",
                requestID: requestID
            )
        case .httpStatus(let code, let requestID):
            return mapHTTPStatus(code, requestID: requestID, context: context)
        case .responseTooLarge(let requestID), .invalidResponse(let requestID):
            return AppError(
                category: .invalidResponse,
                isRetryable: false,
                safeUserMessage: "NAS 返回的数据无法读取，请确认 DSM 已更新到受支持版本。",
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

    private static func mapHTTPStatus(
        _ code: Int,
        requestID: UUID,
        context: DsmErrorContext
    ) -> AppError {
        if code == 401 {
            return AppError(
                category: .authenticationRequired,
                isRetryable: false,
                safeUserMessage: "登录失败，请检查用户名、密码和用户权限。",
                httpStatus: code,
                requestID: requestID
            )
        }

        if code == 403 {
            if case .authentication = context {
                return AppError(
                    category: .authenticationRequired,
                    isRetryable: false,
                    safeUserMessage: "登录失败，请检查用户名、密码和用户权限。",
                    httpStatus: code,
                    requestID: requestID
                )
            }
            return AppError(
                category: .permissionDenied,
                isRetryable: false,
                safeUserMessage: "已经连接到 NAS，但当前用户没有使用 File Station 的权限。请在 DSM 中检查应用权限。",
                httpStatus: code,
                requestID: requestID
            )
        }

        return AppError(
            category: code >= 500 ? .serverBusy : .invalidResponse,
            isRetryable: code >= 500,
            safeUserMessage: code >= 500 ? "NAS 暂时无法响应，请稍后重试。" : "NAS 没有接受这次请求，请检查地址后重试。",
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
                return apiError(.authenticationRequired, false, "用户名或密码错误。", code, requestID)
            case 401:
                return apiError(.authenticationRequired, false, "这个用户已被停用。", code, requestID)
            case 402:
                return apiError(.permissionDenied, false, "当前用户没有登录权限。", code, requestID)
            case 403, 406:
                return apiError(.otpRequired, false, "需要输入双重验证验证码。", code, requestID)
            case 404 where otpWasSubmitted:
                return apiError(.otpRequired, false, "验证码不正确，请重新输入。", code, requestID)
            case 407:
                return apiError(.permissionDenied, false, "NAS 已阻止当前网络位置登录，请在 DSM 中检查自动封锁设置。", code, requestID)
            case 408:
                return apiError(.authenticationRequired, false, "密码已过期，请联系管理员处理。", code, requestID)
            case 409, 410:
                return apiError(.authenticationRequired, false, "请先在 DSM 登录页面修改密码。", code, requestID)
            default:
                break
            }
        }

        switch code {
        case 102, 103:
            return apiError(.apiUnavailable, false, "这台 NAS 暂不支持此功能。", code, requestID)
        case 104:
            return apiError(.versionUnsupported, false, "这台 NAS 的系统版本暂不受支持。", code, requestID)
        case 105:
            return apiError(.permissionDenied, false, "当前用户没有执行此操作的权限。", code, requestID)
        case 106, 107, 119:
            return apiError(.authenticationRequired, false, "登录已过期，请重新登录。", code, requestID)
        case 109, 110, 111, 117, 118:
            return apiError(.serverBusy, true, "NAS 暂时繁忙，请稍后重试。", code, requestID)
        case 150:
            return apiError(.networkUnavailable, false, "网络环境发生变化，请重新连接。", code, requestID)
        default:
            return apiError(.unknown, false, "NAS 无法完成这次操作，请稍后重试。", code, requestID)
        }
    }

    private static func mapTransportCode(_ code: Int, requestID: UUID) -> AppError {
        let urlErrorCode = URLError.Code(rawValue: code)
        switch urlErrorCode {
        case .timedOut:
            return AppError(
                category: .timeout,
                isRetryable: true,
                safeUserMessage: "连接超时，请确认 NAS 已开机并且当前网络可以访问它。",
                requestID: requestID
            )
        case .notConnectedToInternet, .networkConnectionLost, .cannotConnectToHost, .cannotFindHost:
            return AppError(
                category: .networkUnavailable,
                isRetryable: true,
                safeUserMessage: "找不到这台 NAS，请检查地址、端口和当前网络。",
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
                safeUserMessage: "无法建立安全连接。请确认地址和端口正确，并检查 NAS 的证书设置。",
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
                safeUserMessage: "连接中断，请检查网络后重试。",
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
