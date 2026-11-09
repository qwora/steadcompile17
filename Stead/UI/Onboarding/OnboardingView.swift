import SwiftUI

/// First launch: who is this phone for, their name, consent, notifications.
struct OnboardingView: View {
    @AppStorage("mode") private var modeRaw = ""
    @AppStorage("displayName") private var displayName = ""
    @State private var step = 0
    @State private var chosen: AppMode = .protected
    @State private var name = ""
    @State private var autoShare = true
    @FocusState private var nameFocused: Bool

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            RadialGradient(colors: [Theme.teal.opacity(0.18), .clear], center: .top, startRadius: 0, endRadius: 520)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                progress
                Group {
                    switch step {
                    case 0: welcome
                    case 1: whoFor
                    case 2: nameStep
                    default: consent
                    }
                }
                .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                        removal: .move(edge: .leading).combined(with: .opacity)))
            }
            .padding(24)
        }
        .animation(.spring(response: 0.45, dampingFraction: 0.85), value: step)
    }

    private var progress: some View {
        HStack(spacing: 6) {
            ForEach(0..<4) { i in
                Capsule().fill(i <= step ? Theme.teal : Theme.surfaceRaised).frame(height: 4)
            }
        }
        .padding(.bottom, 12)
        .opacity(step == 0 ? 0 : 1)
    }

    // MARK: Steps

    private var welcome: some View {
        VStack(spacing: 22) {
            Spacer()
            KittenView(mood: .watching, size: 170)
            VStack(spacing: 10) {
                Text("Stead").font(.system(size: 48, weight: .bold))
                Text("Safer, together.").font(.title2).foregroundStyle(Theme.teal)
            }
            Text("Stead quietly checks new messages for scam warning signs, and brings your family in when it matters.")
                .font(.title3).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
            Spacer()
            Button("Get started") { step = 1 }.buttonStyle(PrimaryButtonStyle())
        }
    }

    private var whoFor: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Who is this phone for?").font(.largeTitle.bold())
            Text("You can change this later.").foregroundStyle(Theme.muted)
            ChoiceCard(selected: chosen == .protected, color: Theme.teal, mood: .watching,
                       title: "Me", detail: "Check my messages and warn me about scams.") { chosen = .protected }
            ChoiceCard(selected: chosen == .guardian, color: Theme.blue, mood: .happy,
                       title: "Me, and I look out for family", detail: "Stead protects me too, and I can help a parent or relative.") { chosen = .guardian }
            Spacer()
            Button("Continue") { step = 2; nameFocused = true }.buttonStyle(PrimaryButtonStyle())
        }
    }

    private var nameStep: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("What should your family call you?").font(.largeTitle.bold())
            Text(chosen == .protected ? "Shown to family when you ask them for help." : "Shown to the person you look out for.")
                .foregroundStyle(Theme.muted)
            TextField("", text: $name, prompt: Text(chosen == .protected ? "e.g. Mum, Aminah" : "e.g. Daniel").foregroundStyle(Theme.muted))
                .font(.title2)
                .padding(18)
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18))
                .focused($nameFocused)
                .submitLabel(.continue)
                .onSubmit { if canContinue { step = 3 } }
            Spacer()
            Button("Continue") { step = 3 }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(!canContinue).opacity(canContinue ? 1 : 0.4)
        }
    }

    private var consent: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("How Stead protects you").font(.largeTitle.bold())
            VStack(alignment: .leading, spacing: 14) {
                Promise(icon: "iphone", text: "Normal messages stay on this phone.")
                Promise(icon: "sparkles", text: "Only messages with warning signs get a closer AI look.")
                Promise(icon: "person.2.fill", text: "Family sees a short summary, never your chats.")
            }
            Group {
                Card {
                    Toggle(isOn: $autoShare) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Tell my family when it's serious").font(.headline)
                            Text("If Stead sees a likely scam, your family gets a heads-up so they can help.")
                                .font(.subheadline).foregroundStyle(Theme.muted)
                        }
                    }
                    .tint(Theme.teal)
                }
            }
            Spacer()
            Button("Allow alerts and finish") { finish() }
                .buttonStyle(PrimaryButtonStyle())
        }
    }

    private var canContinue: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty }

    private func finish() {
        Task {
            _ = await Notifier.requestPermission()
            Settings.autoShareSerious = autoShare
            displayName = name.trimmingCharacters(in: .whitespaces)
            modeRaw = chosen.rawValue
            // Family helpers start on the Family tab, where they scan the QR.
            if chosen == .guardian { Router.shared.tab = .family }
        }
    }
}

private struct ChoiceCard: View {
    let selected: Bool
    let color: Color
    let mood: KittenView.Mood
    let title: String
    let detail: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                KittenView(color: color, mood: mood, size: 54)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.title3.bold()).foregroundStyle(Theme.text)
                    Text(detail).font(.subheadline).foregroundStyle(Theme.muted).multilineTextAlignment(.leading)
                }
                Spacer()
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.title2).foregroundStyle(selected ? color : Theme.muted)
            }
            .padding(18)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Theme.radius))
            .overlay(RoundedRectangle(cornerRadius: Theme.radius).stroke(selected ? color : Theme.line, lineWidth: selected ? 2 : 1))
        }
        .buttonStyle(.plain)
        .sensoryFeedback(.selection, trigger: selected)
    }
}

private struct Promise: View {
    let icon: String
    let text: String
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon).font(.title3).foregroundStyle(Theme.teal).frame(width: 30)
            Text(text).font(.title3).foregroundStyle(Theme.text)
        }
    }
}

#Preview { OnboardingView() }
