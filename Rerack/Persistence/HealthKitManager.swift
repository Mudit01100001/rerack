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
        // Body metrics are read *and* written: a reading typed into Measures
        // should reach Health like one typed into any scale app, so the two
        // don't drift into separate half-histories.
        let writeTypes: Set<HKSampleType> = [HKObjectType.workoutType(), bodyMassType, bodyFatType]
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
    ///
    /// Deliberately writes **no energy-burned sample.** With no heart-rate
    /// source, any calorie figure would be a guess, and a guess written here
    /// doesn't stay here: Health hands it to every other app as fact and
    /// there's no way to mark it as estimated. The Exercise ring still credits
    /// the session's duration; the Move ring won't move, which is the honest
    /// outcome for data we don't have.
    @discardableResult
    static func writeWorkout(_ workout: Workout) async -> Bool {
        guard isAvailable, let endedAt = workout.endedAt else { return false }
        let configuration = HKWorkoutConfiguration()
        configuration.activityType = .traditionalStrengthTraining
        do {
            let builder = HKWorkoutBuilder(healthStore: store, configuration: configuration, device: .local())
            try await builder.beginCollection(at: workout.startedAt)
            if let title = workout.routineNameSnapshot ?? Optional(workout.title), !title.isEmpty {
                try? await builder.addMetadata([HKMetadataKeyWorkoutBrandName: title])
            }
            try await builder.endCollection(at: endedAt)
            try await builder.finishWorkout()
            return true
        } catch {
            return false // Silent fallback — see type doc.
        }
    }

    // MARK: - Writing body metrics

    /// Writes a bodyweight reading back to Health. Returns whether it landed,
    /// so the caller can record provenance rather than claiming a sync that
    /// silently failed.
    @discardableResult
    static func writeBodyweight(kg: Double, date: Date = Date()) async -> Bool {
        await write(type: bodyMassType, quantity: HKQuantity(unit: .gramUnit(with: .kilo), doubleValue: kg), date: date)
    }

    @discardableResult
    static func writeBodyFatPercentage(_ percent: Double, date: Date = Date()) async -> Bool {
        // HealthKit stores body fat as a 0…1 fraction; the app works in
        // percent everywhere else, so the conversion belongs here rather than
        // at each call site.
        await write(type: bodyFatType, quantity: HKQuantity(unit: .percent(), doubleValue: percent / 100), date: date)
    }

    private static func write(type: HKQuantityType, quantity: HKQuantity, date: Date) async -> Bool {
        guard isAvailable else { return false }
        let sample = HKQuantitySample(type: type, quantity: quantity, start: date, end: date)
        do {
            try await store.save(sample)
            return true
        } catch {
            return false
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
