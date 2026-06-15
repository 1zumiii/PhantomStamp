//
//  CanvasPreviewMapping.swift
//  PhantomStamp
//
//  Maps between canvas layout and image pixels for scaledToFill previews.
//

import CoreGraphics
import UIKit

nonisolated enum CanvasPreviewMapping {
    /// Renders exactly what SwiftUI `scaledToFill` shows in `containerSize` (points),
    /// at `displayScale` pixels — 1:1 with the on-screen canvas and variance grid.
    static func renderDisplayMatchedPreview(
        from image: UIImage,
        containerSize: CGSize,
        displayScale: CGFloat
    ) -> UIImage? {
        guard containerSize.width > 0, containerSize.height > 0, displayScale > 0 else { return nil }

        let format = UIGraphicsImageRendererFormat()
        format.scale = displayScale
        format.opaque = true

        let renderer = UIGraphicsImageRenderer(size: containerSize, format: format)
        return renderer.image { _ in
            aspectFillDraw(image: image, in: CGRect(origin: .zero, size: containerSize))
        }
    }

    /// Crops a `gridSpan`×`gridSpan` macroblock window centered on the reticle block (pixel-accurate).
    static func cropLoupeRegion(
        from image: UIImage,
        reticleBlockX: Int,
        reticleBlockY: Int,
        maxBlocksX: Int,
        maxBlocksY: Int,
        gridSpan: Int
    ) -> (image: UIImage, originBlockX: Int, originBlockY: Int)? {
        guard maxBlocksX > 0, maxBlocksY > 0, gridSpan > 0 else { return nil }

        let pixelW = image.size.width * image.scale
        let pixelH = image.size.height * image.scale
        guard pixelW > 0, pixelH > 0 else { return nil }

        let spanPixels = gridSpan * DCTMatrix8x8.side
        let centerPixelX = ReticleBlockGeometry.blockCenterFraction(
            index: reticleBlockX,
            blockCount: maxBlocksX
        ) * pixelW
        let centerPixelY = ReticleBlockGeometry.blockCenterFraction(
            index: reticleBlockY,
            blockCount: maxBlocksY
        ) * pixelH

        let originPixelX = max(0, min(centerPixelX - CGFloat(spanPixels) * 0.5, pixelW - CGFloat(spanPixels)))
        let originPixelY = max(0, min(centerPixelY - CGFloat(spanPixels) * 0.5, pixelH - CGFloat(spanPixels)))
        let originBlockX = max(0, Int(originPixelX) / DCTMatrix8x8.side)
        let originBlockY = max(0, Int(originPixelY) / DCTMatrix8x8.side)

        let cropPointSize = CGFloat(spanPixels) / image.scale
        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        format.opaque = true

        let renderer = UIGraphicsImageRenderer(size: CGSize(width: cropPointSize, height: cropPointSize), format: format)
        let cropped = renderer.image { _ in
            image.draw(at: CGPoint(x: -originPixelX / image.scale, y: -originPixelY / image.scale))
        }
        return (cropped, originBlockX, originBlockY)
    }

    /// Same aspect-fill math as SwiftUI `.scaledToFill()` in point space.
    private static func aspectFillDraw(image: UIImage, in rect: CGRect) {
        let imageSize = image.size
        guard imageSize.width > 0, imageSize.height > 0 else { return }

        let fillScale = max(rect.width / imageSize.width, rect.height / imageSize.height)
        let drawW = imageSize.width * fillScale
        let drawH = imageSize.height * fillScale
        let drawRect = CGRect(
            x: rect.midX - drawW * 0.5,
            y: rect.midY - drawH * 0.5,
            width: drawW,
            height: drawH
        )
        image.draw(in: drawRect)
    }
}

/// Shared block-center math so crosshair lines and slider cursor tips land on the same coordinate.
nonisolated enum ReticleBlockGeometry {
    /// Default reticle index near the top-leading `marginFraction` boundary (e.g. 10% inset).
    static func defaultBlockIndex(blockCount: Int, marginFraction: CGFloat = 0.10) -> Int {
        guard blockCount > 1 else { return 0 }
        let continuous = marginFraction * CGFloat(blockCount) - 0.5
        return min(blockCount - 1, max(0, Int(continuous.rounded())))
    }

    static func blockCenterFraction(index: Int, blockCount: Int) -> CGFloat {
        guard blockCount > 0 else { return 0.5 }
        guard blockCount > 1 else { return 0.5 }
        return (CGFloat(index) + 0.5) / CGFloat(blockCount)
    }

    static func blockCenterPosition(index: Int, blockCount: Int, trackLength: CGFloat) -> CGFloat {
        blockCenterFraction(index: index, blockCount: blockCount) * trackLength
    }

    static func blockIndex(
        at position: CGFloat,
        blockCount: Int,
        trackLength: CGFloat
    ) -> Int {
        guard blockCount > 0, trackLength > 0 else { return 0 }
        guard blockCount > 1 else { return 0 }
        let fraction = min(max(position / trackLength, 0), 1)
        let continuous = fraction * CGFloat(blockCount) - 0.5
        return min(blockCount - 1, max(0, Int(continuous.rounded())))
    }
}
