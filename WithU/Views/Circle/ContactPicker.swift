//
//  ContactPicker.swift
//  WithU
//
//  The system contact picker. It needs no Contacts permission: the person
//  chooses exactly who to share, and only those contacts reach the app.
//

import Contacts
import ContactsUI
import SwiftUI

struct ContactPicker: UIViewControllerRepresentable {
    /// When true the picker allows choosing several people at once.
    var allowsMultipleSelection = true
    var onPick: ([ContactCandidate]) -> Void

    func makeCoordinator() -> Coordinator {
        allowsMultipleSelection ? MultipleCoordinator(onPick: onPick) : Coordinator(onPick: onPick)
    }

    func makeUIViewController(context: Context) -> CNContactPickerViewController {
        let picker = CNContactPickerViewController()
        picker.delegate = context.coordinator
        picker.displayedPropertyKeys = [CNContactPhoneNumbersKey]
        return picker
    }

    func updateUIViewController(_ uiViewController: CNContactPickerViewController, context: Context) {}

    /// Single selection: implementing `didSelect contact` makes the picker
    /// close after one tap.
    class Coordinator: NSObject, CNContactPickerDelegate {
        let onPick: ([ContactCandidate]) -> Void

        init(onPick: @escaping ([ContactCandidate]) -> Void) {
            self.onPick = onPick
        }

        func contactPicker(_ picker: CNContactPickerViewController, didSelect contact: CNContact) {
            onPick([Self.candidate(from: contact)].compactMap { $0 })
        }

        nonisolated static func candidate(from contact: CNContact) -> ContactCandidate? {
            let name = CNContactFormatter.string(from: contact, style: .fullName)
                ?? [contact.givenName, contact.familyName].filter { !$0.isEmpty }.joined(separator: " ")
            guard !name.isEmpty else { return nil }
            return ContactCandidate(id: contact.identifier,
                                    name: name,
                                    phoneNumber: contact.phoneNumbers.first?.value.stringValue)
        }
    }

    /// Multiple selection: implementing the plural `didSelect contacts` switches
    /// the picker into multi-select mode with a Done button.
    final class MultipleCoordinator: Coordinator {
        func contactPicker(_ picker: CNContactPickerViewController, didSelect contacts: [CNContact]) {
            let picked = contacts.compactMap(Self.candidate(from:))
            // The picker always calls its delegate on the main thread.
            MainActor.assumeIsolated {
                onPick(picked)
            }
        }
    }
}
