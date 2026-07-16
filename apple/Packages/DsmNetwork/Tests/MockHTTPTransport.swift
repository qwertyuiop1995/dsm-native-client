import Foundation
@testable import DsmNetwork

actor MockHTTPTransport: DsmHTTPTransport {
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
}
