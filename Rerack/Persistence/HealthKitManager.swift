import Foundation
import HealthKit

/// PRD §9.6/§9.7/§13.1. Thin async wrapper around HealthKit — reads
/// bodyweight/body-fat for the Measures tile and the bodyweight-in-volume
/// maths, writes finished workouts as `HKWorkout` sessions. Every read
/// quietly returns `nil`/`[]` and every write quietly does nothing when
/// HealthKit isn't available or wasn't authorized — per §10.1's "Connect /
/// Not now, never nags again," a decline has to be a silent fallback
/// everywhere this is called, never a dead end or an alert.
@MainActor
enum HealthKitManager {
    static let store = HKHealthStore()

    private static let bodyMassType = HKQuantityType.quantityType(forIdentifier: .bodyMass)!
    private static let bodyFatType = HKQuantityType.quantityType(forIdentifier: .bodyFatPercentage)!

    static var isAvailable: Bool { HKHealthStore.isHealthDataAvailable() }

    /// PRD §10.1 Screen 3 / §10.2: one prompt, `Connect` or `Not now`. Returns
    /// whether the sheet could even be shown — not whether the user granted
    /// anything, since HealthKit deliberately never reveals per-type grant
    /// state back to the app (read access is always "ask again never").
    @discardableResult
    static func requestAuthorization() async -> Bool {
        guard isAvailable else { return false }
        let readTypes: Set<HKObjectType> = [bodyMassType, bodyFatType]
        let writeTypes: Set<HKSampleType> = [HKObjectType.workoutType()]
        do {
            try await store.requestAuthorization(toShare: writeTypes, read: readTypes)
            return true
        } catch {
            return false
        }
    }

    /// PRD §13.1: the value that folds into `effectiveLoadKg` — the most
    /// recent reading as of `date`, not a same-day match, since most people
    /// don't weigh in every day a bodyweight exercise gets logged.
    static func bodyweightKg(asOf date: Date = Date()) async -> Double? {
        guard let sample = await latestSample(of: bodyMassType, asOf: date) else { return nil }
        return sample.quantity.doubleValue(for: .gramUnit(with: .kilo))
    }

    static func bodyFatPercentage(asOf date: Date = Date()) async -> Double? {
        guard let sample = await latestSample(of: bodyFatType, asOf: date) else { return nil }
        return sample.quantity.doubleValue(for: .percent()) * 100
    }

    /// PRD §9.6 Measures tile — full history for the chart, oldest first.
    static func bodyweightHistory(monthsBack: Int = 12) async -> [(date: Date, kg: Double)] {
        await history(of: bodyMassType, monthsBack: monthsBack)
            .map { ($0.endDate, $0.quantity.doubleValue(for: .gramUnit(with: .kilo))) }
    }

    static func bodyFatHistory(monthsBack: Int = 12) async -> [(date: Date, percent: Double)] {
        await history(of: bodyFatType, monthsBack: monthsBack)
            .map { ($0.endDate, $0.quantity.doubleValue(for: .percent()) * 100) }
    }

    /// PRD §10.2 "Write workout sessions." Fire-and-forget from the caller's
    /// point of view — the workout is already saved locally regardless of
    /// whether this succeeds, so a failure here is never surfaced to the user.
    static func writeWorkout(_ workout: Workout) async {
        guard isAvailable, let endedAt = workout.endedAt else { return }
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .traditionalStrengthTraining
        do {
            let builder = HKWorkoutBuilder(healthStore: store, configuration: configuration, device: .local())
            try await builder.beginCollection(at: workout.startedAt)
            try await builder.endCollection(at: endedAt)
            try await builder.finishWorkout()
        } catch {
            // Silent fallback — see type doc.
        }
    }

    private static func latestSample(of type: HKQuantityType, asOf date: Date) async -> HKQuantitySample? {
        guard isAvailable else { return nil }
        let predicate = HKQuery.predicateForSamples(withStart: nil, end: date, options: .strictEndDate)
        let sortByNewest = [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)]
        return await withCheckedContinuation { (continuation: CheckedContinuation<HKQuantitySample?, Never>) in
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: 1, sortDescriptors: sortByNewest) { _, samples, _ in
                continuation.resume(returning: samples?.first as? HKQuantitySample)
            }
            store.execute(query)
        }
    }

    private static func history(of type: HKQuantityType, monthsBack: Int) async -> [HKQuantitySample] {
        guard isAvailable else { return [] }
        let start = Calendar.current.date(byAdding: .month, value: -monthsBack, to: Date())
        let predicate = HKQuery.predicateForSamples(withStart: start, end: Date(), options: .strictStartDate)
        let sortByOldest = [NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: true)]
        return await withCheckedContinuation { (continuation: CheckedContinuation<[HKQuantitySample], Never>) in
            let query = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit, sortDescriptors: sortByOldest) { _, samples, _ in
                continuation.resume(returning: (samples as? [HKQuantitySample]) ?? [])
            }
            store.execute(query)
        }
    }
}
