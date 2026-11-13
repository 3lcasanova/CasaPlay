// CasaPlay · Designed by 𝐂𝓪sΔηⓞשα
//
// A tiny seam over URLSession so the online clients can be tested without a network.

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public struct HTTPResponse: Sendable {
    public var status: Int
    public var body: Data

    public init(status: Int, body: Data) {
        self.status = status
        self.body = body
    }
}

public protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> HTTPResponse
}

public struct URLSessionTransport: HTTPTransport {
    public init() {}

    public func send(_ request: URLRequest) async throws -> HTTPResponse {
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        return HTTPResponse(status: status, body: data)
    }
}

public enum OnlineServiceError: Error, Equatable, LocalizedError {
    case missingAPIKey(service: String)
    case badStatus(Int)
    case notFound
    case invalidResponse
    case quotaReached(message: String)

    public var errorDescription: String? {
        switch self {
        case .missingAPIKey(let service): return "Add your \(service) API key in Settings."
        case .badStatus(let code): return "The service answered with error \(code)."
        case .notFound: return "Nothing was found."
        case .invalidResponse: return "The service sent something unexpected."
        case .quotaReached(let message): return message
        }
    }
}
