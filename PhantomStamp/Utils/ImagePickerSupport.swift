//
//  ImagePickerSupport.swift
//  PhantomStamp
//
//  Helpers for presenting system photo picking limited to still images.
//

import CoreTransferable
import Photos
import PhotosUI
import SwiftUI
import UIKit

enum ImagePickerSupport {
    /// PHPicker / PhotosPicker filter: photos only (no videos).
    static var imagesOnlyFilter: PHPickerFilter { .images }

    /// Load `SelectedPhotoItem` values from picker results (order preserved).
    /// File name: prefers file URL import (`FileRepresentation`), then PhotoKit `originalFilename`, else `nil` → numbered `Image N` at append time.
    static func loadPickedImages(from items: [PhotosPickerItem]) async -> [SelectedPhotoItem] {
        var result: [SelectedPhotoItem] = []
        result.reserveCapacity(items.count)

        for item in items {
            let payload: PickedImagePayload?
            do {
                payload = try await item.loadTransferable(type: PickedImagePayload.self)
            } catch {
                payload = nil
            }

            let data: Data
            let fromFileName: String?
            if let p = payload {
                data = p.data
                fromFileName = p.suggestedFileName
            } else if let d = try? await item.loadTransferable(type: Data.self) {
                data = d
                fromFileName = nil
            } else {
                continue
            }

            guard let image = UIImage(data: data) else { continue }

            var name = fromFileName.flatMap { sanitizedFileName($0) }
            if name == nil {
                name = await photoLibraryFileName(for: item)
            }
            result.append(SelectedPhotoItem(image: image, suggestedName: name))
        }

        return result
    }

    /// Strip junk paths; keep a non-empty basename.
    private static func sanitizedFileName(_ raw: String) -> String? {
        let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return nil }
        let base = (t as NSString).lastPathComponent
        return base.isEmpty ? nil : base
    }

    /// PhotoKit fallback (library assets). Run on main to match typical PhotoKit usage.
    private static func photoLibraryFileName(for item: PhotosPickerItem) async -> String? {
        await MainActor.run {
            guard let localId = item.itemIdentifier else { return nil }
            let assets = PHAsset.fetchAssets(withLocalIdentifiers: [localId], options: nil)
            guard let asset = assets.firstObject else { return nil }
            let resources = PHAssetResource.assetResources(for: asset)
            if let photo = resources.first(where: { $0.type == .photo }) {
                let n = photo.originalFilename.trimmingCharacters(in: .whitespacesAndNewlines)
                return n.isEmpty ? nil : n
            }
            let n = resources.first?.originalFilename.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return n.isEmpty ? nil : n
        }
    }
}

// MARK: - Transferable (Data + file URL)

/// Picks the best import representation: file URLs often carry a real basename; `Data` alone does not.
private struct PickedImagePayload: Transferable {
    let data: Data
    let suggestedFileName: String?

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(importedContentType: .image) { data in
            PickedImagePayload(data: data, suggestedFileName: nil)
        }
        FileRepresentation(importedContentType: .image, shouldAttemptToOpenInPlace: false) { received in
            let data = try Data(contentsOf: received.file)
            let base = received.file.lastPathComponent
            let name = base.trimmingCharacters(in: .whitespacesAndNewlines)
            return PickedImagePayload(
                data: data,
                suggestedFileName: name.isEmpty ? nil : name
            )
        }
    }
}
