//
//  ContactPicker.swift
//  WithU
//
//  The system contact picker. It needs no Contacts permission: the person
//  chooses exactly who to share, and only those contacts reach the app.
//
//  The picker is presented by UIKit, not wrapped in a SwiftUI sheet. It
//  closes itself after a choice or Cancel; inside a SwiftUI sheet that
//  left SwiftUI thinking the sheet was still open, which could stop the
//  screen underneath from responding (e.g. Create on New Circle).
//

import Contacts
import ContactsUI
import SwiftUI

extension View {
    /// Shows the system contact picker while `isPresented` is true.
    func contactPicker(isPresented: Binding<Bool>,
                       allowsMultipleSelection: Bool = true,
                       onPick: @escaping ([ContactCandidate]) -> Void) -> some View {
        background(
            ContactPickerPresenter(isPresented: isPresented,
                                   allowsMultipleSelection: allowsMultipleSelection,
                                   onPick: onPick)
                .frame(width: 0, height: 0)
        )
    }
}

private struct ContactPickerPresenter: UIViewControllerRepresentable {
    @Binding var isPresented: Bool
    var allowsMultipleSelection: Bool
    var onPick: ([ContactCandidate]) -> Void

    func makeCoordinator() -> Coordinator {
        allowsMultipleSelection ? MultipleCoordinator() : Coordinator()
    }

    func makeUIViewController(context: Context) -> UIViewController {
        UIViewController()
    }

    func updateUIViewController(_ host: UIViewController, context: Context) {
        let coordinator = context.coordinator
        coordinator.onPick = onPick
        coordinator.onFinish = { isPresented = false }

        if isPresented, coordinator.picker == nil {
            let picker = CNContactPickerViewController()
            picker.delegate = coordinator
            picker.displayedPropertyKeys = [CNContactPhoneNumbersKey]
            coordinator.picker = picker
            host.present(picker, animated: true)
        } else if !isPresented, let picker = coordinator.picker {
            coordinator.picker = nil
            if picker.presentingViewController != nil {
                picker.dismiss(animated: true)
            }
        }
    }

    /// Single selection: implementing `didSelect contact` makes the picker
    /// close after one tap.
    class Coordinator: NSObject, CNContactPickerDelegate {
        var onPick: ([ContactCandidate]) -> Void = { _ in }
        var onFinish: () -> Void = {}
        var picker: CNContactPickerViewController?

        func contactPicker(_ picker: CNContactPickerViewController, didSelect contact: CNContact) {
            finish(with: [Self.candidate(from: contact)].compactMap { $0 })
        }

        func contactPickerDidCancel(_ picker: CNContactPickerViewController) {
            // The picker has already closed itself.
            self.picker = nil
            onFinish()
        }

        /// The picker closes itself after a choice; just record it and report.
        func finish(with picked: [ContactCandidate]) {
            picker = nil
            onFinish()
            onPick(picked)
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
            finish(with: contacts.compactMap(Self.candidate(from:)))
        }
    }
}
