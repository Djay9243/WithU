//
//  CameraPicker.swift
//  WithU
//
//  A simple full-screen camera built on AVFoundation: live preview, a glass
//  shutter, and a front/back switch. Returns one photo.
//

import AVFoundation
import SwiftUI
import UIKit

struct CameraPicker: View {
    var onCapture: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var camera = CameraController()

    static var isAvailable: Bool { AVCaptureDevice.default(for: .video) != nil }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            CameraPreview(session: camera.session)
                .ignoresSafeArea()

            if let problem = camera.problem {
                Text(problem)
                    .font(.headline)
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(20)
                    .glassEffect(.regular, in: .rect(cornerRadius: 22))
                    .padding(40)
            }

            if camera.permissionDenied {
                VStack(spacing: 12) {
                    Image(systemName: "camera.fill")
                        .font(.largeTitle)
                    Text("Camera access is off")
                        .font(.headline)
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                    .buttonStyle(.glass)
                }
                .foregroundStyle(.white)
            }

            VStack {
                HStack {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.title3.weight(.semibold))
                            .frame(width: 30, height: 30)
                    }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
                    .accessibilityLabel("Close")
                    Spacer()
                }
                Spacer()
                HStack {
                    Spacer().frame(width: 64)
                    Spacer()
                    Button {
                        camera.capture { image in
                            onCapture(image)
                            dismiss()
                        }
                    } label: {
                        Circle()
                            .fill(.white)
                            .frame(width: 66, height: 66)
                            .padding(8)
                    }
                    .buttonStyle(.plain)
                    .glassEffect(.regular.interactive(), in: .circle)
                    .disabled(!camera.isRunning)
                    .accessibilityLabel("Take Photo")
                    Spacer()
                    Button {
                        camera.switchCamera()
                    } label: {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .font(.title3.weight(.semibold))
                            .frame(width: 40, height: 40)
                    }
                    .buttonStyle(.glass)
                    .buttonBorderShape(.circle)
                    .accessibilityLabel("Switch Camera")
                    .frame(width: 64)
                }
            }
            .tint(.white)
            .padding(20)
        }
        .task { await camera.start() }
        .onDisappear { camera.stop() }
    }
}

// MARK: - Camera controller

@Observable
final class CameraController: NSObject {
    @ObservationIgnored let session = AVCaptureSession()
    private(set) var isRunning = false
    private(set) var permissionDenied = false
    /// Why there's no picture, e.g. the camera is in use elsewhere.
    private(set) var problem: String?

    @ObservationIgnored private let output = AVCapturePhotoOutput()
    @ObservationIgnored private let queue = DispatchQueue(label: "com.jahanzaibali.withu.camera")
    @ObservationIgnored private var position: AVCaptureDevice.Position = .back
    @ObservationIgnored private var completion: ((UIImage) -> Void)?

    func start() async {
        let allowed: Bool
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: allowed = true
        case .notDetermined: allowed = await AVCaptureDevice.requestAccess(for: .video)
        default: allowed = false
        }
        guard allowed else {
            permissionDenied = true
            return
        }
        observeProblems()
        let session = session
        let output = output
        let position = position
        let (running, inputs) = await withCheckedContinuation { (continuation: CheckedContinuation<(Bool, Int), Never>) in
            queue.async {
                Self.configure(session, output: output, position: position)
                session.startRunning()
                continuation.resume(returning: (session.isRunning, session.inputs.count))
            }
        }
        isRunning = running
        if inputs == 0 { problem = "No camera found." }
    }

    /// Shows why the feed stopped, e.g. another app took the camera.
    private func observeProblems() {
        let center = NotificationCenter.default
        center.addObserver(forName: AVCaptureSession.wasInterruptedNotification, object: session, queue: .main) { [weak self] note in
            let raw = (note.userInfo?[AVCaptureSessionInterruptionReasonKey] as? NSNumber)?.intValue ?? -1
            let reason = AVCaptureSession.InterruptionReason(rawValue: raw)
            MainActor.assumeIsolated {
                self?.problem = switch reason {
                case .videoDeviceInUseByAnotherClient: "The camera is being used by another app or device."
                case .videoDeviceNotAvailableWithMultipleForegroundApps: "Close other apps on screen to use the camera."
                case .videoDeviceNotAvailableDueToSystemPressure: "The camera is paused because the phone is too warm."
                case .videoDeviceNotAvailableInBackground: "The camera stopped in the background."
                default: "The camera isn't available right now."
                }
            }
        }
        center.addObserver(forName: AVCaptureSession.interruptionEndedNotification, object: session, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.problem = nil }
        }
        center.addObserver(forName: AVCaptureSession.runtimeErrorNotification, object: session, queue: .main) { [weak self] note in
            let error = note.userInfo?[AVCaptureSessionErrorKey] as? NSError
            MainActor.assumeIsolated { self?.problem = "The camera had a problem. Try again." }
        }
    }

    func stop() {
        let session = session
        queue.async { session.stopRunning() }
        isRunning = false
    }

    func switchCamera() {
        position = position == .back ? .front : .back
        let session = session
        let output = output
        let position = position
        queue.async { Self.configure(session, output: output, position: position) }
    }

    func capture(_ completion: @escaping (UIImage) -> Void) {
        self.completion = completion
        let output = output
        let delegate = self
        queue.async {
            output.capturePhoto(with: AVCapturePhotoSettings(), delegate: delegate)
        }
    }

    /// Sets up (or swaps) the camera input. Runs on the camera queue.
    nonisolated private static func configure(_ session: AVCaptureSession,
                                              output: AVCapturePhotoOutput,
                                              position: AVCaptureDevice.Position) {
        session.beginConfiguration()
        session.sessionPreset = .photo
        session.inputs.forEach { session.removeInput($0) }
        if let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: position),
           let input = try? AVCaptureDeviceInput(device: device),
           session.canAddInput(input) {
            session.addInput(input)
        }
        if !session.outputs.contains(output), session.canAddOutput(output) {
            session.addOutput(output)
        }
        session.commitConfiguration()
    }
}

extension CameraController: AVCapturePhotoCaptureDelegate {
    nonisolated func photoOutput(_ output: AVCapturePhotoOutput,
                                 didFinishProcessingPhoto photo: AVCapturePhoto,
                                 error: Error?) {
        guard error == nil, let data = photo.fileDataRepresentation(), let image = UIImage(data: data) else { return }
        Task { @MainActor in
            completion?(image)
            completion = nil
        }
    }
}

// MARK: - Preview

/// Shows the live camera feed.
private struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.previewLayer.session = session
        view.previewLayer.videoGravity = .resizeAspectFill
        return view
    }

    func updateUIView(_ view: PreviewView, context: Context) {}

    final class PreviewView: UIView {
        override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
        var previewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }
    }
}
