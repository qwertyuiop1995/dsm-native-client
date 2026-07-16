import DsmCore
import Foundation
@testable import DsmNetwork

actor MockHTTPTransport: DsmBinaryHTTPTransport {
    private var responses: [DsmHTTPResponse]
    private var requests: [URLRequest] = []

    init(responses: [DsmHTTPResponse]) {
        self.responses = responses
    }

    func send(_ request: URLRequest) async throws -> DsmHTTPResponse {
        requests.append(request)
        guard !responses.isEmpty else {
            throw URLError(.badServerResponse)
        }
        return responses.removeFirst()
    }

    func recordedRequests() -> [URLRequest] {
        requests
    }

    func download(
        _ request: URLRequest,
        to destinationURL: URL,
        progress: @escaping FileTransferProgress
    ) async throws -> DsmHTTPResponse {
        let response = try await send(request)
        progress(0, Int64(response.data.count))
        try response.data.write(to: destinationURL)
        progress(Int64(response.data.count), Int64(response.data.count))
        return response
    }

    func upload(
        _ request: URLRequest,
        from bodyFileURL: URL,
        progress: @escaping FileTransferProgress
    ) async throws -> DsmHTTPResponse {
        let size = Int64((try? bodyFileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        progress(0, size)
        let response = try await send(request)
        progress(size, size)
        return response
    }
}
