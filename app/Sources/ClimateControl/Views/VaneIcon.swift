import SwiftUI

/// Fan of five vane bars like the MELCloud app: bar 1 (top) is almost horizontal, bar 5 (bottom) almost vertical.
/// All geometry is relative to the square's edge length so the same drawing works as tile icon and picker.
enum VaneGeometry {
    static let positions = ["1_up", "2", "3", "4", "5_down"]
    private static let angles: [Double] = [15, 30, 45, 60, 75]
    private static let inner: CGFloat = 0.53
    private static let outer: CGFloat = 0.94
    static let barWidth: CGFloat = 0.09

    /// The bars radiate from a point just outside the top-left corner.
    static func pivot(_ s: CGFloat) -> CGPoint { CGPoint(x: -0.06 * s, y: -0.08 * s) }

    static func bar(_ index: Int, size s: CGFloat) -> Path {
        let r: Double = angles[index] * .pi / 180
        let c = CGFloat(cos(r)), n = CGFloat(sin(r))
        let p = pivot(s)
        var path = Path()
        path.move(to: CGPoint(x: p.x + c * inner * s, y: p.y + n * inner * s))
        path.addLine(to: CGPoint(x: p.x + c * outer * s, y: p.y + n * outer * s))
        return path
    }

    /// Bar under a point (for clicks/hover in the picker), nil outside the fan.
    static func index(at point: CGPoint, size s: CGFloat) -> Int? {
        let p = pivot(s)
        let dx = Double(point.x - p.x), dy = Double(point.y - p.y)
        let distance = (dx * dx + dy * dy).squareRoot() / Double(s)
        guard distance > Double(inner) * 0.8, distance < Double(outer) * 1.1 else { return nil }
        let degrees = atan2(dy, dx) * 180 / .pi
        let nearest = angles.indices.min { abs(angles[$0] - degrees) < abs(angles[$1] - degrees) }
        guard let nearest, abs(angles[nearest] - degrees) < 12 else { return nil }
        return nearest
    }
}

struct VaneIcon: View {
    let position: String?
    var active: Color = .primary
    var inactive: Color = .primary.opacity(0.25)
    /// Bar under the pointer in the picker.
    var hovered: Int? = nil
    /// "A" / arrow badge for Auto and Swing. Off in the large picker fan, where the buttons carry it.
    var showsMarker = true

    var body: some View {
        Canvas { context, size in
            let s = min(size.width, size.height)
            let selected = position.flatMap(VaneGeometry.positions.firstIndex(of:))
            let style = StrokeStyle(lineWidth: VaneGeometry.barWidth * s, lineCap: .round)

            for index in VaneGeometry.positions.indices {
                context.stroke(VaneGeometry.bar(index, size: s), with: .color(color(for: index, selected: selected)), style: style)
            }

            // Markers sit in the empty corner near the pivot.
            let marker = CGPoint(x: 0.17 * s, y: 0.19 * s)
            switch showsMarker ? position : nil {
            case "auto":
                context.draw(
                    Text("A").font(.system(size: 0.36 * s, weight: .heavy, design: .rounded)).foregroundStyle(active),
                    at: marker
                )
            case "swing":
                context.stroke(Self.swingArrow(center: marker, size: 0.26 * s), with: .color(active),
                               style: StrokeStyle(lineWidth: max(0.06 * s, 1.2), lineCap: .round, lineJoin: .round))
            default:
                break
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityLabel(Labels.vane(position))
    }

    private func color(for index: Int, selected: Int?) -> Color {
        if index == selected { return active }
        if index == hovered { return active.opacity(0.55) }
        if position == "swing" { return active.opacity(0.45) } // swing sweeps through all positions
        return inactive
    }

    /// Small curved double arrow, like the swing glyph in the MELCloud app.
    private static func swingArrow(center: CGPoint, size: CGFloat) -> Path {
        let radius: CGFloat = size * 0.55
        let head: CGFloat = size * 0.28
        let from: Double = -30
        let to: Double = 120
        let pivot = CGPoint(x: center.x - radius * 0.35, y: center.y - radius * 0.35)
        var path = Path()
        path.addArc(center: pivot, radius: radius, startAngle: .degrees(from), endAngle: .degrees(to), clockwise: false)
        for (angle, sweep) in [(from, -1.0), (to, 1.0)] {
            let r: Double = angle * .pi / 180
            let c = CGFloat(cos(r)), n = CGFloat(sin(r)), dir = CGFloat(sweep)
            let tip = CGPoint(x: pivot.x + c * radius, y: pivot.y + n * radius)
            let back = CGPoint(x: tip.x + n * dir * head, y: tip.y - c * dir * head)
            path.move(to: CGPoint(x: back.x + c * head * 0.6, y: back.y + n * head * 0.6))
            path.addLine(to: tip)
            path.addLine(to: CGPoint(x: back.x - c * head * 0.6, y: back.y - n * head * 0.6))
        }
        return path
    }
}

/// Picker modelled on the MELCloud app: Auto / Swing buttons on the left, clickable fan on the right.
struct VanePicker: View {
    let positions: [String]
    let selected: String?
    let accent: Color
    let onSelect: (String) -> Void

    @State private var hovered: Int?
    private let fanSize: CGFloat = 116
    private let fanPadding: CGFloat = 10

    var body: some View {
        HStack(spacing: 8) {
            VStack(spacing: 8) {
                if positions.contains("auto") { modeButton("auto") }
                if positions.contains("swing") { modeButton("swing") }
            }
            .frame(width: 120)

            fan
        }
        .padding(10)
    }

    private var fan: some View {
        VaneIcon(position: selected, active: accent, inactive: .white.opacity(0.22), hovered: hovered, showsMarker: false)
            .frame(width: fanSize, height: fanSize)
            .padding(fanPadding)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.white.opacity(0.06)))
            .contentShape(Rectangle())
            .onContinuousHover { phase in
                if case .active(let location) = phase {
                    hovered = bar(at: location)
                } else {
                    hovered = nil
                }
            }
            .gesture(SpatialTapGesture().onEnded { tap in
                guard let index = bar(at: tap.location) else { return }
                let position = VaneGeometry.positions[index]
                if positions.contains(position) { onSelect(position) }
            })
            .accessibilityElement()
            .accessibilityLabel("Lamellenstufe \(Labels.vane(selected))")
            .accessibilityAdjustableAction { direction in
                let current = selected.flatMap(VaneGeometry.positions.firstIndex(of:)) ?? 2
                let next = direction == .increment ? min(current + 1, 4) : max(current - 1, 0)
                onSelect(VaneGeometry.positions[next])
            }
    }

    private func bar(at location: CGPoint) -> Int? {
        VaneGeometry.index(at: CGPoint(x: location.x - fanPadding, y: location.y - fanPadding), size: fanSize)
    }

    private func modeButton(_ position: String) -> some View {
        PickerModeButton(title: Labels.vane(position), isSelected: position == selected, accent: accent) {
            onSelect(position)
        } glyph: {
            if position == "auto" { AutoGlyph() } else { SwingGlyph() }
        }
    }
}

/// Wide button with glyph + title used next to the fan / vane pickers (Auto, Swing).
struct PickerModeButton<Glyph: View>: View {
    let title: String
    let isSelected: Bool
    let accent: Color
    let action: () -> Void
    @ViewBuilder let glyph: () -> Glyph

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                glyph()
                    .foregroundStyle(isSelected ? .white : accent)
                    .frame(width: 28, height: 28)
                Text(title).font(.callout.weight(.semibold))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .frame(maxHeight: .infinity)
            .foregroundStyle(isSelected ? .white : .primary)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(isSelected ? accent : .white.opacity(0.06)))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Glyphs for the Auto / Swing buttons, modelled on the MELCloud app

/// Arc with optional filled arrowheads. Angles in degrees, increasing clockwise (SwiftUI's flipped y axis).
private func arcArrow(center: CGPoint, radius: CGFloat, from: Double, to: Double, head: CGFloat,
                      startHead: Bool, endHead: Bool) -> (line: Path, heads: Path) {
    var line = Path()
    line.addArc(center: center, radius: radius, startAngle: .degrees(from), endAngle: .degrees(to), clockwise: false)
    var heads = Path()
    for (angle, travel, enabled) in [(from, -1.0, startHead), (to, 1.0, endHead)] where enabled {
        let r: Double = angle * .pi / 180
        let c = CGFloat(cos(r)), n = CGFloat(sin(r)), dir = CGFloat(travel)
        let end = CGPoint(x: center.x + c * radius, y: center.y + n * radius)
        let tangent = CGVector(dx: -n * dir, dy: c * dir) // direction of travel at this end
        let tip = CGPoint(x: end.x + tangent.dx * head * 0.7, y: end.y + tangent.dy * head * 0.7)
        let base = CGPoint(x: end.x - tangent.dx * head * 0.3, y: end.y - tangent.dy * head * 0.3)
        heads.move(to: tip)
        heads.addLine(to: CGPoint(x: base.x + c * head * 0.6, y: base.y + n * head * 0.6))
        heads.addLine(to: CGPoint(x: base.x - c * head * 0.6, y: base.y - n * head * 0.6))
        heads.closeSubpath()
    }
    return (line, heads)
}

/// Three arrows chasing each other around a circle.
struct AutoGlyph: View {
    var body: some View {
        Canvas { context, size in
            let s = min(size.width, size.height)
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            for start in [-75.0, 45.0, 165.0] {
                let arrow = arcArrow(center: center, radius: s * 0.34, from: start, to: start + 72,
                                     head: s * 0.26, startHead: false, endHead: true)
                context.stroke(arrow.line, with: .foreground, style: StrokeStyle(lineWidth: s * 0.11, lineCap: .butt))
                context.fill(arrow.heads, with: .foreground)
            }
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

/// Faint vane fan on the left, curved double arrow sweeping from top right to bottom left.
struct SwingGlyph: View {
    var body: some View {
        Canvas { context, size in
            let s = min(size.width, size.height)
            var fan = context
            fan.opacity = 0.45
            let pivot = CGPoint(x: s * 0.02, y: s * 0.04)
            for degrees in [12.0, 30, 48, 66, 84] {
                let r: Double = degrees * .pi / 180
                let c = CGFloat(cos(r)), n = CGFloat(sin(r))
                var bar = Path()
                bar.move(to: CGPoint(x: pivot.x + c * s * 0.24, y: pivot.y + n * s * 0.24))
                bar.addLine(to: CGPoint(x: pivot.x + c * s * 0.5, y: pivot.y + n * s * 0.5))
                fan.stroke(bar, with: .foreground, style: StrokeStyle(lineWidth: s * 0.07, lineCap: .round))
            }
            let arrow = arcArrow(center: pivot, radius: s * 0.68, from: 10, to: 80,
                                 head: s * 0.26, startHead: true, endHead: true)
            context.stroke(arrow.line, with: .foreground, style: StrokeStyle(lineWidth: s * 0.09, lineCap: .butt))
            context.fill(arrow.heads, with: .foreground)
        }
        .aspectRatio(1, contentMode: .fit)
    }
}
