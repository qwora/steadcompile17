import SwiftUI

/// Stead's watcher: the Veil kitten, drawn natively.
/// Two pill eyes and a head that glance, blink and tilt on their own clock.
/// When Stead is covering for the user (a warning), the veil turns amber and rises.
struct KittenView: View {
    enum Mood { case watching, looking, covering, sleeping, happy }

    var color: Color = Theme.teal
    var mood: Mood = .watching
    var size: CGFloat = 120

    @State private var pose = Pose.neutral
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Canvas { context, canvasSize in
            let scale = canvasSize.width / 100
            context.scaleBy(x: scale, y: scale)
            context.translateBy(x: 50, y: 50)
            context.rotate(by: .degrees(pose.tilt))
            context.translateBy(x: -50, y: -50)

            let body = KittenShape.body
            context.fill(body, with: .color(color))

            // The veil: a soft band across the bottom of the face, clipped to the body.
            var veilContext = context
            veilContext.clip(to: body)
            let rise: CGFloat = mood == .covering ? -18 : 0
            var veil = Path()
            veil.move(to: CGPoint(x: 0, y: 70 + rise))
            veil.addLine(to: CGPoint(x: 50, y: 80 + rise))
            veil.addLine(to: CGPoint(x: 100, y: 70 + rise))
            veil.addLine(to: CGPoint(x: 100, y: 140))
            veil.addLine(to: CGPoint(x: 0, y: 140))
            veil.closeSubpath()
            veilContext.fill(veil, with: .color(mood == .covering ? Theme.amber.opacity(0.9) : Color(hex: 0x0B0D10, opacity: 0.22)))

            drawEye(&context, x: 33, eye: pose.left)
            drawEye(&context, x: 58, eye: pose.right)
        }
        .frame(width: size, height: size)
        .accessibilityLabel(accessibilityText)
        .task(id: mood) { await live() }
    }

    private func drawEye(_ context: inout GraphicsContext, x: CGFloat, eye: Eye) {
        let width: CGFloat = 9, height: CGFloat = 14
        let center = CGPoint(x: x + width / 2 + eye.dx, y: 46 + height / 2 + eye.dy)
        let rect = CGRect(x: center.x - width * eye.sx / 2, y: center.y - height * eye.sy / 2,
                          width: width * eye.sx, height: height * eye.sy)
        let radius = min(rect.width, rect.height) / 2
        context.fill(Path(roundedRect: rect, cornerRadius: radius), with: .color(.white))
    }

    /// Picks a new pose every so often, depending on the mood.
    private func live() async {
        withAnimation(.easeInOut(duration: 0.35)) { pose = mood.restingPose }
        guard !reduceMotion, mood != .sleeping else { return }
        while !Task.isCancelled {
            let (pool, minWait, spread) = mood.loop
            let wait = minWait + Double.random(in: 0...spread)
            try? await Task.sleep(for: .seconds(wait))
            guard !Task.isCancelled else { return }
            let next = pool.randomElement() ?? .neutral
            withAnimation(.spring(response: 0.35, dampingFraction: 0.7)) { pose = next }
            if next == .blink {
                try? await Task.sleep(for: .seconds(0.18))
                withAnimation(.easeOut(duration: 0.15)) { pose = mood.restingPose }
            }
        }
    }

    private var accessibilityText: String {
        switch mood {
        case .watching: "Stead is watching your messages"
        case .looking: "Stead is taking a closer look"
        case .covering: "Stead found warning signs"
        case .sleeping: "Stead is paused"
        case .happy: "Stead is happy"
        }
    }
}

// MARK: - Shape and poses

enum KittenShape {
    /// The Veil kit body path, in a 100 × 100 box.
    static let body: Path = {
        var p = Path()
        p.move(to: CGPoint(x: 22, y: 12))
        p.addQuadCurve(to: CGPoint(x: 38, y: 30), control: CGPoint(x: 30, y: 12))
        p.addQuadCurve(to: CGPoint(x: 62, y: 30), control: CGPoint(x: 50, y: 38))
        p.addQuadCurve(to: CGPoint(x: 78, y: 12), control: CGPoint(x: 70, y: 12))
        p.addQuadCurve(to: CGPoint(x: 88, y: 50), control: CGPoint(x: 90, y: 14))
        p.addCurve(to: CGPoint(x: 50, y: 88), control1: CGPoint(x: 88, y: 74), control2: CGPoint(x: 70, y: 88))
        p.addCurve(to: CGPoint(x: 12, y: 50), control1: CGPoint(x: 30, y: 88), control2: CGPoint(x: 12, y: 74))
        p.addQuadCurve(to: CGPoint(x: 22, y: 12), control: CGPoint(x: 10, y: 14))
        p.closeSubpath()
        return p
    }()
}

struct Eye: Equatable {
    var dx: CGFloat, dy: CGFloat, sx: CGFloat, sy: CGFloat
}

struct Pose: Equatable {
    var left: Eye, right: Eye, tilt: Double

    static func both(_ dx: CGFloat, _ dy: CGFloat, _ sx: CGFloat, _ sy: CGFloat, tilt: Double) -> Pose {
        Pose(left: Eye(dx: dx, dy: dy, sx: sx, sy: sy), right: Eye(dx: dx, dy: dy, sx: sx, sy: sy), tilt: tilt)
    }

    static let neutral = both(0, 0, 1, 1, tilt: 0)
    static let lookLeft = both(-6, 0, 1, 1, tilt: -2)
    static let lookRight = both(6, 0, 1, 1, tilt: 2)
    static let lookUp = both(2, -6, 1, 1, tilt: -3)
    static let lookDown = both(-1, 5, 1, 0.9, tilt: 2)
    static let squint = both(0, 2, 1.1, 0.32, tilt: 0)
    static let happy = both(0, 0, 1.2, 0.22, tilt: -4)
    static let wide = both(0, -1, 1.15, 1.25, tilt: 0)
    static let sleepy = both(0, 4, 1.1, 0.25, tilt: 3)
    static let blink = both(0, 1, 1.05, 0.1, tilt: 0)
    static let tiltLeft = Pose(left: Eye(dx: -4, dy: 1, sx: 1, sy: 1), right: Eye(dx: -4, dy: -1, sx: 1, sy: 1), tilt: -9)
    static let tiltRight = Pose(left: Eye(dx: 4, dy: -1, sx: 1, sy: 1), right: Eye(dx: 4, dy: 1, sx: 1, sy: 1), tilt: 9)
}

private extension KittenView.Mood {
    var restingPose: Pose {
        switch self {
        case .watching: .neutral
        case .looking: .lookRight
        case .covering: .wide
        case .sleeping: .sleepy
        case .happy: .happy
        }
    }

    /// Poses to pick from, minimum wait and random extra wait (seconds).
    var loop: ([Pose], Double, Double) {
        switch self {
        case .watching: ([.neutral, .lookLeft, .lookRight, .lookUp, .lookDown, .tiltLeft, .tiltRight, .wide, .blink, .happy, .neutral], 1.4, 2.6)
        case .looking: ([.lookLeft, .lookRight, .lookUp, .lookLeft, .lookRight, .squint], 0.65, 0.5)
        case .covering: ([.lookDown, .squint, .lookDown, .lookLeft, .lookRight, .wide], 0.7, 0.5)
        case .sleeping: ([.sleepy], 10, 0)
        case .happy: ([.happy, .neutral, .blink, .happy], 1.2, 1.5)
        }
    }
}

#Preview {
    HStack {
        KittenView(mood: .watching, size: 80)
        KittenView(color: Theme.amber, mood: .covering, size: 80)
        KittenView(color: Theme.blue, mood: .sleeping, size: 80)
    }
    .padding()
    .background(.black)
}
