import SwiftUI

/// Gradient slider (blue → amber) with −/+ steppers. Reports values snapped to the device step.
struct TemperatureSlider: View {
    let device: ACDevice
    let theme: Theme
    let unit: TemperatureUnit
    let onChange: (Double) -> Void
    var onEditingChanged: (Bool) -> Void = { _ in }

    @State private var isDragging = false

    private var range: ClosedRange<Double> { device.targetTemperatureMin...device.targetTemperatureMax }
    private var step: Double { max(device.targetTemperatureStep, 0.5) }

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 10) {
                stepButton("minus", delta: -step)
                track
                stepButton("plus", delta: step)
            }
            HStack {
                Text(unit.format(range.lowerBound) + "°")
                Spacer()
                Text(unit.format(range.upperBound) + "°")
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 46)
        }
        .disabled(!device.power)
        .opacity(device.power ? 1 : 0.5)
    }

    private var track: some View {
        GeometryReader { geo in
            let fraction = device.warmth
            let thumb: CGFloat = 30
            let x = (geo.size.width - thumb) * fraction
            ZStack(alignment: .leading) {
                Capsule().fill(.black.opacity(0.35))
                Capsule()
                    .fill(LinearGradient(colors: theme.sliderColors, startPoint: .leading, endPoint: .trailing))
                    .mask(alignment: .leading) { Capsule().frame(width: x + thumb) }
                Circle()
                    .fill(.white)
                    .frame(width: thumb - 6, height: thumb - 6)
                    .shadow(radius: 3)
                    .offset(x: x + 3)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if !isDragging { isDragging = true; onEditingChanged(true) }
                        let f = min(max((value.location.x - thumb / 2) / (geo.size.width - thumb), 0), 1)
                        commit(range.lowerBound + f * (range.upperBound - range.lowerBound))
                    }
                    .onEnded { _ in
                        isDragging = false
                        onEditingChanged(false)
                    }
            )
        }
        .frame(height: 36)
    }

    private func stepButton(_ symbol: String, delta: Double) -> some View {
        Button { commit(device.targetTemperature + delta) } label: {
            Image(systemName: symbol)
                .font(.body.weight(.semibold))
                .frame(width: 36, height: 36)
                .background(Circle().fill(.white.opacity(0.08)))
        }
        .buttonStyle(.plain)
    }

    private func commit(_ raw: Double) {
        let snapped = min(max((raw / step).rounded() * step, range.lowerBound), range.upperBound)
        if snapped != device.targetTemperature { onChange(snapped) }
    }
}
