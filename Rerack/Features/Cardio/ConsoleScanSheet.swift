import SwiftUI
import PhotosUI

/// PRD §22.1. Photograph a cardio console, mark where each number is, and
/// pre-fill the manual form from it.
///
/// You draw the boxes **once per machine** and they're remembered, because
/// gym consoles don't move their own readouts between sessions. That's the
/// whole reason this can work at all: the accuracy spike (see
/// `CardioConsoleScanner`) showed whole-image OCR returns unlabelled numbers
/// in arbitrary order, so knowing *which* region is distance is what turns
/// a pile of digits into data.
///
/// Nothing here submits anything. It hands values back to the form, where
/// they can be seen and corrected — the spike produced a `520` read as `025`,
/// and a pipeline that can be confidently wrong must never write unattended.
@MainActor
struct ConsoleScanSheet: View {
    let activity: CardioActivity
    let onApply: ([ConsoleField: Double]) -> Void

    @Environment(\.dismiss) private var dismiss
    /// Templates are keyed by activity: one treadmill layout, one bike
    /// layout. Not per-gym yet — that needs a machine picker, and this earns
    /// that only if the basic flow proves useful.
    @AppStorage("com.mudit.logbook.consoleRegions") private var storedRegions = "{}"

    @State private var photoItem: PhotosPickerItem?
    @State private var image: UIImage?
    @State private var regions: [ConsoleField: CGRect] = [:]
    @State private var activeField: ConsoleField?
    @State private var dragStart: CGPoint?
    @State private var dragCurrent: CGPoint?
    @State private var readings: [CardioConsoleScanner.Reading] = []
    @State private var isScanning = false

    private var fields: [ConsoleField] { ConsoleField.fields(for: activity) }

    var body: some View {
        NavigationStack {
            Group {
                if let image {
                    editor(image: image)
                } else {
                    picker
                }
            }
            .navigationTitle("Scan Console")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                if image != nil {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Use Values") { apply() }
                            .disabled(readings.allSatisfy { $0.value == nil })
                    }
                }
            }
            .task(id: photoItem) {
                guard let photoItem,
                      let data = try? await photoItem.loadTransferable(type: Data.self),
                      let loaded = UIImage(data: data) else { return }
                image = loaded
                regions = loadRegions()
                await rescan()
            }
        }
    }

    // MARK: - Picker

    private var picker: some View {
        VStack(spacing: DS.Space.md) {
            Spacer()
            Image(systemName: "camera.viewfinder")
                .dsFont(DS.TypeScale.display, relativeTo: .largeTitle)
                .foregroundStyle(.tertiary)
            Text("Photograph the console")
                .dsFont(DS.TypeScale.body, relativeTo: .headline, weight: .semibold)
            Text("Then drag a box around each number. The boxes are saved, so next time it reads them straight off.")
                .dsFont(DS.TypeScale.caption, relativeTo: .subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, DS.Space.xl)

            PhotosPicker(selection: $photoItem, matching: .images) {
                // Plain `.font` rather than `dsFont`: PhotosPicker's label
                // builder isn't main-actor isolated, and `dsFont` is backed by
                // `@ScaledMetric`, which is. Dynamic Type still applies here —
                // `.subheadline` is a semantic style.
                Label("Choose Photo", systemImage: "photo")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity, minHeight: 48)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal, DS.Space.lg)
            Spacer()
        }
    }

    // MARK: - Editor

    /// The drawing surface is sized to the image exactly, so gesture
    /// coordinates *are* image coordinates.
    ///
    /// The first version let `scaledToFit` letterbox inside a larger ZStack
    /// and tried to compensate with a computed frame. That silently broke
    /// scanning: draw and store shared the same wrong transform, so every box
    /// rendered exactly where you dragged it while the crop it described
    /// landed off the image and OCR found nothing. Anything that maps
    /// touches to pixels has to be measured, not inferred.
    private func editor(image: UIImage) -> some View {
        VStack(spacing: 0) {
            GeometryReader { geometry in
                let size = fittedSize(for: image.size, in: geometry.size)
                ZStack(alignment: .topLeading) {
                    Image(uiImage: image)
                        .resizable()
                        .frame(width: size.width, height: size.height)

                    ForEach(fields) { field in
                        if let rect = regions[field] {
                            box(for: field, normalised: rect, in: size)
                        }
                    }

                    if let start = dragStart, let current = dragCurrent, activeField != nil {
                        Rectangle()
                            .strokeBorder(Color.accentColor, lineWidth: 2)
                            .background(Color.accentColor.opacity(0.15))
                            .frame(width: abs(current.x - start.x), height: abs(current.y - start.y))
                            .offset(x: min(start.x, current.x), y: min(start.y, current.y))
                    }
                }
                .frame(width: size.width, height: size.height)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 6)
                        .onChanged { value in
                            guard activeField != nil else { return }
                            if dragStart == nil { dragStart = value.startLocation }
                            dragCurrent = value.location
                        }
                        .onEnded { value in
                            defer { dragStart = nil; dragCurrent = nil }
                            guard let field = activeField, let start = dragStart else { return }
                            let rect = CGRect(
                                x: min(start.x, value.location.x), y: min(start.y, value.location.y),
                                width: abs(value.location.x - start.x), height: abs(value.location.y - start.y)
                            )
                            guard rect.width > 12, rect.height > 12 else { return }
                            regions[field] = normalise(rect, in: size)
                            saveRegions()
                            activeField = nil
                            Task { await rescan() }
                        }
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            }
            .frame(maxHeight: .infinity)

            controls
        }
    }

    private func box(for field: ConsoleField, normalised: CGRect, in size: CGSize) -> some View {
        let rect = denormalise(normalised, in: size)
        return Rectangle()
            .strokeBorder(Color.accentColor, lineWidth: 2)
            .background(Color.accentColor.opacity(0.10))
            .frame(width: rect.width, height: rect.height)
            .offset(x: rect.minX, y: rect.minY)
            .overlay(alignment: .topLeading) {
                Text(field.displayName)
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 4).padding(.vertical, 1)
                    .background(Color.accentColor, in: Capsule())
                    .offset(x: rect.minX + 2, y: rect.minY - 8)
            }
    }

    private var controls: some View {
        VStack(spacing: DS.Space.xs) {
            Text(activeField == nil
                 ? "Tap a field, then drag a box around its number."
                 : "Drag a box around \(activeField!.displayName).")
                .dsFont(DS.TypeScale.caption2, relativeTo: .caption2)
                .foregroundStyle(.secondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DS.Space.xs) {
                    ForEach(fields) { field in
                        fieldChip(field)
                    }
                }
                .padding(.horizontal, DS.Space.md)
            }

            if isScanning {
                ProgressView().padding(.vertical, DS.Space.xs)
            }
        }
        .padding(.vertical, DS.Space.sm)
        .background(.bar)
    }

    private func fieldChip(_ field: ConsoleField) -> some View {
        let reading = readings.first { $0.field == field }
        let isActive = activeField == field
        return Button {
            activeField = isActive ? nil : field
        } label: {
            VStack(spacing: 1) {
                Text(field.displayName)
                    .dsFont(DS.TypeScale.caption2, relativeTo: .caption2, weight: .semibold)
                Text(readingLabel(reading))
                    .dsFont(DS.TypeScale.caption, relativeTo: .caption, weight: .medium, design: .rounded)
            }
            .foregroundStyle(isActive ? .white : .primary)
            .padding(.horizontal, DS.Space.sm)
            .padding(.vertical, DS.Space.xs)
            .background(
                isActive ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.quaternary),
                in: .rect(cornerRadius: DS.Radius.small, style: .continuous)
            )
            .overlay(alignment: .topTrailing) {
                // §22.1: a low-confidence number still gets shown, but it is
                // never shown as if it were certain.
                if let reading, reading.value != nil, reading.isLowConfidence {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(.orange)
                        .offset(x: 4, y: -4)
                }
            }
        }
        .buttonStyle(.plain)
    }

    private func readingLabel(_ reading: CardioConsoleScanner.Reading?) -> String {
        guard let reading else { return "—" }
        guard let value = reading.value else { return regions[reading.field] == nil ? "—" : "?" }
        return value.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(value)) : String(format: "%.1f", value)
    }

    // MARK: - Scanning

    private func rescan() async {
        guard let image, !regions.isEmpty else { return }
        isScanning = true
        readings = await CardioConsoleScanner.scan(image: image, regions: regions)
        isScanning = false
    }

    private func apply() {
        var values: [ConsoleField: Double] = [:]
        for reading in readings {
            if let value = reading.value { values[reading.field] = value }
        }
        onApply(values)
        dismiss()
    }

    // MARK: - Coordinate mapping

    /// Largest size preserving aspect ratio that fits the container. The view
    /// is then sized to exactly this, so there's no letterbox to compensate
    /// for and touch coordinates map straight onto the image.
    private func fittedSize(for imageSize: CGSize, in container: CGSize) -> CGSize {
        guard imageSize.width > 0, imageSize.height > 0 else { return .zero }
        let scale = min(container.width / imageSize.width, container.height / imageSize.height)
        return CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
    }

    /// Stored 0...1 against the image, so a template drawn on one photo still
    /// applies to the next one at a different resolution.
    private func normalise(_ rect: CGRect, in size: CGSize) -> CGRect {
        guard size.width > 0, size.height > 0 else { return .zero }
        return CGRect(
            x: rect.minX / size.width, y: rect.minY / size.height,
            width: rect.width / size.width, height: rect.height / size.height
        )
    }

    private func denormalise(_ rect: CGRect, in size: CGSize) -> CGRect {
        CGRect(
            x: rect.minX * size.width, y: rect.minY * size.height,
            width: rect.width * size.width, height: rect.height * size.height
        )
    }

    // MARK: - Template persistence

    private func loadRegions() -> [ConsoleField: CGRect] {
        guard let data = storedRegions.data(using: .utf8),
              let all = try? JSONDecoder().decode([String: [String: [CGFloat]]].self, from: data),
              let mine = all[activity.rawValue] else { return [:] }
        return mine.reduce(into: [:]) { result, entry in
            guard let field = ConsoleField(rawValue: entry.key), entry.value.count == 4 else { return }
            result[field] = CGRect(x: entry.value[0], y: entry.value[1], width: entry.value[2], height: entry.value[3])
        }
    }

    private func saveRegions() {
        var all: [String: [String: [CGFloat]]] = [:]
        if let data = storedRegions.data(using: .utf8),
           let existing = try? JSONDecoder().decode([String: [String: [CGFloat]]].self, from: data) {
            all = existing
        }
        all[activity.rawValue] = regions.reduce(into: [:]) { result, entry in
            result[entry.key.rawValue] = [entry.value.minX, entry.value.minY, entry.value.width, entry.value.height]
        }
        if let data = try? JSONEncoder().encode(all), let string = String(data: data, encoding: .utf8) {
            storedRegions = string
        }
    }
}
