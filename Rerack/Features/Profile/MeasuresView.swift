import SwiftUI
import SwiftData
import Charts

/// PRD §9.6 Measures tile / §9.7. Bodyweight and body-fat charts from Apple
/// Health, with manual entry as the fallback — not as a second-class path:
/// someone who declines Health (§10.1) gets the same charts from the same
/// `BodyMetric` rows, just typed in rather than synced.
struct MeasuresView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \BodyMetric.date, order: .forward) private var metrics: [BodyMetric]

    @State private var metricType: MetricType = .bodyweight
    @State private var showingEntrySheet = false
    @State private var isSyncing = false
    @State private var syncMessage: String?

    private var shown: [BodyMetric] {
        metrics.filter { $0.type == metricType }
    }

    private var unit: String { metricType == .bodyweight ? "kg" : "%" }

    private var latest: BodyMetric? { shown.last }

    /// Swift Charts can't infer a sane scale from one point (or from several
    /// nearly-identical ones) — the domain collapses and the axis renders
    /// upside down. Padding by at least ±1 unit keeps the very first reading
    /// someone logs looking like a chart rather than a rendering bug.
    private var chartDomain: ClosedRange<Double> {
        let values = shown.map(\.value)
        guard let min = values.min(), let max = values.max() else { return 0...1 }
        let padding = Swift.max((max - min) * 0.15, 1)
        return (min - padding)...(max + padding)
    }

    var body: some View {
        List {
            Section {
                Picker("Metric", selection: $metricType) {
                    Text("Bodyweight").tag(MetricType.bodyweight)
                    Text("Body Fat").tag(MetricType.bodyFatPercentage)
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
            }

            Section {
                if shown.isEmpty {
                    emptyState
                } else {
                    chart
                    if let latest {
                        HStack {
                            Text("Latest")
                            Spacer()
                            Text("\(formatted(latest.value)) \(unit)")
                                .foregroundStyle(.secondary)
                            Text(latest.date, format: .dateTime.day().month().year())
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                        .font(.subheadline)
                    }
                }
            }

            Section {
                Button {
                    showingEntrySheet = true
                } label: {
                    Label("Add Reading", systemImage: "plus")
                }
                Button {
                    Task { await syncFromHealth() }
                } label: {
                    HStack {
                        Label("Sync from Apple Health", systemImage: "heart")
                        if isSyncing {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .disabled(isSyncing || !HealthKitManager.isAvailable)
            } footer: {
                if let syncMessage {
                    Text(syncMessage)
                } else if !HealthKitManager.isAvailable {
                    Text("Apple Health isn't available on this device. Readings can still be added manually.")
                }
            }

            if !shown.isEmpty {
                Section("History") {
                    // Newest first — the chart already reads left-to-right in
                    // chronological order, so repeating that here would bury
                    // today's reading at the bottom of a long scroll.
                    ForEach(shown.reversed()) { metric in
                        HStack {
                            Text("\(formatted(metric.value)) \(unit)")
                            Spacer()
                            Text(metric.date, format: .dateTime.day().month().year())
                                .foregroundStyle(.secondary)
                            if metric.source == .healthKit {
                                Image(systemName: "heart.fill")
                                    .font(.caption2)
                                    .foregroundStyle(.pink)
                                    .accessibilityLabel("From Apple Health")
                            }
                        }
                        .font(.subheadline)
                    }
                    .onDelete(perform: delete)
                }
            }
        }
        .navigationTitle("Measures")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingEntrySheet) {
            AddMeasurementSheet(type: metricType) { value, date in
                let metric = BodyMetric(type: metricType, value: value, date: date, source: .manual)
                modelContext.insert(metric)
                try? modelContext.save()
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "scalemass")
                .font(.largeTitle)
                .foregroundStyle(.tertiary)
            Text("No readings yet")
                .font(.headline)
            Text("Sync from Apple Health, or add one by hand.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
    }

    private var chart: some View {
        Chart(shown) { metric in
            LineMark(
                x: .value("Date", metric.date),
                y: .value(metricType == .bodyweight ? "kg" : "%", metric.value)
            )
            .interpolationMethod(.monotone)
            PointMark(
                x: .value("Date", metric.date),
                y: .value(metricType == .bodyweight ? "kg" : "%", metric.value)
            )
        }
        // Never zero-based: a bodyweight range of 72–76 kg against a 0 axis is
        // a flat line, which hides exactly the change this chart exists to show.
        .chartYScale(domain: chartDomain)
        .frame(height: 200)
        .padding(.vertical, 4)
    }

    /// Additive and idempotent: an existing reading for the same
    /// type+timestamp is skipped rather than duplicated, so syncing twice in a
    /// row doesn't double every point on the chart.
    private func syncFromHealth() async {
        isSyncing = true
        syncMessage = nil
        defer { isSyncing = false }

        guard await HealthKitManager.requestAuthorization() else {
            syncMessage = "Apple Health access wasn't granted. Readings can still be added manually."
            return
        }

        var imported = 0
        let existing = Set(metrics.map { "\($0.typeRaw)@\($0.date.timeIntervalSince1970)" })

        for entry in await HealthKitManager.bodyweightHistory() {
            let key = "\(MetricType.bodyweight.rawValue)@\(entry.date.timeIntervalSince1970)"
            guard !existing.contains(key) else { continue }
            modelContext.insert(BodyMetric(type: .bodyweight, value: entry.kg, date: entry.date, source: .healthKit))
            imported += 1
        }
        for entry in await HealthKitManager.bodyFatHistory() {
            let key = "\(MetricType.bodyFatPercentage.rawValue)@\(entry.date.timeIntervalSince1970)"
            guard !existing.contains(key) else { continue }
            modelContext.insert(BodyMetric(type: .bodyFatPercentage, value: entry.percent, date: entry.date, source: .healthKit))
            imported += 1
        }

        try? modelContext.save()
        syncMessage = imported == 0
            ? "Nothing new to import."
            : "Imported \(imported) reading\(imported == 1 ? "" : "s")."
    }

    private func delete(at offsets: IndexSet) {
        let reversed = Array(shown.reversed())
        for index in offsets {
            modelContext.delete(reversed[index])
        }
        try? modelContext.save()
    }

    private func formatted(_ value: Double) -> String {
        value.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(value)) : String(format: "%.1f", value)
    }
}

/// Manual entry (§9.6 "manual entry fallback"). Deliberately allows a past
/// date — people weigh in and log it later, and forcing "now" would put the
/// point in the wrong place on the chart forever.
private struct AddMeasurementSheet: View {
    let type: MetricType
    let onSave: (Double, Date) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var valueText = ""
    @State private var date = Date()

    private var parsedValue: Double? {
        guard let value = Double(valueText), value > 0 else { return nil }
        // A body-fat percentage above 100 is a typo, not a reading.
        if type == .bodyFatPercentage && value > 100 { return nil }
        return value
    }

    var body: some View {
        NavigationStack {
            Form {
                HStack {
                    TextField(type == .bodyweight ? "Weight" : "Body fat", text: $valueText)
                        .keyboardType(.decimalPad)
                    Text(type == .bodyweight ? "kg" : "%")
                        .foregroundStyle(.secondary)
                }
                DatePicker("Date", selection: $date, in: ...Date(), displayedComponents: .date)
            }
            .navigationTitle(type == .bodyweight ? "Add Bodyweight" : "Add Body Fat")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        guard let parsedValue else { return }
                        onSave(parsedValue, date)
                        dismiss()
                    }
                    .disabled(parsedValue == nil)
                }
            }
        }
    }
}
