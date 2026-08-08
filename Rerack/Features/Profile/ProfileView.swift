import SwiftUI
import SwiftData
import Charts

/// PRD §9.6. Header totals, the activity graph, dashboard tiles, and
/// settings. Measures stays a stub until HealthKit lands in M9.
struct ProfileView: View {
    @AppStorage(AppearanceStorageKey.value) private var appearanceModeRaw = AppearanceMode.system.rawValue
    @Environment(\.modelContext) private var modelContext
    @Query private var profiles: [UserProfile]

    @Query(
        filter: #Predicate<Workout> { $0.endedAt != nil },
        sort: \Workout.startedAt,
        order: .reverse
    )
    private var workouts: [Workout]

    @State private var activityMetric: ActivityMetric = .duration
    @State private var activityRange: ActivityRange = .oneMonth

    enum ActivityMetric: String, CaseIterable, Identifiable {
        case duration = "Duration", volume = "Volume", reps = "Reps"
        var id: String { rawValue }
    }

    enum ActivityRange: String, CaseIterable, Identifiable {
        case oneMonth = "1M", threeMonths = "3M", sixMonths = "6M", oneYear = "1Y"
        var id: String { rawValue }

        var months: Int {
            switch self {
            case .oneMonth: 1
            case .threeMonths: 3
            case .sixMonths: 6
            case .oneYear: 12
            }
        }

        /// §9.6: past 3 months a bar per day stops being legible.
        var aggregatesWeekly: Bool { months > 3 }
    }

    /// PRD §10.1: onboarding (which would normally create this row) hasn't
    /// shipped yet, so Settings is the first place a `UserProfile` might get
    /// created — done lazily here rather than at app launch, matching "one
    /// row is expected to exist" without forcing a migration step.
    @State private var ensuredProfile: UserProfile?
    @State private var showingRestPicker = false

    private var appearanceMode: Binding<AppearanceMode> {
        Binding(
            get: { AppearanceMode(rawValue: appearanceModeRaw) ?? .system },
            set: { appearanceModeRaw = $0.rawValue }
        )
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    headerSection
                }

                if !workouts.isEmpty {
                    Section("Activity") {
                        activityGraph
                    }
                }

                Section("Preferences") {
                    Picker("Appearance", selection: appearanceMode) {
                        ForEach(AppearanceMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                }

                if let profile = ensuredProfile {
                    workoutSection(profile)
                }

                Section("Dashboard") {
                    NavigationLink {
                        StatisticsView()
                    } label: {
                        Label("Statistics", systemImage: "chart.bar")
                    }
                    NavigationLink {
                        ExerciseUsageView()
                    } label: {
                        Label("Exercises", systemImage: "list.bullet")
                    }
                    NavigationLink {
                        WorkoutCalendarView()
                    } label: {
                        Label("Calendar", systemImage: "calendar")
                    }
                    // Measures needs HealthKit bodyweight / body fat — M9.
                    dashboardRow("Measures", systemImage: "scalemass")
                }
            }
            .navigationTitle("Profile")
        }
        .task { ensureProfile() }
    }

    // MARK: - Header & activity graph (PRD §9.6)

    private var headerSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(profiles.first?.displayName.isEmpty == false ? profiles.first!.displayName : AppIdentity.displayName)
                .font(.title2.bold())
            HStack(spacing: 14) {
                totalItem("\(workouts.count)", "workouts")
                totalItem("\(Int(workouts.reduce(0) { $0 + ProfileStats.volume(of: $1) }))", "kg")
                totalItem(String(format: "%.1f", workouts.reduce(0) { $0 + ProfileStats.duration(of: $1) } / 3600), "hours")
            }
        }
        .padding(.vertical, 4)
    }

    private func totalItem(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(value).font(.headline)
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
    }

    private var activityBuckets: [ProfileStats.DayBucket] {
        let cutoff = Calendar.current.date(byAdding: .month, value: -activityRange.months, to: Date()) ?? .distantPast
        let inRange = workouts.filter { $0.startedAt >= cutoff }
        let daily = ProfileStats.dayBuckets(inRange)
        return activityRange.aggregatesWeekly ? ProfileStats.aggregateWeekly(daily) : daily
    }

    /// Always span the full selected range, so one workout renders as one
    /// narrow bar in a month rather than a block filling the plot area.
    private var activityDomain: ClosedRange<Date> {
        let now = Date()
        let start = Calendar.current.date(byAdding: .month, value: -activityRange.months, to: now) ?? now
        return start...now
    }

    private func value(_ bucket: ProfileStats.DayBucket) -> Double {
        switch activityMetric {
        case .duration: bucket.durationHours
        case .volume: bucket.volumeKg
        case .reps: Double(bucket.reps)
        }
    }

    private var activityGraph: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Metric", selection: $activityMetric) {
                ForEach(ActivityMetric.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)

            let buckets = activityBuckets
            if buckets.isEmpty {
                Text("Nothing in this range.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 120)
            } else {
                Chart(buckets) { bucket in
                    BarMark(
                        x: .value("Date", bucket.date, unit: activityRange.aggregatesWeekly ? .weekOfYear : .day),
                        y: .value(activityMetric.rawValue, value(bucket))
                    )
                    // Without a fixed width, a single data point stretches
                    // its bar across the whole plot area and the x-axis
                    // collapses to hours — which reads as broken on the
                    // first workout you ever log.
                    .foregroundStyle(Color.accentColor)
                }
                .chartXScale(domain: activityDomain)
                .frame(height: 140)
            }

            HStack(spacing: 8) {
                ForEach(ActivityRange.allCases) { option in
                    FilterChip(title: option.rawValue, isSelected: activityRange == option) {
                        activityRange = option
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    /// PRD §10.2 Workout section.
    private func workoutSection(_ profile: UserProfile) -> some View {
        Section("Workout") {
            Button {
                showingRestPicker = true
            } label: {
                HStack {
                    Text("Default rest time")
                        .foregroundStyle(.primary)
                    Spacer()
                    Text(RestNotificationScheduler.formattedClock(profile.defaultRestSeconds))
                        .foregroundStyle(.secondary)
                }
            }
            .sheet(isPresented: $showingRestPicker) {
                RestDurationPickerSheet(
                    title: "Default Rest Time",
                    initialSeconds: profile.defaultRestSeconds,
                    onSave: { seconds, _ in profile.defaultRestSeconds = seconds }
                )
            }

            Toggle("Rest timer sound", isOn: Binding(
                get: { profile.restTimerSoundEnabled },
                set: { profile.restTimerSoundEnabled = $0 }
            ))
            Toggle("Auto-start rest timer", isOn: Binding(
                get: { profile.autoStartRestTimer },
                set: { profile.autoStartRestTimer = $0 }
            ))
            Toggle("Keep screen awake during workout", isOn: Binding(
                get: { profile.keepScreenAwakeDuringWorkout },
                set: { profile.keepScreenAwakeDuringWorkout = $0 }
            ))
        }
    }

    private func ensureProfile() {
        if let existing = profiles.first {
            ensuredProfile = existing
        } else {
            let created = UserProfile()
            modelContext.insert(created)
            try? modelContext.save()
            ensuredProfile = created
        }
    }

    private func dashboardRow(_ title: String, systemImage: String) -> some View {
        HStack {
            Label(title, systemImage: systemImage)
            Spacer()
            Text("Soon")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .foregroundStyle(.secondary)
    }
}

#Preview {
    ProfileView()
        .modelContainer(for: [UserProfile.self], inMemory: true)
}
