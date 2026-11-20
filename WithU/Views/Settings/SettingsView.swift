//
//  SettingsView.swift
//  WithU
//

import LocalAuthentication
import SwiftUI
import UIKit

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.colorScheme) private var colorScheme
    @State private var pinSetup: PINSetupView.Kind?
    @State private var choosingName = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            List {
                profileSection
                appearanceSection(settings: $model.settings)
                tripsSection(settings: $model.settings)
                safetySection
                permissionsSection
            }
            .scrollContentBackground(.hidden)
            .background(ScreenBackground())
            .tint(Theme.primary)
            .navigationTitle("Settings")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .sheet(item: $pinSetup) { kind in
            PINSetupView(kind: kind)
                .environment(model)
                .preferredColorScheme(model.settings.appearance.colorScheme)
        }
        .sheet(isPresented: $choosingName) {
            ContactPicker(allowsMultipleSelection: false) { picked in
                if let card = picked.first {
                    // The name is set once and then locked; the number can be added later.
                    if model.settings.userName.isEmpty {
                        model.settings.userName = card.name
                    }
                    model.setOwnPhone(card.phoneNumber)
                }
                choosingName = false
            }
            .ignoresSafeArea()
        }
        .task { await model.refreshPermissions() }
    }

    // MARK: Sections

    /// Your name comes from your contact card once and can't be edited afterwards.
    @ViewBuilder
    private var profileSection: some View {
        Section {
            if model.settings.userName.isEmpty {
                Button {
                    choosingName = true
                } label: {
                    Label("Choose Your Contact Card", systemImage: "person.crop.circle.badge.plus")
                }
                .listRowBackground(Theme.surface)
            } else {
                HStack(spacing: 12) {
                    AvatarView(name: model.settings.userName, colorIndex: 0, size: 40)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(model.settings.userName)
                            .font(.headline)
                            .foregroundStyle(Theme.ink)
                        if let phone = model.settings.userPhone {
                            Text(phone)
                                .font(.subheadline)
                                .foregroundStyle(Theme.inkSecondary)
                        }
                    }
                }
                .listRowBackground(Theme.surface)
                .accessibilityElement(children: .combine)

                if model.settings.userPhone == nil {
                    Button {
                        choosingName = true
                    } label: {
                        Label("Add Your Phone Number", systemImage: "phone.badge.plus")
                    }
                    .listRowBackground(Theme.surface)
                }
            }
        }
    }

    private func appearanceSection(settings: Binding<AppSettings>) -> some View {
        Section("Appearance") {
            Toggle(isOn: Binding(
                get: {
                    switch settings.wrappedValue.appearance {
                    case .dark: true
                    case .light: false
                    case .system: colorScheme == .dark
                    }
                },
                set: { settings.wrappedValue.appearance = $0 ? .dark : .light }
            )) {
                Label("Dark Mode", systemImage: "moon.fill")
            }
            .tint(Theme.safeGreen)
            .listRowBackground(Theme.surface)
        }
    }

    private func tripsSection(settings: Binding<AppSettings>) -> some View {
        Section("Trips") {
            Toggle(isOn: settings.preferBusyRoute) {
                Label("Busy Routes", systemImage: "storefront")
            }
            .listRowBackground(Theme.surface)
            Toggle(isOn: settings.lowBatteryPing) {
                Label("Low-Battery Location", systemImage: "battery.25percent")
            }
            .listRowBackground(Theme.surface)
            Toggle(isOn: settings.checkOnStop) {
                Label("Check In When I Stop", systemImage: "figure.stand")
            }
            .listRowBackground(Theme.surface)
            if settings.wrappedValue.checkOnStop {
                Picker(selection: settings.stopThresholdMinutes) {
                    ForEach([5, 8, 12, 15, 20], id: \.self) { minutes in
                        Text("\(minutes) min").tag(minutes)
                    }
                } label: {
                    Label("After", systemImage: "hourglass")
                }
                .listRowBackground(Theme.surface)
            }
            Toggle(isOn: settings.homeDeadlineEnabled) {
                Label("Home By", systemImage: "house")
            }
            .listRowBackground(Theme.surface)
            if settings.wrappedValue.homeDeadlineEnabled {
                DatePicker(selection: deadlineBinding(settings), displayedComponents: .hourAndMinute) {
                    Label("Time", systemImage: "clock")
                }
                .listRowBackground(Theme.surface)
            }
            Picker(selection: settings.checkInResponseSeconds) {
                ForEach(TripRules.checkInWindowOptions, id: \.self) { seconds in
                    Text(Format.responseTime(seconds).replacingOccurrences(of: "minutes", with: "min").replacingOccurrences(of: "minute", with: "min"))
                        .tag(seconds)
                }
            } label: {
                Label("Time to Reply", systemImage: "timer")
            }
            .listRowBackground(Theme.surface)
        }
        .tint(Theme.safeGreen)
    }

    private func deadlineBinding(_ settings: Binding<AppSettings>) -> Binding<Date> {
        Binding(
            get: {
                let minutes = settings.wrappedValue.homeDeadlineMinutes
                return Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: .now) ?? .now
            },
            set: { date in
                let components = Calendar.current.dateComponents([.hour, .minute], from: date)
                settings.wrappedValue.homeDeadlineMinutes = (components.hour ?? 22) * 60 + (components.minute ?? 45)
            }
        )
    }

    private var safetySection: some View {
        Section("Safety") {
            pinRow(title: "Safety PIN", systemImage: "lock.fill", isSet: model.auth.hasPIN) {
                pinSetup = .pin
            }
        }
    }

    private func pinRow(title: String, systemImage: String, isSet: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Label(title, systemImage: systemImage)
                    .foregroundStyle(Theme.ink)
                Spacer()
                Text(isSet ? "On" : "Off")
                    .foregroundStyle(Theme.inkSecondary)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.inkSecondary.opacity(0.6))
            }
        }
        .listRowBackground(Theme.surface)
    }

    private var permissionsSection: some View {
        Section("Permissions") {
            permissionRow("Location", systemImage: "location.fill", isOn: model.location.isAuthorized)
            permissionRow("Notifications", systemImage: "bell.fill", isOn: model.notifications.isAuthorized)
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .listRowBackground(Theme.surface)
        }
    }

    private func permissionRow(_ title: String, systemImage: String, isOn: Bool) -> some View {
        HStack {
            Label(title, systemImage: systemImage)
                .foregroundStyle(Theme.ink)
            Spacer()
            Text(isOn ? "On" : "Off")
                .foregroundStyle(isOn ? Theme.safeGreen : Theme.inkSecondary)
        }
        .listRowBackground(Theme.surface)
    }
}

#Preview {
    SettingsView()
        .environment(AppModel.shared)
}
