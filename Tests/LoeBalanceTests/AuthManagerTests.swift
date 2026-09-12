import Foundation
import XCTest
@testable import LoeBalance

final class AuthManagerTests: XCTestCase {
    func testLoginStoresRefreshTokenButNotPasswordOrAccessToken() async throws {
        let credentials = InMemoryCredentialStore()
        let api = FakeAPIClient(session: .fixture)
        let manager = AuthManager(api: api, credentials: credentials, now: { .fixtureNow })

        try await manager.login(email: "user@example.com", password: "secret123")

        XCTAssertEqual(credentials.saved, StoredCredential(refreshToken: "refresh-token", userID: 42))
        let receivedLogin = await api.receivedLogin
        XCTAssertEqual(receivedLogin?.email, "user@example.com")
        XCTAssertEqual(receivedLogin?.password, "secret123")
    }

    func testLoginWithoutUserIDDoesNotPersistCredential() async {
        let credentials = InMemoryCredentialStore()
        let session = AuthSession(
            accessToken: "access-token",
            refreshToken: "refresh-token",
            expiresAt: .fixtureNow.addingTimeInterval(3_600),
            userID: nil
        )
        let manager = AuthManager(
            api: FakeAPIClient(session: session),
            credentials: credentials,
            now: { .fixtureNow }
        )

        await assertAppError(.invalidResponse) {
            try await manager.login(email: "user@example.com", password: "secret123")
        }
        XCTAssertNil(credentials.saved)
    }

    func testRestorePreservesStoredUserIDWhenRefreshOmitsIdentity() async throws {
        let credentials = InMemoryCredentialStore(
            StoredCredential(refreshToken: "stored-refresh-token", userID: 42)
        )
        let refreshed = AuthSession(
            accessToken: "restored-access-token",
            refreshToken: "rotated-refresh-token",
            expiresAt: .fixtureNow.addingTimeInterval(3_600),
            userID: nil
        )
        let api = FakeAPIClient(refreshResults: [.success(refreshed)])
        let manager = AuthManager(api: api, credentials: credentials, now: { .fixtureNow })

        let restoredSession = try await manager.restoreSession()
        let token = try await manager.withAccessToken { $0 }
        let receivedRefreshTokens = await api.receivedRefreshTokens

        XCTAssertTrue(restoredSession)
        XCTAssertEqual(token, "restored-access-token")
        XCTAssertEqual(receivedRefreshTokens, ["stored-refresh-token"])
        XCTAssertEqual(
            credentials.saved,
            StoredCredential(refreshToken: "rotated-refresh-token", userID: 42)
        )
    }

    func testRestoreIdentityMismatchDeletesCredentialAndRequiresLogin() async {
        let credentials = InMemoryCredentialStore(
            StoredCredential(refreshToken: "stored-refresh-token", userID: 42)
        )
        let mismatched = AuthSession(
            accessToken: "other-access-token",
            refreshToken: "other-refresh-token",
            expiresAt: .fixtureNow.addingTimeInterval(3_600),
            userID: 84
        )
        let manager = AuthManager(
            api: FakeAPIClient(refreshResults: [.success(mismatched)]),
            credentials: credentials,
            now: { .fixtureNow }
        )

        await assertAppError(.loginRequired) {
            try await manager.restoreSession()
        }
        XCTAssertNil(credentials.saved)
        XCTAssertEqual(credentials.deleteCount, 1)
        await assertAppError(.loginRequired) {
            try await manager.withAccessToken { $0 }
        }
    }

    func testAccessTokenRefreshesProactivelyNearExpiry() async throws {
        let expiring = AuthSession(
            accessToken: "expiring-access-token",
            refreshToken: "refresh-token",
            expiresAt: .fixtureNow.addingTimeInterval(30),
            userID: 42
        )
        let refreshed = AuthSession(
            accessToken: "fresh-access-token",
            refreshToken: "rotated-refresh-token",
            expiresAt: .fixtureNow.addingTimeInterval(3_600),
            userID: nil
        )
        let credentials = InMemoryCredentialStore()
        let api = FakeAPIClient(session: expiring, refreshResults: [.success(refreshed)])
        let manager = AuthManager(api: api, credentials: credentials, now: { .fixtureNow })
        try await manager.login(email: "user@example.com", password: "secret123")

        let token = try await manager.withAccessToken { $0 }
        let refreshCallCount = await api.refreshCallCount

        XCTAssertEqual(token, "fresh-access-token")
        XCTAssertEqual(refreshCallCount, 1)
        XCTAssertEqual(
            credentials.saved,
            StoredCredential(refreshToken: "rotated-refresh-token", userID: 42)
        )
    }

    func testConcurrentAccessRequestsShareOneInFlightRefresh() async throws {
        let refreshStarted = AsyncGate()
        let releaseRefresh = AsyncGate()
        let expiring = AuthSession(
            accessToken: "expiring-access-token",
            refreshToken: "refresh-token",
            expiresAt: .fixtureNow.addingTimeInterval(30),
            userID: 42
        )
        let refreshed = AuthSession(
            accessToken: "fresh-access-token",
            refreshToken: "rotated-refresh-token",
            expiresAt: .fixtureNow.addingTimeInterval(3_600),
            userID: nil
        )
        let api = FakeAPIClient(
            session: expiring,
            refreshResults: [.success(refreshed)],
            refreshStarted: refreshStarted,
            refreshGate: releaseRefresh
        )
        let manager = AuthManager(api: api, credentials: InMemoryCredentialStore(), now: { .fixtureNow })
        try await manager.login(email: "user@example.com", password: "secret123")

        async let first = manager.withAccessToken { $0 }
        async let second = manager.withAccessToken { $0 }
        await refreshStarted.wait()
        await releaseRefresh.open()
        let tokenPair = try await (first, second)
        let tokens = [tokenPair.0, tokenPair.1]
        let refreshCallCount = await api.refreshCallCount

        XCTAssertEqual(tokens, ["fresh-access-token", "fresh-access-token"])
        XCTAssertEqual(refreshCallCount, 1)
    }

    func testUnauthorizedOperationRefreshesAndReplaysExactlyOnce() async throws {
        let refreshed = AuthSession(
            accessToken: "fresh-access-token",
            refreshToken: "rotated-refresh-token",
            expiresAt: .fixtureNow.addingTimeInterval(3_600),
            userID: 42
        )
        let api = FakeAPIClient(refreshResults: [.success(refreshed)])
        let manager = AuthManager(api: api, credentials: InMemoryCredentialStore(), now: { .fixtureNow })
        let operation = UnauthorizedOnceOperation()
        try await manager.login(email: "user@example.com", password: "secret123")

        let result = try await manager.withAccessToken { token in
            try await operation.run(token: token)
        }
        let tokens = await operation.tokens
        let refreshCallCount = await api.refreshCallCount

        XCTAssertEqual(result, "accepted")
        XCTAssertEqual(tokens, ["access-token", "fresh-access-token"])
        XCTAssertEqual(refreshCallCount, 1)
    }

    func testSecondUnauthorizedIsReturnedWithoutAnotherRefreshOrThirdAttempt() async throws {
        let refreshed = AuthSession(
            accessToken: "fresh-access-token",
            refreshToken: "rotated-refresh-token",
            expiresAt: .fixtureNow.addingTimeInterval(3_600),
            userID: 42
        )
        let api = FakeAPIClient(refreshResults: [.success(refreshed)])
        let manager = AuthManager(api: api, credentials: InMemoryCredentialStore(), now: { .fixtureNow })
        let operation = AlwaysUnauthorizedOperation()
        try await manager.login(email: "user@example.com", password: "secret123")

        await assertAppError(.unauthorized) {
            try await manager.withAccessToken { token in
                try await operation.run(token: token)
            }
        }
        let tokens = await operation.tokens
        let refreshCallCount = await api.refreshCallCount

        XCTAssertEqual(tokens, ["access-token", "fresh-access-token"])
        XCTAssertEqual(refreshCallCount, 1)
    }

    func testFailedRefreshClearsCredentialAndProducesLoginRequired() async throws {
        let expiring = AuthSession(
            accessToken: "expiring-access-token",
            refreshToken: "refresh-token",
            expiresAt: .fixtureNow.addingTimeInterval(30),
            userID: 42
        )
        let credentials = InMemoryCredentialStore()
        let manager = AuthManager(
            api: FakeAPIClient(session: expiring, refreshResults: [.failure(.unauthorized)]),
            credentials: credentials,
            now: { .fixtureNow }
        )
        try await manager.login(email: "user@example.com", password: "secret123")

        await assertAppError(.loginRequired) {
            try await manager.withAccessToken { $0 }
        }
        XCTAssertNil(credentials.saved)
        XCTAssertEqual(credentials.deleteCount, 1)
        await assertAppError(.loginRequired) {
            try await manager.withAccessToken { $0 }
        }
    }

    func testLogoutDeletesCredentialAndClearsSession() async throws {
        let credentials = InMemoryCredentialStore()
        let manager = AuthManager(
            api: FakeAPIClient(session: .fixture),
            credentials: credentials,
            now: { .fixtureNow }
        )
        try await manager.login(email: "user@example.com", password: "secret123")

        try await manager.logout()

        XCTAssertNil(credentials.saved)
        XCTAssertEqual(credentials.deleteCount, 1)
        await assertAppError(.loginRequired) {
            try await manager.withAccessToken { $0 }
        }
    }

    private func assertAppError<T>(
        _ expected: AppError,
        operation: () async throws -> T,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            _ = try await operation()
            XCTFail("Expected \(expected)", file: file, line: line)
        } catch let error as AppError {
            XCTAssertEqual(error, expected, file: file, line: line)
        } catch {
            XCTFail("Expected AppError, got \(error)", file: file, line: line)
        }
    }
}

private actor UnauthorizedOnceOperation {
    private(set) var tokens: [String] = []

    func run(token: String) throws -> String {
        tokens.append(token)
        if tokens.count == 1 {
            throw AppError.unauthorized
        }
        return "accepted"
    }
}

private actor AlwaysUnauthorizedOperation {
    private(set) var tokens: [String] = []

    func run(token: String) throws -> String {
        tokens.append(token)
        throw AppError.unauthorized
    }
}
