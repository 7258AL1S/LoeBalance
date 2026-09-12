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

private actor HarnessAPI: APIClientProtocol {
    private let result: Result<AuthSession, AppError>
    private let loginStarted: AsyncGate?
    private let loginGate: AsyncGate?
    private(set) var loginCount = 0
    private(set) var lastPassword = ""

    init(
        result: Result<AuthSession, AppError>,
        loginStarted: AsyncGate? = nil,
        loginGate: AsyncGate? = nil
    ) {
        self.result = result
        self.loginStarted = loginStarted
        self.loginGate = loginGate
    }

    func login(email: String, password: String) async throws -> AuthSession {
        loginCount += 1
        lastPassword = password
        await loginStarted?.open()
        await loginGate?.wait()
        return try result.get()
    }

    func refresh(refreshToken: String) async throws -> AuthSession { throw AppError.invalidResponse }
    func fetchCurrentUser(accessToken: String) async throws -> CurrentUserDTO { throw AppError.invalidResponse }
    func fetchDashboardStats(accessToken: String) async throws -> DashboardStatsDTO { throw AppError.invalidResponse }
    func fetchUsage(accessToken: String, pageSize: Int) async throws -> [UsageRecord] { throw AppError.invalidResponse }
}

private final class HarnessCredentials: CredentialStoreProtocol, @unchecked Sendable {
    private var value: StoredCredential?
    func load() throws -> StoredCredential? { value }
    func save(_ credential: StoredCredential) throws { value = credential }
    func delete() throws { value = nil }
}

private final class HarnessPreferences: PreferencesStoreProtocol {
    private(set) var value: AppPreferences?
    var saveError: SaveFailure?
    func load() throws -> AppPreferences? { value }
    func save(_ preferences: AppPreferences) throws {
        if let saveError { throw saveError }
        value = preferences
    }
}

private enum SaveFailure: Error { case failed }

private actor HarnessScheduler: RefreshScheduling {
    private(set) var interval: TimeInterval?
    func start() async {}
    func stop() {}
    func updateInterval(_ seconds: TimeInterval) { interval = seconds }
    func refreshNow() async {}
    func networkBecameAvailable() async {}
    func systemDidWake() async {}
}

private final class HarnessLaunchService: LaunchAtLoginServicing {
    enum Failure: Error { case failed }
    var isEnabled = false
    var failure: Failure?

    func setEnabled(_ enabled: Bool) throws {
        if let failure { throw failure }
        isEnabled = enabled
    }
}

@main
@MainActor
struct Task10Harness {
    static func main() async throws {
        let session = AuthSession(
            accessToken: "access",
            refreshToken: "refresh",
            expiresAt: Date().addingTimeInterval(3_600),
            userID: 42
        )
        let api = HarnessAPI(result: .success(session))
        let auth = AuthManager(api: api, credentials: HarnessCredentials())
        let login = LoginViewModel(auth: auth)
        login.email = "invalid"
        login.password = "12345"
        await login.submit()
        require(login.errorMessage == "Enter a valid email address.", "email validation")
        let invalidLoginCount = await api.loginCount
        require(invalidLoginCount == 0, "invalid login not submitted")

        login.email = "user@example.com"
        login.password = "secret"
        await login.submit()
        require(login.password.isEmpty, "password cleared after success")
        let successfulPassword = await api.lastPassword
        require(successfulPassword == "secret", "password copied to AuthManager")

        let failingAPI = HarnessAPI(result: .failure(.unauthorized))
        let failingAuth = AuthManager(api: failingAPI, credentials: HarnessCredentials())
        let failingLogin = LoginViewModel(auth: failingAuth)
        failingLogin.email = "user@example.com"
        failingLogin.password = "secret"
        await failingLogin.submit()
        require(failingLogin.password.isEmpty, "password cleared after failure")
        require(failingLogin.errorMessage != nil, "failure reported")

        let started = AsyncGate()
        let release = AsyncGate()
        let gatedAPI = HarnessAPI(result: .success(session), loginStarted: started, loginGate: release)
        let gatedAuth = AuthManager(api: gatedAPI, credentials: HarnessCredentials())
        let gatedLogin = LoginViewModel(auth: gatedAuth)
        gatedLogin.email = "user@example.com"
        gatedLogin.password = "secret"
        let firstSubmit = Task { await gatedLogin.submit() }
        await started.wait()
        gatedLogin.email = "invalid"
        gatedLogin.password = "short"
        await gatedLogin.submit()
        let gatedCalls = await gatedAPI.loginCount
        require(gatedLogin.isSubmitting, "concurrent submit remains in flight")
        require(gatedLogin.errorMessage == nil, "concurrent submit preserves error state")
        require(gatedCalls == 1, "concurrent submit does not issue second request")
        await release.open()
        await firstSubmit.value

        let preferences = HarnessPreferences()
        let scheduler = HarnessScheduler()
        let launch = HarnessLaunchService()
        var shakeCallback: ShakeStrength?
        var cardCallback: Bool?
        var logoutCount = 0
        let settings = SettingsViewModel(
            preferencesStore: preferences,
            scheduler: scheduler,
            launchAtLogin: launch,
            onShakeStrengthChanged: { shakeCallback = $0 },
            onShowsDesktopCardChanged: { cardCallback = $0 },
            logout: { logoutCount += 1 }
        )

        settings.selectRefreshPreset(.fiveMinutes)
        require(settings.refreshIntervalSeconds == 300, "five-minute preset")
        settings.refreshPreset = .custom
        settings.refreshUnit = .minutes
        settings.customInterval = "2"
        try await settings.applyRefreshInterval()
        let minuteInterval = await scheduler.interval
        require(minuteInterval == 120, "minutes conversion")
        require(preferences.value?.refreshInterval == 120, "interval persistence")

        settings.refreshUnit = .seconds
        settings.customInterval = "1"
        try await settings.applyRefreshInterval()
        let lowerInterval = await scheduler.interval
        require(lowerInterval == 10, "lower interval clamp")
        settings.customInterval = "99999"
        try await settings.applyRefreshInterval()
        let upperInterval = await scheduler.interval
        require(upperInterval == 3_600, "upper interval clamp")

        settings.setShakeStrength(.strong)
        settings.setShowsDesktopCard(false)
        require(shakeCallback == .strong, "shake callback")
        require(cardCallback == false, "card callback")
        require(preferences.value?.shakeStrength == .strong, "shake persistence")
        require(preferences.value?.showsDesktopCard == false, "card persistence")

        let failedPreferences = HarnessPreferences()
        let failedSettings = SettingsViewModel(
            preferencesStore: failedPreferences,
            scheduler: HarnessScheduler(),
            launchAtLogin: HarnessLaunchService(),
            logout: {}
        )
        failedPreferences.saveError = .failed
        failedSettings.setShakeStrength(.strong)
        failedSettings.setShowsDesktopCard(false)
        require(failedSettings.shakeStrength == .weak, "shake rollback after save failure")
        require(failedSettings.showsDesktopCard, "card rollback after save failure")
        require(failedSettings.errorMessage == "Unable to save settings.", "save failure is visible")

        let intervalPreferences = HarnessPreferences()
        let intervalScheduler = HarnessScheduler()
        let intervalSettings = SettingsViewModel(
            preferencesStore: intervalPreferences,
            scheduler: intervalScheduler,
            launchAtLogin: HarnessLaunchService(),
            logout: {}
        )
        intervalSettings.refreshPreset = .custom
        intervalSettings.refreshUnit = .minutes
        intervalSettings.customInterval = "2"
        intervalPreferences.saveError = .failed
        do {
            try await intervalSettings.applyRefreshInterval()
            fatalError("FAIL: interval persistence failure did not throw")
        } catch {
            let interval = await intervalScheduler.interval
            require(interval == nil, "interval scheduler unchanged after save failure")
            require(intervalSettings.refreshPreset == .thirtySeconds, "refresh preset rollback")
            require(intervalSettings.customInterval == "30", "refresh value rollback")
            require(intervalSettings.refreshUnit == .seconds, "refresh unit rollback")
            require(intervalSettings.errorMessage == "Unable to save settings.", "interval failure is visible")
        }

        try settings.setLaunchAtLogin(true)
        require(settings.launchAtLogin && launch.isEnabled, "launch registration state")
        launch.failure = .failed
        do {
            try settings.setLaunchAtLogin(false)
            fatalError("FAIL: launch failure did not throw")
        } catch {
            require(settings.launchAtLogin && launch.isEnabled, "launch toggle rollback")
        }

        let launchSavePreferences = HarnessPreferences()
        let launchSaveService = HarnessLaunchService()
        let launchSaveSettings = SettingsViewModel(
            preferencesStore: launchSavePreferences,
            scheduler: HarnessScheduler(),
            launchAtLogin: launchSaveService,
            logout: {}
        )
        launchSavePreferences.saveError = .failed
        do {
            try launchSaveSettings.setLaunchAtLogin(true)
            fatalError("FAIL: launch persistence failure did not throw")
        } catch {
            require(!launchSaveSettings.launchAtLogin, "launch UI rollback after save failure")
            require(!launchSaveService.isEnabled, "launch service rollback after save failure")
            require(launchSaveSettings.errorMessage == "Unable to save settings.", "launch failure is visible")
        }

        await settings.logout()
        require(logoutCount == 1, "logout command")
        print("task-10 harness passed: login validation/cleanup, interval settings, callbacks, launch rollback, logout")
    }
}

private actor AsyncGate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func open() {
        isOpen = true
        let pending = waiters
        waiters.removeAll()
        pending.forEach { $0.resume() }
    }
}

private func require(_ condition: @autoclosure () -> Bool, _ message: String) {
    guard condition() else { fatalError("FAIL: \(message)") }
}
