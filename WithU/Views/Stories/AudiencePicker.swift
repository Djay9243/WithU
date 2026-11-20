//
//  AudiencePicker.swift
//  WithU
//
//  Chooses who can see a story: only you, whole circles, or chosen members
//  of your circles. Nobody outside your circles can be picked.
//

import SwiftUI

struct AudiencePicker: View {
    @Environment(AppModel.self) private var model
    @Binding var audience: StoryAudience
    @State private var choosingPeople = false

    var body: some View {
        VStack(spacing: 0) {
            row(title: "Only Me",
                subtitle: "Saved to your journal",
                systemImage: "lock.fill",
                selected: audience.isPrivate) {
                audience = .onlyMe
            }
            ForEach(model.storyCircles) { circle in
                Divider().padding(.leading, 52)
                row(title: circle.name,
                    subtitle: "\(circle.contacts.count) \(circle.contacts.count == 1 ? "person" : "people")",
                    systemImage: "person.2.fill",
                    selected: audience.circleIDs.contains(circle.id)) {
                    toggleCircle(circle.id)
                }
            }
            if !model.storyCircles.isEmpty {
                Divider().padding(.leading, 52)
                row(title: "Choose People…",
                    subtitle: peopleSubtitle,
                    systemImage: "person.crop.circle.badge.checkmark",
                    selected: !audience.memberIDs.isEmpty,
                    showsCheck: false) {
                    choosingPeople = true
                }
            }
        }
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .sheet(isPresented: $choosingPeople) {
            PeoplePicker(audience: $audience)
                .environment(model)
                .presentationDetents([.medium, .large])
        }
    }

    private var peopleSubtitle: String {
        let count = audience.memberIDs.count
        return count == 0 ? "Only some people in a circle" : "\(count) chosen"
    }

    private func toggleCircle(_ id: UUID) {
        if let index = audience.circleIDs.firstIndex(of: id) {
            audience.circleIDs.remove(at: index)
        } else {
            audience.circleIDs.append(id)
        }
    }

    private func row(title: String,
                     subtitle: String,
                     systemImage: String,
                     selected: Bool,
                     showsCheck: Bool = true,
                     action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(selected ? .white : Theme.primary)
                    .frame(width: 32, height: 32)
                    .background(selected ? Theme.primary : Theme.lavender, in: Circle())
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.ink)
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(Theme.inkSecondary)
                }
                Spacer()
                Image(systemName: showsCheck ? (selected ? "checkmark.circle.fill" : "circle") : "chevron.right")
                    .font(showsCheck ? .title3 : .footnote.weight(.semibold))
                    .foregroundStyle(selected && showsCheck ? Theme.primary : Theme.inkSecondary.opacity(0.6))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Picks individual members of your circles.
private struct PeoplePicker: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @Binding var audience: StoryAudience

    var body: some View {
        NavigationStack {
            List {
                ForEach(model.storyCircles) { circle in
                    Section(circle.name) {
                        ForEach(circle.contacts) { contact in
                            let selected = audience.memberIDs.contains(contact.id)
                            Button {
                                toggle(contact.id)
                            } label: {
                                HStack(spacing: 12) {
                                    AvatarView(name: contact.name, colorIndex: contact.colorIndex, size: 32)
                                    Text(contact.name)
                                        .foregroundStyle(Theme.ink)
                                    Spacer()
                                    Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                                        .font(.title3)
                                        .foregroundStyle(selected ? Theme.primary : Theme.inkSecondary.opacity(0.6))
                                }
                            }
                            .accessibilityAddTraits(selected ? .isSelected : [])
                        }
                    }
                }
            }
            .navigationTitle("Choose People")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                // Choices apply as you tap, so there's nothing to save: just close.
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close", systemImage: "xmark") { dismiss() }
                }
            }
        }
    }

    private func toggle(_ id: UUID) {
        if let index = audience.memberIDs.firstIndex(of: id) {
            audience.memberIDs.remove(at: index)
        } else {
            audience.memberIDs.append(id)
        }
    }
}
