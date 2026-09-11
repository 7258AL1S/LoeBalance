import Foundation

struct AuthSession: Codable, Equatable, Sendable {
    let accessToken: String
    let refreshToken: String
    let expiresAt: Date
    let userID: Int64
}

struct CurrentUserDTO: Codable, Equatable, Sendable {
    let id: Int64?
    let email: String?
    let username: String?
    let balance: Money
}

struct DashboardStatsDTO: Codable, Equatable, Sendable {
    let todayRequests: Int
    let todayActualCost: Money
}

struct UsagePageDTO: Codable, Equatable, Sendable {
    let items: [UsageRecord]
}

protocol APIClientProtocol: Sendable {
    func login(email: String, password: String) async throws -> AuthSession
    func refresh(refreshToken: String) async throws -> AuthSession
    func fetchCurrentUser(accessToken: String) async throws -> CurrentUserDTO
    func fetchDashboardStats(accessToken: String) async throws -> DashboardStatsDTO
    func fetchUsage(accessToken: String, pageSize: Int) async throws -> [UsageRecord]
}

struct APIEnvelope<Payload: Decodable>: Decodable {
    let code: Int
    let data: Payload?
    let message: String?
}

struct AuthResponseDTO: Decodable {
    struct UserDTO: Decodable {
        let id: Int64
    }

    let accessToken: String
    let refreshToken: String
    let expiresIn: TimeInterval
    let user: UserDTO?
}

struct LoginRequestDTO: Encodable {
    let email: String
    let password: String
}

struct RefreshRequestDTO: Encodable {
    let refreshToken: String
}
