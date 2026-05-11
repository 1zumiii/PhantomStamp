//
//  WatermarkInsertViewModel.swift
//  PhantomStamp
//
//  Orchestrates image selection, payload validation, embedding via WatermarkService,
//  and saving outputs to the photo library.
//

import Observation
import UIKit

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

    func appendPickedItems(_ items: [SelectedPhotoItem]) {
        guard !items.isEmpty else { return }
        let start = selectedPhotoItems.count
        let adjusted: [SelectedPhotoItem] = items.enumerated().map { offset, item in
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

    func embedWatermark() async {
        guard canStartEmbed else { return }

        let text = trimmedPayload
        isEmbedding = true
        defer { isEmbedding = false }

        let images = selectedPhotoItems.map(\.image)

        do {
            let outputs: [UIImage]
            if images.count == 1 {
                // Single-file API drives `watermarkProgress*` notifications only.
                let one = try await watermarkService.embedWatermark(into: images[0], text: text)
                outputs = [one]
            } else {
                // Batch API posts `watermarkBatchProgress` + per-file drain semantics.
                outputs = try await watermarkService.embedWatermark(into: images, text: text)
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
