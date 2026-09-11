import Foundation

struct APIClient: APIClientProtocol, Sendable {
    private static let baseURL = URL(string: "https://api.loe.cx/api/v1")!

    private let session: URLSession
    private let now: @Sendable () -> Date

    init(
        session: URLSession = APIClient.makeSession(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.session = session
        self.now = now
    }

    func login(email: String, password: String) async throws -> AuthSession {
        let body = try encode(LoginRequestDTO(email: email, password: password))
        let response: AuthResponseDTO = try await request(path: "/auth/login", method: "POST", body: body)
        guard let userID = response.user?.id else {
            throw AppError.invalidResponse
        }
        return makeSession(from: response, userID: userID)
    }

    func refresh(refreshToken: String) async throws -> AuthSession {
        let body = try encode(RefreshRequestDTO(refreshToken: refreshToken))
        let response: AuthResponseDTO = try await request(path: "/auth/refresh", method: "POST", body: body)
        let userID = response.user?.id ?? Self.userID(fromAccessToken: response.accessToken)
        guard let userID else {
            throw AppError.invalidResponse
        }
        return makeSession(from: response, userID: userID)
    }

    func fetchCurrentUser(accessToken: String) async throws -> CurrentUserDTO {
        try await request(path: "/auth/me", accessToken: accessToken)
    }

    func fetchDashboardStats(accessToken: String) async throws -> DashboardStatsDTO {
        try await request(path: "/usage/dashboard/stats", accessToken: accessToken)
    }

    func fetchUsage(accessToken: String, pageSize: Int) async throws -> [UsageRecord] {
        var components = URLComponents(url: Self.baseURL.appendingPathComponent("usage"), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "page", value: "1"),
            URLQueryItem(name: "page_size", value: String(pageSize))
        ]
        guard let url = components?.url else {
            throw AppError.invalidURL
        }
        let page: UsagePageDTO = try await request(url: url, accessToken: accessToken)
        return page.items
    }

    private func makeSession(from response: AuthResponseDTO, userID: Int64) -> AuthSession {
        AuthSession(
            accessToken: response.accessToken,
            refreshToken: response.refreshToken,
            expiresAt: now().addingTimeInterval(response.expiresIn),
            userID: userID
        )
    }

    private func request<Response: Decodable>(
        path: String,
        method: String = "GET",
        accessToken: String? = nil,
        body: Data? = nil
    ) async throws -> Response {
        let url = Self.baseURL.appendingPathComponent(path.removingPrefix("/"))
        return try await request(url: url, method: method, accessToken: accessToken, body: body)
    }

    private func request<Response: Decodable>(
        url: URL,
        method: String = "GET",
        accessToken: String? = nil,
        body: Data? = nil
    ) async throws -> Response {
        var request = URLRequest(url: url, timeoutInterval: 30)
        request.httpMethod = method
        request.httpBody = body
        if body != nil {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if let accessToken {
            request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
            request.setValue("zh", forHTTPHeaderField: "Accept-Language")
            request.setValue("1", forHTTPHeaderField: "X-User-UI-Request")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError {
            throw AppError.transport(error)
        } catch {
            throw AppError.invalidResponse
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw AppError.invalidResponse
        }
        switch httpResponse.statusCode {
        case 200..<300:
            break
        case 401:
            throw AppError.unauthorized
        case 429:
            throw AppError.rateLimited(retryAfter: retryAfter(from: httpResponse))
        default:
            throw AppError.serverStatus(httpResponse.statusCode)
        }

        let envelope: APIEnvelope<Response>
        do {
            envelope = try Self.makeDecoder().decode(APIEnvelope<Response>.self, from: data)
        } catch {
            throw AppError.invalidResponse
        }
        guard envelope.code == 0 else {
            throw AppError.apiEnvelope(code: envelope.code, message: envelope.message ?? "")
        }
        guard let payload = envelope.data else {
            throw AppError.invalidResponse
        }
        return payload
    }

    private func encode<Value: Encodable>(_ value: Value) throws -> Data {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        do {
            return try encoder.encode(value)
        } catch {
            throw AppError.invalidResponse
        }
    }

    private func retryAfter(from response: HTTPURLResponse) -> Date? {
        guard let value = response.value(forHTTPHeaderField: "Retry-After") else {
            return nil
        }
        if let seconds = TimeInterval(value) {
            return now().addingTimeInterval(max(0, seconds))
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "EEE',' dd MMM yyyy HH':'mm':'ss z"
        return formatter.date(from: value)
    }

    private static func makeSession() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 30
        configuration.timeoutIntervalForResource = 30
        return URLSession(configuration: configuration)
    }

    private static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            let fractional = ISO8601DateFormatter()
            fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let date = fractional.date(from: value) {
                return date
            }
            let standard = ISO8601DateFormatter()
            standard.formatOptions = [.withInternetDateTime]
            if let date = standard.date(from: value) {
                return date
            }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Expected an ISO-8601 timestamp."
            )
        }
        return decoder
    }

    private static func userID(fromAccessToken token: String) -> Int64? {
        let segments = token.split(separator: ".", omittingEmptySubsequences: false)
        guard segments.count >= 2 else {
            return nil
        }
        var payload = String(segments[1])
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        payload += String(repeating: "=", count: (4 - payload.count % 4) % 4)
        guard let data = Data(base64Encoded: payload),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        if let subject = object["sub"] as? String {
            return Int64(subject)
        }
        if let subject = object["sub"] as? NSNumber {
            return subject.int64Value
        }
        return nil
    }
}

private extension String {
    func removingPrefix(_ prefix: Character) -> String {
        first == prefix ? String(dropFirst()) : self
    }
}
