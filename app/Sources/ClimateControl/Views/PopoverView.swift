import SwiftUI

struct PopoverView: View {
    @Environment(ClimateStore.self) private var store

    var body: some View {
        Group {
            if let device = store.device {
                DeviceView(device: device)
            } else {
                PlaceholderView()
            }
        }
        .frame(width: 340)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.cornerRadius, style: .continuous)
                .strokeBorder(.white.opacity(0.08), lineWidth: 1)
        }
        .preferredColorScheme(.dark)
    }
}

private struct DeviceView: View {
    @Environment(ClimateStore.self) private var store
    let device: ACDevice

    @Environment(UpdateChecker.self) private var updates

    private var theme: Theme { Theme(warmth: device.warmth, isOn: device.power) }
    private var unit: TemperatureUnit { store.preferences.temperatureUnit }
    private var showsHorizontalVane: Bool {
        store.preferences.showHorizontalVane && !device.vaneHorizontalPositions.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            if let update = updates.available { updateBanner(update) }
            header
            ACUnitView(device: device, theme: theme, temperatureUnit: unit)
                .frame(height: 150)
            temperatureReadout
            TemperatureSlider(
                device: device, theme: theme, unit: unit,
                onChange: { store.setTemperature($0) },
                onEditingChanged: { store.setInteracting($0) }
            )
            controls
            if let message = store.errorMessage {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
        .padding(20)
        .background(theme.background)
        .animation(.easeInOut(duration: 0.6), value: device.warmth)
        .animation(.easeInOut(duration: 0.4), value: device.power)
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                devicePicker
                roomTemperature
            }
            Spacer()
            powerButton
        }
    }

    private var roomTemperature: some View {
        HStack(spacing: 8) {
            Label {
                Text("Room ").foregroundStyle(.secondary)
                    + Text(device.roomTemperature.map { unit.format($0) + unit.symbol } ?? "–")
                    .fontWeight(.semibold)
            } icon: {
                Image(systemName: "thermometer.medium").foregroundStyle(theme.accent)
            }
            Circle()
                .fill(store.isSending ? .yellow : (device.hasError ? .red : theme.accent))
                .frame(width: 6, height: 6)
        }
    }

    private var powerButton: some View {
        Button(action: store.togglePower) {
            Image(systemName: "power")
                .font(.title2.weight(.semibold))
                .frame(width: 48, height: 48)
                .background(Circle().fill(device.power ? theme.accent : .white.opacity(0.1)))
                .shadow(color: device.power ? theme.accent.opacity(0.6) : .clear, radius: 12)
        }
        .buttonStyle(.plain)
        .help(device.power ? "Turn off" : "Turn on")
    }

    @ViewBuilder
    private var devicePicker: some View {
        if store.devices.count > 1 {
            Menu {
                ForEach(store.devices) { option in
                    Button {
                        store.selectDevice(option.id)
                    } label: {
                        if option.id == device.id { Label(option.name, systemImage: "checkmark") } else { Text(option.name) }
                    }
                }
            } label: {
                Text(device.name).font(.headline)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .help("Switch device")
        } else {
            Text(device.name)
                .font(.headline)
        }
    }

    private var temperatureReadout: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(unit.format(device.targetTemperature))
                .font(.system(size: 64, weight: .light, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText(value: unit.value(device.targetTemperature)))
            Text(unit.symbol).font(.title3.weight(.semibold)).foregroundStyle(theme.accent)
        }
        .lineLimit(1)
        .fixedSize()
        .opacity(device.power ? 1 : 0.4)
    }

    /// One row of three tiles, or a 2×2 grid when the horizontal vane tile is shown.
    @ViewBuilder
    private var controls: some View {
        Group {
            if showsHorizontalVane {
                VStack(spacing: 8) {
                    HStack(spacing: 8) { modeTile; fanTile }
                    HStack(spacing: 8) { verticalVaneTile(title: "Vertical vane"); horizontalVaneTile }
                }
            } else {
                HStack(spacing: 8) { modeTile; fanTile; verticalVaneTile(title: "Vane") }
            }
        }
        .disabled(!device.power)
        .opacity(device.power ? 1 : 0.5)
    }

    private var modeTile: some View {
        ControlTile(
            title: "Mode", value: device.operationMode.title, symbol: device.operationMode.symbol, theme: theme,
            options: store.preferences.modes(for: device).map { ($0.rawValue, $0.title, $0.symbol) },
            selected: device.operationMode.rawValue
        ) { if let mode = OperationMode(rawValue: $0) { store.setMode(mode) } }
    }

    private var fanTile: some View {
        ControlTile(title: "Fan", value: Labels.fanSpeed(device.fanSpeed), theme: theme) {
            FanSpeedIcon(speed: device.fanSpeed, levels: max(device.fanSpeeds.count - 1, 1),
                         active: theme.accent, inactive: theme.accent.opacity(0.28))
        } picker: { dismiss in
            FanSpeedPicker(speeds: device.fanSpeeds, selected: device.fanSpeed, accent: theme.accent) {
                store.setFanSpeed($0)
                dismiss()
            }
        }
    }

    private func verticalVaneTile(title: String) -> some View {
        ControlTile(title: title, value: Labels.vane(device.vaneVertical), theme: theme) {
            VaneIcon(position: device.vaneVertical, active: theme.accent, inactive: theme.accent.opacity(0.28))
        } picker: { dismiss in
            VanePicker(positions: device.vaneVerticalPositions, selected: device.vaneVertical, accent: theme.accent) {
                store.setVaneVertical($0)
                dismiss()
            }
        }
    }

    private var horizontalVaneTile: some View {
        ControlTile(title: "Horizontal vane", value: Labels.horizontalVane(device.vaneHorizontal), theme: theme) {
            HorizontalVaneIcon(position: device.vaneHorizontal, active: theme.accent, inactive: theme.accent.opacity(0.28))
        } picker: { dismiss in
            HorizontalVanePicker(
                positions: device.vaneHorizontalPositions, selected: device.vaneHorizontal, accent: theme.accent
            ) {
                store.setVaneHorizontal($0)
                dismiss()
            }
        }
    }

    private func updateBanner(_ update: UpdateChecker.Update) -> some View {
        Button(action: updates.openReleasePage) {
            HStack(spacing: 8) {
                Image(systemName: "arrow.down.circle.fill").foregroundStyle(theme.accent)
                Text("Version \(update.version) is available").font(.callout.weight(.medium))
                Spacer()
                Text("Download").font(.callout).foregroundStyle(theme.accent)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(.white.opacity(0.08)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Opens the release page on GitHub")
    }
}

private struct PlaceholderView: View {
    @Environment(ClimateStore.self) private var store

    var body: some View {
        VStack(spacing: 12) {
            if store.needsSignIn {
                Image(systemName: "person.crop.circle.badge.questionmark").font(.largeTitle).foregroundStyle(.secondary)
                Text("Sign in to MELCloud").font(.headline)
                if let message = store.errorMessage {
                    Text(message).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
                }
                Button("Open Settings…", action: store.openSettings)
                    .buttonStyle(.borderedProminent)
            } else if let message = store.errorMessage {
                Image(systemName: "wifi.exclamationmark").font(.largeTitle).foregroundStyle(.secondary)
                Text(message).font(.headline).multilineTextAlignment(.center)
                Button("Try Again") { Task { await store.refresh(force: true) } }
            } else {
                ProgressView()
                Text("Connecting to MELCloud…").foregroundStyle(.secondary)
            }
            Divider()
            HStack(spacing: 16) {
                Button("Settings…", action: store.openSettings)
                Button("Quit") { NSApplication.shared.terminate(nil) }
            }
            .buttonStyle(.link)
        }
        .padding(28)
        .frame(maxWidth: .infinity)
        .background(Theme.offBackground)
    }
}
