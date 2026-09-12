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
        let shortPasswordLoginCount = await api.loginCallCount
        XCTAssertEqual(shortPasswordLoginCount, 0)
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

    func testConcurrentLoginSubmitIsIgnoredBeforeValidationOrSecondRequest() async {
        let started = AsyncGate()
        let release = AsyncGate()
        let api = SettingsTestAPI(loginStarted: started, loginGate: release)
        let auth = AuthManager(api: api, credentials: SettingsCredentialStore())
        let viewModel = LoginViewModel(auth: auth)
        viewModel.email = "user@example.com"
        viewModel.password = "secret"

        let first = Task { await viewModel.submit() }
        await started.wait()
        viewModel.email = "invalid"
        viewModel.password = "short"
        let errorBeforeSecondSubmit = viewModel.errorMessage

        await viewModel.submit()

        let callsWhileInFlight = await api.loginCallCount
        XCTAssertTrue(viewModel.isSubmitting)
        XCTAssertEqual(viewModel.errorMessage, errorBeforeSecondSubmit)
        XCTAssertEqual(callsWhileInFlight, 1)
        await release.open()
        await first.value
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

    func testPreferenceSaveFailureKeepsShakeAndCardStateAndSuppressesCallbacks() {
        let preferences = SettingsPreferencesStore()
        let scheduler = SettingsScheduler()
        let launch = SettingsLaunchService()
        var shakeCallbackCount = 0
        var cardCallbackCount = 0
        let viewModel = SettingsViewModel(
            preferencesStore: preferences,
            scheduler: scheduler,
            launchAtLogin: launch,
            onShakeStrengthChanged: { _ in shakeCallbackCount += 1 },
            onShowsDesktopCardChanged: { _ in cardCallbackCount += 1 },
            logout: {}
        )
        preferences.saveError = .failed

        viewModel.setShakeStrength(.strong)
        viewModel.setShowsDesktopCard(false)

        XCTAssertEqual(viewModel.shakeStrength, .weak)
        XCTAssertTrue(viewModel.showsDesktopCard)
        XCTAssertEqual(shakeCallbackCount, 0)
        XCTAssertEqual(cardCallbackCount, 0)
        XCTAssertEqual(viewModel.errorMessage, "Unable to save settings.")
    }

    func testIntervalSaveFailureRestoresLastPersistedControlsAndDoesNotUpdateScheduler() async {
        let preferences = SettingsPreferencesStore(preferences: AppPreferences(refreshInterval: 30))
        let scheduler = SettingsScheduler()
        let viewModel = SettingsViewModel(
            preferencesStore: preferences,
            scheduler: scheduler,
            launchAtLogin: SettingsLaunchService(),
            logout: {}
        )
        viewModel.refreshPreset = .custom
        viewModel.refreshUnit = .minutes
        viewModel.customInterval = "2"
        preferences.saveError = .failed

        do {
            try await viewModel.applyRefreshInterval()
            XCTFail("Expected persistence failure")
        } catch {
            let schedulerInterval = await scheduler.lastInterval
            XCTAssertNil(schedulerInterval)
            XCTAssertEqual(viewModel.refreshPreset, .thirtySeconds)
            XCTAssertEqual(viewModel.customInterval, "30")
            XCTAssertEqual(viewModel.refreshUnit, .seconds)
            XCTAssertEqual(viewModel.errorMessage, "Unable to save settings.")
        }
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

    func testLaunchAtLoginSaveFailureRestoresActualServiceAndPreferenceState() {
        let preferences = SettingsPreferencesStore()
        let launch = SettingsLaunchService()
        let viewModel = SettingsViewModel(
            preferencesStore: preferences,
            scheduler: SettingsScheduler(),
            launchAtLogin: launch,
            logout: {}
        )
        preferences.saveError = .failed

        XCTAssertThrowsError(try viewModel.setLaunchAtLogin(true))
        XCTAssertFalse(viewModel.launchAtLogin)
        XCTAssertFalse(launch.isEnabled)
        XCTAssertEqual(viewModel.errorMessage, "Unable to save settings.")
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
    private let loginStarted: AsyncGate?
    private let loginGate: AsyncGate?
    private(set) var loginCallCount = 0
    private(set) var lastPassword = ""

    init(
        loginResult: Result<AuthSession, AppError> = .success(.fixture),
        loginStarted: AsyncGate? = nil,
        loginGate: AsyncGate? = nil
    ) {
        self.loginResult = loginResult
        self.loginStarted = loginStarted
        self.loginGate = loginGate
    }

    func login(email: String, password: String) async throws -> AuthSession {
        loginCallCount += 1
        lastPassword = password
        await loginStarted?.open()
        await loginGate?.wait()
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
    var saveError: SaveFailure?
    func load() throws -> AppPreferences? { preferences }
    func save(_ preferences: AppPreferences) throws {
        if let saveError { throw saveError }
        self.preferences = preferences
    }
}

private enum SaveFailure: Error { case failed }

private actor SettingsScheduler: RefreshScheduling {
    private(set) var lastInterval: TimeInterval?
    func start() async {}
    func stop() {}
    func updateInterval(_ seconds: TimeInterval) { lastInterval = seconds }
    func refreshNow() async {}
    func networkBecameUnavailable() {}
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
