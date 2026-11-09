import SwiftUI

/// How to connect the iOS 27 Shortcuts automation to Stead's "Check Message" action.
struct SetupGuideView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(spacing: 12) {
                    KittenView(mood: .watching, size: 100)
                    Text("Let Stead check new messages").font(.title.bold()).multilineTextAlignment(.center)
                    Text("Takes about two minutes, once. Needs iOS 27.").foregroundStyle(Theme.muted)
                }
                .frame(maxWidth: .infinity)

                GuideStep(n: 1, title: "Open Shortcuts", text: "Go to the Automation tab and tap +.") {
                    Link(destination: URL(string: "shortcuts://")!) {
                        Label("Open Shortcuts", systemImage: "arrow.up.forward.app").frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PrimaryButtonStyle())
                }
                GuideStep(n: 2, title: "Choose \"Notification\"", text: "Under \"from\", add Messages and WhatsApp (and any other chat app).") {
                    Mock {
                        Label("When I receive a notification", systemImage: "bell.badge.fill").font(.subheadline.weight(.semibold))
                        HStack { Text("from").font(.subheadline); Chip("Messages"); Chip("WhatsApp") }
                    }
                }
                GuideStep(n: 3, title: "Run without asking", text: "Choose \"Run Immediately\" and turn \"Notify When Run\" off.") {
                    Mock {
                        Label("Run Immediately", systemImage: "checkmark").font(.subheadline)
                        Toggle("Notify When Run", isOn: .constant(false)).font(.subheadline).disabled(true)
                    }
                }
                GuideStep(n: 4, title: "Add \"Check Message\"", text: "Search Stead, add Check Message, then tap each field and pick the matching notification detail.") {
                    Mock {
                        HStack { KittenView(mood: .watching, size: 24); Text("Check message from").font(.subheadline.weight(.semibold)); Chip("App", blue: true) }
                        ForEach(["Title", "Subtitle", "Body", "Date"], id: \.self) { f in
                            HStack { Text(f).font(.subheadline); Spacer(); Chip(f, blue: true) }
                        }
                    }
                    Label("Don't skip App and Body: Body carries the message.", systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote).foregroundStyle(Theme.amber)
                }
                GuideStep(n: 5, title: "Test it", text: "Ask someone to message you. Stead's alert appears within seconds and the message shows in Activity.") { EmptyView() }

                Card {
                    Text("If nothing happens").font(.headline)
                    Tip("Settings → Notifications → Stead: allow notifications.")
                    Tip("Unknown numbers: turn off Settings → Apps → Messages → Screen Unknown Senders.")
                    Tip("Messages and WhatsApp must show previews.")
                    Tip("No iOS 27? Copy a message and use \"Check a message\" on Home.")
                }
            }
            .padding(20)
        }
        .background(Theme.background)
        .navigationTitle("Setup")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct GuideStep<Extra: View>: View {
    let n: Int, title: String, text: String
    @ViewBuilder var extra: Extra
    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Text("\(n)").font(.headline).foregroundStyle(.black).frame(width: 32, height: 32).background(Theme.teal, in: Circle())
            VStack(alignment: .leading, spacing: 10) {
                Text(title).font(.title3.bold())
                Text(text).foregroundStyle(Theme.muted)
                extra
            }
        }
    }
}

private struct Mock<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 10) { content }
            .padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: 16))
    }
}

private struct Chip: View {
    let text: String; var blue = false
    init(_ text: String, blue: Bool = false) { self.text = text; self.blue = blue }
    var body: some View {
        Text(text).font(.subheadline.weight(.medium)).foregroundStyle(blue ? Theme.blue : Theme.teal)
            .padding(.horizontal, 8).padding(.vertical, 3).background(Color.white.opacity(0.08), in: Capsule())
    }
}

private struct Tip: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        HStack(alignment: .top, spacing: 8) { Text("•").foregroundStyle(Theme.muted); Text(text).font(.callout) }
    }
}
