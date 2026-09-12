import Foundation
@testable import LoeBalance

final class URLProtocolStub: URLProtocol, @unchecked Sendable {
    typealias Handler = @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)
    private static let lock = NSLock()
    nonisolated(unsafe) private static var handler: Handler = { _ in
        throw URLError(.badServerResponse)
    }

    static func install(_ newHandler: @escaping Handler) {
        lock.lock()
        handler = newHandler
        lock.unlock()
    }

    static func reset() {
        install { _ in throw URLError(.badServerResponse) }
    }

    private static func response(for request: URLRequest) throws -> (HTTPURLResponse, Data) {
        lock.lock()
        let currentHandler = handler
        lock.unlock()
        return try currentHandler(request)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (response, data) = try Self.response(for: request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }
    override func stopLoading() {}
}

final class LockedBox<Value>: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: Value

    init(_ value: Value) {
        storage = value
    }

    var value: Value {
        lock.lock()
        defer { lock.unlock() }
        return storage
    }

    func set(_ value: Value) {
        lock.lock()
        storage = value
        lock.unlock()
    }

    func update(_ body: (inout Value) -> Void) {
        lock.lock()
        body(&storage)
        lock.unlock()
    }
}

extension Date {
    static let fixtureNow = Date(timeIntervalSince1970: 1_800_000_000)
}

extension AuthSession {
    static let fixture = Self(
        accessToken: "access-token",
        refreshToken: "refresh-token",
        expiresAt: .fixtureNow.addingTimeInterval(3_600),
        userID: 42
    )
}

extension URLRequest {
    func bodyData() throws -> Data? {
        if let httpBody {
            return httpBody
        }
        guard let httpBodyStream else {
            return nil
        }

        httpBodyStream.open()
        defer { httpBodyStream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 1_024)
        while httpBodyStream.hasBytesAvailable {
            let count = httpBodyStream.read(&buffer, maxLength: buffer.count)
            if count < 0 {
                throw httpBodyStream.streamError ?? URLError(.cannotDecodeContentData)
            }
            if count == 0 {
                break
            }
            data.append(buffer, count: count)
        }
        return data
    }
}

actor AsyncGate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    func open() {
        isOpen = true
        let pending = waiters
        waiters.removeAll()
        pending.forEach { $0.resume() }
    }
}

actor FakeAPIClient: APIClientProtocol {
    struct LoginCall: Equatable, Sendable {
        let email: String
        let password: String
    }

    private let loginSession: AuthSession
    private var refreshResults: [Result<AuthSession, AppError>]
    private let refreshStarted: AsyncGate?
    private let refreshGate: AsyncGate?

    private(set) var receivedLogin: LoginCall?
    private(set) var receivedRefreshTokens: [String] = []

    init(
        session: AuthSession = .fixture,
        refreshResults: [Result<AuthSession, AppError>] = [.success(.fixture)],
        refreshStarted: AsyncGate? = nil,
        refreshGate: AsyncGate? = nil
    ) {
        loginSession = session
        self.refreshResults = refreshResults
        self.refreshStarted = refreshStarted
        self.refreshGate = refreshGate
    }

    var refreshCallCount: Int {
        receivedRefreshTokens.count
    }

    func login(email: String, password: String) async throws -> AuthSession {
        receivedLogin = LoginCall(email: email, password: password)
        return loginSession
    }

    func refresh(refreshToken: String) async throws -> AuthSession {
        receivedRefreshTokens.append(refreshToken)
        await refreshStarted?.open()
        await refreshGate?.wait()
        guard !refreshResults.isEmpty else {
            throw AppError.invalidResponse
        }
        return try refreshResults.removeFirst().get()
    }

    func fetchCurrentUser(accessToken: String) async throws -> CurrentUserDTO {
        throw AppError.invalidResponse
    }

    func fetchDashboardStats(accessToken: String) async throws -> DashboardStatsDTO {
        throw AppError.invalidResponse
    }

    func fetchUsage(accessToken: String, pageSize: Int) async throws -> [UsageRecord] {
        throw AppError.invalidResponse
    }
}

final class InMemoryCredentialStore: CredentialStoreProtocol, @unchecked Sendable {
    private let stored: LockedBox<StoredCredential?>
    private let deletionCount = LockedBox(0)

    init(_ credential: StoredCredential? = nil) {
        stored = LockedBox(credential)
    }

    var saved: StoredCredential? {
        stored.value
    }

    var deleteCount: Int {
        deletionCount.value
    }

    func load() throws -> StoredCredential? {
        stored.value
    }

    func save(_ credential: StoredCredential) throws {
        stored.set(credential)
    }

    func delete() throws {
        stored.set(nil)
        deletionCount.update { $0 += 1 }
    }
}
