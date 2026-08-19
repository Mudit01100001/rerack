import SwiftUI

/// Haptics can only be judged by feel, on a real device — the simulator has
/// no Taptic Engine, and every number in `Haptics.swift` was tuned against
/// research, not a thumb. This screen exists so whoever is holding the phone
/// can play each event, drag its numbers until it feels right, and copy the
/// result out as text to paste back into `Haptics.baseSpec(for:)`. It is a
/// developer tool, not a user setting — deliberately plain and dense rather
/// than polished, and its edits (`Haptics.override`) live only in memory for
/// this run of the app.
struct HapticsLabView: View {
    /// Shown briefly after "Copy values" so there's *some* confirmation the
    /// tap did something — `UIPasteboard` writes give no system feedback of
    /// their own.
    @State private var showingCopiedConfirmation = false

    var body: some View {
        List {
            Section {
                Text("Haptics can only be judged on a device. Tune here, then Copy values and paste them back.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Section("Events") {
                ForEach(Haptics.Event.allCases, id: \.self) { event in
                    HapticEventRow(event: event)
                }
            }
        }
        .navigationTitle("Haptics Lab")
        .toolbar {
            // Icon-only and packed tight on purpose — this is a tool, not a
            // page, and the three actions are self-explanatory to whoever
            // is reaching for them.
            ToolbarItemGroup(placement: .topBarTrailing) {
                if showingCopiedConfirmation {
                    Text("Copied")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .transition(.opacity)
                }
                Button(action: copyValues) {
                    Image(systemName: "doc.on.doc")
                }
                .accessibilityLabel("Copy values")
                Button {
                    Haptics.resetOverrides()
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                }
                .accessibilityLabel("Reset")
                Button(action: playAll) {
                    Image(systemName: "play.fill")
                }
                .accessibilityLabel("Play all")
            }
        }
    }

    /// Sequential with a gap, not simultaneous — the whole point is to feel
    /// each event as its own thing, and Core Haptics playback overlapping
    /// itself is indistinguishable from a single muddled buzz.
    private func playAll() {
        for (index, event) in Haptics.Event.allCases.enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(index) * 0.7) {
                Haptics.play(event)
            }
        }
    }

    private func copyValues() {
        let text = Haptics.Event.allCases
            .map { "\($0.displayName):\n\(Haptics.currentSpec(for: $0).exportText())" }
            .joined(separator: "\n\n")
        UIPasteboard.general.string = text
        withAnimation {
            showingCopiedConfirmation = true
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            withAnimation { showingCopiedConfirmation = false }
        }
    }
}

// MARK: - Per-event row

/// One event: a name, a Play button, and — for anything that actually
/// routes through Core Haptics — an editor for every transient/continuous
/// event in its `HapticSpec`. Collapsed by default; a session tuning every
/// event would otherwise be scrolling past a wall of sliders to find the
/// next Play button.
private struct HapticEventRow: View {
    let event: Haptics.Event

    @State private var spec: HapticSpec
    @State private var isExpanded = false

    init(event: Haptics.Event) {
        self.event = event
        _spec = State(initialValue: Haptics.currentSpec(for: event))
    }

    /// `scrubTick` / `timerAdjusted` / `selection` / `failure` are kept on
    /// the system generators on purpose (see `Haptics.play(_:)`) and never
    /// consult `Haptics.override`, regardless of what gets added here.
    private var alwaysUsesSystemGenerator: Bool {
        switch event {
        case .scrubTick, .timerAdjusted, .selection, .failure: true
        default: false
        }
    }

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            editor
        } label: {
            HStack {
                Text(event.displayName)
                Spacer()
                Button("Play") { Haptics.play(event) }
                    .buttonStyle(.borderless)
                    .controlSize(.small)
            }
        }
    }

    @ViewBuilder
    private var editor: some View {
        if alwaysUsesSystemGenerator {
            Text("This event always plays through the system generator (UISelectionFeedbackGenerator or UINotificationFeedbackGenerator), not Core Haptics — there's nothing here to tune. \"Add transient\"/\"Add continuous\" below are for experimenting only; Play above won't reflect them.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.vertical, DS.Space.xxs)
        }
        VStack(alignment: .leading, spacing: DS.Space.sm) {
            ForEach($spec.transients) { $transient in
                transientEditor($transient)
            }
            ForEach($spec.continuous) { $continuous in
                continuousEditor($continuous)
            }
            HStack(spacing: DS.Space.md) {
                Button("Add transient") {
                    spec.transients.append(.init(time: 0, intensity: 0.6, sharpness: 0.4))
                    apply()
                }
                Button("Add continuous") {
                    spec.continuous.append(.init(time: 0, duration: 0.2, intensity: 0.6, sharpness: 0.3))
                    apply()
                }
            }
            .font(.caption)
        }
        .padding(.vertical, DS.Space.xs)
    }

    private func transientEditor(_ binding: Binding<HapticSpec.Transient>) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.xxs) {
            HStack {
                Text("Transient").font(.caption.bold())
                Spacer()
                deleteButton { spec.transients.removeAll { $0.id == binding.wrappedValue.id } }
            }
            slider("Intensity", binding.intensity.asDouble, in: 0...1)
            slider("Sharpness", binding.sharpness.asDouble, in: 0...1)
            slider("Time", binding.time, in: 0...1.5)
        }
        .padding(DS.Space.sm)
        .dsCard(radius: DS.Radius.small)
    }

    private func continuousEditor(_ binding: Binding<HapticSpec.Continuous>) -> some View {
        VStack(alignment: .leading, spacing: DS.Space.xxs) {
            HStack {
                Text("Continuous").font(.caption.bold())
                Spacer()
                deleteButton { spec.continuous.removeAll { $0.id == binding.wrappedValue.id } }
            }
            slider("Intensity", binding.intensity.asDouble, in: 0...1)
            slider("Sharpness", binding.sharpness.asDouble, in: 0...1)
            slider("Time", binding.time, in: 0...1.5)
            slider("Duration", binding.duration, in: 0.05...1)
        }
        .padding(DS.Space.sm)
        .dsCard(radius: DS.Radius.small)
    }

    private func deleteButton(_ action: @escaping () -> Void) -> some View {
        Button {
            action()
            apply()
        } label: {
            Image(systemName: "trash")
        }
        .buttonStyle(.borderless)
        .tint(.red)
    }

    private func slider(_ label: String, _ value: Binding<Double>, in range: ClosedRange<Double>) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 62, alignment: .leading)
            Slider(value: Binding(
                get: { value.wrappedValue },
                set: { value.wrappedValue = $0; apply() }
            ), in: range)
            Text(String(format: "%.2f", value.wrappedValue))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 38, alignment: .trailing)
        }
    }

    /// Live-applies the working copy so `Haptics.play(event)` — including
    /// the row's own Play button and "Play all" — reflects every drag as it
    /// happens, not just after a separate save step.
    private func apply() {
        Haptics.override(spec, for: event)
    }
}

private extension Binding where Value == Float {
    /// `Slider` needs `Double`; every spec value is `Float`. A tiny bridging
    /// binding here is cheaper than making `HapticSpec` carry `Double` just
    /// for this one screen.
    var asDouble: Binding<Double> {
        Binding<Double>(
            get: { Double(wrappedValue) },
            set: { wrappedValue = Float($0) }
        )
    }
}

extension Haptics.Event {
    /// Not derived from the case name because `restComplete` etc. read fine
    /// as identifiers but flat as a label on a screen meant to be scanned
    /// quickly.
    var displayName: String {
        switch self {
        case .setCompleted: "Set Completed"
        case .setUncompleted: "Set Uncompleted"
        case .setAdded: "Set Added"
        case .setDeleted: "Set Deleted"
        case .dropAdded: "Drop Added"
        case .swipeThreshold: "Swipe Threshold"
        case .scrubTick: "Scrub Tick"
        case .timerAdjusted: "Timer Adjusted"
        case .timerSkipped: "Timer Skipped"
        case .restComplete: "Rest Complete"
        case .personalRecord: "Personal Record"
        case .celebration: "Celebration"
        case .failure: "Failure"
        case .selection: "Selection"
        }
    }
}

#Preview {
    NavigationStack {
        HapticsLabView()
    }
}
