import SwiftUI

/// Fan strength as rising bars (like a signal meter): stage 3 lights the first three bars.
/// Geometry is relative to the square's edge length, so it works as tile icon and as picker.
enum FanGeometry {
    static let gapRatio: CGFloat = 0.45 // gap relative to bar width
    private static let minHeight: CGFloat = 0.3

    static func barRect(_ index: Int, count: Int, size s: CGFloat) -> CGRect {
        let width = s / (CGFloat(count) + CGFloat(count - 1) * gapRatio)
        let step = width * (1 + gapRatio)
        let fraction = count > 1 ? CGFloat(index) / CGFloat(count - 1) : 1
        let height = s * (minHeight + (1 - minHeight) * fraction)
        return CGRect(x: CGFloat(index) * step, y: s - height, width: width, height: height)
    }

    /// Column under a point; the full height counts so short bars are easy to hit.
    static func index(at point: CGPoint, count: Int, size s: CGFloat) -> Int? {
        guard point.x >= 0, point.x <= s, point.y >= 0, point.y <= s, count > 0 else { return nil }
        let step = s / CGFloat(count)
        return min(Int(point.x / step), count - 1)
    }
}

struct FanSpeedIcon: View {
    /// pymelcloud value: "auto" or "1"…"5".
    let speed: String?
    var levels = 5
    var active: Color = .primary
    var inactive: Color = .primary.opacity(0.25)
    /// Bar under the pointer in the picker: previews that stage.
    var hovered: Int? = nil
    /// "A" badge for Auto. Off in the large picker meter, where the Auto button carries it.
    var showsMarker = true

    private var level: Int { speed.flatMap { Int($0) } ?? 0 }

    var body: some View {
        Canvas { context, size in
            let s = min(size.width, size.height)
            for index in 0..<levels {
                let rect = FanGeometry.barRect(index, count: levels, size: s)
                let path = Path(roundedRect: rect, cornerRadius: rect.width * 0.35)
                context.fill(path, with: .color(color(for: index)))
            }
            if showsMarker, speed == "auto" {
                context.draw(
                    Text("A").font(.system(size: 0.38 * s, weight: .heavy, design: .rounded)).foregroundStyle(active),
                    at: CGPoint(x: 0.2 * s, y: 0.22 * s)
                )
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityLabel(Labels.fanSpeed(speed))
    }

    private func color(for index: Int) -> Color {
        if let hovered, index <= hovered, index >= level { return active.opacity(0.55) }
        return index < level ? active : inactive
    }
}

/// Picker in the same style as the vane picker: Auto on the left, clickable strength meter on the right.
struct FanSpeedPicker: View {
    let speeds: [String]
    let selected: String?
    let accent: Color
    let onSelect: (String) -> Void

    @State private var hovered: Int?
    private let meterSize: CGFloat = 116
    private let meterPadding: CGFloat = 10

    private var stages: [String] { speeds.filter { Int($0) != nil } }

    var body: some View {
        HStack(spacing: 8) {
            if speeds.contains("auto") {
                PickerModeButton(title: "Auto", isSelected: selected == "auto", accent: accent) {
                    onSelect("auto")
                } glyph: {
                    AutoGlyph()
                }
                .frame(width: 120, height: meterSize + meterPadding * 2)
            }
            meter
        }
        .padding(10)
    }

    private var meter: some View {
        VStack(spacing: 6) {
            FanSpeedIcon(speed: selected, levels: stages.count, active: accent, inactive: .white.opacity(0.22),
                         hovered: hovered, showsMarker: false)
                .frame(width: meterSize, height: meterSize - 18)
            HStack(spacing: 0) {
                ForEach(Array(stages.enumerated()), id: \.element) { index, stage in
                    Text(stage)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(stage == selected ? accent : .secondary)
                        .frame(maxWidth: .infinity)
                }
            }
            .frame(width: meterSize, height: 12)
        }
        .padding(meterPadding)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.white.opacity(0.06)))
        .contentShape(Rectangle())
        .onContinuousHover { phase in
            if case .active(let location) = phase { hovered = stage(at: location) } else { hovered = nil }
        }
        .gesture(SpatialTapGesture().onEnded { tap in
            if let index = stage(at: tap.location) { onSelect(stages[index]) }
        })
        .accessibilityElement()
        .accessibilityLabel("Fan \(Labels.fanSpeed(selected))")
        .accessibilityAdjustableAction { direction in
            let current = selected.flatMap { stages.firstIndex(of: $0) } ?? 0
            let next = direction == .increment ? min(current + 1, stages.count - 1) : max(current - 1, 0)
            onSelect(stages[next])
        }
    }

    /// Columns span the whole meter (bars + numbers), relative to the padded content.
    private func stage(at location: CGPoint) -> Int? {
        let x = location.x - meterPadding
        guard x >= 0, x <= meterSize else { return nil }
        return FanGeometry.index(at: CGPoint(x: x, y: 0), count: stages.count, size: meterSize)
    }
}
