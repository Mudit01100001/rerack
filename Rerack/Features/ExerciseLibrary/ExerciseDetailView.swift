import SwiftUI
import SwiftData
import Charts

/// PRD §9.2. Three tabs: Summary, History, How To.
///
/// The header starts at the exercise name — **no image, no video, no
/// placeholder frame, and no space reserved for one** (§6.2). That's a
/// product decision for M1–M10, revisited at M11 (§23.3), not an oversight.
struct ExerciseDetailView: View {
    let exercise: Exercise

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var tab: Tab = .summary
    @State private var metric: GraphMetric = .heaviestWeight
    @State private var range: GraphRange = .threeMonths

    /// Progress-flavoured views exclude untracked sessions (§9.3); History
    /// shows everything you actually did.
    @State private var trackedSessions: [ExerciseSession] = []
    @State private var allSessions: [ExerciseSession] = []
    @State private var records: [PRType: PersonalRecord] = [:]
    @State private var historyLimit = 20

    enum Tab: String, CaseIterable, Identifiable {
        case summary = "Summary"
        case history = "History"
        case howTo = "How To"
        var id: String { rawValue }
    }

    enum GraphMetric: String, CaseIterable, Identifiable {
        case heaviestWeight = "Heaviest Weight"
        case oneRepMax = "One-Rep Max"
        case bestSetVolume = "Best Set Volume"
        case sessionVolume = "Session Volume"
        case totalReps = "Total Reps"
        var id: String { rawValue }

        var explainer: ExplainerTerm? {
            switch self {
            case .oneRepMax: .estimatedOneRepMax
            case .bestSetVolume, .sessionVolume: .setVsSessionVolume
            case .heaviestWeight, .totalReps: nil
            }
        }

        var isWeight: Bool { self != .totalReps }
    }

    enum GraphRange: String, CaseIterable, Identifiable {
        case oneMonth = "1M", threeMonths = "3M", sixMonths = "6M", oneYear = "1Y", all = "All"
        var id: String { rawValue }

        var cutoff: Date? {
            let now = Date()
            return switch self {
            case .oneMonth: Calendar.current.date(byAdding: .month, value: -1, to: now)
            case .threeMonths: Calendar.current.date(byAdding: .month, value: -3, to: now)
            case .sixMonths: Calendar.current.date(byAdding: .month, value: -6, to: now)
            case .oneYear: Calendar.current.date(byAdding: .year, value: -1, to: now)
            case .all: nil
            }
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header
                Picker("Section", selection: $tab) {
                    ForEach(Tab.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.bottom, 8)

                switch tab {
                case .summary: summaryTab
                case .history: historyTab
                case .howTo: howToTab
                }
            }
            .navigationTitle(exercise.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .task { load() }
        }
    }

    private func load() {
        trackedSessions = ExerciseHistory.sessions(for: exercise, context: modelContext)
        allSessions = ExerciseHistory.sessions(for: exercise, includeUntracked: true, context: modelContext)
        records = ExerciseHistory.personalRecords(for: exercise, context: modelContext)
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(exercise.equipment.displayName)
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color(.secondarySystemBackground), in: Capsule())
                Text(exercise.primaryMuscle.displayName)
                    .font(.subheadline.weight(.semibold))
            }
            if !exercise.secondaryMuscles.isEmpty {
                Text(exercise.secondaryMuscles.map(\.displayName).joined(separator: ", "))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal)
        .padding(.bottom, 10)
    }

    // MARK: - Summary

    private var graphSessions: [ExerciseSession] {
        guard let cutoff = range.cutoff else { return trackedSessions.reversed() }
        return trackedSessions.filter { $0.date >= cutoff }.reversed()
    }

    private func value(_ session: ExerciseSession) -> Double? {
        switch metric {
        case .heaviestWeight: session.heaviestWeightKg
        case .oneRepMax: session.bestOneRepMaxKg
        case .bestSetVolume: session.bestSetVolumeKg
        case .sessionVolume: session.sessionVolumeKg
        case .totalReps: Double(session.totalReps)
        }
    }

    private var summaryTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                graphSection
                recordsSection
                lifetimeSection
            }
            .padding(.horizontal)
            .padding(.bottom, 32)
        }
    }

    private var graphSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                Text("Progress").font(.headline)
                if let explainer = metric.explainer {
                    ExplainerButton(term: explainer)
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(GraphMetric.allCases) { option in
                        FilterChip(title: option.rawValue, isSelected: metric == option) {
                            metric = option
                        }
                    }
                }
                .padding(.horizontal, 1)
            }

            // PRD §9.2: "Log this exercise twice to see your progress."
            if trackedSessions.count < 2 {
                Text("Log this exercise twice to see your progress.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 160)
            } else {
                let points = graphSessions.compactMap { session -> (Date, Double)? in
                    guard let value = value(session) else { return nil }
                    return (session.date, value)
                }
                if points.isEmpty {
                    Text("Nothing in this range.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 160)
                } else {
                    Chart {
                        ForEach(Array(points.enumerated()), id: \.offset) { _, point in
                            LineMark(x: .value("Date", point.0), y: .value(metric.rawValue, point.1))
                                .interpolationMethod(.monotone)
                            PointMark(x: .value("Date", point.0), y: .value(metric.rawValue, point.1))
                        }
                    }
                    .chartYAxisLabel(metric.isWeight ? "kg" : "reps")
                    .frame(height: 180)
                }

                HStack(spacing: 8) {
                    ForEach(GraphRange.allCases) { option in
                        FilterChip(title: option.rawValue, isSelected: range == option) {
                            range = option
                        }
                    }
                }
            }
        }
    }

    private var recordsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 4) {
                Text("Personal Records").font(.headline)
                ExplainerButton(term: .personalRecordTypes)
            }
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
                recordCard("Heaviest Weight", .heaviestWeight, unit: "kg")
                recordCard("Best 1RM", .best1RM, unit: "kg")
                recordCard("Best Set Volume", .bestSetVolume, unit: "kg")
                recordCard("Best Session Volume", .bestSessionVolume, unit: "kg")
            }
        }
    }

    private func recordCard(_ title: String, _ type: PRType, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.secondary)
            if let record = records[type] {
                Text("\(formatted(record.valueKg)) \(unit)")
                    .font(.title3.weight(.semibold))
                Text(record.achievedAt.formatted(date: .abbreviated, time: .omitted))
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            } else {
                Text("—")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.tertiary)
                Text("Not set yet")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
    }

    private var lifetimeSection: some View {
        let stats = ExerciseHistory.lifetimeStats(from: trackedSessions)
        return VStack(alignment: .leading, spacing: 8) {
            Text("Lifetime").font(.headline)
            VStack(spacing: 6) {
                statRow("Sessions", "\(stats.sessionCount)")
                statRow("Sets", "\(stats.setCount)")
                statRow("Reps", "\(stats.repCount)")
                statRow("Volume", "\(formatted(stats.volumeKg)) kg")
                if let first = stats.firstPerformed {
                    statRow("First performed", first.formatted(date: .abbreviated, time: .omitted))
                }
                if let last = stats.lastPerformed {
                    statRow("Last performed", last.formatted(date: .abbreviated, time: .omitted))
                }
            }
        }
    }

    private func statRow(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(.subheadline).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.subheadline.weight(.medium))
        }
    }

    // MARK: - History

    private var historyTab: some View {
        Group {
            if allSessions.isEmpty {
                ContentUnavailableView(
                    "No history yet",
                    systemImage: "clock",
                    description: Text("Log this exercise in a workout and it'll show up here.")
                )
            } else {
                List {
                    ForEach(allSessions.prefix(historyLimit)) { session in
                        Section {
                            ForEach(session.sets) { set in
                                setRow(set, isDrop: false)
                                ForEach(session.dropsByParentID[set.id] ?? []) { drop in
                                    setRow(drop, isDrop: true)
                                }
                            }
                            HStack {
                                Text("\(session.sets.count) sets · \(session.totalReps) reps")
                                Spacer()
                                Text("\(formatted(session.sessionVolumeKg)) kg")
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        } header: {
                            HStack {
                                if let group = session.supersetGroup {
                                    Text("Superset \(group)")
                                        .font(.caption2.bold())
                                        .foregroundStyle(Color.accentColor)
                                }
                                Text(session.workoutTitle)
                                Spacer()
                                Text(session.date.formatted(date: .abbreviated, time: .omitted))
                            }
                        }
                    }
                    if allSessions.count > historyLimit {
                        Button("Show more") { historyLimit += 20 }
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
    }

    private func setRow(_ set: SetLog, isDrop: Bool) -> some View {
        HStack(spacing: 8) {
            if isDrop {
                Image(systemName: "arrow.turn.down.right")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 12)
            } else {
                Text("\(set.orderIndex + 1)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(width: 16)
            }
            if set.setType == .warmup {
                Text("W").font(.caption2.bold()).foregroundStyle(.secondary)
            }
            Text("\(formatted(set.effectiveLoadKg)) kg × \(set.reps)")
                .font(.subheadline)
            Spacer()
            if !set.prFlags.isEmpty {
                Text("🏆").font(.caption)
            }
        }
    }

    // MARK: - How To (PRD §9.2 Tab 3 — the stub, and nothing else)

    private var howToTab: some View {
        VStack(spacing: 6) {
            Spacer()
            Text("Coming Soon").font(.headline)
            Text("Form cues are on the way.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func formatted(_ value: Double) -> String {
        value.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(value)) : String(format: "%.1f", value)
    }
}
