import SwiftUI

/// On a message that claims to be family and asks for something: check their rotating family code.
struct FamilyCodeCheckCard: View {
    let event: MessageEvent
    @EnvironmentObject private var store: EventStore
    @StateObject private var family = FamilyStore.shared
    @State private var chosen: UUID?
    @State private var code = ""
    @State private var shake = 0
    @FocusState private var focused: Bool

    private var memberID: UUID? { event.familyMemberID ?? chosen }
    private var member: FamilyMember? { memberID.flatMap(family.member(id:)) }
    private var name: String { member?.name ?? "them" }
    private var kittenColor: Color { member?.color.color ?? Theme.teal }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            switch event.familyCheck {
            case .verified: verified
            case .failed: failed
            default: ask
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(background, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 26, style: .continuous).stroke(border, lineWidth: 1.5))
        .animation(.spring(response: 0.4, dampingFraction: 0.8), value: event.familyCheck)
    }

    // MARK: States

    private var ask: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                KittenView(color: kittenColor, mood: .looking, size: 64, veilColor: Theme.amber)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Ask \(name) for the family code").font(.title3.bold())
                    Text("Before you send anything").font(.subheadline).foregroundStyle(Theme.amber)
                }
            }

            if event.familyMemberID == nil {
                Text("Who do they say they are?").font(.headline)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 10) {
                        ForEach(family.members.filter(\.paired)) { m in
                            Button { chosen = m.id } label: {
                                HStack(spacing: 8) {
                                    KittenView(color: m.color.color, mood: .watching, size: 28)
                                    Text(m.name).font(.headline).foregroundStyle(Theme.text)
                                }
                                .padding(.horizontal, 12).padding(.vertical, 8)
                                .background(chosen == m.id ? m.color.color.opacity(0.25) : Theme.surfaceRaised, in: Capsule())
                                .overlay(Capsule().stroke(chosen == m.id ? m.color.color : .clear, lineWidth: 2))
                            }
                        }
                    }
                }
            }

            Text("Call \(name) on the number you already have, or ask in person. The real \(name) opens the code in Stead with their face. A hacker can't.")
                .font(.body).foregroundStyle(Theme.text)

            TextField("", text: $code, prompt: Text("6-digit code").foregroundStyle(Theme.muted))
                .keyboardType(.numberPad)
                .font(.system(size: 34, weight: .bold, design: .monospaced))
                .multilineTextAlignment(.center)
                .padding(.vertical, 14)
                .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 18))
                .focused($focused)
                .onChange(of: code) { _, new in
                    let digits = String(new.filter(\.isNumber).prefix(6))
                    if digits != new { code = digits }
                    // Checks by itself once all six digits are in: no hunting for a button behind the keyboard.
                    if digits.count == 6 && memberID != nil { check() }
                }
                .modifier(Shake(animatableData: CGFloat(shake)))

            Button("Check code") { check() }
                .buttonStyle(PrimaryButtonStyle(tint: kittenColor))
                .disabled(code.count != 6 || memberID == nil)
                .opacity(code.count == 6 && memberID != nil ? 1 : 0.4)

            if family.members.filter(\.paired).isEmpty {
                Label("No family member has a code yet. Add one in the Family tab.", systemImage: "info.circle")
                    .font(.footnote).foregroundStyle(Theme.muted)
            }
        }
    }

    private var verified: some View {
        HStack(alignment: .top, spacing: 14) {
            KittenView(color: kittenColor, mood: .happy, size: 72)
            VStack(alignment: .leading, spacing: 6) {
                Label("Code matches", systemImage: "checkmark.seal.fill").font(.headline).foregroundStyle(Theme.teal)
                Text("This is really \(name).").font(.title2.bold())
                Text("Only send money if you're comfortable. You can still call them first.")
                    .font(.subheadline).foregroundStyle(Theme.muted)
            }
        }
    }

    private var failed: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 14) {
                KittenView(color: kittenColor, mood: .covering, size: 72, veilColor: Theme.red)
                VStack(alignment: .leading, spacing: 6) {
                    Label("Wrong code", systemImage: "xmark.octagon.fill").font(.headline).foregroundStyle(Theme.red)
                    Text("This may not be \(name).").font(.title2.bold())
                    Text("Don't send money or codes. Call \(name) on the number you already have.")
                        .font(.body).foregroundStyle(Theme.text)
                }
            }
            Button("Try another code") {
                code = ""
                store.update(event.id) { $0.familyCheck = .needed }
            }
            .font(.subheadline).foregroundStyle(Theme.muted)
        }
    }

    // MARK: Logic

    private func check() {
        guard let memberID else { return }
        let ok = family.verify(code: code, memberID: memberID)
        focused = false
        store.update(event.id) {
            $0.familyCheck = ok ? .verified : .failed
            $0.familyMemberID = memberID
            if ok { $0.familyNote = "Family code checked: this is really \(name)." }
            if !ok { $0.level = .urgent }
        }
        if !ok { withAnimation(.default) { shake += 1 } }
        Speaker.shared.speak(ok ? "Code matches. This is really \(name)." : "Wrong code. This may not be \(name). Don't send money.")
    }

    private var background: Color {
        switch event.familyCheck {
        case .verified: Theme.teal.opacity(0.12)
        case .failed: Theme.red.opacity(0.12)
        default: Theme.amber.opacity(0.10)
        }
    }

    private var border: Color {
        switch event.familyCheck {
        case .verified: Theme.teal.opacity(0.5)
        case .failed: Theme.red.opacity(0.6)
        default: Theme.amber.opacity(0.5)
        }
    }
}

private struct Shake: GeometryEffect {
    var animatableData: CGFloat
    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: 10 * sin(animatableData * .pi * 4), y: 0))
    }
}
