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
        self.customInterval = String(format: "%.0f", self.preferences.refreshInterval)
        self.refreshUnit = .seconds
        self.refreshPreset = Self.preset(for: self.preferences.refreshInterval)
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
            throw SettingsError.invalidInterval
        }

        let seconds = refreshUnit == .minutes ? value * 60 : value
        preferences.setRefreshInterval(seconds)
        customInterval = String(format: "%.0f", preferences.refreshInterval)
        refreshPreset = Self.preset(for: preferences.refreshInterval)
        try preferencesStore.save(preferences)
        await scheduler.updateInterval(preferences.refreshInterval)
    }

    func setShakeStrength(_ value: ShakeStrength) {
        shakeStrength = value
        preferences.shakeStrength = value
        persistPreferences()
        onShakeStrengthChanged(value)
    }

    func setShowsDesktopCard(_ value: Bool) {
        showsDesktopCard = value
        preferences.showsDesktopCard = value
        persistPreferences()
        onShowsDesktopCardChanged(value)
    }

    func setLaunchAtLogin(_ value: Bool) throws {
        do {
            try launchAtLoginService.setEnabled(value)
            launchAtLogin = launchAtLoginService.isEnabled
            preferences.launchAtLogin = launchAtLogin
            try preferencesStore.save(preferences)
        } catch {
            launchAtLogin = launchAtLoginService.isEnabled
            throw error
        }
    }

    func logout() async {
        await logoutAction()
    }

    private func persistPreferences() {
        do {
            try preferencesStore.save(preferences)
            errorMessage = nil
        } catch {
            errorMessage = "Unable to save settings."
        }
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
