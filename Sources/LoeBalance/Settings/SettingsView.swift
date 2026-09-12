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
                    viewModel.selectRefreshPreset($0)
                    Task { try? await viewModel.applyRefreshInterval() }
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
                    Picker("Unit", selection: $viewModel.refreshUnit) {
                        Text("Seconds").tag(RefreshIntervalUnit.seconds)
                        Text("Minutes").tag(RefreshIntervalUnit.minutes)
                    }
                    .labelsHidden()
                    Button("Apply") {
                        Task { try? await viewModel.applyRefreshInterval() }
                    }
                }
            }

            Toggle("Show Desktop Card", isOn: Binding(
                get: { viewModel.showsDesktopCard },
                set: { viewModel.setShowsDesktopCard($0) }
            ))

            Toggle("Launch at Login", isOn: Binding(
                get: { viewModel.launchAtLogin },
                set: { value in try? viewModel.setLaunchAtLogin(value) }
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
