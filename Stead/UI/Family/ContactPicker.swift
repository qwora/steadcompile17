import ContactsUI
import SwiftUI

/// Apple's contact picker. Needs no Contacts permission: Stead only gets the contacts chosen.
/// Several contacts can be picked at once, e.g. one person saved twice with numbers from two countries.
/// Presented modally from a host controller: wrapping the picker in a SwiftUI sheet drops selections.
struct ContactPicker: UIViewControllerRepresentable {
    struct Picked { let displayName: String; let names: [String]; let phones: [String] }
    @Binding var isPresented: Bool
    let onPick: (Picked) -> Void

    func makeUIViewController(context: Context) -> UIViewController { UIViewController() }

    func updateUIViewController(_ host: UIViewController, context: Context) {
        guard isPresented, host.presentedViewController == nil else { return }
        let picker = CNContactPickerViewController()
        picker.delegate = context.coordinator
        picker.displayedPropertyKeys = [CNContactPhoneNumbersKey]
        // Tapping a contact selects it (instead of opening its card).
        picker.predicateForSelectionOfContact = NSPredicate(value: true)
        DispatchQueue.main.async { host.present(picker, animated: true) }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, CNContactPickerDelegate {
        let parent: ContactPicker
        init(_ parent: ContactPicker) { self.parent = parent }

        func contactPicker(_ picker: CNContactPickerViewController, didSelect contacts: [CNContact]) {
            parent.isPresented = false
            guard !contacts.isEmpty else { return }
            var names: [String] = []
            var phones: [String] = []
            for contact in contacts {
                let full = CNContactFormatter.string(from: contact, style: .fullName) ?? ""
                // Every way this contact's name might appear as a notification title.
                names += [full, contact.givenName, contact.nickname,
                          [contact.givenName, contact.familyName].filter { !$0.isEmpty }.joined(separator: " "),
                          [contact.familyName, contact.givenName].filter { !$0.isEmpty }.joined(separator: "")]
                phones += contact.phoneNumbers.map(\.value.stringValue)
            }
            let first = contacts[0]
            let display = CNContactFormatter.string(from: first, style: .fullName) ?? phones.first ?? "Contact"
            let label = contacts.count > 1 ? "\(display) + \(contacts.count - 1) more" : display
            parent.onPick(Picked(displayName: label,
                                 names: Array(Set(names.filter { !$0.isEmpty })),
                                 phones: Array(Set(phones))))
        }

        func contactPickerDidCancel(_ picker: CNContactPickerViewController) {
            parent.isPresented = false
        }
    }
}
