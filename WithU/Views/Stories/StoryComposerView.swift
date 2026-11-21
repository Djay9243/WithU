//
//  StoryComposerView.swift
//  WithU
//
//  "Share a Moment": the camera opens straight away, then a photo, a short
//  note, the place and who sees it. Nothing is shared until Share is tapped.
//

import CoreLocation
import SwiftUI

struct StoryComposerView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    /// Called after the story is saved, e.g. to answer a stop check-in.
    var onShared: (Story) -> Void = { _ in }

    @State private var photo: UIImage?
    @State private var caption = ""
    @State private var place: StoryPlace?
    @State private var showsPlace = true
    @State private var audience: StoryAudience = .onlyMe
    /// Presents the system camera from UIKit, one at a time.
    @State private var camera = CameraPicker()
    /// Camera access is off in Settings.
    @State private var cameraDenied = false
    @State private var didOpen = false
    @State private var didAutoOpenCamera = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    photoArea
                    TextField("Say something…", text: $caption, axis: .vertical)
                        .lineLimit(1...3)
                        .padding(.horizontal, 18)
                        .padding(.vertical, 14)
                        .glassEffect(.regular, in: .rect(cornerRadius: 22))
                    placeChip
                    audienceChips
                }
                .padding(20)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(ScreenBackground())
            .navigationTitle("Share a Moment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", systemImage: "xmark") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Share", systemImage: "paperplane.fill") { share() }
                        .disabled(!canShare)
                }
            }
        }
        .task { await loadPlace() }
        .onAppear {
            guard !didOpen else { return }
            didOpen = true
            audience = model.defaultStoryAudience
        }
        .task {
            // Open the camera once. The presenter waits for this sheet to
            // finish opening; the task is cancelled with the sheet.
            guard !didAutoOpenCamera, CameraPicker.isAvailable else { return }
            didAutoOpenCamera = true
            guard photo == nil else { return }
            await openCamera()
        }
        .alert("Camera Access Is Off", isPresented: $cameraDenied) {
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("Not Now", role: .cancel) {}
        } message: {
            Text("Turn on Camera for WithU in Settings to take a photo of the moment.")
        }
    }

    private var canShare: Bool {
        photo != nil || !caption.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: Photo

    @ViewBuilder
    private var photoArea: some View {
        if let photo {
            // Shows the photo you just took, cropped to the card, never stretched.
            Color.clear
                .frame(maxWidth: .infinity)
                .frame(height: 380)
                .overlay {
                    Image(uiImage: photo)
                        .resizable()
                        .scaledToFill()
                }
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                .overlay(alignment: .bottomTrailing) {
                    Menu {
                        if CameraPicker.isAvailable {
                            Button("Take Another Photo", systemImage: "camera") { Task { await openCamera() } }
                        }
                        Button("Remove Photo", systemImage: "trash", role: .destructive) { self.photo = nil }
                    } label: {
                        Label("Change", systemImage: "camera.rotate")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 9)
                            .glassEffect(.regular, in: .capsule)
                    }
                    .padding(12)
                }
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Your photo")
        } else {
            VStack(spacing: 14) {
                Image(systemName: "camera.fill")
                    .font(.system(size: 36, weight: .semibold))
                    .foregroundStyle(Theme.primary)
                    .accessibilityHidden(true)
                if CameraPicker.isAvailable {
                    Button {
                        Task { await openCamera() }
                    } label: {
                        Label("Take Photo", systemImage: "camera")
                            .font(.subheadline.weight(.semibold))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(Theme.primary)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 220)
            .glassEffect(.regular, in: .rect(cornerRadius: 28))
        }
    }

    private func openCamera() async {
        let result = await camera.present { image in
            photo = image
        }
        if result == .denied { cameraDenied = true }
    }

    // MARK: Place

    @ViewBuilder
    private var placeChip: some View {
        if let place {
            HStack {
                Button {
                    withAnimation(.snappy) { showsPlace.toggle() }
                } label: {
                    Label(showsPlace ? place.name : "No location",
                          systemImage: showsPlace ? place.symbol : "location.slash")
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .foregroundStyle(showsPlace ? Theme.primary : Theme.inkSecondary)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.plain)
                .glassEffect(.regular.interactive(), in: .capsule)
                .accessibilityHint("Double-tap to \(showsPlace ? "hide" : "show") the location")
                Spacer()
            }
        }
    }

    private func loadPlace() async {
        guard let location = await model.location.currentFix() else { return }
        if let nearest = await PlaceService.nearbyPlaces(around: location, radius: 120).first {
            place = nearest
        } else if let city = await PlaceService.cityName(for: location) {
            place = StoryPlace(name: city,
                               city: city,
                               latitude: location.coordinate.latitude,
                               longitude: location.coordinate.longitude,
                               symbol: "building.2")
        }
    }

    // MARK: Audience

    /// Only Me, or one or more circles.
    private var audienceChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    chip(title: "Only Me", systemImage: "lock.fill", selected: audience.isPrivate) {
                        audience = .onlyMe
                    }
                    ForEach(model.storyCircles) { circle in
                        chip(title: circle.name, systemImage: "person.2.fill",
                             selected: audience.circleIDs.contains(circle.id)) {
                            if let index = audience.circleIDs.firstIndex(of: circle.id) {
                                audience.circleIDs.remove(at: index)
                            } else {
                                audience.circleIDs.append(circle.id)
                            }
                        }
                    }
                }
            }
            .padding(.vertical, 2)
        }
        .scrollClipDisabled()
    }

    private func chip(title: String, systemImage: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(selected ? .white : Theme.ink)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
        }
        .buttonStyle(.plain)
        .glassEffect(selected ? .regular.tint(Theme.primary).interactive() : .regular.interactive(), in: .capsule)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    // MARK: Share

    private func share() {
        guard let story = model.stories.add(caption: caption,
                                            images: photo.map { [$0] } ?? [],
                                            place: showsPlace ? place : nil,
                                            precision: .place,
                                            audience: audience,
                                            expiresAfter: nil,
                                            tripID: model.trip.isActive ? model.trip.tripID : nil) else { return }
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        onShared(story)
        dismiss()
    }
}

#Preview {
    StoryComposerView()
        .environment(AppModel.shared)
}
