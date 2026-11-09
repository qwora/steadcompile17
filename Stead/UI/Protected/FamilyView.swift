import SwiftUI

/// Protected side: the family circle, each member's kitten, linked contact and pairing state.
struct FamilyView: View {
    @EnvironmentObject private var store: EventStore
    @EnvironmentObject private var router: Router
    @StateObject private var family = FamilyStore.shared
    @AppStorage("displayName") private var myName = ""
    @State private var adding = false
    @State private var showingQR: PairingPayload?
    @State private var linkingMember: UUID?
    @State private var pickerOpen = false
    @State private var openKey: FamilyKey?

    private var shared: [MessageEvent] { store.events.filter { $0.familyStatus != .none } }

    var body: some View {
        ScrollView {
            VStack(spacing: 18) {
                circleHeader

                ForEach(family.members) { m in memberRow(m) }

                Button { adding = true } label: { Label("Add family member", systemImage: "person.badge.plus") }
                    .buttonStyle(PrimaryButtonStyle())

                SectionTitle(text: "Family alerts")
                LookingOutSection()

                Card {
                    Label("How the family code works", systemImage: "lock.shield.fill").font(.headline).foregroundStyle(Theme.teal)
                    Text("Family asking for money? Ask for their code. Only the real person can open it.")
                        .font(.subheadline).foregroundStyle(Theme.muted)
                }

                if !shared.isEmpty {
                    SectionTitle(text: "Shared with family")
                    ForEach(shared) { event in
                        Button { router.openEvent = event.id } label: { Card(padding: 14) { EventRow(event: event) } }
                            .buttonStyle(.plain)
                    }
                }
            }
            .padding(20)
        }
        .background(Theme.background)
        .navigationTitle("Family")
        .sheet(isPresented: $adding) { NavigationStack { AddMemberView() } }
        .fullScreenCover(item: $openKey) { key in CodeView(key: key) }
        .sheet(item: $showingQR) { p in NavigationStack { PairingQRView(payload: p) { showingQR = nil } } }
        .background {
            ContactPicker(isPresented: $pickerOpen) { picked in
                guard let id = linkingMember else { return }
                family.update(id) { m in
                    m.contactNames = Array(Set(m.contactNames + picked.names))
                    m.phoneNumbers = Array(Set(m.phoneNumbers + picked.phones))
                }
            }
            .frame(width: 0, height: 0)
        }
    }

    private func showCode(_ key: FamilyKey) {
        Task { if await OwnerCheck.confirm(reason: "Show your family code for \(key.protectedName)") { openKey = key } }
    }

    private var circleHeader: some View {
        VStack(spacing: 12) {
            HStack(spacing: -14) {
                KittenView(mood: .watching, size: 64)
                ForEach(family.members.prefix(4)) { m in KittenView(color: m.color.color, mood: .happy, size: 64) }
            }
            Text(family.members.isEmpty ? "Your family circle" : "\(myName.isEmpty ? "You" : myName) + \(family.members.count)")
                .font(.title2.bold())
            Text(family.members.isEmpty
                 ? "Add your family. You all look out for each other."
                 : "You all look out for each other.")
                .font(.subheadline).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
        }
        .padding(.vertical, 10)
    }

    private func memberRow(_ m: FamilyMember) -> some View {
        Card(padding: 14) {
            HStack(spacing: 14) {
                KittenView(color: m.color.color, mood: m.paired ? .watching : .sleeping, size: 52)
                VStack(alignment: .leading, spacing: 4) {
                    Text(m.relationship.map { "\(m.name) · \($0)" } ?? m.name).font(.headline)
                    Label(m.paired ? "Family code set up" : "Not paired yet",
                          systemImage: m.paired ? "lock.shield.fill" : "qrcode")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(m.paired ? Theme.teal : Theme.amber)
                    if m.contactNames.count > 1 || !m.phoneNumbers.isEmpty {
                        Label("Linked to contact", systemImage: "person.crop.circle.badge.checkmark")
                            .font(.caption).foregroundStyle(Theme.muted)
                    }
                }
                Spacer()
                if m.paired, let key = family.keys.first(where: { $0.id == m.id }) {
                    Button { showCode(key) } label: {
                        Image(systemName: "faceid").font(.title2).foregroundStyle(m.color.color)
                    }
                    .accessibilityLabel("Show my family code for \(m.name)")
                }
                Menu {
                    Menu {
                        ForEach(FamilyStore.relationships, id: \.self) { r in
                            Button(r) { family.update(m.id) { $0.relationship = r } }
                        }
                    } label: { Label("Relationship", systemImage: "person.2") }
                    Button {
                        Task {
                            let invite = await CircleService.shared.inviteForPairing(myName: myName)
                            showingQR = family.payload(for: m, protectedName: myName.isEmpty ? "Family" : myName, invite: invite)
                        }
                    } label: { Label("Show pairing QR", systemImage: "qrcode") }
                    Button { linkingMember = m.id; pickerOpen = true } label: {
                        Label("Link contacts", systemImage: "person.crop.circle.badge.plus")
                    }
                    Button(role: .destructive) { family.remove(m.id) } label: { Label("Remove", systemImage: "trash") }
                } label: {
                    Image(systemName: "ellipsis.circle").font(.title2).foregroundStyle(Theme.muted)
                }
            }
        }
    }
}

extension PairingPayload: Identifiable {}
