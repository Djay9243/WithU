//
//  PINSetupView.swift
//  WithU
//
//  Creates or changes the Safety PIN.
//

import SwiftUI

struct PINSetupView: View {
    enum Kind: String, Identifiable {
        case pin
        var id: String { rawValue }
    }

    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    var kind: Kind

    @State private var first = ""
    @State private var digits = ""
    @State private var error: String?

    private var isConfirming: Bool { !first.isEmpty }

    var body: some View {
        NavigationStack {
            ZStack {
                ScreenBackground()
                VStack(spacing: 18) {
                    Spacer(minLength: 20)
                    VStack(spacing: 6) {
                        Text(isConfirming ? "Confirm Your PIN" : title)
                            .font(.title2.bold())
                            .foregroundStyle(Theme.ink)
                        Text(subtitle)
                            .font(.footnote)
                            .foregroundStyle(Theme.inkSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 36)
                    }
                    PINDots(filled: digits.count)
                        .padding(.top, 6)
                    Text(error ?? " ")
                        .font(.footnote)
                        .foregroundStyle(Theme.alertRed)
                    Spacer()
                    PINKeypad(digits: $digits, onComplete: handle) {
                        EmptyView()
                    }
                    .padding(.bottom, 24)
                }
            }
            .navigationTitle("Safety PIN")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        dismiss()
                    } label: {
                        Label("Back", systemImage: "chevron.left")
                            .labelStyle(.titleAndIcon)
                    }
                }
            }
        }
    }

    private var title: String {
        "Choose a 4-Digit PIN"
    }

    private var subtitle: String {
        "Used to cancel an alert if \(model.auth.biometryName) isn't available."
    }

    private func handle(_ pin: String) {
        if !isConfirming {
            first = pin
            digits = ""
            error = nil
            return
        }
        guard pin == first else {
            error = "The PINs didn't match. Start again."
            first = ""
            digits = ""
            return
        }
        model.auth.setPIN(pin)
        dismiss()
    }
}

#Preview {
    PINSetupView(kind: .pin)
        .environment(AppModel.shared)
}
