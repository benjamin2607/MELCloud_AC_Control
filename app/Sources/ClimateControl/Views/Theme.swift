import SwiftUI

/// Dynamic palette: interpolates between a cold (blue) and warm (amber) look based on the setpoint.
struct Theme {
    let warmth: Double
    let isOn: Bool

    /// Popover corner radius; larger than the system default so the panel sits softly under the menu bar.
    static let cornerRadius: CGFloat = 26

    private static let coldTop = RGB(0.11, 0.17, 0.35), coldBottom = RGB(0.06, 0.09, 0.20)
    private static let warmTop = RGB(0.38, 0.19, 0.12), warmBottom = RGB(0.17, 0.09, 0.07)
    private static let offTop = RGB(0.17, 0.17, 0.19), offBottom = RGB(0.09, 0.09, 0.10)
    private static let coldAccent = RGB(0.26, 0.55, 1.00), warmAccent = RGB(1.00, 0.56, 0.20)

    var backgroundTop: Color { (isOn ? Self.coldTop.lerp(Self.warmTop, warmth) : Self.offTop).color }
    var backgroundBottom: Color { (isOn ? Self.coldBottom.lerp(Self.warmBottom, warmth) : Self.offBottom).color }
    var accent: Color { isOn ? Self.coldAccent.lerp(Self.warmAccent, warmth).color : .gray }
    var sliderColors: [Color] { isOn ? [Self.coldAccent.color, Self.warmAccent.color] : [Color(white: 0.45), Color(white: 0.6)] }

    static let offBackground = LinearGradient(colors: [offTop.color, offBottom.color], startPoint: .top, endPoint: .bottom)

    var background: LinearGradient {
        LinearGradient(colors: [backgroundTop, backgroundBottom], startPoint: .top, endPoint: .bottom)
    }
}

struct RGB: Equatable {
    var r, g, b: Double
    init(_ r: Double, _ g: Double, _ b: Double) { (self.r, self.g, self.b) = (r, g, b) }

    func lerp(_ other: RGB, _ t: Double) -> RGB {
        let t = min(max(t, 0), 1)
        return RGB(r + (other.r - r) * t, g + (other.g - g) * t, b + (other.b - b) * t)
    }

    var color: Color { Color(.sRGB, red: r, green: g, blue: b) }
}
