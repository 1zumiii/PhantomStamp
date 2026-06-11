//
//  CanvasPreviewMapping.swift
//  PhantomStamp
//
//  Maps between canvas layout and image pixels for scaledToFill previews.
//

import CoreGraphics
import UIKit

enum CanvasPreviewMapping {
    /// Crops the region that `scaledToFill` would show inside `containerSize` (matches on-screen preview).
    static func cropScaledToFillPreview(from image: UIImage, containerSize: CGSize) -> UIImage? {
        let pixelW = image.size.width * image.scale
        let pixelH = image.size.height * image.scale
        guard pixelW > 0, pixelH > 0,
              containerSize.width > 0, containerSize.height > 0 else { return nil }

        let fillScale = max(containerSize.width / pixelW, containerSize.height / pixelH)
        let visibleW = containerSize.width / fillScale
        let visibleH = containerSize.height / fillScale
        let originX = (pixelW - visibleW) * 0.5
        let originY = (pixelH - visibleH) * 0.5

        let format = UIGraphicsImageRendererFormat()
        format.scale = image.scale
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(
            size: CGSize(width: visibleW, height: visibleH),
            format: format
        )
        return renderer.image { _ in
            image.draw(at: CGPoint(x: -originX, y: -originY))
        }
    }
}

/// Shared block-center math so crosshair lines and slider cursor tips land on the same coordinate.
enum ReticleBlockGeometry {
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
