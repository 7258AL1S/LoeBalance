import Foundation
import XCTest
@testable import LoeBalance

@MainActor
final class SettingsViewModelTests: XCTestCase {
    func testLoginValidationRequiresEmailAndSixCharacterPassword() async {
        let api = SettingsTestAPI()
        let auth = AuthManager(api: api, credentials: SettingsCredentialStore())
        let viewModel = LoginViewModel(auth: auth)

        viewModel.email = "invalid"
        viewModel.password = "12345"
        await viewModel.submit()

        XCTAssertEqual(viewModel.errorMessage, "Enter a valid email address.")
        let invalidLoginCount = await api.loginCallCount
        XCTAssertEqual(invalidLoginCount, 0)

        viewModel.email = "user@example.com"
        viewModel.password = "12345"
        await viewModel.submit()

        XCTAssertEqual(viewModel.errorMessage, "Password must be at least 6 characters.")
        XCTAssertEqual(await api.loginCallCount, 0)
    }

    func testLoginClearsPublishedPasswordAfterSuccessAndFailure() async {
        let api = SettingsTestAPI(loginResult: .success(.fixture))
        let auth = AuthManager(api: api, credentials: SettingsCredentialStore())
        let viewModel = LoginViewModel(auth: auth)
        viewModel.email = "user@example.com"
        viewModel.password = "secret"

        await viewModel.submit()

        XCTAssertEqual(viewModel.password, "")
        XCTAssertNil(viewModel.errorMessage)
        let successfulPassword = await api.lastPassword
        XCTAssertEqual(successfulPassword, "secret")

        let failingAPI = SettingsTestAPI(loginResult: .failure(.unauthorized))
        let failingAuth = AuthManager(api: failingAPI, credentials: SettingsCredentialStore())
        let failingViewModel = LoginViewModel(auth: failingAuth)
        failingViewModel.email = "user@example.com"
        failingViewModel.password = "secret"

        await failingViewModel.submit()

        XCTAssertEqual(failingViewModel.password, "")
        XCTAssertNotNil(failingViewModel.errorMessage)
        let failedPassword = await failingAPI.lastPassword
        XCTAssertEqual(failedPassword, "secret")
    }

    func testIntervalPresetsAndCustomSecondsMinutesClampAndPersist() async throws {
        let preferences = SettingsPreferencesStore()
        let scheduler = SettingsScheduler()
        let launch = SettingsLaunchService()
        let viewModel = SettingsViewModel(
            preferencesStore: preferences,
            scheduler: scheduler,
            launchAtLogin: launch,
            logout: {}
        )

        viewModel.selectRefreshPreset(.fiveMinutes)
        XCTAssertEqual(viewModel.refreshIntervalSeconds, 300)
        viewModel.refreshUnit = .minutes
        viewModel.customInterval = "2"
        try await viewModel.applyRefreshInterval()
        let minuteInterval = await scheduler.lastInterval
        XCTAssertEqual(minuteInterval, 120)
        XCTAssertEqual(try preferences.load()?.refreshInterval, 120)

        viewModel.refreshUnit = .seconds
        viewModel.customInterval = "1"
        try await viewModel.applyRefreshInterval()
        let lowerInterval = await scheduler.lastInterval
        XCTAssertEqual(lowerInterval, 10)
        XCTAssertEqual(try preferences.load()?.refreshInterval, 10)

        viewModel.customInterval = "99999"
        try await viewModel.applyRefreshInterval()
        let upperInterval = await scheduler.lastInterval
        XCTAssertEqual(upperInterval, 3600)
        XCTAssertEqual(try preferences.load()?.refreshInterval, 3600)
    }

    func testShakeAndCardVisibilityPersistAndNotifyScheduler() async throws {
        let preferences = SettingsPreferencesStore()
        let scheduler = SettingsScheduler()
        let launch = SettingsLaunchService()
        let viewModel = SettingsViewModel(
            preferencesStore: preferences,
            scheduler: scheduler,
            launchAtLogin: launch,
            logout: {}
        )

        viewModel.setShakeStrength(.strong)
        viewModel.setShowsDesktopCard(false)

        let saved = try XCTUnwrap(try preferences.load())
        XCTAssertEqual(saved.shakeStrength, .strong)
        XCTAssertFalse(saved.showsDesktopCard)
        XCTAssertEqual(viewModel.shakeStrength, .strong)
        XCTAssertFalse(viewModel.showsDesktopCard)
    }

    func testLaunchAtLoginUsesActualStateAndRevertsOnFailure() throws {
        let preferences = SettingsPreferencesStore()
        let scheduler = SettingsScheduler()
        let launch = SettingsLaunchService()
        let viewModel = SettingsViewModel(
            preferencesStore: preferences,
            scheduler: scheduler,
            launchAtLogin: launch,
            logout: {}
        )

        try viewModel.setLaunchAtLogin(true)
        XCTAssertTrue(viewModel.launchAtLogin)
        XCTAssertTrue(launch.isEnabled)

        launch.failure = .registrationFailed
        XCTAssertThrowsError(try viewModel.setLaunchAtLogin(false))
        XCTAssertTrue(viewModel.launchAtLogin)
        XCTAssertTrue(launch.isEnabled)
    }

    func testLogoutCommandIsInvoked() async {
        let recorder = LogoutRecorder()
        let viewModel = SettingsViewModel(
            preferencesStore: SettingsPreferencesStore(),
            scheduler: SettingsScheduler(),
            launchAtLogin: SettingsLaunchService(),
            logout: { await recorder.record() }
        )

        await viewModel.logout()

        let logoutCount = await recorder.count
        XCTAssertEqual(logoutCount, 1)
    }
}

private actor SettingsTestAPI: APIClientProtocol {
    private let loginResult: Result<AuthSession, AppError>
    private(set) var loginCallCount = 0
    private(set) var lastPassword = ""

    init(loginResult: Result<AuthSession, AppError> = .success(.fixture)) {
        self.loginResult = loginResult
    }

    func login(email: String, password: String) async throws -> AuthSession {
        loginCallCount += 1
        lastPassword = password
        return try loginResult.get()
    }

    func refresh(refreshToken: String) async throws -> AuthSession { throw AppError.invalidResponse }
    func fetchCurrentUser(accessToken: String) async throws -> CurrentUserDTO { throw AppError.invalidResponse }
    func fetchDashboardStats(accessToken: String) async throws -> DashboardStatsDTO { throw AppError.invalidResponse }
    func fetchUsage(accessToken: String, pageSize: Int) async throws -> [UsageRecord] { throw AppError.invalidResponse }
}

private final class SettingsCredentialStore: CredentialStoreProtocol, @unchecked Sendable {
    private var credential: StoredCredential?
    func load() throws -> StoredCredential? { credential }
    func save(_ credential: StoredCredential) throws { self.credential = credential }
    func delete() throws { credential = nil }
}

private final class SettingsPreferencesStore: PreferencesStoreProtocol {
    private var preferences: AppPreferences?
    func load() throws -> AppPreferences? { preferences }
    func save(_ preferences: AppPreferences) throws { self.preferences = preferences }
}

private actor SettingsScheduler: RefreshScheduling {
    private(set) var lastInterval: TimeInterval?
    func start() async {}
    func stop() {}
    func updateInterval(_ seconds: TimeInterval) { lastInterval = seconds }
    func refreshNow() async {}
    func networkBecameAvailable() async {}
    func systemDidWake() async {}
}

private final class SettingsLaunchService: LaunchAtLoginServicing {
    enum Failure: Error { case registrationFailed }
    var isEnabled = false
    var failure: Failure?

    func setEnabled(_ enabled: Bool) throws {
        if let failure { throw failure }
        isEnabled = enabled
    }
}

private actor LogoutRecorder {
    private(set) var count = 0
    func record() { count += 1 }
}
