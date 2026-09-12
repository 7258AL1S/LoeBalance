import AppKit
import Foundation
import SwiftUI

protocol CoordinatorAuthenticating: Sendable {
    func restoreSession() async throws -> Bool
    func logout() async throws
}

protocol BalanceServicing: Sendable {
    func refresh() async throws -> RefreshResult
    func clearBaseline() async throws
}

@MainActor
protocol SettingsWindowPresenting: AnyObject {
    func present()
}

extension SettingsWindowController: SettingsWindowPresenting {}

private struct AuthManagerAdapter: CoordinatorAuthenticating {
    let manager: AuthManager

    func restoreSession() async throws -> Bool {
        try await manager.restoreSession()
    }

    func logout() async throws {
        try await manager.logout()
    }
}

private struct BalanceServiceAdapter: BalanceServicing {
    let service: BalanceService

    func refresh() async throws -> RefreshResult {
        try await service.refresh()
    }

    func clearBaseline() async throws {
        try await service.clearBaseline()
    }
}

@MainActor
private final class CoordinatorBridge {
    weak var coordinator: AppCoordinator?

    func deliver(_ result: RefreshResult) {
        coordinator?.handleRefreshResult(result)
    }

    func deliverNetworkRecovery() {
        coordinator?.networkBecameAvailable()
    }

    func refreshNow() {
        coordinator?.refreshNow()
    }

    func openSettings() {
        coordinator?.openSettings()
    }

    func toggleDesktopCard() {
        coordinator?.toggleDesktopCard()
    }

    func logout() {
        Task { await coordinator?.logout() }
    }

    func quit() {
        NSApp.terminate(nil)
    }

    func loginSucceeded() {
        coordinator?.loginSucceeded()
    }
}

@MainActor
final class AppCoordinator {
    struct Dependencies {
        let authentication: any CoordinatorAuthenticating
        let balanceService: any BalanceServicing
        let scheduler: any RefreshScheduling
        let networkMonitor: any NetworkMonitoring
        let desktopCard: any DesktopCardPresenting
        let statusBar: any StatusBarPresenting
        let settingsWindow: any SettingsWindowPresenting
        let openLogin: @MainActor () -> Void
        let initialPreferences: AppPreferences
        let reduceMotion: Bool
    }

    private let authentication: any CoordinatorAuthenticating
    private let balanceService: any BalanceServicing
    private let scheduler: any RefreshScheduling
    private let networkMonitor: any NetworkMonitoring
    private let desktopCard: any DesktopCardPresenting
    private let statusBar: any StatusBarPresenting
    private let settingsWindow: any SettingsWindowPresenting
    private let openLoginAction: @MainActor () -> Void
    private let reduceMotion: Bool

    private(set) var shakeStrength: ShakeStrength
    private(set) var showsDesktopCard: Bool
    private(set) var currentSnapshot: BalanceSnapshot?

    private var isAuthenticated = false
    private var started = false

    init(dependencies: Dependencies) {
        authentication = dependencies.authentication
        balanceService = dependencies.balanceService
        scheduler = dependencies.scheduler
        networkMonitor = dependencies.networkMonitor
        desktopCard = dependencies.desktopCard
        statusBar = dependencies.statusBar
        settingsWindow = dependencies.settingsWindow
        openLoginAction = dependencies.openLogin
        shakeStrength = dependencies.initialPreferences.shakeStrength
        showsDesktopCard = dependencies.initialPreferences.showsDesktopCard
        reduceMotion = dependencies.reduceMotion
    }

    convenience init() {
        let preferencesStore = UserDefaultsPreferencesStore(userDefaults: .standard)
        let preferences = (try? preferencesStore.load()) ?? AppPreferences()
        let api = APIClient()
        let auth = AuthManager(api: api)
        let snapshotStore = UserDefaultsSnapshotStore(userDefaults: .standard)
        let balanceService = BalanceService(api: api, auth: auth, snapshotStore: snapshotStore)
        let bridge = CoordinatorBridge()
        let scheduler = RefreshScheduler(
            interval: preferences.refreshInterval,
            refresh: {
                let result = try await balanceService.refresh()
                await MainActor.run { bridge.deliver(result) }
                return result
            }
        )
        let networkMonitor = NetworkMonitor { available in
            guard available else { return }
            Task { await scheduler.networkBecameAvailable() }
        }
        let desktopCard = DesktopCardController(preferencesStore: preferencesStore)
        let statusBar = StatusBarController(commands: StatusBarCommands(
            refreshNow: { bridge.refreshNow() },
            toggleDesktopCard: { bridge.toggleDesktopCard() },
            openSettings: { bridge.openSettings() },
            logout: { bridge.logout() },
            quit: { bridge.quit() }
        ))
        let launchAtLogin = LaunchAtLoginService()
        let settingsViewModel = SettingsViewModel(
            preferencesStore: preferencesStore,
            scheduler: scheduler,
            launchAtLogin: launchAtLogin,
            onShakeStrengthChanged: { value in bridge.coordinator?.preferenceShakeStrengthChanged(value) },
            onShowsDesktopCardChanged: { value in bridge.coordinator?.preferenceDesktopCardChanged(value) },
            logout: { await bridge.coordinator?.logout() }
        )
        let settingsWindow = SettingsWindowController(viewModel: settingsViewModel)
        let loginWindow = LoginWindowController(
            viewModel: LoginViewModel(auth: auth, onSuccess: { bridge.loginSucceeded() })
        )

        self.init(dependencies: Dependencies(
            authentication: AuthManagerAdapter(manager: auth),
            balanceService: BalanceServiceAdapter(service: balanceService),
            scheduler: scheduler,
            networkMonitor: networkMonitor,
            desktopCard: desktopCard,
            statusBar: statusBar,
            settingsWindow: settingsWindow,
            openLogin: { loginWindow.present() },
            initialPreferences: preferences,
            reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        ))
        bridge.coordinator = self
    }

    func start() async {
        guard !started else { return }
        started = true
        do {
            isAuthenticated = try await authentication.restoreSession()
        } catch {
            AppLogger.auth.error("Session restore failed: \(String(describing: error), privacy: .public)")
            isAuthenticated = false
        }

        guard isAuthenticated else {
            desktopCard.setVisible(false)
            openLoginAction()
            networkMonitor.start()
            return
        }

        networkMonitor.start()
        desktopCard.setVisible(showsDesktopCard)
        await scheduler.start()
    }

    func handleRefreshResult(_ result: RefreshResult) {
        guard isAuthenticated else { return }
        currentSnapshot = result.snapshot
        desktopCard.present(snapshot: result.snapshot, connection: result.connectionState)
        statusBar.present(
            snapshot: result.snapshot,
            connection: result.connectionState,
            showsDesktopCard: showsDesktopCard
        )
        desktopCard.play(events: result.events, shake: shakeStrength, reduceMotion: reduceMotion)
        statusBar.play(events: result.events, reduceMotion: reduceMotion)
    }

    func handleRefreshFailure(_ error: Error) {
        AppLogger.refresh.error("Refresh failed: \(String(describing: error), privacy: .public)")
    }

    func refreshNow() {
        Task { await scheduler.refreshNow() }
    }

    func openSettings() {
        settingsWindow.present()
    }

    func toggleDesktopCard() {
        preferenceDesktopCardChanged(!showsDesktopCard)
    }

    func preferenceRefreshIntervalChanged(_ seconds: TimeInterval) {
        Task { await scheduler.updateInterval(seconds) }
    }

    func preferenceShakeStrengthChanged(_ value: ShakeStrength) {
        shakeStrength = value
    }

    func preferenceDesktopCardChanged(_ visible: Bool) {
        showsDesktopCard = visible
        desktopCard.setVisible(visible && isAuthenticated)
    }

    func logout() async {
        await scheduler.stop()
        networkMonitor.stop()
        do {
            try await authentication.logout()
        } catch {
            AppLogger.auth.error("Logout failed: \(String(describing: error), privacy: .public)")
        }
        do {
            try await balanceService.clearBaseline()
        } catch {
            AppLogger.refresh.error("Snapshot baseline clear failed: \(String(describing: error), privacy: .public)")
        }
        isAuthenticated = false
        currentSnapshot = nil
        desktopCard.setVisible(false)
        openLoginAction()
    }

    func applicationDidWake() {
        guard isAuthenticated else { return }
        Task { await scheduler.systemDidWake() }
    }

    func networkBecameAvailable() {
        guard isAuthenticated else { return }
        Task { await scheduler.networkBecameAvailable() }
    }

    func stopForTermination() {
        networkMonitor.stop()
        Task { await scheduler.stop() }
    }

    fileprivate func loginSucceeded() {
        isAuthenticated = true
        started = true
        desktopCard.setVisible(showsDesktopCard)
        networkMonitor.start()
        Task { await scheduler.start() }
    }
}

@MainActor
private final class LoginWindowController: NSWindowController {
    init(viewModel: LoginViewModel) {
        let hosting = NSHostingController(rootView: LoginView(viewModel: viewModel))
        let window = NSWindow(contentViewController: hosting)
        window.title = "Sign In"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.setContentSize(NSSize(width: 340, height: 220))
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    func present() {
        showWindow(nil)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
