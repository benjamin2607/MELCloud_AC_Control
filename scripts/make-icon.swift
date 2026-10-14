// Renders the app icon (1024×1024 PNG). Used by scripts/make-icon.sh.
// Usage: swiftc -parse-as-library -o /tmp/make-icon scripts/make-icon.swift && /tmp/make-icon out.png
import AppKit
import SwiftUI

struct AppIcon: View {
    var body: some View {
        ZStack {
            // macOS icon grid: 824 pt squircle centred on a 1024 canvas.
            RoundedRectangle(cornerRadius: 185, style: .continuous)
                .fill(LinearGradient(
                    colors: [Color(red: 0.16, green: 0.36, blue: 0.86), Color(red: 0.98, green: 0.52, blue: 0.18)],
                    startPoint: .topLeading, endPoint: .bottomTrailing
                ))
                .frame(width: 824, height: 824)
                .shadow(color: .black.opacity(0.3), radius: 18, y: 10)

            VStack(spacing: 36) {
                // Indoor unit
                RoundedRectangle(cornerRadius: 56, style: .continuous)
                    .fill(LinearGradient(colors: [.white, Color(white: 0.86)], startPoint: .top, endPoint: .bottom))
                    .frame(width: 560, height: 190)
                    .overlay(alignment: .bottom) {
                        Capsule().fill(Color(white: 0.55)).frame(width: 470, height: 18).padding(.bottom, 34)
                    }
                    .shadow(color: .black.opacity(0.25), radius: 20, y: 12)
                // Airflow
                HStack(spacing: 46) {
                    ForEach(0..<5) { i in
                        Capsule()
                            .fill(.white.opacity(0.9))
                            .frame(width: 26, height: 150)
                            .rotationEffect(.degrees(Double(2 - i) * 14), anchor: .top)
                    }
                }
            }
            .offset(y: -10)
        }
        .frame(width: 1024, height: 1024)
    }
}

@main
struct MakeIcon {
    @MainActor static func main() {
        let renderer = ImageRenderer(content: AppIcon())
        renderer.scale = 1
        guard let image = renderer.cgImage,
              let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
            fatalError("render failed")
        }
        try! png.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
    }
}
