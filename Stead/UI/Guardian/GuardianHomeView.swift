import SwiftUI
import VisionKit

/// "You look out for": the people who paired with me, my family code for each (Face ID),
/// and their live cases. Shown inside everyone's app: family members are protected too.
struct LookingOutSection: View {
    var compact = false
    @StateObject private var family = FamilyStore.shared
    @StateObject private var circle = CircleService.shared
    @AppStorage("displayName") private var myName = ""
    @State private var scanning = false
    @State private var pasting = false
    @State private var openKey: FamilyKey?
    @State private var justPaired: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let justPaired {
                Label("Paired with \(justPaired)", systemImage: "checkmark.seal.fill")
                    .font(.headline).foregroundStyle(Theme.teal)
                    .transition(.scale.combined(with: .opacity))
            }

            // Keys for people already in my family list show as a Face ID button on their row.
            ForEach(family.keys.filter { k in !family.members.contains { $0.id == k.id } }) { key in
                Button { open(key) } label: { keyRow(key) }.buttonStyle(.plain)
            }

            if !compact {
                if family.keys.isEmpty {
                    Text("Joining someone's family? Scan the QR on their Stead.")
                        .font(.subheadline).foregroundStyle(Theme.muted)
                }
                Button { scanning = true } label: { Label("Scan family QR", systemImage: "qrcode.viewfinder") }
                    .buttonStyle(PrimaryButtonStyle(tint: Theme.blue))
                Button("Enter pairing code instead") { pasting = true }
                    .font(.subheadline).foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity)
            }

            if !circle.memberships.isEmpty { CaseList(onlyOpen: compact) }
        }
        .sheet(isPresented: $scanning) { QRScannerSheet { handle($0) } }
        .sheet(isPresented: $pasting) { NavigationStack { PastePairingView { handle($0) } } }
        .fullScreenCover(item: $openKey) { key in CodeView(key: key) }
    }

    private func keyRow(_ key: FamilyKey) -> some View {
        Card(padding: 16) {
            HStack(spacing: 14) {
                KittenView(color: key.color.color, mood: .watching, size: 52)
                VStack(alignment: .leading, spacing: 4) {
                    Text(key.protectedName).font(.title3.bold())
                    Label("Show my family code · Face ID", systemImage: "faceid").font(.subheadline).foregroundStyle(Theme.muted)
                }
                Spacer()
                Image(systemName: "lock.fill").font(.title3).foregroundStyle(key.color.color)
            }
        }
    }

    private func open(_ key: FamilyKey) {
        Task {
            if await OwnerCheck.confirm(reason: "Show your family code for \(key.protectedName)") { openKey = key }
        }
    }

    private func handle(_ text: String) {
        guard let payload = PairingPayload.decode(text) else { return }
        family.addKey(from: payload, myName: myName)
        // Two-way: they can check my code, and I can check theirs (same secret, same pairing id).
        family.addMemberFromPairing(payload)
        scanning = false; pasting = false
        withAnimation(.spring) { justPaired = payload.protectedName }
        guard let invite = payload.invite else { return }
        Task {
            _ = await Notifier.requestPermission()
            // Join under the name they know us by, so their phone can match us to this pairing.
            await circle.join(code: invite, as: payload.memberName, pairingID: payload.id)
        }
    }
}

/// Full-screen rotating code with a countdown ring. Hidden again when the app leaves the screen.
struct CodeView: View {
    let key: FamilyKey
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var phase
    @StateObject private var family = FamilyStore.shared

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let code = family.currentCode(for: key) ?? "------"
            let left = FamilyCode.secondsLeft(at: context.date)
            VStack(spacing: 26) {
                Spacer()
                KittenView(color: key.color.color, mood: .happy, size: 110)
                Text("Your family code for \(key.protectedName)").font(.title3).foregroundStyle(Theme.muted)
                Text(FamilyCode.pretty(code))
                    .font(.system(size: 64, weight: .bold, design: .monospaced))
                    .foregroundStyle(Theme.text)
                    .contentTransition(.numericText())
                    .animation(.snappy, value: code)
                    .accessibilityLabel(code.map(String.init).joined(separator: " "))
                ZStack {
                    Circle().stroke(Theme.surfaceRaised, lineWidth: 6)
                    Circle().trim(from: 0, to: CGFloat(left) / CGFloat(FamilyCode.step))
                        .stroke(key.color.color, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                        .animation(.linear(duration: 1), value: left)
                    Text("\(left)s").font(.headline.monospacedDigit())
                }
                .frame(width: 70, height: 70)
                Text("Read it to \(key.protectedName) on a call.")
                    .font(.subheadline).foregroundStyle(Theme.muted).multilineTextAlignment(.center)
                Spacer()
                Button("Hide code") { dismiss() }.buttonStyle(PrimaryButtonStyle(tint: key.color.color))
            }
            .padding(28)
        }
        .background(Theme.background.ignoresSafeArea())
        .onChange(of: phase) { _, p in if p != .active { dismiss() } }
    }
}

/// Camera QR scanner (VisionKit). Falls back to a message when the camera isn't available.
struct QRScannerSheet: View {
    let onCode: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Group {
                if DataScannerViewController.isSupported && DataScannerViewController.isAvailable {
                    QRScanner(onCode: onCode).ignoresSafeArea()
                } else {
                    ContentUnavailableView("Camera not available", systemImage: "camera.slash",
                                           description: Text("Use \"Enter pairing code instead\"."))
                }
            }
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } } }
            .navigationTitle("Scan family QR").navigationBarTitleDisplayMode(.inline)
        }
    }
}

private struct QRScanner: UIViewControllerRepresentable {
    let onCode: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let vc = DataScannerViewController(recognizedDataTypes: [.barcode(symbologies: [.qr])], isHighlightingEnabled: true)
        vc.delegate = context.coordinator
        try? vc.startScanning()
        return vc
    }

    func updateUIViewController(_ vc: DataScannerViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(onCode: onCode) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onCode: (String) -> Void
        private var done = false
        init(onCode: @escaping (String) -> Void) { self.onCode = onCode }

        func dataScanner(_ scanner: DataScannerViewController, didAdd items: [RecognizedItem], allItems: [RecognizedItem]) {
            guard !done else { return }
            for item in items {
                if case .barcode(let code) = item, let value = code.payloadStringValue, PairingPayload.decode(value) != nil {
                    done = true
                    scanner.stopScanning()
                    onCode(value)
                    return
                }
            }
        }
    }
}

struct PastePairingView: View {
    let onCode: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Paste the pairing code from the other phone.").foregroundStyle(Theme.muted)
            TextField("STEAD1:…", text: $text, axis: .vertical)
                .lineLimit(3...6).font(.footnote.monospaced())
                .padding(14).background(Theme.surface, in: RoundedRectangle(cornerRadius: 16))
            if !text.isEmpty && PairingPayload.decode(text) == nil {
                Text("That doesn't look like a Stead pairing code.").font(.footnote).foregroundStyle(Theme.amber)
            }
            Button("Pair") { onCode(text) }
                .buttonStyle(PrimaryButtonStyle(tint: Theme.blue))
                .disabled(PairingPayload.decode(text) == nil)
            Spacer()
        }
        .padding(20)
        .background(Theme.background)
        .navigationTitle("Pairing code").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarLeading) { Button("Cancel") { dismiss() } } }
    }
}

extension FamilyKey {}
