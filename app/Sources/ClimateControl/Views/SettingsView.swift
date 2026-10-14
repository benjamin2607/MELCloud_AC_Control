import SwiftUI

struct SettingsView: View {
    @Environment(ClimateStore.self) private var store

    var body: some View {
        Form {
            AccountSection()
            if !store.needsSignIn {
                DeviceSection()
            }
            GeneralSection()
            AboutSection()
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct AccountSection: View {
    @Environment(ClimateStore.self) private var store
    @State private var email = ""
    @State private var password = ""
    @State private var isWorking = false
    @State private var error: String?

    var body: some View {
        Section {
            if store.needsSignIn {
                TextField("Email", text: $email)
                    .textContentType(.username)
                SecureField("Password", text: $password)
                    .textContentType(.password)
                    .onSubmit(signIn)
                if let error {
                    Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                }
                HStack {
                    Spacer()
                    if isWorking { ProgressView().controlSize(.small) }
                    Button("Sign In", action: signIn)
                        .keyboardShortcut(.defaultAction)
                        .disabled(email.isEmpty || password.isEmpty || isWorking)
                }
            } else {
                LabeledContent("Signed in as", value: store.accountEmail ?? "–")
                HStack {
                    Spacer()
                    Button("Sign Out", role: .destructive) { Task { await store.signOut() } }
                }
            }
        } header: {
            Text("MELCloud Account")
        } footer: {
            if store.needsSignIn {
                Text("Use the same login as the MELCloud app. Your password is only sent to MELCloud and is never stored; the app keeps just the session token in your Keychain.")
                    .foregroundStyle(.secondary)
            }
        }
        .onAppear { email = store.accountEmail ?? email }
    }

    private func signIn() {
        guard !email.isEmpty, !password.isEmpty else { return }
        isWorking = true
        error = nil
        Task {
            do {
                try await store.signIn(email: email.trimmingCharacters(in: .whitespaces), password: password)
                password = ""
            } catch {
                self.error = (error as? LocalizedError)?.errorDescription ?? "Sign-in failed."
            }
            isWorking = false
        }
    }
}

private struct DeviceSection: View {
    @Environment(ClimateStore.self) private var store

    var body: some View {
        Section("Air Conditioner") {
            if store.devices.isEmpty {
                Text("No devices loaded yet.").foregroundStyle(.secondary)
            } else {
                Picker("Show in menu bar", selection: Binding(
                    get: { store.device?.id ?? store.devices.first?.id ?? 0 },
                    set: { store.selectDevice($0) }
                )) {
                    ForEach(store.devices) { Text($0.name).tag($0.id) }
                }
            }
            if let device = store.device {
                ModeVisibility(device: device)
            }
        }
    }
}

private struct ModeVisibility: View {
    @Environment(ClimateStore.self) private var store
    let device: ACDevice

    var body: some View {
        LabeledContent("Shown modes") {
            HStack(spacing: 6) {
                ForEach(device.operationModes, id: \.self) { mode in
                    let isShown = !store.preferences.hiddenModes.contains(mode)
                    Toggle(isOn: Binding(
                        get: { isShown },
                        set: { show in
                            if show { store.preferences.hiddenModes.remove(mode) } else { store.preferences.hiddenModes.insert(mode) }
                        }
                    )) {
                        Label(mode.title, systemImage: mode.symbol)
                    }
                    .toggleStyle(.button)
                    .help(isShown ? "Hide \(mode.title)" : "Show \(mode.title)")
                }
            }
        }
    }
}

private struct GeneralSection: View {
    @Environment(ClimateStore.self) private var store

    var body: some View {
        let preferences = store.preferences
        Section("General") {
            Toggle("Launch at login", isOn: Binding(
                get: { preferences.launchAtLogin },
                set: { preferences.setLaunchAtLogin($0) }
            ))
            .disabled(!preferences.canManageLoginItem)
            if !preferences.canManageLoginItem {
                Text("Available when running the installed ClimateControl.app.")
                    .font(.caption).foregroundStyle(.secondary)
            } else if preferences.launchAtLoginNeedsApproval {
                Text("Approve ClimateControl in System Settings › General › Login Items.")
                    .font(.caption).foregroundStyle(.orange)
            }
        }
        .onAppear { preferences.refreshLoginItemStatus() }
    }
}

private struct AboutSection: View {
    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }

    var body: some View {
        Section("About") {
            LabeledContent("Version", value: version)
            Link("Source code on GitHub", destination: URL(string: "https://github.com/benjamin2607/melcloud_macos_popover")!)
            Text("Not affiliated with or endorsed by Mitsubishi Electric. MELCloud is a trademark of Mitsubishi Electric Corporation.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
