//
//  ImageResizeUtils.swift
//  PhantomStamp
//
//  Proportional UIImage resizing for export + robustness testing.
//

import UIKit

enum ImageResizeUtils {
    /// Which edge the user-specified pixel count should match after proportional scaling.
    enum FitMode: String, CaseIterable, Identifiable {
        case width = "Width"
        case height = "Height"
        case longEdge = "Long edge"

        var id: String { rawValue }
    }

    /// Output size after uniform isotropic scaling.
    static func previewOutputSize(sourceWidth: Int, sourceHeight: Int, scaleFactor: Double) -> (width: Int, height: Int)? {
        guard sourceWidth > 0, sourceHeight > 0, scaleFactor > 0 else { return nil }
        let outW = max(1, Int((Double(sourceWidth) * scaleFactor).rounded()))
        let outH = max(1, Int((Double(sourceHeight) * scaleFactor).rounded()))
        return (outW, outH)
    }

    /// Uniform isotropic scale. Output uses `scale = 1`.
    static func resize(image: UIImage, scaleFactor: Double) -> UIImage? {
        let srcW = Int((image.size.width * image.scale).rounded())
        let srcH = Int((image.size.height * image.scale).rounded())
        guard let preview = previewOutputSize(sourceWidth: srcW, sourceHeight: srcH, scaleFactor: scaleFactor) else {
            return nil
        }
        let size = CGSize(width: preview.width, height: preview.height)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { context in
            context.cgContext.interpolationQuality = .medium
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    /// Computes the output pixel size without rendering — useful for live UI previews.
    static func previewOutputSize(
        sourceWidth: Int,
        sourceHeight: Int,
        targetPixels: Int,
        mode: FitMode
    ) -> (width: Int, height: Int)? {
        guard sourceWidth > 0, sourceHeight > 0, targetPixels > 0 else { return nil }
        let scale = scaleFactor(
            sourceWidth: sourceWidth,
            sourceHeight: sourceHeight,
            targetPixels: targetPixels,
            mode: mode
        )
        guard scale > 0 else { return nil }
        let outW = max(1, Int((Double(sourceWidth) * scale).rounded()))
        let outH = max(1, Int((Double(sourceHeight) * scale).rounded()))
        return (outW, outH)
    }

    /// Renders a proportionally scaled copy. Output uses `scale = 1` (pixel dimensions == point size).
    static func resize(
        image: UIImage,
        targetPixels: Int,
        mode: FitMode
    ) -> UIImage? {
        let srcW = Int((image.size.width * image.scale).rounded())
        let srcH = Int((image.size.height * image.scale).rounded())
        guard let preview = previewOutputSize(
            sourceWidth: srcW,
            sourceHeight: srcH,
            targetPixels: targetPixels,
            mode: mode
        ) else { return nil }

        let size = CGSize(width: preview.width, height: preview.height)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1.0
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { context in
            // `.medium` maps to bilinear resampling in Quartz (not nearest-neighbor).
            context.cgContext.interpolationQuality = .medium
            image.draw(in: CGRect(origin: .zero, size: size))
        }
    }

    private static func scaleFactor(
        sourceWidth: Int,
        sourceHeight: Int,
        targetPixels: Int,
        mode: FitMode
    ) -> Double {
        switch mode {
        case .width:
            return Double(targetPixels) / Double(sourceWidth)
        case .height:
            return Double(targetPixels) / Double(sourceHeight)
        case .longEdge:
            let long = max(sourceWidth, sourceHeight)
            guard long > 0 else { return 0 }
            return Double(targetPixels) / Double(long)
        }
    }
}
