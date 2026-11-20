//
//  ShakeDetector.swift
//  WithU Watch
//
//  Three sharp shakes of the wrist within two seconds start an SOS
//  countdown. Normal walking or running never comes close to the threshold,
//  and the countdown can always be cancelled.
//

import CoreMotion
import Foundation

final class ShakeDetector {
    var onShake: (() -> Void)?

    private let motion = CMMotionManager()
    private var peaks: [Date] = []
    private var cooldownUntil: Date = .distantPast

    /// Acceleration (in g, gravity removed) that counts as a sharp shake.
    private let threshold = 2.3
    private let requiredPeaks = 3
    private let window: TimeInterval = 2
    /// Peaks closer than this belong to the same shake.
    private let minimumGap: TimeInterval = 0.15

    func start() {
        guard motion.isDeviceMotionAvailable, !motion.isDeviceMotionActive else { return }
        motion.deviceMotionUpdateInterval = 1.0 / 50.0
        motion.startDeviceMotionUpdates(to: .main) { [weak self] data, _ in
            guard let self, let data else { return }
            let a = data.userAcceleration
            let magnitude = (a.x * a.x + a.y * a.y + a.z * a.z).squareRoot()
            self.handle(magnitude)
        }
    }

    func stop() {
        motion.stopDeviceMotionUpdates()
        peaks = []
    }

    private func handle(_ magnitude: Double) {
        let now = Date.now
        guard now > cooldownUntil, magnitude >= threshold else { return }
        if let last = peaks.last, now.timeIntervalSince(last) < minimumGap { return }
        peaks.append(now)
        peaks.removeAll { now.timeIntervalSince($0) > window }
        if peaks.count >= requiredPeaks {
            peaks = []
            cooldownUntil = now.addingTimeInterval(10)
            onShake?()
        }
    }
}
