import DsmCore
import Foundation

public enum DsmParameterValue: Equatable, Sendable {
    case string(String)
    case integer(Int)
    case boolean(Bool)
    case stringArray([String])

    fileprivate func encoded(for requestFormat: DsmRequestFormat) throws -> String {
        switch (requestFormat, self) {
        case (.form, .string(let value)):
            return value
        case (.form, .integer(let value)):
            return String(value)
        case (.form, .boolean(let value)):
            return value ? "true" : "false"
        case (.form, .stringArray(let value)):
            return try Self.jsonString(value)
        case (.json, .string(let value)):
            return try Self.jsonString(value)
        case (.json, .integer(let value)):
            return try Self.jsonString(value)
        case (.json, .boolean(let value)):
            return try Self.jsonString(value)
        case (.json, .stringArray(let value)):
            return try Self.jsonString(value)
        }
    }

    private static func jsonString<T: Encodable>(_ value: T) throws -> String {
        let data = try JSONEncoder().encode(value)
        guard let result = String(data: data, encoding: .utf8) else {
            throw EncodingError.invalidValue(
                value,
                EncodingError.Context(
                    codingPath: [],
                    debugDescription: "无法生成 UTF-8 参数。"
                )
            )
        }
        return result
    }
}

public struct DsmSessionCredential: Equatable, Sendable {
    public let sid: String
    public let synoToken: String?

    public init(sid: String, synoToken: String?) {
        self.sid = sid
        self.synoToken = synoToken
    }
}

enum DsmRequestError: Error, Sendable {
    case insecureBaseURL
    case invalidAPIPath
    case parameterEncodingFailed
}

enum FormURLEncoder {
    private static let allowedCharacters = CharacterSet(
        charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~"
    )

    static func encode(_ fields: [String: String]) throws -> Data {
        let body = try fields
            .sorted { $0.key < $1.key }
            .map { key, value in
                guard let encodedKey = key.addingPercentEncoding(withAllowedCharacters: allowedCharacters),
                      let encodedValue = value.addingPercentEncoding(withAllowedCharacters: allowedCharacters) else {
                    throw DsmRequestError.parameterEncodingFailed
                }
                return "\(encodedKey)=\(encodedValue)"
            }
            .joined(separator: "&")

        guard let data = body.data(using: .utf8) else {
            throw DsmRequestError.parameterEncodingFailed
        }
        return data
    }
}

enum DsmRequestBuilder {
    static func build(
        baseURL: URL,
        path: String,
        api: String,
        version: Int,
        method: String,
        requestFormat: DsmRequestFormat,
        parameters: [String: DsmParameterValue],
        credential: DsmSessionCredential? = nil
    ) throws -> URLRequest {
        guard baseURL.scheme?.lowercased() == NasScheme.https.rawValue,
              baseURL.host != nil,
              baseURL.user == nil,
              baseURL.password == nil,
              baseURL.query == nil,
              baseURL.fragment == nil else {
            throw DsmRequestError.insecureBaseURL
        }

        let pathSegments = path.split(separator: "/", omittingEmptySubsequences: false)
        guard !path.isEmpty,
              !path.hasPrefix("/"),
              pathSegments.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            throw DsmRequestError.invalidAPIPath
        }

        var url = baseURL.appendingPathComponent("webapi", isDirectory: true)
        for segment in pathSegments {
            url.appendPathComponent(String(segment), isDirectory: false)
        }

        var fields = [
            "api": api,
            "version": String(version),
            "method": method
        ]

        for (key, value) in parameters {
            fields[key] = try value.encoded(for: requestFormat)
        }

        if let credential {
            fields["_sid"] = credential.sid
            if let synoToken = credential.synoToken, !synoToken.isEmpty {
                fields["SynoToken"] = synoToken
            }
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(
            "application/x-www-form-urlencoded; charset=utf-8",
            forHTTPHeaderField: "Content-Type"
        )
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try FormURLEncoder.encode(fields)
        return request
    }
}
