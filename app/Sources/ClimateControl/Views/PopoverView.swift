import SwiftUI

struct PopoverView: View {
    @Environment(ClimateStore.self) private var store

    var body: some View {
        Group {
            if let device = store.device {
                DeviceView(device: device)
            } else {
                PlaceholderView(message: store.errorMessage)
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

    private var theme: Theme { Theme(warmth: device.warmth, isOn: device.power) }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header
            ACUnitView(device: device, theme: theme)
                .frame(height: 150)
            temperatureReadout
            TemperatureSlider(
                device: device, theme: theme,
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
                Text("Raum ").foregroundStyle(.secondary)
                    + Text(device.roomTemperature.map { "\($0.formatted(.number.precision(.fractionLength(0...1))))°C" } ?? "–")
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
        .help(device.power ? "Ausschalten" : "Einschalten")
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
            .help("Gerät wechseln")
        } else {
            Text(device.name)
                .font(.headline)
        }
    }

    private var temperatureReadout: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(device.targetTemperature.formatted(.number.precision(.fractionLength(0...1))))
                .font(.system(size: 64, weight: .light, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText(value: device.targetTemperature))
            Text("°C").font(.title3.weight(.semibold)).foregroundStyle(theme.accent)
        }
        .lineLimit(1)
        .fixedSize()
        .opacity(device.power ? 1 : 0.4)
    }

    private var controls: some View {
        HStack(spacing: 8) {
            ControlTile(
                title: "Modus", value: device.operationMode.title, symbol: device.operationMode.symbol, theme: theme,
                options: device.selectableModes.map { ($0.rawValue, $0.title, $0.symbol) }, selected: device.operationMode.rawValue
            ) { if let mode = OperationMode(rawValue: $0) { store.setMode(mode) } }

            ControlTile(title: "Lüfter", value: Labels.fanSpeed(device.fanSpeed), theme: theme) {
                FanSpeedIcon(speed: device.fanSpeed, levels: max(device.fanSpeeds.count - 1, 1),
                             active: theme.accent, inactive: theme.accent.opacity(0.28))
            } picker: { dismiss in
                FanSpeedPicker(speeds: device.fanSpeeds, selected: device.fanSpeed, accent: theme.accent) {
                    store.setFanSpeed($0)
                    dismiss()
                }
            }

            // No horizontal-vane tile: it is adjusted by hand on the MSZ-AY, even though MELCloud reports positions.
            ControlTile(title: "Lamelle", value: Labels.vane(device.vaneVertical), theme: theme) {
                VaneIcon(position: device.vaneVertical, active: theme.accent, inactive: theme.accent.opacity(0.28))
            } picker: { dismiss in
                VanePicker(positions: device.vaneVerticalPositions, selected: device.vaneVertical, accent: theme.accent) {
                    store.setVaneVertical($0)
                    dismiss()
                }
            }
        }
        .disabled(!device.power)
        .opacity(device.power ? 1 : 0.5)
    }
}

private struct PlaceholderView: View {
    let message: String?

    var body: some View {
        VStack(spacing: 12) {
            if let message {
                Image(systemName: "bolt.horizontal.circle").font(.largeTitle).foregroundStyle(.secondary)
                Text(message).font(.headline)
                Text("Läuft die Bridge? `scripts/run-bridge.sh`").font(.caption).foregroundStyle(.secondary)
            } else {
                ProgressView()
                Text("Verbinde mit MELCloud …").foregroundStyle(.secondary)
            }
            Divider()
            Button("ClimateControl beenden") { NSApplication.shared.terminate(nil) }
                .buttonStyle(.link)
        }
        .padding(28)
        .frame(maxWidth: .infinity)
        .background(Theme.offBackground)
    }
}
