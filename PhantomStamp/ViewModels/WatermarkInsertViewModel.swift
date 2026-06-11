//
//  WatermarkInsertViewModel.swift
//  PhantomStamp
//
//  Orchestrates image selection, payload validation, embedding via WatermarkService,
//  and saving outputs to the photo library.
//

import Observation
import UIKit

/// One-shot parameter overrides coming from the Advanced Mode panel (local view state).
/// Passed directly into `WatermarkService` for a single embed run — never written to `UserSettingsStore`.
struct AdvancedEmbedOverrides {
    /// Continuous variance → gain mapping (replaces binary smooth-block threshold in Advanced Mode).
    let varianceGainCurve: VarianceGainCurve
    /// Global adaptive-Q multiplier for this run.
    let embeddingIntensity: Double
}

@MainActor
@Observable
final class WatermarkInsertViewModel {
    private let watermarkService: any WatermarkServiceProtocol

    /// Selected photos in pick order (new picks append to the end).
    private(set) var selectedPhotoItems: [SelectedPhotoItem] = []

    /// User-facing watermark text (trimmed when embedding).
    var watermarkPayload: String = ""

    var isEmbedding: Bool = false

    /// Shown on top of the upload card after a successful embed.
    var showSuccessOverlay: Bool = false

    var embedErrorMessage: String?
    var showEmbedErrorAlert: Bool = false

    static let payloadMinLength = 8
    static let payloadMaxLength = 16
    static let maxSelectedImageCount = 9

    init(watermarkService: any WatermarkServiceProtocol) {
        self.watermarkService = watermarkService
    }

    /// Trimmed payload used for validation and embedding.
    var trimmedPayload: String {
        watermarkPayload.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// True when length is within bounds (empty is invalid).
    var isPayloadLengthValid: Bool {
        let t = trimmedPayload
        guard !t.isEmpty else { return false }
        return t.count >= Self.payloadMinLength && t.count <= Self.payloadMaxLength
    }

    var canStartEmbed: Bool {
        !selectedPhotoItems.isEmpty && isPayloadLengthValid && !isEmbedding && !showSuccessOverlay
    }

    var remainingImageSlots: Int {
        max(0, Self.maxSelectedImageCount - selectedPhotoItems.count)
    }

    var isAtImageLimit: Bool {
        remainingImageSlots == 0
    }

    func appendPickedItems(_ items: [SelectedPhotoItem]) {
        guard !items.isEmpty, remainingImageSlots > 0 else { return }
        let start = selectedPhotoItems.count
        let adjusted: [SelectedPhotoItem] = items.prefix(remainingImageSlots).enumerated().map { offset, item in
            guard item.displayName == SelectedPhotoItem.missingFileNamePlaceholder else { return item }
            let n = start + offset + 1
            return SelectedPhotoItem(
                id: item.id,
                image: item.image,
                width: item.width,
                height: item.height,
                suggestedName: "Image \(n)")
        }
        selectedPhotoItems.append(contentsOf: adjusted)
    }

    func removePhoto(id: UUID) {
        selectedPhotoItems.removeAll { $0.id == id }
    }

    /// Advanced mode is a single-image pipeline: keep only the first pick when switching in.
    func keepOnlyFirstPhoto() {
        guard selectedPhotoItems.count > 1 else { return }
        selectedPhotoItems = Array(selectedPhotoItems.prefix(1))
    }

    /// Clears selection and payload (toolbar reset).
    func resetDraft() {
        selectedPhotoItems = []
        watermarkPayload = ""
        showSuccessOverlay = false
    }

    /// Removes success overlay and clears upload state so the user can pick again.
    func dismissSuccessOverlayAndResetUploadState() {
        showSuccessOverlay = false
        selectedPhotoItems = []
    }

    func embedWatermark(advancedOverrides: AdvancedEmbedOverrides? = nil) async {
        guard canStartEmbed else { return }

        let text = trimmedPayload
        isEmbedding = true
        defer { isEmbedding = false }

        // Advanced mode is single-image by contract; the view also enforces this at pick time.
        let items = advancedOverrides == nil ? selectedPhotoItems : Array(selectedPhotoItems.prefix(1))
        let images = items.map(\.image)
        let names = items.map(\.displayName)

        do {
            let outputs: [UIImage]
            if images.count == 1 {
                // Single-file API drives `watermarkProgress*` notifications only.
                if let overrides = advancedOverrides, let svc = watermarkService as? WatermarkService {
                    let one = try await svc.embedWatermark(
                        into: images[0],
                        text: text,
                        sourceImageName: names.first,
                        parameterOverrides: overrides
                    )
                    outputs = [one]
                } else if let svc = watermarkService as? WatermarkService {
                    let one = try await svc.embedWatermark(into: images[0], text: text, sourceImageName: names.first)
                    outputs = [one]
                } else {
                    let one = try await watermarkService.embedWatermark(into: images[0], text: text)
                    outputs = [one]
                }
            } else {
                // Batch API posts `watermarkBatchProgress` + per-file drain semantics.
                if let svc = watermarkService as? WatermarkService {
                    outputs = try await svc.embedWatermark(into: images, text: text, sourceImageNames: names)
                } else {
                    outputs = try await watermarkService.embedWatermark(into: images, text: text)
                }
            }

            let shouldSaveToPhotos: Bool = {
                // Settings are owned by the runtime `WatermarkService` instance and injected from `RootView.onAppear`.
                // When running in previews/tests with a different service, default to saving.
                guard let svc = watermarkService as? WatermarkService else { return true }
                return svc.settingsStore?.saveToPhotos ?? true
            }()
            if shouldSaveToPhotos {
                for image in outputs {
                    try await PhotoLibraryExporter.saveToPhotoLibrary(image)
                }
            }

            showSuccessOverlay = true
        } catch {
            embedErrorMessage = error.localizedDescription
            showEmbedErrorAlert = true
        }
    }

    func acknowledgeEmbedError() {
        showEmbedErrorAlert = false
        embedErrorMessage = nil
    }
}
