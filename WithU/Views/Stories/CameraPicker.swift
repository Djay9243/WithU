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
    var onCapture: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

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

    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        private let parent: CameraPicker

        init(_ parent: CameraPicker) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.onCapture(image)
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
