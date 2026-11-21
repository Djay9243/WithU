//
//  PINEntryView.swift
//  WithU
//
//  PIN fallback for cancelling an alert when Face ID isn't available or fails.
//

import LocalAuthentication
import SwiftUI
import UIKit

struct PINEntryView: View {
    @Environment(AppModel.self) private var model
    @State private var digits = ""

    private var trip: TripManager { model.trip }

    var body: some View {
        ZStack {
            ScreenBackground(tone: .alert)
            VStack(spacing: 18) {
                Spacer(minLength: 24)
                VStack(spacing: 6) {
                    Text("Enter Your PIN")
                        .font(.title2.bold())
                        .foregroundStyle(Theme.ink)
                    Text("To cancel the alert.")
                        .font(.subheadline)
                        .foregroundStyle(Theme.inkSecondary)
                }
                PINDots(filled: digits.count)
                    .padding(.top, 6)
                Text(trip.pinError ?? " ")
                    .font(.footnote)
                    .foregroundStyle(Theme.alertRed)
                Spacer()
                PINKeypad(digits: $digits, onComplete: submit) {
                    if model.auth.biometryAvailable {
                        Button {
                            trip.cancelPINEntry()
                            Task { await trip.requestCancelAlert() }
                        } label: {
                            Image(systemName: model.auth.biometryType == .touchID ? "touchid" : "faceid")
                                .font(.title2)
                        }
                        .accessibilityLabel("Use \(model.auth.biometryName)")
                    }
                }
                .padding(.bottom, 24)
            }
        }
        .overlay(alignment: .topLeading) {
            // Back to the alert screen, top left like every other way out.
            Button {
                trip.cancelPINEntry()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                    .frame(width: 44, height: 44)
                    .background(Theme.surface, in: Circle())
            }
            .buttonStyle(.plain)
            .padding(.leading, 16)
            .padding(.top, 12)
            .accessibilityLabel("Back")
        }
    }

    private func submit(_ pin: String) {
        trip.submitPIN(pin)
        if trip.phase == .enteringPIN {
            // Wrong PIN: clear for another attempt.
            digits = ""
        }
    }
}

// MARK: - Shared PIN components

struct PINDots: View {
    var filled: Int
    var total = 4

    var body: some View {
        HStack(spacing: 14) {
            ForEach(0..<total, id: \.self) { index in
                Circle()
                    .strokeBorder(Theme.inkSecondary.opacity(0.6), lineWidth: 1.5)
                    .background(Circle().fill(index < filled ? Theme.ink : .clear))
                    .frame(width: 14, height: 14)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(filled) of \(total) digits entered")
    }
}

struct PINKeypad<Accessory: View>: View {
    @Binding var digits: String
    var length = 4
    var onComplete: (String) -> Void
    @ViewBuilder var accessory: () -> Accessory

    private let rows: [[String]] = [["1", "2", "3"], ["4", "5", "6"], ["7", "8", "9"]]

    var body: some View {
        VStack(spacing: 14) {
            ForEach(rows, id: \.self) { row in
                HStack(spacing: 22) {
                    ForEach(row, id: \.self) { key in
                        keyButton(key)
                    }
                }
            }
            HStack(spacing: 22) {
                accessory()
                    .frame(width: 72, height: 56)
                    .foregroundStyle(Theme.ink)
                keyButton("0")
                Button {
                    if !digits.isEmpty { digits.removeLast() }
                } label: {
                    Text("Delete")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(Theme.ink)
                        .frame(width: 72, height: 56)
                }
                .accessibilityLabel("Delete last digit")
            }
        }
    }

    private func keyButton(_ key: String) -> some View {
        Button {
            guard digits.count < length else { return }
            digits.append(key)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            if digits.count == length {
                onComplete(digits)
            }
        } label: {
            Text(key)
                .font(.title2.weight(.medium))
                .foregroundStyle(Theme.ink)
                .frame(width: 72, height: 56)
                .background(Theme.surface, in: Capsule())
        }
    }
}

#Preview {
    PINEntryView()
        .environment(AppModel.shared)
}
