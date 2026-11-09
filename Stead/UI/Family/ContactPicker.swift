import ContactsUI
import SwiftUI

/// Apple's contact picker. Needs no Contacts permission: Stead only gets the one contact chosen.
struct ContactPicker: UIViewControllerRepresentable {
    struct Picked { let displayName: String; let names: [String]; let phones: [String] }
    let onPick: (Picked) -> Void

    func makeUIViewController(context: Context) -> CNContactPickerViewController {
        let picker = CNContactPickerViewController()
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: CNContactPickerViewController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(onPick: onPick) }

    final class Coordinator: NSObject, CNContactPickerDelegate {
        let onPick: (Picked) -> Void
        init(onPick: @escaping (Picked) -> Void) { self.onPick = onPick }

        func contactPicker(_ picker: CNContactPickerViewController, didSelect contact: CNContact) {
            let full = CNContactFormatter.string(from: contact, style: .fullName) ?? ""
            // Every way this contact's name might appear as a notification title.
            var names = [full, contact.givenName, contact.nickname,
                         [contact.givenName, contact.familyName].filter { !$0.isEmpty }.joined(separator: " "),
                         [contact.familyName, contact.givenName].filter { !$0.isEmpty }.joined(separator: "")]
            names = names.filter { !$0.isEmpty }
            let phones = contact.phoneNumbers.map(\.value.stringValue)
            onPick(Picked(displayName: full.isEmpty ? (phones.first ?? "Contact") : full,
                          names: Array(Set(names)), phones: phones))
        }
    }
}
