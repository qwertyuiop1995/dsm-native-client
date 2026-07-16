import DsmCore
import Foundation

enum DsmEndpoint {
    static func baseURL(for profile: NasProfile) throws -> URL {
        var components = URLComponents()
        components.scheme = profile.scheme.rawValue
        components.host = profile.host
        components.port = profile.port
        components.path = "/"

        guard let url = components.url,
              url.scheme == NasScheme.https.rawValue,
              url.host != nil else {
            throw DsmRequestError.insecureBaseURL
        }
        return url
    }

    static func normalizeAPIPath(_ rawPath: String) -> String? {
        var path = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        if path.hasPrefix("/webapi/") {
            path.removeFirst("/webapi/".count)
        } else if path.hasPrefix("webapi/") {
            path.removeFirst("webapi/".count)
        }

        let segments = path.split(separator: "/", omittingEmptySubsequences: false)
        guard !path.isEmpty,
              !path.hasPrefix("/"),
              !path.contains("?"),
              !path.contains("#"),
              segments.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            return nil
        }
        return path
    }
}
