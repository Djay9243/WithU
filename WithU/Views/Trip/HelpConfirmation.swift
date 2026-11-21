//
//  HelpConfirmation.swift
//  WithU
//
//  "Get Help" asks first, then Face ID, then tells the circle. One shared
//  popup for the trip screen, the check-in and the stop prompt.
//

import SwiftUI

private struct HelpConfirmationModifier: ViewModifier {
    @Environment(AppModel.self) private var model
    @Binding var isPresented: Bool
    @State private var notSent = false

    private var circleName: String {
        model.trip.circleName.isEmpty ? "your circle" : model.trip.circleName
    }

    func body(content: Content) -> some View {
        content
            .alert("Send an alert to \(circleName)?", isPresented: $isPresented) {
                Button("Cancel", role: .cancel) {}
                Button("Send Alert") {
                    Task {
                        if await model.trip.requestHelp() == false { notSent = true }
                    }
                }
            } message: {
                Text("Everyone in \(circleName) will be told you need help, with where you are and your battery.")
            }
            .alert("Alert Not Sent", isPresented: $notSent) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("We couldn't confirm it's you, so nobody was told. You can try again any time.")
            }
    }
}

extension View {
    /// Shows the "Send an alert?" popup; Send Alert asks for Face ID, then alerts the circle.
    func helpConfirmation(isPresented: Binding<Bool>) -> some View {
        modifier(HelpConfirmationModifier(isPresented: isPresented))
    }
}
