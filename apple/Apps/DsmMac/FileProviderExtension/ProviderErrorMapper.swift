import DsmCore
import FileProvider
import Foundation

enum ProviderErrorMapper {
    static func map(
        _ error: Error,
        itemIdentifier: NSFileProviderItemIdentifier
    ) -> Error {
        if error is CancellationError {
            return CocoaError(.userCancelled)
        }
        if let appError = error as? AppError {
            switch appError.category {
            case .cancelled:
                return CocoaError(.userCancelled)
            case .authenticationRequired, .otpRequired:
                return NSFileProviderError(.notAuthenticated)
            case .permissionDenied:
                return CocoaError(.fileReadNoPermission)
            case .notFound:
                return NSError.fileProviderErrorForNonExistentItem(
                    withIdentifier: itemIdentifier
                )
            case .localStorageFull:
                return CocoaError(.fileWriteOutOfSpace)
            case .networkUnavailable, .timeout, .tlsUntrusted,
                 .tlsCertificateChanged, .serverBusy:
                return NSFileProviderError(.serverUnreachable)
            case .apiUnavailable, .versionUnsupported, .invalidResponse,
                 .partialFailure, .conflict, .remoteStorageFull, .unknown:
                return NSFileProviderError(.cannotSynchronize)
            }
        }
        let cocoaError = error as NSError
        if cocoaError.domain == NSFileProviderErrorDomain
            || cocoaError.domain == NSCocoaErrorDomain {
            return error
        }
        return NSFileProviderError(.serverUnreachable)
    }
}
