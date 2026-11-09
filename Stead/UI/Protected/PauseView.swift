import SwiftUI

/// Full-screen "Wait. Take a moment." shown once for an urgent message, before its details.
/// Scams work by rushing people; this buys a short pause and puts "call family" first.
/// The person stays in control: after the countdown they can always continue.
struct PauseView: View {
    let event: MessageEvent
    let onDone: () -> Void
    @Environment(\.openURL) private var openURL
    @State private var left = PauseView.seconds
    @State private var breathe = false

    static let seconds = 20
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    /// Who to call: the family member the message claims to be (on the number saved before),
    /// otherwise the first family member with a saved number.
    private var callee: FamilyMember? {
        let family = FamilyStore.shared
        if let id = event.familyMemberID, let m = family.member(id: id), !m.phoneNumbers.isEmpty { return m }
        return family.members.first { !$0.phoneNumbers.isEmpty }
    }

    private var message: String {
        let told = event.caseID != nil ? " Your family has been told." : ""
        return "This message is rushing you. Scammers do that. You have time.\(told)"
    }

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Circle()
                .fill(Theme.red.opacity(0.25))
                .frame(width: 160, height: 160)
                .overlay(Image(systemName: "hand.raised.fill").font(.system(size: 64)).foregroundStyle(Theme.red))
                .scaleEffect(breathe ? 1.08 : 0.92)
                .animation(.easeInOut(duration: 4).repeatForever(autoreverses: true), value: breathe)
                .accessibilityHidden(true)
            Text("Wait. Take a moment.").font(.largeTitle.bold()).multilineTextAlignment(.center)
            Text(message).font(.title3).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
            Text("Breathe slowly. Don't send money, codes or photos yet.")
                .font(.body).foregroundStyle(Theme.text).multilineTextAlignment(.center)
            Spacer()

            if let m = callee, let number = m.phoneNumbers.first,
               let url = URL(string: "tel:" + number.filter { $0.isNumber || $0 == "+" }) {
                Button { openURL(url) } label: { Label("Call \(m.name)", systemImage: "phone.fill") }
                    .buttonStyle(PrimaryButtonStyle(tint: Theme.teal))
            } else {
                Text("Call someone you trust on a number you already have.")
                    .font(.headline).multilineTextAlignment(.center)
            }

            Button(left > 0 ? "Continue in \(left)s" : "I've had a moment. Continue") { onDone() }
                .font(.headline).frame(maxWidth: .infinity, minHeight: 50)
                .foregroundStyle(left > 0 ? Theme.muted : Theme.text)
                .disabled(left > 0)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.background)
        .onAppear {
            breathe = true
            Speaker.shared.speak("Wait. Take a moment. \(message)")
        }
        .onDisappear { Speaker.shared.stop() }
        .onReceive(timer) { _ in if left > 0 { left -= 1 } }
        .interactiveDismissDisabled()
    }
}
