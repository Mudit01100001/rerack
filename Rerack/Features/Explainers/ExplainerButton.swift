import SwiftUI

/// PRD §10.3. A small `?` placed inline after a term. It never shifts
/// layout and never competes with the number it's explaining — the point is
/// that it's available, not that it's noticed.
struct ExplainerButton: View {
    let term: ExplainerTerm
    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented = true
        } label: {
            Image(systemName: "questionmark.circle")
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("What is \(term.title)?")
        .sheet(isPresented: $isPresented) {
            ExplainerSheet(term: term)
        }
    }
}

/// Medium detent on purpose (§10.3): you can read it and dismiss without
/// losing your place — a full screen would feel like navigating away
/// mid-workout, and an alert can't hold this much text.
struct ExplainerSheet: View {
    let term: ExplainerTerm
    @Environment(\.dismiss) private var dismiss

    /// Split on blank lines so each paragraph gets its own `Text`, which is
    /// what makes SwiftUI's inline markdown (bold, `code`) render per block
    /// instead of being flattened into one run.
    private var paragraphs: [String] {
        term.body
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    Text(term.summary)
                        .font(.headline)
                        .fixedSize(horizontal: false, vertical: true)

                    ForEach(Array(paragraphs.enumerated()), id: \.offset) { _, paragraph in
                        Text(LocalizedStringKey(paragraph))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            }
            .navigationTitle(term.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

#Preview {
    VStack(spacing: 20) {
        HStack(spacing: 4) {
            Text("Estimated 1RM").font(.headline)
            ExplainerButton(term: .estimatedOneRepMax)
        }
        HStack(spacing: 4) {
            Text("Streak").font(.headline)
            ExplainerButton(term: .streak)
        }
    }
}
