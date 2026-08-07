import SwiftUI
import SwiftData

/// PRD §7.8 / §9.3: one exercise within a routine, its target sets, and its
/// superset membership. `allExercisesInRoutine` is passed in (rather than
/// queried) so the superset label ("A1", "A2"...) and the group-with
/// candidate list can be computed against sibling state without a second
/// SwiftData fetch.
///
/// Reordering here is up/down buttons rather than drag handles — a
/// deliberate M2 simplification (drag-to-reorder needs an active EditMode,
/// which crowds a modal sheet's toolbar for little benefit at this stage).
struct RoutineExerciseRow: View {
    @Bindable var routineExercise: RoutineExercise
    let allExercisesInRoutine: [RoutineExercise]
    let canMoveUp: Bool
    let canMoveDown: Bool

    let onRemove: () -> Void
    let onUngroup: () -> Void
    let onGroupWith: (RoutineExercise) -> Void
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let onAddSet: () -> Void
    let onDeleteSet: (RoutineSetTemplate) -> Void

    @State private var showingGroupPicker = false
    @State private var restOverrideText = ""

    private var supersetLabel: String? {
        SupersetGrouping.label(for: routineExercise, among: allExercisesInRoutine)
    }

    private var groupCandidates: [RoutineExercise] {
        allExercisesInRoutine.filter { $0.id != routineExercise.id }
    }

    private var sortedTemplates: [RoutineSetTemplate] {
        (routineExercise.setTemplates ?? []).sorted { $0.orderIndex < $1.orderIndex }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                if let supersetLabel {
                    Text(supersetLabel)
                        .font(.caption.bold())
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.accentColor, in: Capsule())
                }
                Text(routineExercise.exercise?.name ?? "Exercise")
                    .font(.headline)
                Spacer()
                Menu {
                    Button {
                        onMoveUp()
                    } label: {
                        Label("Move Up", systemImage: "arrow.up")
                    }
                    .disabled(!canMoveUp)

                    Button {
                        onMoveDown()
                    } label: {
                        Label("Move Down", systemImage: "arrow.down")
                    }
                    .disabled(!canMoveDown)

                    Button {
                        showingGroupPicker = true
                    } label: {
                        Label("Group With…", systemImage: "link")
                    }

                    if routineExercise.supersetGroup != nil {
                        Button(action: onUngroup) {
                            Label("Ungroup", systemImage: "link.badge.minus")
                        }
                    }

                    Button(role: .destructive, action: onRemove) {
                        Label("Remove Exercise", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                        .imageScale(.large)
                }
            }

            ForEach(sortedTemplates) { template in
                RoutineSetTemplateRow(template: template) {
                    onDeleteSet(template)
                }
            }

            Button(action: onAddSet) {
                Label("Add Set", systemImage: "plus")
                    .font(.subheadline)
            }

            HStack {
                Text("Rest override")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                TextField("Default", text: $restOverrideText)
                    .keyboardType(.numberPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 70)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: restOverrideText) { _, newValue in
                        routineExercise.restSecondsOverride = Int(newValue)
                    }
                Text("sec")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 6)
        .sheet(isPresented: $showingGroupPicker) {
            GroupWithPickerSheet(
                candidates: groupCandidates,
                nameProvider: { $0.exercise?.name ?? "Exercise" },
                onPick: onGroupWith
            )
        }
        .onAppear {
            if let override = routineExercise.restSecondsOverride {
                restOverrideText = String(override)
            }
        }
    }
}
