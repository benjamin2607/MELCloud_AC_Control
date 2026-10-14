import SwiftUI

/// Stylised indoor unit with animated airflow; speed follows the fan setting.
struct ACUnitView: View {
    let device: ACDevice
    let theme: Theme

    /// Points per second the air dashes travel. Stage 1 is a gentle drift, stage 5 a clear rush.
    private var flowSpeed: Double {
        let speeds: [String: Double] = ["1": 18, "2": 32, "3": 50, "4": 75, "5": 105]
        return speeds[device.fanSpeed ?? "auto"] ?? 50
    }

    var body: some View {
        VStack(spacing: 0) {
            unit.zIndex(1)
            if device.power {
                AirflowView(color: theme.accent, speed: flowSpeed)
                    .transition(.opacity)
            } else {
                Spacer()
            }
        }
        // Without the full-width airflow the stack would shrink to the unit and hug the left edge.
        .frame(maxWidth: .infinity)
    }

    private var unit: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(LinearGradient(colors: [.white, Color(white: 0.85)], startPoint: .top, endPoint: .bottom))
            .frame(width: 190, height: 52)
            .overlay(alignment: .topTrailing) {
                HStack(spacing: 4) {
                    Text("\(Int(device.targetTemperature.rounded()))")
                        .font(.system(size: 11, weight: .bold, design: .rounded))
                    Circle().frame(width: 4, height: 4)
                }
                .foregroundStyle(device.power ? theme.accent : .gray)
                .padding(10)
            }
            .overlay(alignment: .bottom) {
                Capsule().fill(Color(white: 0.45)).frame(height: 4).padding(.horizontal, 14).padding(.bottom, 8)
            }
            .shadow(color: theme.accent.opacity(device.power ? 0.35 : 0), radius: 16, y: 6)
    }
}

private struct AirflowView: View {
    let color: Color
    let speed: Double

    @State private var clock = FlowClock()

    var body: some View {
        // .periodic instead of .animation: the display-link schedule doesn't reliably tick in MenuBarExtra windows.
        TimelineView(.periodic(from: .now, by: 1.0 / 60)) { timeline in
            let travelled = clock.advance(to: timeline.date, speed: speed)
            Canvas { context, size in
                let lines = 9
                let origin = CGPoint(x: size.width / 2, y: 0)
                for i in 0..<lines {
                    let spread = (Double(i) / Double(lines - 1) - 0.5) * 2 // -1…1
                    var path = Path()
                    path.move(to: CGPoint(x: origin.x + spread * 70, y: origin.y))
                    path.addQuadCurve(
                        to: CGPoint(x: origin.x + spread * size.width * 0.5, y: size.height),
                        control: CGPoint(x: origin.x + spread * 80, y: size.height * 0.55)
                    )
                    context.stroke(
                        path,
                        with: .linearGradient(
                            Gradient(colors: [color.opacity(0.85), color.opacity(0)]),
                            startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)
                        ),
                        style: StrokeStyle(lineWidth: 1.5, lineCap: .round, dash: [10, 14],
                                           dashPhase: -CGFloat(travelled + Double(i) * 7))
                    )
                }
            }
        }
    }
}

/// Integrates speed over time so changing the fan stage changes the pace without the dashes jumping.
private final class FlowClock {
    private var last: Date?
    private var travelled: Double = 0

    func advance(to date: Date, speed: Double) -> Double {
        if let last { travelled += min(date.timeIntervalSince(last), 0.1) * speed }
        last = date
        return travelled.truncatingRemainder(dividingBy: 24_000)
    }
}
