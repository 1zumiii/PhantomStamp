//
//  WatermarkServiceProtocol.swift
//  PhantomStamp
//
//  The contract that both the UI and algorithm must follow: `async throws` is convenient for handling time-consuming and failure scenarios.
//
import Foundation
import UIKit

protocol WatermarkServiceProtocol {
    /// Embed text watermark into a bitmap; time-consuming operations must be implemented in a background-friendly manner (internal thread switching when necessary).
    func embedWatermark(into image: UIImage, text: String) async throws -> UIImage

    /// Embed sequentially into multiple images (posts batch progress notifications).
    func embedWatermark(into images: [UIImage], text: String) async throws -> [UIImage]

    /// Extract watermark text from a bitmap.
    func extractWatermark(from image: UIImage) async throws -> String

    /// Extract sequentially from multiple images (posts batch progress notifications). Stops on first thrown error.
    func extractWatermark(from images: [UIImage]) async throws -> [String]

    /// Extract from multiple images without failing the whole batch; `nil` marks per-image failure.
    func extractWatermarkBestEffort(from images: [UIImage]) async -> [String?]
}

extension WatermarkServiceProtocol {
    /// Embed with an optional source file name so history can display the original file name.
    func embedWatermark(into image: UIImage, text: String, sourceImageName: String?) async throws -> UIImage {
        try await embedWatermark(into: image, text: text)
    }

    /// Embed sequentially with aligned optional source file names.
    func embedWatermark(into images: [UIImage], text: String, sourceImageNames: [String]?) async throws -> [UIImage] {
        try await embedWatermark(into: images, text: text)
    }

    /// Extract with an optional source file name so history can display the original file name.
    func extractWatermark(from image: UIImage, sourceImageName: String?) async throws -> String {
        try await extractWatermark(from: image)
    }

    /// Extract sequentially with aligned optional source file names.
    func extractWatermark(from images: [UIImage], sourceImageNames: [String]?) async throws -> [String] {
        try await extractWatermark(from: images)
    }

    /// Best-effort extract with aligned optional source file names.
    func extractWatermarkBestEffort(from images: [UIImage], sourceImageNames: [String]?) async -> [String?] {
        await extractWatermarkBestEffort(from: images)
    }
}

enum WatermarkError: Error {
    case imageTooSmall
    case extractFailed
    case processingError
}

extension WatermarkError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .imageTooSmall:
            return "Image size is too small, cannot meet the minimum requirements for watermark processing."
        case .extractFailed:
            return "Failed to extract watermark from the current image (algorithm not completed or image does not contain valid watermark)."
        case .processingError:
            return "Error occurred during watermark processing."
        }
    }
}
