import Foundation
import SwiftUI

enum RefreshIntervalUnit: String, CaseIterable, Identifiable, Sendable {
    case seconds
    case minutes

    var id: Self { self }
}

enum RefreshIntervalPreset: String, CaseIterable, Identifiable, Sendable {
    case thirtySeconds
    case oneMinute
    case fiveMinutes
    case custom

    var id: Self { self }

    var title: String {
        switch self {
        case .thirtySeconds: "30 seconds"
        case .oneMinute: "1 minute"
        case .fiveMinutes: "5 minutes"
        case .custom: "Custom"
        }
    }

    var seconds: TimeInterval? {
        switch self {
        case .thirtySeconds: 30
        case .oneMinute: 60
        case .fiveMinutes: 300
        case .custom: nil
        }
    }
}

@MainActor
final class SettingsViewModel: ObservableObject {
    @Published var shakeStrength: ShakeStrength
    @Published var showsDesktopCard: Bool
    @Published var launchAtLogin: Bool
    @Published var refreshPreset: RefreshIntervalPreset
    @Published var customInterval: String
    @Published var refreshUnit: RefreshIntervalUnit
    @Published var errorMessage: String?

    var refreshIntervalSeconds: TimeInterval {
        if let presetSeconds = refreshPreset.seconds {
            return presetSeconds
        }
        guard let value = Double(customInterval), value.isFinite else { return 0 }
        return refreshUnit == .minutes ? value * 60 : value
    }

    private let preferencesStore: any PreferencesStoreProtocol
    private let scheduler: any RefreshScheduling
    private let launchAtLoginService: any LaunchAtLoginServicing
    private var preferences: AppPreferences
    private var persistedRefreshPreset: RefreshIntervalPreset
    private var persistedCustomInterval: String
    private var persistedRefreshUnit: RefreshIntervalUnit
    private let onShakeStrengthChanged: @MainActor (ShakeStrength) -> Void
    private let onShowsDesktopCardChanged: @MainActor (Bool) -> Void
    private let logoutAction: @MainActor () async -> Void

    init(
        preferencesStore: any PreferencesStoreProtocol,
        scheduler: any RefreshScheduling,
        launchAtLogin: any LaunchAtLoginServicing,
        onShakeStrengthChanged: @escaping @MainActor (ShakeStrength) -> Void = { _ in },
        onShowsDesktopCardChanged: @escaping @MainActor (Bool) -> Void = { _ in },
        logout: @escaping @MainActor () async -> Void
    ) {
        self.preferencesStore = preferencesStore
        self.scheduler = scheduler
        self.launchAtLoginService = launchAtLogin
        self.preferences = (try? preferencesStore.load()) ?? AppPreferences()
        self.shakeStrength = self.preferences.shakeStrength
        self.showsDesktopCard = self.preferences.showsDesktopCard
        self.launchAtLogin = launchAtLogin.isEnabled
        let initialCustomInterval = String(format: "%.0f", self.preferences.refreshInterval)
        let initialRefreshUnit = RefreshIntervalUnit.seconds
        let initialRefreshPreset = Self.preset(for: self.preferences.refreshInterval)
        self.customInterval = initialCustomInterval
        self.refreshUnit = initialRefreshUnit
        self.refreshPreset = initialRefreshPreset
        self.persistedRefreshPreset = initialRefreshPreset
        self.persistedCustomInterval = initialCustomInterval
        self.persistedRefreshUnit = initialRefreshUnit
        self.onShakeStrengthChanged = onShakeStrengthChanged
        self.onShowsDesktopCardChanged = onShowsDesktopCardChanged
        self.logoutAction = logout
    }

    func selectRefreshPreset(_ preset: RefreshIntervalPreset) {
        refreshPreset = preset
        if let seconds = preset.seconds {
            refreshUnit = .seconds
            customInterval = String(format: "%.0f", seconds)
        }
    }

    func applyRefreshInterval() async throws {
        let raw = customInterval.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value = Double(raw), value.isFinite, value >= 0 else {
            restorePersistedRefreshInterval()
            errorMessage = "Enter a valid refresh interval."
            throw SettingsError.invalidInterval
        }

        let seconds = refreshUnit == .minutes ? value * 60 : value
        var candidate = preferences
        candidate.setRefreshInterval(seconds)
        let candidatePreset = Self.preset(for: candidate.refreshInterval)
        let candidateCustomInterval = String(format: "%.0f", candidate.refreshInterval)
        let candidateUnit = candidatePreset == .custom ? refreshUnit : .seconds

        do {
            try preferencesStore.save(candidate)
        } catch {
            restorePersistedRefreshInterval()
            errorMessage = "Unable to save settings."
            throw error
        }

        preferences = candidate
        refreshPreset = candidatePreset
        customInterval = candidateCustomInterval
        refreshUnit = candidateUnit
        persistedRefreshPreset = candidatePreset
        persistedCustomInterval = candidateCustomInterval
        persistedRefreshUnit = candidateUnit
        errorMessage = nil
        await scheduler.updateInterval(candidate.refreshInterval)
    }

    func setShakeStrength(_ value: ShakeStrength) {
        var candidate = preferences
        candidate.shakeStrength = value
        do {
            try preferencesStore.save(candidate)
        } catch {
            errorMessage = "Unable to save settings."
            return
        }
        preferences = candidate
        shakeStrength = value
        errorMessage = nil
        onShakeStrengthChanged(value)
    }

    func setShowsDesktopCard(_ value: Bool) {
        var candidate = preferences
        candidate.showsDesktopCard = value
        do {
            try preferencesStore.save(candidate)
        } catch {
            errorMessage = "Unable to save settings."
            return
        }
        preferences = candidate
        showsDesktopCard = value
        errorMessage = nil
        onShowsDesktopCardChanged(value)
    }

    func setLaunchAtLogin(_ value: Bool) throws {
        let previousServiceState = launchAtLoginService.isEnabled
        do {
            try launchAtLoginService.setEnabled(value)
        } catch {
            launchAtLogin = launchAtLoginService.isEnabled
            errorMessage = "Unable to update Launch at Login."
            throw error
        }

        let actualState = launchAtLoginService.isEnabled
        var candidate = preferences
        candidate.launchAtLogin = actualState
        do {
            try preferencesStore.save(candidate)
        } catch {
            do {
                try launchAtLoginService.setEnabled(previousServiceState)
            } catch {
                // Preserve the framework-reported state if rollback is unavailable.
            }
            launchAtLogin = launchAtLoginService.isEnabled
            errorMessage = "Unable to save settings."
            throw error
        }

        preferences = candidate
        launchAtLogin = actualState
        errorMessage = nil
    }

    func logout() async {
        await logoutAction()
    }

    private func restorePersistedRefreshInterval() {
        refreshPreset = persistedRefreshPreset
        customInterval = persistedCustomInterval
        refreshUnit = persistedRefreshUnit
    }

    private static func preset(for seconds: TimeInterval) -> RefreshIntervalPreset {
        switch seconds {
        case 30: .thirtySeconds
        case 60: .oneMinute
        case 300: .fiveMinutes
        default: .custom
        }
    }
}

enum SettingsError: Error, Equatable {
    case invalidInterval
}
