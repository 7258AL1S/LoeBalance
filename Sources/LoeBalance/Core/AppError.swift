import Foundation
import Security

enum AppError: Error, Equatable, Sendable {
    case invalidURL
    case transport(URLError)
    case serverStatus(Int)
    case apiEnvelope(code: Int, message: String)
    case unauthorized
    case rateLimited(retryAfter: Date?)
    case invalidResponse
    case keychainStatus(OSStatus)
    case loginChallenge
}
