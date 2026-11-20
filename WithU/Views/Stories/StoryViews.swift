//
//  StoryViews.swift
//  WithU
//
//  Showing stories: a thumbnail for rows and grids, and a detail screen where
//  the owner can change who sees a story or delete it.
//

import SwiftUI

/// Square story preview: the first photo, or the caption on a tinted card.
struct StoryThumbnail: View {
    @Environment(AppModel.self) private var model
    var story: Story
    var size: CGFloat = 120

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            if let file = story.photoFiles.first, let image = model.stories.image(named: file) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size, height: size * 1.25)
                    .clipped()
                LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .center, endPoint: .bottom)
            } else {
                Theme.lavenderDeep
                Text(story.caption)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(Theme.ink)
                    .lineLimit(5)
                    .padding(10)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
            if let place = story.displayPlace, !story.photoFiles.isEmpty {
                Text(place)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .padding(8)
            }
        }
        .frame(width: size, height: size * 1.25)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(alignment: .topTrailing) {
            if story.audience.isPrivate {
                Image(systemName: "lock.fill")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(6)
                    .background(.black.opacity(0.35), in: Circle())
                    .padding(6)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        var parts = [story.caption.isEmpty ? "Story" : story.caption]
        if let place = story.displayPlace { parts.append(place) }
        if story.audience.isPrivate { parts.append("Only you") }
        return parts.joined(separator: ", ")
    }
}

/// A full story with its photos, place and audience.
struct StoryDetailView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    var storyID: UUID

    @State private var editingAudience = false
    @State private var confirmingDelete = false

    private var story: Story? { model.stories.stories.first { $0.id == storyID } }

    var body: some View {
        ScrollView {
            if let story {
                VStack(alignment: .leading, spacing: 16) {
                    if !story.photoFiles.isEmpty {
                        TabView {
                            ForEach(story.photoFiles, id: \.self) { file in
                                if let image = model.stories.image(named: file) {
                                    Image(uiImage: image)
                                        .resizable()
                                        .scaledToFill()
                                        .frame(maxWidth: .infinity)
                                        .clipped()
                                }
                            }
                        }
                        .tabViewStyle(.page(indexDisplayMode: story.photoFiles.count > 1 ? .always : .never))
                        .frame(height: 420)
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                    }
                    if !story.caption.isEmpty {
                        Text(story.caption)
                            .font(.title3.weight(.semibold))
                            .foregroundStyle(Theme.ink)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        if let place = story.displayPlace {
                            Label(place, systemImage: story.precision.symbol)
                        }
                        Label(story.createdAt.formatted(date: .abbreviated, time: .shortened), systemImage: "clock")
                        if let expires = story.expiresAt {
                            Label("Disappears \(expires.formatted(.relative(presentation: .named)))", systemImage: "timer")
                        }
                    }
                    .font(.subheadline)
                    .foregroundStyle(Theme.inkSecondary)

                    Button {
                        editingAudience = true
                    } label: {
                        HStack {
                            Image(systemName: story.audience.isPrivate ? "lock.fill" : "person.2.fill")
                                .foregroundStyle(Theme.primary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Who Can See This")
                                    .font(.caption)
                                    .foregroundStyle(Theme.inkSecondary)
                                Text(model.audienceSummary(story.audience))
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(Theme.ink)
                            }
                            Spacer()
                            Text("Change")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(Theme.primary)
                        }
                        .card(fill: Theme.surface, padding: 14)
                    }
                    .buttonStyle(.plain)
                }
                .padding(20)
            }
        }
        .background(ScreenBackground())
        .navigationTitle("Story")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .destructiveAction) {
                Button(role: .destructive) {
                    confirmingDelete = true
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
        .confirmationDialog("Delete this story?", isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Delete Story", role: .destructive) {
                if let story { model.stories.delete(story) }
                dismiss()
            }
        } message: {
            Text("It's removed for everyone who could see it.")
        }
        .sheet(isPresented: $editingAudience) {
            if let story {
                AudienceEditor(storyID: story.id, initial: story.audience)
                    .environment(model)
                    .presentationDetents([.medium, .large])
            }
        }
    }
}

/// Changes who can see a story after it was shared.
private struct AudienceEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    var storyID: UUID
    @State private var audience: StoryAudience

    init(storyID: UUID, initial: StoryAudience) {
        self.storyID = storyID
        _audience = State(initialValue: initial)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                AudiencePicker(audience: $audience)
                    .padding(20)
            }
            .background(ScreenBackground())
            .navigationTitle("Who Can See This")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        model.stories.updateAudience(of: storyID, to: audience)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}
