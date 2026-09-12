import Foundation

extension AppError {
    static var loginRequired: Self { .loginChallenge }
}

actor AuthManager {
    private static let proactiveRefreshInterval: TimeInterval = 60

    private let api: any APIClientProtocol
    private let credentials: any CredentialStoreProtocol
    private let now: @Sendable () -> Date

    private var activeSession: AuthSession?
    private var inFlightRefresh: Task<AuthSession, Error>?
    private var inFlightRefreshID: Int?
    private var nextRefreshID = 0
    private var sessionRevision = 0

    init(
        api: any APIClientProtocol,
        credentials: any CredentialStoreProtocol = KeychainCredentialStore(),
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.api = api
        self.credentials = credentials
        self.now = now
    }

    func login(email: String, password: String) async throws {
        let session = try await api.login(email: email, password: password)
        guard let userID = session.userID else {
            throw AppError.invalidResponse
        }

        let credential = StoredCredential(refreshToken: session.refreshToken, userID: userID)
        try credentials.save(credential)
        replaceActiveSession(session)
    }

    func restoreSession() async throws -> Bool {
        guard let stored = try credentials.load() else {
            clearActiveSession()
            return false
        }

        let placeholder = AuthSession(
            accessToken: "",
            refreshToken: stored.refreshToken,
            expiresAt: .distantPast,
            userID: stored.userID
        )
        replaceActiveSession(placeholder)
        _ = try await refreshActiveSession()
        return true
    }

    func withAccessToken<T: Sendable>(
        _ operation: @Sendable (String) async throws -> T
    ) async throws -> T {
        let session = try await usableSession()
        do {
            return try await operation(session.accessToken)
        } catch AppError.unauthorized {
            let retrySession: AuthSession
            if let current = activeSession, current.accessToken != session.accessToken {
                retrySession = current
            } else {
                retrySession = try await refreshActiveSession()
            }
            return try await operation(retrySession.accessToken)
        }
    }

    func logout() throws {
        inFlightRefresh?.cancel()
        inFlightRefresh = nil
        inFlightRefreshID = nil
        clearActiveSession()
        try credentials.delete()
    }

    private func usableSession() async throws -> AuthSession {
        guard let session = activeSession, session.userID != nil else {
            throw AppError.loginRequired
        }
        if session.expiresAt.timeIntervalSince(now()) <= Self.proactiveRefreshInterval {
            return try await refreshActiveSession()
        }
        return session
    }

    private func refreshActiveSession() async throws -> AuthSession {
        if let task = inFlightRefresh, let refreshID = inFlightRefreshID {
            return try await awaitRefresh(task, id: refreshID)
        }
        guard let session = activeSession, let userID = session.userID else {
            throw AppError.loginRequired
        }

        nextRefreshID += 1
        let refreshID = nextRefreshID
        let revision = sessionRevision
        let refreshToken = session.refreshToken
        let task = Task<AuthSession, Error> { [api] in
            let refreshed: AuthSession
            do {
                refreshed = try await api.refresh(refreshToken: refreshToken)
            } catch {
                try self.failRefresh(forRevision: revision)
            }
            return try self.acceptRefresh(
                refreshed,
                expectedUserID: userID,
                revision: revision
            )
        }
        inFlightRefresh = task
        inFlightRefreshID = refreshID
        return try await awaitRefresh(task, id: refreshID)
    }

    private func awaitRefresh(_ task: Task<AuthSession, Error>, id: Int) async throws -> AuthSession {
        defer {
            if inFlightRefreshID == id {
                inFlightRefresh = nil
                inFlightRefreshID = nil
            }
        }
        return try await task.value
    }

    private func acceptRefresh(
        _ refreshed: AuthSession,
        expectedUserID: Int64,
        revision: Int
    ) throws -> AuthSession {
        guard revision == sessionRevision else {
            throw AppError.loginRequired
        }
        guard refreshed.userID == nil || refreshed.userID == expectedUserID else {
            invalidateSession()
            throw AppError.loginRequired
        }

        let verified = AuthSession(
            accessToken: refreshed.accessToken,
            refreshToken: refreshed.refreshToken,
            expiresAt: refreshed.expiresAt,
            userID: expectedUserID
        )
        do {
            try credentials.save(
                StoredCredential(refreshToken: verified.refreshToken, userID: expectedUserID)
            )
        } catch {
            invalidateSession()
            throw error
        }
        activeSession = verified
        return verified
    }

    private func failRefresh(forRevision revision: Int) throws -> Never {
        if revision == sessionRevision {
            invalidateSession()
        }
        throw AppError.loginRequired
    }

    private func replaceActiveSession(_ session: AuthSession) {
        inFlightRefresh?.cancel()
        inFlightRefresh = nil
        inFlightRefreshID = nil
        sessionRevision += 1
        activeSession = session
    }

    private func clearActiveSession() {
        sessionRevision += 1
        activeSession = nil
    }

    private func invalidateSession() {
        inFlightRefresh?.cancel()
        inFlightRefresh = nil
        inFlightRefreshID = nil
        clearActiveSession()
        try? credentials.delete()
    }
}
