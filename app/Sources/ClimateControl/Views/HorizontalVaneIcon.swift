import SwiftUI

/// Top-down view of the left/right vane: five bars fanning out from the unit, like `VaneIcon` but sideways.
enum HorizontalVaneGeometry {
    static let positions = ["1_left", "2", "3", "4", "5_right"]
    /// Degrees from straight ahead (down on screen); negative = left.
    private static let angles: [Double] = [-52, -26, 0, 26, 52]
    private static let inner: CGFloat = 0.42
    private static let outer: CGFloat = 0.92
    static let barWidth: CGFloat = 0.09

    static func pivot(_ s: CGFloat) -> CGPoint { CGPoint(x: 0.5 * s, y: 0.02 * s) }

    static func bar(_ index: Int, size s: CGFloat) -> Path {
        let r: Double = angles[index] * .pi / 180
        let dx = CGFloat(sin(r)), dy = CGFloat(cos(r))
        let p = pivot(s)
        var path = Path()
        path.move(to: CGPoint(x: p.x + dx * inner * s, y: p.y + dy * inner * s))
        path.addLine(to: CGPoint(x: p.x + dx * outer * s, y: p.y + dy * outer * s))
        return path
    }

    static func index(at point: CGPoint, size s: CGFloat) -> Int? {
        let p = pivot(s)
        let dx = Double(point.x - p.x), dy = Double(point.y - p.y)
        let distance = (dx * dx + dy * dy).squareRoot() / Double(s)
        guard distance > Double(inner) * 0.8, distance < Double(outer) * 1.1 else { return nil }
        let degrees = atan2(dx, dy) * 180 / .pi
        let nearest = angles.indices.min { abs(angles[$0] - degrees) < abs(angles[$1] - degrees) }
        guard let nearest, abs(angles[nearest] - degrees) < 13 else { return nil }
        return nearest
    }
}

struct HorizontalVaneIcon: View {
    let position: String?
    var active: Color = .primary
    var inactive: Color = .primary.opacity(0.25)
    var hovered: Int? = nil
    /// "A" badge for Auto. Off in the large picker fan.
    var showsMarker = true

    var body: some View {
        Canvas { context, size in
            let s = min(size.width, size.height)
            let style = StrokeStyle(lineWidth: HorizontalVaneGeometry.barWidth * s, lineCap: .round)
            for index in HorizontalVaneGeometry.positions.indices {
                context.stroke(HorizontalVaneGeometry.bar(index, size: s), with: .color(color(for: index)), style: style)
            }
            if showsMarker, position == "auto" {
                context.draw(
                    Text("A").font(.system(size: 0.34 * s, weight: .heavy, design: .rounded)).foregroundStyle(active),
                    at: CGPoint(x: 0.5 * s, y: 0.24 * s)
                )
            }
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityLabel(Labels.horizontalVane(position))
    }

    private func color(for index: Int) -> Color {
        let selected = position.flatMap(HorizontalVaneGeometry.positions.firstIndex(of:))
        if index == selected { return active }
        if position == "split", index == 0 || index == 4 { return active } // both outer directions
        if index == hovered { return active.opacity(0.55) }
        if position == "swing" { return active.opacity(0.45) }
        return inactive
    }
}

/// Two arrows pointing away from each other: air split to the left and right.
struct SplitGlyph: View {
    var body: some View {
        Canvas { context, size in
            let s = min(size.width, size.height)
            var path = Path()
            let top = CGPoint(x: 0.5 * s, y: 0.12 * s)
            for side in [-1.0, 1.0] {
                let end = CGPoint(x: 0.5 * s + CGFloat(side) * 0.36 * s, y: 0.84 * s)
                path.move(to: top)
                path.addQuadCurve(to: end, control: CGPoint(x: 0.5 * s, y: 0.62 * s))
                // Arrowhead at the end, roughly along the curve's final direction.
                let back = CGPoint(x: end.x - CGFloat(side) * 0.2 * s, y: end.y - 0.08 * s)
                path.move(to: back)
                path.addLine(to: end)
                path.addLine(to: CGPoint(x: end.x - CGFloat(side) * 0.04 * s, y: end.y - 0.2 * s))
            }
            context.stroke(path, with: .foreground, style: StrokeStyle(lineWidth: 0.09 * s, lineCap: .round, lineJoin: .round))
        }
        .aspectRatio(1, contentMode: .fit)
    }
}

/// Same layout as `VanePicker`: Auto / Swing / Split buttons on the left, clickable fan on the right.
struct HorizontalVanePicker: View {
    let positions: [String]
    let selected: String?
    let accent: Color
    let onSelect: (String) -> Void

    @State private var hovered: Int?
    private let fanSize: CGFloat = 116
    private let fanPadding: CGFloat = 10

    private var specials: [String] { ["auto", "swing", "split"].filter(positions.contains) }

    var body: some View {
        HStack(spacing: 8) {
            VStack(spacing: 8) {
                ForEach(specials, id: \.self) { position in
                    PickerModeButton(
                        title: Labels.horizontalVane(position), isSelected: position == selected, accent: accent
                    ) {
                        onSelect(position)
                    } glyph: {
                        switch position {
                        case "auto": AutoGlyph()
                        case "swing": SwingGlyph()
                        default: SplitGlyph()
                        }
                    }
                }
            }
            .frame(width: 120)

            HorizontalVaneIcon(position: selected, active: accent, inactive: .white.opacity(0.22),
                               hovered: hovered, showsMarker: false)
                .frame(width: fanSize, height: fanSize)
                .padding(fanPadding)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.white.opacity(0.06)))
                .contentShape(Rectangle())
                .onContinuousHover { phase in
                    if case .active(let location) = phase { hovered = bar(at: location) } else { hovered = nil }
                }
                .gesture(SpatialTapGesture().onEnded { tap in
                    guard let index = bar(at: tap.location) else { return }
                    let position = HorizontalVaneGeometry.positions[index]
                    if positions.contains(position) { onSelect(position) }
                })
                .accessibilityElement()
                .accessibilityLabel("Horizontal vane \(Labels.horizontalVane(selected))")
                .accessibilityAdjustableAction { direction in
                    let current = selected.flatMap(HorizontalVaneGeometry.positions.firstIndex(of:)) ?? 2
                    let next = direction == .increment ? min(current + 1, 4) : max(current - 1, 0)
                    onSelect(HorizontalVaneGeometry.positions[next])
                }
        }
        .padding(10)
    }

    private func bar(at location: CGPoint) -> Int? {
        HorizontalVaneGeometry.index(at: CGPoint(x: location.x - fanPadding, y: location.y - fanPadding), size: fanSize)
    }
}
