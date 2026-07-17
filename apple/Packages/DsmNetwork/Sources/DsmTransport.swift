import DsmCore
import Foundation

private final class DownloadLocationBox: @unchecked Sendable {
    private let lock = NSLock()
    private var url: URL?

    func store(_ url: URL) {
        lock.lock()
        self.url = url
        lock.unlock()
    }

    func take() -> URL? {
        lock.lock()
        defer { lock.unlock() }
        let value = url
        url = nil
        return value
    }
}

public struct DsmHTTPResponse: Sendable {
    public let data: Data
    public let statusCode: Int
    public let headers: [String: String]

    public init(data: Data, statusCode: Int, headers: [String: String] = [:]) {
        self.data = data
        self.statusCode = statusCode
        self.headers = headers
    }
}

public protocol DsmHTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> DsmHTTPResponse
}

public protocol DsmBinaryHTTPTransport: DsmHTTPTransport {
    func download(
        _ request: URLRequest,
        to destinationURL: URL,
        progress: @escaping FileTransferProgress
    ) async throws -> DsmHTTPResponse

    func upload(
        _ request: URLRequest,
        from bodyFileURL: URL,
        progress: @escaping FileTransferProgress
    ) async throws -> DsmHTTPResponse
}


public final class URLSessionTransport: DsmBinaryHTTPTransport, @unchecked Sendable {
    private let session: URLSession
    private let tlsDelegate: DsmTLSDelegate

    public init(
        configuration: URLSessionConfiguration = .ephemeral,
        expectedHost: String? = nil,
        pinnedCertificateSHA256: String? = nil,
        requiresSystemCertificateTrust: Bool = false
    ) {
        configuration.timeoutIntervalForRequest = 120
        configuration.timeoutIntervalForResource = 60 * 60
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpShouldSetCookies = false
        configuration.httpCookieAcceptPolicy = .never
        tlsDelegate = DsmTLSDelegate(
            expectedHost: expectedHost,
            pinnedFingerprint: pinnedCertificateSHA256,
            requiresSystemTrust: requiresSystemCertificateTrust
        )
        session = URLSession(
            configuration: configuration,
            delegate: tlsDelegate,
            delegateQueue: nil
        )
    }

    public func send(_ request: URLRequest) async throws -> DsmHTTPResponse {
        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw URLError(.badServerResponse)
            }
            return DsmHTTPResponse(
                data: data,
                statusCode: httpResponse.statusCode,
                headers: Self.headers(from: httpResponse)
            )
        } catch {
            if let trustError = tlsDelegate.consumeFailure() {
                throw trustError
            }
            throw error
        }
    }

    public func download(
        _ request: URLRequest,
        to destinationURL: URL,
        progress: @escaping FileTransferProgress
    ) async throws -> DsmHTTPResponse {
        let task = session.downloadTask(with: request)
        let downloadedFile = DownloadLocationBox()
        
        do {
            return try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { continuation in
                    tlsDelegate.registerTask(task, progress: progress, completion: { httpResponse, error in
                        self.tlsDelegate.unregisterTask(task)

                        if let error = error {
                            if let trustError = self.tlsDelegate.consumeFailure() {
                                continuation.resume(throwing: trustError)
                            } else {
                                continuation.resume(throwing: error)
                            }
                            return
                        }
                        guard let httpResponse = httpResponse else {
                            continuation.resume(throwing: URLError(.badServerResponse))
                            return
                        }
                        guard let srcURL = downloadedFile.take() else {
                            continuation.resume(throwing: URLError(.badServerResponse))
                            return
                        }
                        do {
                            if FileManager.default.fileExists(atPath: destinationURL.path) {
                                try FileManager.default.removeItem(at: destinationURL)
                            }
                            try FileManager.default.moveItem(at: srcURL, to: destinationURL)
                            let size = try? destinationURL.resourceValues(forKeys: [.fileSizeKey]).fileSize
                            let expected = httpResponse.expectedContentLength > 0
                                ? httpResponse.expectedContentLength
                                : size.map(Int64.init)
                            progress(Int64(size ?? 0), expected)
                            continuation.resume(returning: DsmHTTPResponse(
                                data: Data(),
                                statusCode: httpResponse.statusCode,
                                headers: Self.headers(from: httpResponse)
                            ))
                        } catch {
                            continuation.resume(throwing: error)
                        }
                    }, onDownloadFinish: { location in
                        let cacheURL = FileManager.default.temporaryDirectory
                            .appendingPathComponent("LanStashDownloadTemp-\(UUID().uuidString)")
                        do {
                            try FileManager.default.moveItem(at: location, to: cacheURL)
                            downloadedFile.store(cacheURL)
                        } catch {
                            try? FileManager.default.removeItem(at: cacheURL)
                        }
                    })

                    task.resume()
                }
            } onCancel: {
                task.cancel()
            }
        } catch {
            if let url = downloadedFile.take() {
                try? FileManager.default.removeItem(at: url)
            }
            if let trustError = tlsDelegate.consumeFailure() {
                throw trustError
            }
            throw error
        }
    }

    public func upload(
        _ request: URLRequest,
        from bodyFileURL: URL,
        progress: @escaping FileTransferProgress
    ) async throws -> DsmHTTPResponse {
        let task = session.uploadTask(with: request, fromFile: bodyFileURL)
        var responseData = Data()
        
        do {
            let size = try? bodyFileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize
            progress(0, size.map(Int64.init))
            
            return try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { continuation in
                    tlsDelegate.registerTask(task, progress: progress, completion: { httpResponse, error in
                        self.tlsDelegate.unregisterTask(task)
                    
                    if let error = error {
                        if let trustError = self.tlsDelegate.consumeFailure() {
                            continuation.resume(throwing: trustError)
                        } else {
                            continuation.resume(throwing: error)
                        }
                        return
                    }
                    guard let httpResponse = httpResponse else {
                        continuation.resume(throwing: URLError(.badServerResponse))
                        return
                    }
                    progress(Int64(size ?? 0), size.map(Int64.init))
                    continuation.resume(returning: DsmHTTPResponse(
                        data: responseData,
                        statusCode: httpResponse.statusCode,
                        headers: Self.headers(from: httpResponse)
                    ))
                    }, onDataReceive: { data in
                        responseData.append(data)
                    })

                    task.resume()
                }
            } onCancel: {
                task.cancel()
            }
        } catch {
            if let trustError = tlsDelegate.consumeFailure() {
                throw trustError
            }
            throw error
        }
    }

    private static func headers(from response: HTTPURLResponse) -> [String: String] {
        Dictionary(uniqueKeysWithValues: response.allHeaderFields.compactMap { key, value in
            guard let key = key as? String else {
                return nil
            }
            return (key.lowercased(), String(describing: value))
        })
    }
}
