import SwiftUI

struct SettingsView: View {
    @ObservedObject var viewModel: SettingsViewModel

    var body: some View {
        Form {
            Picker("Shake", selection: Binding(
                get: { viewModel.shakeStrength },
                set: { viewModel.setShakeStrength($0) }
            )) {
                Text("Off").tag(ShakeStrength.off)
                Text("Weak").tag(ShakeStrength.weak)
                Text("Strong").tag(ShakeStrength.strong)
            }
            .pickerStyle(.segmented)

            Picker("Refresh", selection: Binding(
                get: { viewModel.refreshPreset },
                set: {
                    let preset = $0
                    Task {
                        do {
                            try await viewModel.chooseRefreshPreset(preset)
                        } catch {
                            // The view model restores the last persisted controls and publishes the error.
                        }
                    }
                }
            )) {
                ForEach(RefreshIntervalPreset.allCases) { preset in
                    Text(preset.title).tag(preset)
                }
            }

            if viewModel.refreshPreset == .custom {
                HStack {
                    TextField("Interval", text: $viewModel.customInterval)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 90)
                        .onSubmit {
                            Task {
                                try? await viewModel.applyRefreshInterval()
                            }
                        }
                    Text("seconds")
                        .foregroundStyle(.secondary)
                    Button("Apply") {
                        Task {
                            do {
                                try await viewModel.applyRefreshInterval()
                            } catch {
                                // The view model restores the last persisted controls and publishes the error.
                            }
                        }
                    }
                }
            }

            Toggle("Show Desktop Card", isOn: Binding(
                get: { viewModel.showsDesktopCard },
                set: { viewModel.setShowsDesktopCard($0) }
            ))

            Toggle("Launch at Login", isOn: Binding(
                get: { viewModel.launchAtLogin },
                set: { value in
                    do {
                        try viewModel.setLaunchAtLogin(value)
                    } catch {
                        // The view model restores the actual service state and publishes the error.
                    }
                }
            ))

            if let errorMessage = viewModel.errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("Log Out") {
                    Task { await viewModel.logout() }
                }
            }
        }
        .formStyle(.grouped)
        .padding(14)
        .frame(width: 390)
    }
}
