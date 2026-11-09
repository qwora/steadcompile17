import SwiftUI

/// Stead's look: the Veil theme (black, teal, amber) with large, calm type for older eyes.
enum Theme {
    static let background = Color(hex: 0x000000)
    static let surface = Color(hex: 0x111317)
    static let surfaceRaised = Color(hex: 0x1A1D23)
    static let line = Color.white.opacity(0.08)
    static let text = Color(hex: 0xF5F6F7)
    static let muted = Color(hex: 0xA3A9B2)

    static let teal = Color(hex: 0x12C2A8)
    static let amber = Color(hex: 0xFFB020)
    static let red = Color(hex: 0xFF3B4E)
    static let blue = Color(hex: 0x2F80FF)

    static let radius: CGFloat = 22
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: opacity)
    }
}

/// A rounded dark card used across the app.
struct Card<Content: View>: View {
    var padding: CGFloat = 18
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) { content }
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous).stroke(Theme.line))
    }
}

/// The main full-width button.
struct PrimaryButtonStyle: ButtonStyle {
    var tint: Color = Theme.teal

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headline)
            .foregroundStyle(.black)
            .frame(maxWidth: .infinity, minHeight: 56)
            .background(tint.opacity(configuration.isPressed ? 0.8 : 1), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}
