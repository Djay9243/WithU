//
//  CameraPicker.swift
//  WithU
//
//  The system camera (UIImagePickerController), presented straight from UIKit.
//
//  Why not a custom AVFoundation camera: the earlier custom one saved photos
//  sideways (the photo output's rotation was never set), had no focus, zoom
//  or flash, and needed its own permission and interruption handling. The
//  system camera handles all of that, matches what people know from the
//  Camera app, and returns an upright photo.
//
//  Why not a SwiftUI fullScreenCover: the camera sits on a sheet on top of the
//  trip's full screen cover. Covers presented while a sheet was animating were
//  sometimes dropped, and re-presenting to recover could start a second camera
//  while the first capture session was still tearing down. The second one then
//  never got the hardware and showed a black screen. Presenting from UIKit lets
//  us wait for running transitions and guarantees one camera at a time.
//
//  One camera for the whole app: every composer gets its own `CameraPicker`
//  handle, but they all go through `CameraPresenter.shared`. It only opens a
//  camera when no other one is opening, open or still shutting down, and it
//  closes a handle's camera when that handle goes away (e.g. the trip screen
//  changed under the Share a Moment sheet). A camera left half torn down kept
//  the hardware busy, which also turned the iPhone Camera app black.
//

import AVFoundation
import SwiftUI
import UIKit

/// A composer's handle on the app's single camera.
@MainActor
final class CameraPicker {
    /// False in the Simulator and on devices without a camera.
    static var isAvailable: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }

    enum Result {
        case presented
        /// Camera access is off in Settings (the picker would only show black).
        case denied
        case unavailable
    }

    private let owner = UUID()

    deinit {
        // The composer that owned this handle is gone; don't leave its
        // camera open on top of whatever replaced it.
        let owner = self.owner
        Task { @MainActor in CameraPresenter.shared.close(owner: owner) }
    }

    /// Opens the camera; `onCapture` gets the photo after "Use Photo".
    /// Does nothing while any camera in the app is already opening or open.
    @discardableResult
    func present(onCapture: @escaping (UIImage) -> Void) async -> Result {
        await CameraPresenter.shared.present(owner: owner, onCapture: onCapture)
    }
}

/// Owns the one UIImagePickerController the app may show at a time.
@MainActor
private final class CameraPresenter: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
    static let shared = CameraPresenter()

    private enum State: Equatable {
        case idle
        /// Waiting for camera access or for a transition to finish.
        case opening(owner: UUID)
        case open(owner: UUID)
        /// Dismissed; the capture session may still be stopping.
        case closing
    }

    /// Time given to the capture session to release the hardware after the
    /// camera leaves the screen, before another camera may start.
    private static let shutdownDelay: Duration = .milliseconds(500)

    private var state: State = .idle
    private var onCapture: ((UIImage) -> Void)?
    private weak var picker: UIImagePickerController?
    /// Bumped on every close, so a late "finished closing" can't reset a newer camera.
    private var closeGeneration = 0

    func present(owner: UUID, onCapture: @escaping (UIImage) -> Void) async -> CameraPicker.Result {
        guard CameraPicker.isAvailable else { return .unavailable }
        // A previous camera may still be shutting down; starting a new one now
        // is what left the screen black.
        guard await waitUntilIdle() else { return .unavailable }
        // Claim the camera before any waiting, so a second tap can't open another.
        state = .opening(owner: owner)

        guard await Self.requestAccess() else {
            if state == .opening(owner: owner) { state = .idle }
            return .denied
        }

        // Wait for the sheet (or anything else) to finish animating; a
        // presentation started mid-transition can be dropped by UIKit.
        for _ in 0..<30 {
            // Cancelled, or the owner closed while we waited.
            guard !Task.isCancelled, state == .opening(owner: owner) else { break }
            if let top = Self.topViewController(), !Self.isTransitioning(top) {
                let picker = UIImagePickerController()
                picker.sourceType = .camera
                picker.cameraCaptureMode = .photo
                picker.mediaTypes = ["public.image"]
                picker.allowsEditing = false
                picker.modalPresentationStyle = .fullScreen
                picker.delegate = self
                self.onCapture = onCapture
                self.picker = picker
                state = .open(owner: owner)
                top.present(picker, animated: true)
                return .presented
            }
            try? await Task.sleep(for: .milliseconds(100))
        }
        if state == .opening(owner: owner) { state = .idle }
        return .unavailable
    }

    /// Closes the camera if `owner` opened it (or is still opening it).
    func close(owner: UUID) {
        if state == .opening(owner: owner) {
            // The present loop sees this and stops.
            state = .idle
        } else if state == .open(owner: owner) {
            if let picker { dismiss(picker, animated: false) } else { beginShutdown() }
        }
    }

    // MARK: UIImagePickerControllerDelegate

    func imagePickerController(_ picker: UIImagePickerController,
                               didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
        let image = info[.originalImage] as? UIImage
        let onCapture = self.onCapture
        // The photo is taken: shut the camera right away instead of keeping
        // the capture session alive through the dismiss animation.
        dismiss(picker, animated: false)
        if let image { onCapture?(image) }
    }

    func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
        dismiss(picker, animated: true)
    }

    // MARK: Closing

    private func dismiss(_ picker: UIImagePickerController, animated: Bool) {
        onCapture = nil
        // Detach first so the picker (and its capture session) can be
        // released as soon as it leaves the screen.
        picker.delegate = nil
        self.picker = nil
        let generation = beginShutdown(waitForDismissal: true)
        guard picker.presentingViewController != nil else {
            finishShutdown(generation)
            return
        }
        picker.dismiss(animated: animated) { [weak self] in
            self?.finishShutdown(generation)
        }
        // If the screens below were torn down at the same moment, UIKit may
        // never call the completion; don't stay closed forever.
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            self?.finishShutdown(generation)
        }
    }

    /// Marks the camera as shutting down. Unless waiting for a dismissal,
    /// it becomes available again after `shutdownDelay`.
    @discardableResult
    private func beginShutdown(waitForDismissal: Bool = false) -> Int {
        closeGeneration += 1
        let generation = closeGeneration
        state = .closing
        if !waitForDismissal { finishShutdown(generation) }
        return generation
    }

    /// The camera is off screen; give its session time to stop, then allow a new one.
    private func finishShutdown(_ generation: Int) {
        Task { [weak self] in
            try? await Task.sleep(for: Self.shutdownDelay)
            guard let self, self.closeGeneration == generation, self.state == .closing else { return }
            self.state = .idle
        }
    }

    /// Waits for a closing camera to finish. False if one is opening or open,
    /// or the wait was cancelled.
    private func waitUntilIdle() async -> Bool {
        for _ in 0..<40 {
            if Task.isCancelled { return false }
            switch state {
            case .idle:
                return true
            case .opening:
                return false
            case .open:
                // Removed by UIKit without a delegate call, e.g. the sheet
                // under it was dismissed because the trip screen changed.
                if isPickerGone { beginShutdown() } else { return false }
            case .closing:
                break
            }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return false
    }

    private var isPickerGone: Bool {
        guard let picker else { return true }
        return picker.presentingViewController == nil && !picker.isBeingPresented
    }

    // MARK: Helpers

    private static func requestAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .video)
        default: return false
        }
    }

    private static func isTransitioning(_ controller: UIViewController) -> Bool {
        controller.transitionCoordinator != nil || controller.isBeingPresented || controller.isBeingDismissed
    }

    /// The controller currently on top, e.g. the Share a Moment sheet.
    private static func topViewController() -> UIViewController? {
        let window = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .filter { $0.activationState == .foregroundActive }
            .flatMap(\.windows)
            .first(where: \.isKeyWindow)
        var top = window?.rootViewController
        while let presented = top?.presentedViewController, !presented.isBeingDismissed {
            top = presented
        }
        return top
    }
}
