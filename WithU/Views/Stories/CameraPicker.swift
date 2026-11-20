//
//  CameraPicker.swift
//  WithU
//
//  The system camera (UIImagePickerController), wrapped for SwiftUI.
//
//  Why not a custom AVFoundation camera: the earlier custom one saved photos
//  sideways (the photo output's rotation was never set), had no focus, zoom
//  or flash, and needed its own permission and interruption handling. The
//  system camera handles all of that, matches what people know from the
//  Camera app, and returns an upright photo.
//

import SwiftUI
import UIKit

struct CameraPicker: UIViewControllerRepresentable {
    /// Called with the photo after "Use Photo". The presenter closes the camera.
    var onCapture: (UIImage) -> Void
    /// Called when the person cancels. The presenter closes the camera.
    var onCancel: () -> Void

    /// False in the Simulator and on devices without a camera.
    static var isAvailable: Bool { UIImagePickerController.isSourceTypeAvailable(.camera) }

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = Self.isAvailable ? .camera : .photoLibrary
        if Self.isAvailable {
            picker.cameraCaptureMode = .photo
        }
        picker.mediaTypes = ["public.image"]
        picker.allowsEditing = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {
        // Keep the callbacks current if the presenter was redrawn.
        context.coordinator.onCapture = onCapture
        context.coordinator.onCancel = onCancel
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onCapture: onCapture, onCancel: onCancel)
    }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        var onCapture: (UIImage) -> Void
        var onCancel: () -> Void

        init(onCapture: @escaping (UIImage) -> Void, onCancel: @escaping () -> Void) {
            self.onCapture = onCapture
            self.onCancel = onCancel
        }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            // The presenter closes the camera in both callbacks; nothing is read
            // from the environment here, so it works outside a view update.
            if let image = info[.originalImage] as? UIImage {
                onCapture(image)
            } else {
                onCancel()
            }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onCancel()
        }
    }
}
