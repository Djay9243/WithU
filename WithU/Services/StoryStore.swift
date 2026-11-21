//
//  StoryStore.swift
//  WithU
//
//  Keeps stories and finished journeys on the device. Photos are re-encoded
//  before saving, which drops their metadata, including where they were taken.
//  Sending stories to circles is added on top once iCloud sharing is on.
//

import Foundation
import ImageIO
import Observation
import UIKit

@Observable
final class StoryStore {
    /// How long a story shows in the Journal's Stories.
    static let storyLifetime: TimeInterval = 24 * 60 * 60
    /// How long a finished trip, and the photos taken on it, are kept.
    static let tripLifetime: TimeInterval = 30 * 24 * 60 * 60

    /// Newest first, including trip photos older than a day (they stay in the
    /// trip's recap). Use `liveStories` for the Stories row.
    private(set) var stories: [Story] {
        didSet { Persistence.save(stories, for: .stories) }
    }

    /// Finished trips, newest first.
    private(set) var journeys: [Journey] {
        didSet { Persistence.save(journeys, for: .journeys) }
    }

    @ObservationIgnored private let cache = NSCache<NSString, UIImage>()
    @ObservationIgnored private let thumbnails = NSCache<NSString, UIImage>()

    init() {
        stories = Persistence.load([Story].self, for: .stories) ?? []
        journeys = Persistence.load([Journey].self, for: .journeys) ?? []
        removeExpired()
    }

    // MARK: - Stories

    /// Saves the photos and adds the story. Returns nil if no photo could be saved.
    @discardableResult
    func add(caption: String,
             images: [UIImage],
             place: StoryPlace?,
             precision: LocationPrecision,
             audience: StoryAudience,
             expiresAfter: TimeInterval?,
             tripID: UUID?) -> Story? {
        let files = images.compactMap(savePhoto)
        guard !files.isEmpty || !caption.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        let story = Story(tripID: tripID,
                          caption: caption.trimmingCharacters(in: .whitespacesAndNewlines),
                          photoFiles: files,
                          placeName: place?.name,
                          cityName: place?.city,
                          latitude: place?.latitude,
                          longitude: place?.longitude,
                          precision: place == nil ? .hidden : precision,
                          audience: audience,
                          expiresAt: expiresAfter.map { Date.now.addingTimeInterval($0) })
        stories.insert(story, at: 0)
        return story
    }

    func updateAudience(of storyID: UUID, to audience: StoryAudience) {
        guard let index = stories.firstIndex(where: { $0.id == storyID }) else { return }
        stories[index].audience = audience
    }

    func delete(_ story: Story) {
        story.photoFiles.forEach(deletePhoto)
        stories.removeAll { $0.id == story.id }
    }

    func stories(forTrip tripID: UUID) -> [Story] {
        stories.filter { $0.tripID == tripID }
    }

    /// Stories from the last 24 hours, for the Journal's Stories.
    func liveStories(at date: Date = .now) -> [Story] {
        stories.filter { !$0.isExpired(at: date) && date.timeIntervalSince($0.createdAt) < Self.storyLifetime }
    }

    /// Clears out what's past its time, photos included:
    /// • trips 30 days after they ended, with every photo taken on them;
    /// • stories not from a trip, 24 hours after they were shared;
    /// • trip photos whose trip isn't in the journal, after 30 days.
    func removeExpired(at date: Date = .now) {
        let oldTrips = Set(journeys.filter { date.timeIntervalSince($0.endedAt) >= Self.tripLifetime }.map(\.id))
        if !oldTrips.isEmpty {
            journeys.removeAll { oldTrips.contains($0.id) }
        }
        let keptTrips = Set(journeys.map(\.id))
        let expired = stories.filter { story in
            if story.isExpired(at: date) { return true }
            let age = date.timeIntervalSince(story.createdAt)
            guard let tripID = story.tripID else { return age >= Self.storyLifetime }
            if oldTrips.contains(tripID) { return true }
            // A trip photo stays with its trip. Without one (an SOS, or the
            // trip still running) it's kept as long as a trip would be.
            return !keptTrips.contains(tripID) && age >= Self.tripLifetime
        }
        guard !expired.isEmpty else { return }
        expired.flatMap(\.photoFiles).forEach(deletePhoto)
        let ids = Set(expired.map(\.id))
        stories.removeAll { ids.contains($0.id) }
    }

    /// A circle or person left: stop including them in story audiences.
    func removeFromAudiences(circleID: UUID? = nil, memberIDs: Set<UUID> = []) {
        for index in stories.indices {
            if let circleID { stories[index].audience.circleIDs.removeAll { $0 == circleID } }
            stories[index].audience.memberIDs.removeAll { memberIDs.contains($0) }
        }
    }

    // MARK: - Journeys

    func record(_ journey: Journey) {
        journeys.removeAll { $0.id == journey.id }
        journeys.insert(journey, at: 0)
    }

    /// Removes the trip and the photos taken on it.
    func deleteJourney(_ journey: Journey) {
        journeys.removeAll { $0.id == journey.id }
        let moments = stories(forTrip: journey.id)
        moments.flatMap(\.photoFiles).forEach(deletePhoto)
        stories.removeAll { $0.tripID == journey.id }
    }

    // MARK: - Photos

    func image(named file: String) -> UIImage? {
        if let cached = cache.object(forKey: file as NSString) { return cached }
        guard let image = UIImage(contentsOfFile: Self.folder.appendingPathComponent(file).path) else { return nil }
        cache.setObject(image, forKey: file as NSString)
        return image
    }

    /// A small copy for grids, chips and map pins. Decoding a 1600 px JPEG for
    /// every thumbnail made the Journal slow; ImageIO decodes straight to size.
    func thumbnail(named file: String, maxPixelSize: CGFloat) -> UIImage? {
        let key = "\(file)@\(Int(maxPixelSize))" as NSString
        if let cached = thumbnails.object(forKey: key) { return cached }
        let url = Self.folder.appendingPathComponent(file)
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        let image = UIImage(cgImage: cgImage)
        thumbnails.setObject(image, forKey: key)
        return image
    }

    private static let folder: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let url = base.appendingPathComponent("Stories", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    /// Scales the photo down and writes it as a fresh JPEG. Re-encoding from
    /// pixels means no EXIF or GPS data from the original is carried over.
    private func savePhoto(_ image: UIImage) -> String? {
        let scaled = image.scaledToFit(maxDimension: 1600)
        guard let data = scaled.jpegData(compressionQuality: 0.82) else { return nil }
        let name = UUID().uuidString + ".jpg"
        do {
            try data.write(to: Self.folder.appendingPathComponent(name), options: [.atomic, .completeFileProtection])
            cache.setObject(scaled, forKey: name as NSString)
            return name
        } catch {
            return nil
        }
    }

    private func deletePhoto(_ file: String) {
        cache.removeObject(forKey: file as NSString)
        thumbnails.removeAllObjects()
        try? FileManager.default.removeItem(at: Self.folder.appendingPathComponent(file))
    }
}

/// A place a story can be tagged with.
nonisolated struct StoryPlace: Hashable, Identifiable, Sendable {
    var name: String
    var city: String?
    var latitude: Double
    var longitude: Double
    /// SF Symbol for the place category.
    var symbol: String = "mappin"

    var id: String { "\(name)|\(latitude)|\(longitude)" }
}

extension UIImage {
    /// Draws the image at most `maxDimension` points on its longest side.
    /// Always redraws a rotated photo, so it's saved upright with no
    /// orientation flag (camera photos are stored sideways plus a flag).
    func scaledToFit(maxDimension: CGFloat) -> UIImage {
        let longest = max(size.width, size.height)
        guard longest > maxDimension || imageOrientation != .up else { return self }
        let factor = min(maxDimension / longest, 1)
        let target = CGSize(width: size.width * factor, height: size.height * factor)
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            draw(in: CGRect(origin: .zero, size: target))
        }
    }
}
