//
//  CircleView.swift
//  WithU
//
//  Your circles, one card each showing everyone in it, so you can see who's
//  where without opening them. Swipe a circle to rename or delete it; tap it
//  to manage who's in it. Everyone in a circle is told at the same time.
//

import MapKit
import SwiftUI

struct CircleView: View {
    @Environment(AppModel.self) private var model
    @State private var editor: CircleNameEditor?
    @State private var creating = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    if let cloud = model.cloud {
                        CloudSections(cloud: cloud)
                    }
                    ForEach(model.circles) { circle in
                        NavigationLink(value: circle.id) {
                            CircleCard(circle: circle)
                        }
                        .buttonStyle(PressableStyle())
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            if model.circles.count > 1 {
                                Button(role: .destructive) {
                                    model.deleteCircle(circle)
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                            Button {
                                editor = .rename(circle)
                            } label: {
                                Label("Rename", systemImage: "pencil")
                            }
                            .tint(Theme.primary)
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 20)
            }
            .swipeActionsContainer()
            .background(ScreenBackground())
            .refreshable { await model.cloud?.refresh() }
            .navigationTitle("Circles")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        creating = true
                    } label: {
                        Label("New Circle", systemImage: "plus")
                    }
                }
            }
            .navigationDestination(for: UUID.self) { id in
                CircleDetailView(circleID: id)
            }
        }
        .circleNameEditor($editor)
        .sheet(isPresented: $creating) {
            NewCircleSheet()
                .environment(model)
        }
    }
}

/// One circle: its name and everyone in it, with their avatar and first name.
private struct CircleCard: View {
    var circle: TrustedCircle

    private let columns = [GridItem(.adaptive(minimum: 64), spacing: 8, alignment: .top)]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 6) {
                Text(circle.name)
                    .font(.title3.bold())
                    .foregroundStyle(Theme.ink)
                    .lineLimit(1)
                Text("· \(circle.contacts.count)")
                    .font(.title3)
                    .foregroundStyle(Theme.inkSecondary)
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.inkSecondary)
                    .accessibilityHidden(true)
            }

            if circle.contacts.isEmpty {
                Label("Add people to this circle", systemImage: "person.crop.circle.badge.plus")
                    .font(.subheadline)
                    .foregroundStyle(Theme.inkSecondary)
            } else {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                    ForEach(circle.contacts) { contact in
                        VStack(spacing: 6) {
                            AvatarView(name: contact.name, colorIndex: contact.colorIndex, size: 46)
                            Text(firstName(contact.name))
                                .font(.caption)
                                .foregroundStyle(Theme.ink)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .card(padding: 18)
        .contentShape(.rect(cornerRadius: 22))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private func firstName(_ name: String) -> String {
        name.split(separator: " ").first.map(String.init) ?? name
    }

    private var accessibilityText: String {
        guard !circle.contacts.isEmpty else { return "\(circle.name), no people yet" }
        let names = circle.contacts.map { firstName($0.name) }.formatted(.list(type: .and))
        return "\(circle.name): \(names)"
    }
}

// MARK: - Circle detail

struct CircleDetailView: View {
    @Environment(AppModel.self) private var model
    var circleID: UUID
    @State private var showingPicker = false

    private var circle: TrustedCircle? { model.circle(withID: circleID) }

    var body: some View {
        List {
            if let circle {
                Section {
                    if circle.contacts.isEmpty {
                        Text("Add people with WithU. They only hear from us if you need them.")
                            .font(.subheadline)
                            .foregroundStyle(Theme.inkSecondary)
                            .listRowBackground(Theme.surface)
                    }
                    ForEach(Array(circle.contacts.enumerated()), id: \.element.id) { index, contact in
                        HStack(spacing: 12) {
                            AvatarView(name: contact.name, colorIndex: contact.colorIndex, size: 36)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(contact.name)
                                    .font(.body)
                                    .foregroundStyle(Theme.ink)
                                Text(subtitle(for: contact, index: index))
                                    .font(.caption)
                                    .foregroundStyle(contact.link?.status == .declined ? Theme.alertRed : Theme.inkSecondary)
                            }
                        }
                        .listRowBackground(Theme.surface)
                        .swipeActions(edge: .leading) {
                            if model.cloud?.isAvailable == true, !contact.isConnected, contact.phoneNumber != nil {
                                Button {
                                    model.invite(contact.id, in: circleID)
                                } label: {
                                    Label(contact.link == nil ? "Invite" : "Resend", systemImage: "paperplane")
                                }
                                .tint(Theme.safeGreen)
                            }
                            if index > 0 {
                                Button {
                                    model.moveContacts(from: IndexSet(integer: index), to: index - 1, in: circleID)
                                } label: {
                                    Label("Move Up", systemImage: "arrow.up")
                                }
                                .tint(Theme.primary)
                            }
                        }
                    }
                    .onDelete { offsets in
                        model.removeContacts(at: offsets, from: circleID)
                    }
                } header: {
                    Text("People")
                } footer: {
                    if !circle.contacts.isEmpty {
                        Text("If you miss a check-in, everyone here hears at the same time.")
                    }
                }

                Section {
                    Button {
                        showingPicker = true
                    } label: {
                        Label("Add From Contacts", systemImage: "person.crop.circle.badge.plus")
                    }
                    .listRowBackground(Theme.surface)
                }

                Section {
                    Toggle(isOn: Binding(
                        get: { circle.receivesStories },
                        set: { model.setReceivesStories($0, for: circleID) }
                    )) {
                        Label("Can See My Stories", systemImage: "camera.fill")
                    }
                    .tint(Theme.safeGreen)
                    .listRowBackground(Theme.surface)
                } footer: {
                    Text("Off: they get alerts, not photos.")
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(ScreenBackground())
        .navigationTitle(circle?.name ?? "Circle")
        .contactPicker(isPresented: $showingPicker) { picked in
            model.addContacts(picked, to: circleID)
        }
    }

    /// Alert position, plus whether they can actually be reached.
    private func subtitle(for contact: TrustedContact, index: Int) -> String {
        let order = index == 0 ? "Alerted first" : "Alerted \(ordinal(index + 1))"
        guard model.cloud != nil else { return order }
        switch contact.link?.status {
        case .connected: return "\(order) · On WithU"
        case .invited: return "Invite Sent"
        case .declined: return "Declined"
        case nil: return contact.phoneNumber == nil ? "No phone number" : "Not Invited"
        }
    }

    private func ordinal(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .ordinal
        return formatter.string(from: NSNumber(value: value)) ?? "#\(value)"
    }
}

// MARK: - Invites and followed trips

/// Shown above your circles when iCloud sync is on.
private struct CloudSections: View {
    @Environment(AppModel.self) private var model
    var cloud: CloudCircleService

    var body: some View {
        if let problem = cloud.problem, !cloud.isAvailable {
            Label(problem, systemImage: "icloud.slash")
                .font(.subheadline)
                .foregroundStyle(Theme.inkSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .card(padding: 14)
        }

        if !cloud.incomingInvites.isEmpty {
            SectionLabel(text: "Invites")
                .padding(.top, 4)
            ForEach(cloud.incomingInvites) { invite in
                    HStack(spacing: 12) {
                        AvatarView(name: invite.fromName, colorIndex: 3, size: 36)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(invite.fromName)
                                .font(.headline)
                                .foregroundStyle(Theme.ink)
                            Text("Wants to add you to their circle")
                                .font(.caption)
                                .foregroundStyle(Theme.inkSecondary)
                        }
                        Spacer()
                        Button("Decline") {
                            Task { await cloud.answer(invite, accept: false) }
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(Theme.inkSecondary)
                        Button("Accept") {
                            Task { await cloud.answer(invite, accept: true) }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Theme.primary)
                    }
                    .card(padding: 14)
            }
        }

        if !cloud.following.isEmpty {
            SectionLabel(text: "Following")
                .padding(.top, 4)
            ForEach(cloud.following) { trip in
                FollowedTripRow(trip: trip,
                                hasResponded: cloud.hasResponded(to: trip),
                                onIt: { Task { await cloud.sendOnIt(to: trip) } },
                                onOpenSOS: { cloud.reopenSOS(trip) })
                .card(fill: trip.state == .needsHelp ? Theme.alertRed : Theme.cardWhite, padding: 14)
            }
        }

        if !cloud.incomingInvites.isEmpty || !cloud.following.isEmpty {
            SectionLabel(text: "Your Circles")
                .padding(.top, 4)
        }
    }
}

private struct FollowedTripRow: View {
    var trip: FollowedTrip
    var hasResponded: Bool
    var onIt: () -> Void
    var onOpenSOS: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                if trip.state == .needsHelp { onOpenSOS() } else { openInMaps() }
            } label: {
                HStack(spacing: 12) {
                    AvatarView(name: trip.name, colorIndex: 1, size: 36)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(trip.name)
                            .font(.headline)
                            .foregroundStyle(Theme.ink)
                        Text(status)
                            .font(.caption)
                            .foregroundStyle(trip.state == .needsHelp ? Theme.alertRed : Theme.inkSecondary)
                    }
                    Spacer()
                    if trip.state == .needsHelp {
                        Image(systemName: "chevron.right")
                            .font(.footnote.weight(.semibold))
                            .foregroundStyle(Theme.inkSecondary)
                    } else if trip.coordinate != nil {
                        Image(systemName: "map.fill")
                            .foregroundStyle(Theme.primary)
                            .accessibilityHidden(true)
                    }
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint(trip.state == .needsHelp ? "Opens the alert." : "Shows them in Maps.")

            if trip.state == .needsHelp {
                Button {
                    onIt()
                } label: {
                    Label(hasResponded ? "They Know You're On It" : "I'm On It",
                          systemImage: hasResponded ? "checkmark" : "hand.raised.fill")
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(hasResponded ? Theme.deepGreen : Theme.alertRed)
                .disabled(hasResponded)
            }
        }
        .padding(.vertical, 4)
    }

    private var status: String {
        let updated = trip.updatedAt.formatted(.relative(presentation: .named))
        let battery = trip.battery.map { " · \(Int(($0 * 100).rounded()))% battery" } ?? ""
        switch trip.state {
        case .onTheWay:
            if let destination = trip.destination { return "Heading to \(destination) · \(updated)\(battery)" }
            return "On a trip · \(updated)\(battery)"
        case .needsHelp: return "Needs help · \(updated)\(battery)"
        case .safe: return "Safe · \(updated)"
        case .arrived: return "Arrived · \(updated)"
        case .ended: return "Trip ended · \(updated)"
        }
    }

    private func openInMaps() {
        guard let lat = trip.latitude, let lon = trip.longitude else { return }
        let item = MKMapItem(location: CLLocation(latitude: lat, longitude: lon), address: nil)
        item.name = trip.name
        item.openInMaps()
    }
}

// MARK: - Circle picker

/// Horizontal row of circle chips used on the map to choose who a trip is
/// shared with.
struct CirclePickerRow: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(model.circles) { circle in
                    let selected = circle.id == model.selectedCircle.id
                    Button {
                        model.selectCircle(circle)
                    } label: {
                        HStack(spacing: 6) {
                            Text(circle.name)
                                .font(.subheadline.weight(.semibold))
                                .lineLimit(1)
                            Text("\(circle.contacts.count)")
                                .font(.caption.weight(.bold))
                                .foregroundStyle(selected ? Color.white.opacity(0.85) : Theme.inkSecondary)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 9)
                        .foregroundStyle(selected ? .white : Theme.ink)
                    }
                    .buttonStyle(.plain)
                    .glassEffect(selected ? .regular.tint(Theme.primary).interactive() : .regular.interactive(), in: .capsule)
                    .accessibilityLabel("\(circle.name), \(circle.contacts.count) people")
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            .padding(.vertical, 2)
        }
    }
}

// MARK: - Name editor

enum CircleNameEditor: Identifiable {
    case rename(TrustedCircle)

    var id: String {
        switch self {
        case .rename(let circle): circle.id.uuidString
        }
    }
}

private struct CircleNameEditorModifier: ViewModifier {
    @Environment(AppModel.self) private var model
    @Binding var editor: CircleNameEditor?
    @State private var name = ""

    func body(content: Content) -> some View {
        content
            .alert(title, isPresented: isPresented) {
                TextField("Circle Name", text: $name)
                    .textInputAutocapitalization(.words)
                Button("Cancel", role: .cancel) { editor = nil }
                Button(buttonTitle) {
                    if case .rename(let circle) = editor {
                        model.renameCircle(circle, to: name)
                    }
                    editor = nil
                }
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            } message: {
                Text(message)
            }
            .onChange(of: editor?.id) { _, _ in
                if case .rename(let circle) = editor {
                    name = circle.name
                } else {
                    name = ""
                }
            }
    }

    private var isPresented: Binding<Bool> {
        Binding(get: { editor != nil }, set: { if !$0 { editor = nil } })
    }

    private let title = "Rename Circle"
    private let buttonTitle = "Save"
    private let message = "For example Family or Friends."
}

extension View {
    func circleNameEditor(_ editor: Binding<CircleNameEditor?>) -> some View {
        modifier(CircleNameEditorModifier(editor: editor))
    }
}

#Preview {
    CircleView()
        .environment(AppModel.shared)
}
