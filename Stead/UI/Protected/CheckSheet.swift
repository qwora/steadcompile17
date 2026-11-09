import SwiftUI

/// Manual check: paste or type a message (works on any iPhone, no Shortcuts needed), or try a sample.
struct CheckSheet: View {
    @EnvironmentObject private var router: Router
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var sender = ""
    @State private var working = false
    @FocusState private var focused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Copy the message you're unsure about, then paste it here.")
                    .font(.title3).foregroundStyle(Theme.muted)

                PasteButton(payloadType: String.self) { strings in
                    if let first = strings.first { Task { @MainActor in text = first } }
                }
                .buttonBorderShape(.capsule)
                .controlSize(.large)
                .tint(Theme.teal)

                ZStack(alignment: .topLeading) {
                    if text.isEmpty {
                        Text("Or type it here…").foregroundStyle(Theme.muted).padding(.horizontal, 18).padding(.vertical, 20)
                    }
                    TextEditor(text: $text)
                        .focused($focused)
                        .scrollContentBackground(.hidden)
                        .font(.body)
                        .padding(12)
                        .frame(minHeight: 160)
                }
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18))

                TextField("", text: $sender, prompt: Text("Who sent it? (optional)").foregroundStyle(Theme.muted))
                    .padding(16)
                    .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18))

                Button { check(app: "Pasted", sender: sender, body: text, source: .paste) } label: {
                    if working { ProgressView().tint(.black) } else { Text("Check this message") }
                }
                .buttonStyle(PrimaryButtonStyle())
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || working)

                SectionTitle(text: "Try an example")
                ForEach(Samples.all) { sample in
                    Button { check(app: sample.app, sender: sample.sender, body: sample.body, source: .sample) } label: {
                        HStack {
                            Image(systemName: sample.app == "WhatsApp" ? "phone.bubble.fill" : "message.fill").foregroundStyle(Theme.teal)
                            Text(sample.label).foregroundStyle(Theme.text)
                            Spacer()
                            Image(systemName: "chevron.right").foregroundStyle(Theme.muted)
                        }
                        .padding(16)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16))
                    }
                    .disabled(working)
                }
            }
            .padding(20)
        }
        .background(Theme.background)
        .navigationTitle("Check a message")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } } }
    }

    private func check(app: String, sender: String, body: String, source: MessageEvent.Source) {
        working = true
        Task {
            let event = await Pipeline.process(app: app, sender: sender, subtitle: "", body: body, source: source)
            working = false
            dismiss()
            try? await Task.sleep(for: .milliseconds(350))
            router.openEvent = event.id
        }
    }
}
