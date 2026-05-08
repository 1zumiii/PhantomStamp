//
//  PhotoLibraryExporter.swift
//  PhantomStamp
//
//  Centralized photo library permission + exporting.
//

import Photos
import UIKit

@MainActor
enum PhotoLibraryExporter {
    enum ExportError: LocalizedError {
        case notAuthorized(status: PHAuthorizationStatus)
        case saveFailed(underlying: Error)

        var errorDescription: String? {
            switch self {
            case .notAuthorized(let status):
                return "Photo Library access not authorized (status=\(status.rawValue))."
            case .saveFailed(let underlying):
                return "Failed to save image to Photo Library: \(underlying.localizedDescription)"
            }
        }
    }

    /// Request Photo Library add-only permission early (recommended on app launch).
    /// If status is already determined, this is a no-op.
    static func preflightAddOnlyAuthorizationIfNeeded() async {
        let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        guard status == .notDetermined else { return }
        _ = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
    }

    /// Save image to the system photo library.
    ///
    /// - Important: this function will **not** trigger an authorization prompt.
    ///   Call `preflightAddOnlyAuthorizationIfNeeded()` at app launch to avoid prompting mid-flow.
    static func saveToPhotoLibrary(_ image: UIImage) async throws {
        let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        guard status == .authorized || status == .limited else {
            throw ExportError.notAuthorized(status: status)
        }
        do {
            try await PHPhotoLibrary.shared().performChanges {
                PHAssetChangeRequest.creationRequestForAsset(from: image)
            }
        } catch {
            throw ExportError.saveFailed(underlying: error)
        }
    }
}

