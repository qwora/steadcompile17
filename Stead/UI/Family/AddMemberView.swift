import CoreImage.CIFilterBuiltins
import SwiftUI

/// Protected side: add a family member, link their contact, pair in person with a QR code.
struct AddMemberView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var family = FamilyStore.shared
    @AppStorage("displayName") private var myName = ""

    @State private var name = ""
    @State private var color: KittenColor = FamilyStore.shared.nextColor
    @State private var linked: ContactPicker.Picked?
    @State private var relationship: String?
    @State private var showPicker = false
    @State private var payload: PairingPayload?

    var body: some View {
        Group {
            if let payload { PairingQRView(payload: payload) { dismiss() } } else { form }
        }
        .background(Theme.background)
        .navigationTitle(payload == nil ? "Add family" : "Pair \(name)")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } } }
        .background {
            ContactPicker(isPresented: $showPicker) { picked in
                linked = picked
                if name.isEmpty { name = picked.names.first(where: { !$0.contains(" ") }) ?? picked.displayName }
            }
            .frame(width: 0, height: 0)
        }
    }

    private var form: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                HStack {
                    Spacer()
                    KittenView(color: color.color, mood: .happy, size: 110)
                        .animation(.easeInOut, value: color)
                    Spacer()
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Who is it?").font(.headline)
                    TextField("", text: $name, prompt: Text("e.g. Daniel").foregroundStyle(Theme.muted))
                        .font(.title3).padding(16)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16))
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("They are your…").font(.headline)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(FamilyStore.relationships, id: \.self) { r in
                                Button(r) { relationship = r }
                                    .font(.headline)
                                    .padding(.horizontal, 14).padding(.vertical, 9)
                                    .foregroundStyle(relationship == r ? .black : Theme.text)
                                    .background(relationship == r ? color.color : Theme.surface, in: Capsule())
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Their kitten").font(.headline)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(KittenColor.allCases) { c in
                                Button { color = c } label: {
                                    KittenView(color: c.color, mood: .watching, size: 46)
                                        .padding(6)
                                        .background(Circle().stroke(c == color ? c.color : .clear, lineWidth: 3))
                                }
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Link their contact").font(.headline)
                    Text("So Stead knows when a message really comes from their name, and can ask for their family code if it asks for money.")
                        .font(.subheadline).foregroundStyle(Theme.muted)
                    Button { showPicker = true } label: {
                        HStack {
                            Image(systemName: linked == nil ? "person.crop.circle.badge.plus" : "person.crop.circle.badge.checkmark")
                                .font(.title2).foregroundStyle(linked == nil ? Theme.teal : color.color)
                            VStack(alignment: .leading) {
                                Text(linked?.displayName ?? "Choose from Contacts (pick all their numbers)").font(.headline).foregroundStyle(Theme.text)
                                if let phones = linked?.phones, !phones.isEmpty {
                                    Text(phones.joined(separator: ", ")).font(.caption).foregroundStyle(Theme.muted).lineLimit(1)
                                }
                            }
                            Spacer()
                            Image(systemName: "chevron.right").foregroundStyle(Theme.muted)
                        }
                        .padding(16)
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16))
                    }
                }

                Button("Continue to pairing") {
                    Task {
                        // A fresh single-use invite rides in the QR so scanning also joins the circle.
                        let invite = await CircleService.shared.inviteForPairing(myName: myName)
                        defer { if let id = payload?.id { family.update(id) { $0.relationship = relationship } } }
                    payload = family.addMember(name: name.trimmingCharacters(in: .whitespaces), color: color,
                                                   contactNames: linked?.names ?? [], phones: linked?.phones ?? [],
                                                   protectedName: myName.isEmpty ? "Family" : myName, invite: invite)
                    }
                }
                .buttonStyle(PrimaryButtonStyle(tint: color.color))
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
                .opacity(name.trimmingCharacters(in: .whitespaces).isEmpty ? 0.4 : 1)
            }
            .padding(20)
        }
    }
}

/// The QR code the family member scans. Shown again later from the member's row.
struct PairingQRView: View {
    let payload: PairingPayload
    var onDone: () -> Void
    @StateObject private var family = FamilyStore.shared
    @State private var copied = false

    private var color: Color { (KittenColor(rawValue: payload.color) ?? .blue).color }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Text("Ask \(payload.memberName) to scan this")
                    .font(.title2.bold()).multilineTextAlignment(.center)
                Text("On \(payload.memberName)'s phone: open Stead → \"Someone in my family\" → Scan family QR.")
                    .foregroundStyle(Theme.muted).multilineTextAlignment(.center)

                ZStack {
                    RoundedRectangle(cornerRadius: 28).fill(.white)
                    if let image = QRCode.image(payload.encoded) {
                        Image(uiImage: image).interpolation(.none).resizable().scaledToFit().padding(22)
                    }
                    KittenView(color: color, mood: .watching, size: 54)
                        .padding(6).background(Circle().fill(.white))
                }
                .frame(width: 290, height: 290)

                Label("Pair in person. This QR is the key to \(payload.memberName)'s family code.", systemImage: "lock.fill")
                    .font(.footnote).foregroundStyle(Theme.amber).multilineTextAlignment(.center)

                Button {
                    family.markPaired(payload.id)
                    onDone()
                } label: { Text("\(payload.memberName) has scanned it") }
                .buttonStyle(PrimaryButtonStyle(tint: color))

                Button {
                    UIPasteboard.general.string = payload.encoded
                    copied = true
                } label: {
                    Label(copied ? "Copied" : "Copy pairing code instead", systemImage: copied ? "checkmark" : "doc.on.doc")
                        .font(.subheadline)
                }
                .foregroundStyle(Theme.muted)
            }
            .padding(24)
        }
        .background(Theme.background)
    }
}

enum QRCode {
    static func image(_ text: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(text.utf8)
        filter.correctionLevel = "H"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 10, y: 10)),
              let cg = CIContext().createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: cg)
    }
}
