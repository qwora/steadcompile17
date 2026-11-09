import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var store: EventStore
    @AppStorage("displayName") private var displayName = ""
    @AppStorage("mode") private var modeRaw = ""
    @AppStorage("showEveryCheck") private var showEveryCheck = false
    @AppStorage("autoShareSerious") private var autoShare = true
    @AppStorage("alertFrom") private var alertFrom = Level.worthALook.rawValue
    @AppStorage("pauseOnUrgent") private var pauseOnUrgent = true
    @State private var confirmClear = false

    var body: some View {
        List {
            Section("You") {
                TextField("Name", text: $displayName)
            }
            Section {
                NavigationLink { SetupGuideView() } label: { Label("Set up automatic checks", systemImage: "bolt.badge.automatic.fill") }
            }
            Section {
                Picker("Warn me when", selection: $alertFrom) {
                    Text("Anything looks off").tag(Level.worthALook.rawValue)
                    Text("Only when it's serious").tag(Level.beCareful.rawValue)
                    Text("Only urgent (stop & call family)").tag(Level.urgent.rawValue)
                }
            } header: {
                Text("Alerts")
            } footer: {
                Text("Stead still checks every message and keeps them in Activity. Family-code checks always alert you.")
            }
            Section {
                Toggle("Pause before urgent messages", isOn: $pauseOnUrgent)
            } footer: {
                Text("When a message pushes you hard, Stead shows a short \"Wait. Take a moment.\" screen first, with a button to call family. You can always continue after it.")
            }
            Section {
                Toggle("Tell my family when it's serious", isOn: $autoShare)
                    .onChange(of: autoShare) { Task { await CircleService.shared.syncConsent() } }
                Toggle("Show every check (for testing)", isOn: $showEveryCheck)
            } footer: {
                Text("Normal messages are checked on this phone and never sent anywhere.")
            }
            Section("Server") {
                Label(Config.isBackendConfigured ? "Connected" : "Not set up: using on-phone checks only",
                      systemImage: Config.isBackendConfigured ? "checkmark.circle.fill" : "circle.dashed")
                    .foregroundStyle(Config.isBackendConfigured ? Theme.teal : Theme.muted)
            }
            Section {
                Button("Clear message history", role: .destructive) { confirmClear = true }
                Button("Switch who this phone is for") { modeRaw = "" }
            }
        }
        .tint(Theme.teal)
        .scrollContentBackground(.hidden)
        .background(Theme.background)
        .navigationTitle("Settings")
        .confirmationDialog("Clear all checked messages from this phone?", isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Clear history", role: .destructive) { store.clear() }
        }
    }
}
