//
//  PermissionsView.swift
//  WithU
//
//  "Your Safety Comes First": location and notifications, each requested only
//  when the person turns its switch on. Styled like Settings.
//

import SwiftUI
import UIKit

struct PermissionsView: View {
    @Environment(AppModel.self) private var model
    var onContinue: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            List {
                Section {
                    PermissionRow(title: "Location",
                                  subtitle: "Used only during trips",
                                  systemImage: "location.fill",
                                  isOn: model.location.isAuthorized,
                                  isDenied: model.location.isDenied) {
                        await model.location.requestAuthorization()
                    }
                    PermissionRow(title: "Notifications",
                                  subtitle: "For check-ins and alerts",
                                  systemImage: "bell.fill",
                                  isOn: model.notifications.isAuthorized,
                                  isDenied: model.notifications.authorizationStatus == .denied) {
                        await model.notifications.requestAuthorization()
                    }
                } header: {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("A Few Permissions")
                            .font(.title2.bold())
                            .foregroundStyle(Theme.ink)
                        Text("Location is shared only during trips.")
                            .font(.subheadline)
                            .foregroundStyle(Theme.inkSecondary)
                    }
                    .textCase(nil)
                    .padding(.bottom, 12)
                    .padding(.top, 24)
                }
            }
            .scrollContentBackground(.hidden)
            .tint(Theme.primary)
            .scrollDisabled(true)

            Button("Continue", action: onContinue)
                .buttonStyle(.primary)
                .padding(.horizontal, 36)
                .padding(.bottom, 28)
        }
        .task { await model.refreshPermissions() }
    }
}

struct PermissionRow: View {
    var title: String
    var subtitle: String
    var systemImage: String
    var isOn: Bool
    var isDenied: Bool
    var request: () async -> Void

    @State private var isRequesting = false

    var body: some View {
        Toggle(isOn: toggleBinding) {
            Label {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .foregroundStyle(Theme.ink)
                    Text(isDenied ? "Turned off in Settings" : subtitle)
                        .font(.caption)
                        .foregroundStyle(isDenied ? Theme.alertRed : Theme.inkSecondary)
                }
            } icon: {
                Image(systemName: systemImage)
            }
        }
        .tint(Theme.safeGreen)
        .disabled(isRequesting)
        .listRowBackground(Theme.surface)
    }

    private var toggleBinding: Binding<Bool> {
        Binding(
            get: { isOn },
            set: { wantsOn in
                if !wantsOn {
                    // Permissions can only be revoked in the Settings app.
                    if isOn { openSettings() }
                    return
                }
                if isDenied {
                    openSettings()
                    return
                }
                isRequesting = true
                Task {
                    await request()
                    isRequesting = false
                }
            }
        )
    }

    private func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
}

#Preview {
    ZStack {
        ScreenBackground()
        PermissionsView {}
    }
    .environment(AppModel.shared)
}
