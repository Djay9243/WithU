//
//  HeartRateMonitor.swift
//  WithU Watch
//
//  Streams heart-rate samples from HealthKit while a trip is active and
//  flags a sudden spike against the person's recent baseline.
//

import Foundation
import HealthKit
import Observation

@Observable
final class HeartRateMonitor {
    private struct Sample {
        var date: Date
        var bpm: Double
    }

    private(set) var latestBPM: Double?
    private(set) var isMonitoring = false
    var onSpike: ((Double) -> Void)?

    private let store = HKHealthStore()
    private var query: HKAnchoredObjectQuery?
    private var recent: [Sample] = []

    /// A reading at least this many times the recent median counts as a spike.
    private let spikeRatio = 1.35
    /// Readings below this never count, whatever the baseline.
    private let spikeFloor = 110.0

    var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    func start() async {
        guard isAvailable, query == nil,
              let type = HKQuantityType.quantityType(forIdentifier: .heartRate) else { return }
        do {
            try await store.requestAuthorization(toShare: [], read: [type])
        } catch {
            return
        }
        let predicate = HKQuery.predicateForSamples(withStart: .now, end: nil)
        let anchored = HKAnchoredObjectQuery(type: type,
                                             predicate: predicate,
                                             anchor: nil,
                                             limit: HKObjectQueryNoLimit) { [weak self] _, samples, _, _, _ in
            self?.receive(samples)
        }
        anchored.updateHandler = { [weak self] _, samples, _, _, _ in
            self?.receive(samples)
        }
        store.execute(anchored)
        query = anchored
        isMonitoring = true
    }

    func stop() {
        if let query { store.stop(query) }
        query = nil
        recent = []
        isMonitoring = false
    }

    nonisolated private func receive(_ samples: [HKSample]?) {
        let unit = HKUnit.count().unitDivided(by: .minute())
        let values: [(Date, Double)] = (samples as? [HKQuantitySample])?
            .map { ($0.endDate, $0.quantity.doubleValue(for: unit)) } ?? []
        guard !values.isEmpty else { return }
        Task { @MainActor in self.ingest(values) }
    }

    private func ingest(_ values: [(Date, Double)]) {
        for (date, bpm) in values.sorted(by: { $0.0 < $1.0 }) {
            let window = recent.filter { date.timeIntervalSince($0.date) < 180 }.map(\.bpm)
            latestBPM = bpm
            if window.count >= 5, let baseline = median(window),
               bpm >= spikeFloor, bpm >= baseline * spikeRatio {
                onSpike?(bpm)
            }
            recent.append(Sample(date: date, bpm: bpm))
            recent.removeAll { date.timeIntervalSince($0.date) > 600 }
        }
    }

    private func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        return sorted.count.isMultiple(of: 2) ? (sorted[middle - 1] + sorted[middle]) / 2 : sorted[middle]
    }
}
