import Foundation
import Vision
import CoreImage
import UIKit

/// PRD §22.1. Reads numbers off a photo of a cardio machine console.
///
/// ## What the accuracy spike found
///
/// §22.1 asked for a spike before any UI, on the grounds that generic OCR is
/// known to struggle with seven-segment displays. It was right to ask, and
/// the results shaped everything here. Measured against rendered
/// seven-segment panels (red and amber, sharp and blurred):
///
/// - **Whole-image OCR: unusable.** It silently dropped a field on a *clean*
///   image, produced garbage on a blurred one, and returns unlabelled numbers
///   in arbitrary order, so you can't tell distance from calories anyway.
/// - **Naive crop-and-upscale: worse.** 0/4 on the clean panel. A cropped
///   glowing number on black looks nothing like the document text Vision is
///   trained on.
/// - **Invert + greyscale + upscale + wide white margin: 9/12.** Same crops,
///   same engine. The preprocessing is doing nearly all the work.
///
/// 75% on synthetic, perfectly-square, glare-free images is the *ceiling*,
/// not the expectation. A real photo taken at an angle in a gym will be
/// worse.
///
/// ## Why that shapes the API
///
/// One failure was `520` read as `025` — digits reversed. Not a blank, a
/// plausible wrong number. A pipeline whose errors look like valid data can
/// never auto-submit, so this type returns *candidates with confidence* and
/// nothing else. Committing them is the user's, via a pre-filled form they
/// can see and correct (§22.1 step 2).
enum CardioConsoleScanner {

    struct Reading {
        let field: ConsoleField
        /// Digits only. Nil when nothing legible came back, which is a better
        /// outcome than a guess.
        let value: Double?
        /// Vision's own confidence, 0...1. Surfaced so the form can mark a
        /// shaky reading rather than presenting every number as equally sure.
        let confidence: Float
        var isLowConfidence: Bool { confidence < 0.5 }
    }

    /// Runs one region per field. Regions are normalised (0...1) so a saved
    /// template survives a photo taken at a different resolution.
    static func scan(
        image: UIImage,
        regions: [ConsoleField: CGRect]
    ) async -> [Reading] {
        guard let cgImage = image.cgImage else { return [] }
        var readings: [Reading] = []
        for (field, normalised) in regions {
            let reading = await recognise(cgImage: cgImage, normalisedRect: normalised, field: field)
            readings.append(reading)
        }
        return readings.sorted { $0.field.rawValue < $1.field.rawValue }
    }

    private static func recognise(
        cgImage: CGImage,
        normalisedRect: CGRect,
        field: ConsoleField
    ) async -> Reading {
        guard let prepared = preprocess(cgImage: cgImage, normalisedRect: normalisedRect) else {
            return Reading(field: field, value: nil, confidence: 0)
        }

        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        // A console shows digits, not words. Language correction actively
        // hurts: it tries to turn "512" into something lexical.
        request.usesLanguageCorrection = false
        request.recognitionLanguages = ["en-US"]

        let handler = VNImageRequestHandler(cgImage: prepared, options: [:])
        try? handler.perform([request])

        let observations = request.results ?? []
        let candidates = observations.compactMap { $0.topCandidates(1).first }
        let text = candidates.map(\.string).joined()
        let confidence = candidates.map(\.confidence).min() ?? 0

        let digits = text.filter { $0.isNumber || $0 == "." }
        guard !digits.isEmpty, let value = Double(digits) else {
            return Reading(field: field, value: nil, confidence: 0)
        }
        return Reading(field: field, value: value, confidence: confidence)
    }

    /// The preprocessing the spike found necessary. Each step earned its place
    /// by moving the score; none of it is cargo-culted.
    private static func preprocess(cgImage: CGImage, normalisedRect: CGRect) -> CGImage? {
        let full = CGRect(x: 0, y: 0, width: cgImage.width, height: cgImage.height)
        let crop = CGRect(
            x: normalisedRect.minX * full.width,
            y: normalisedRect.minY * full.height,
            width: normalisedRect.width * full.width,
            height: normalisedRect.height * full.height
        ).integral.intersection(full)
        guard !crop.isNull, crop.width > 8, crop.height > 8,
              let cropped = cgImage.cropping(to: crop) else { return nil }

        let context = CIContext()
        var ci = CIImage(cgImage: cropped)

        // Greyscale, then invert: a glowing LED on black is the photographic
        // negative of the dark-ink-on-paper Vision expects.
        ci = ci.applyingFilter("CIPhotoEffectMono")
        ci = ci.applyingFilter("CIColorInvert")
        // Push mid-tones apart so segments read as solid strokes.
        ci = ci.applyingFilter("CIColorControls", parameters: [
            kCIInputContrastKey: 1.6, kCIInputBrightnessKey: 0.05,
        ])

        let scale: CGFloat = 2
        ci = ci.transformed(by: CGAffineTransform(scaleX: scale, y: scale))

        // The white margin matters as much as anything else — without it
        // Vision often finds no text region at all.
        let margin: CGFloat = 80
        let padded = CGRect(
            x: ci.extent.minX - margin, y: ci.extent.minY - margin,
            width: ci.extent.width + margin * 2, height: ci.extent.height + margin * 2
        )
        let white = CIImage(color: .white).cropped(to: padded)
        ci = ci.composited(over: white)

        return context.createCGImage(ci, from: padded)
    }
}

/// The fields a console can show. Which ones apply depends on the machine,
/// so `CardioActivity` decides rather than every console offering all of them.
enum ConsoleField: String, CaseIterable, Codable, Identifiable {
    case duration, distance, calories, incline, resistance

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .duration: "Time"
        case .distance: "Distance"
        case .calories: "Calories"
        case .incline: "Incline"
        case .resistance: "Resistance"
        }
    }

    var hint: String {
        switch self {
        case .duration: "Usually mm:ss"
        case .distance: "km on most machines"
        case .calories: "kcal"
        case .incline: "Percent"
        case .resistance: "Level"
        }
    }

    /// Only the fields that machine actually has a readout for. Offering a
    /// box to draw around an incline figure a rowing machine doesn't display
    /// is asking the user to find something that isn't there.
    static func fields(for activity: CardioActivity) -> [ConsoleField] {
        switch activity {
        case .treadmill: [.duration, .distance, .calories, .incline]
        case .bike, .rower, .elliptical: [.duration, .distance, .calories, .resistance]
        case .outdoorRun, .outdoorBike, .swim, .walk, .other: [.duration, .distance, .calories]
        }
    }
}
