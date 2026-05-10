//
//  ImageCompressionUtils.swift
//  PhantomStamp
//
//  JPEG recompression helpers for export + robustness testing.
//
//  Notes on Q (compressionQuality):
//  - UIKit uses a floating "quality" slider in [0, 1] for JPEG encoding.
//  - It is NOT a linear “quality percentage”, and is not directly comparable to file size ratio.
//
//  Conservative lower bound:
//  - On the bundled `TestImg` (4032×3024), with the current watermark algorithm, we measured
//    an extraction limit around Q ≈ 0.51 (passes at ~0.51, fails at ~0.50).
//  - Different images / textures may have different limits, so we keep the built-in `.low`
//    preset safely above this threshold (default 0.55).
//

import UIKit

/// User-facing export presets for JPEG output.
enum ImageExportQualityPreset: String, CaseIterable, Sendable {
    case high
    case medium
    case low

    /// JPEG encoder quality in [0.05, 0.95].
    ///
    /// - Important: `.low` is intentionally conservative (>= 0.55) to reduce the chance that
    ///   watermark extraction fails after recompression.
    var jpegQuality: Double {
        switch self {
        case .high:
            return 0.90
        case .medium:
            return 0.70
        case .low:
            return 0.55
        }
    }
}

enum ImageCompressionUtils {
    /// Re-encode a UIImage as JPEG and decode it back as UIImage (simulates platform compression).
    ///
    /// - Returns: attacked image + JPEG byte size.
    static func recompressJPEG(image: UIImage, quality: Double) -> (image: UIImage, jpegBytes: Int)? {
        let q = clampQuality(quality)
        guard let jpeg = image.jpegData(compressionQuality: q),
              let attacked = UIImage(data: jpeg) else { return nil }
        return (attacked, jpeg.count)
    }

    /// Convenience overload using a preset.
    static func recompressJPEG(image: UIImage, preset: ImageExportQualityPreset) -> (image: UIImage, jpegBytes: Int)? {
        recompressJPEG(image: image, quality: preset.jpegQuality)
    }

    /// Clamp to a safe range so we don't feed pathological values into the encoder.
    static func clampQuality(_ q: Double) -> Double {
        min(max(q, 0.05), 0.95)
    }
}

