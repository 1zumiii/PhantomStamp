//
//  LoupeDisplayBuilder.swift
//  PhantomStamp
//
//  Off-main-thread loupe crop + smooth-mask precompute for Advanced Mode.
//

import UIKit

enum LoupeDisplayBuilder {
    struct Model: Sendable {
        let croppedImage: UIImage
        let maskOverlayImage: UIImage
        let originBlockX: Int
        let originBlockY: Int
        let smoothLocalCells: [(x: Int, y: Int)]
        let activeLocalX: Int
        let activeLocalY: Int
    }

    struct Key: Hashable {
        let reticleBlockX: Int
        let reticleBlockY: Int
        let varianceThresholdBits: UInt32
        let maxBlocksX: Int
        let maxBlocksY: Int
        let imagePixelWidth: Int
        let imagePixelHeight: Int
        let gridSpan: Int
        let loupePixelSize: Int
    }

    static func key(
        image: UIImage,
        cache: MacroblockVarianceCache,
        reticleBlockX: Int,
        reticleBlockY: Int,
        varianceThreshold: Float,
        gridSpan: Int,
        loupeSize: CGFloat,
        displayScale: CGFloat
    ) -> Key {
        Key(
            reticleBlockX: reticleBlockX,
            reticleBlockY: reticleBlockY,
            varianceThresholdBits: varianceThreshold.bitPattern,
            maxBlocksX: cache.maxBlocksX,
            maxBlocksY: cache.maxBlocksY,
            imagePixelWidth: Int(image.size.width * image.scale),
            imagePixelHeight: Int(image.size.height * image.scale),
            gridSpan: gridSpan,
            loupePixelSize: Int((loupeSize * displayScale).rounded())
        )
    }

    nonisolated static func build(
        image: UIImage,
        cache: MacroblockVarianceCache,
        reticleBlockX: Int,
        reticleBlockY: Int,
        varianceThreshold: Float,
        gridSpan: Int,
        loupeSize: CGFloat,
        displayScale: CGFloat
    ) -> Model? {
        guard let crop = CanvasPreviewMapping.cropLoupeRegion(
            from: image,
            reticleBlockX: reticleBlockX,
            reticleBlockY: reticleBlockY,
            maxBlocksX: cache.maxBlocksX,
            maxBlocksY: cache.maxBlocksY,
            gridSpan: gridSpan
        ) else { return nil }

        let originX = crop.originBlockX
        let originY = crop.originBlockY
        var smoothLocalCells: [(x: Int, y: Int)] = []
        smoothLocalCells.reserveCapacity(gridSpan * gridSpan / 2)

        for localY in 0..<gridSpan {
            for localX in 0..<gridSpan {
                let blockX = originX + localX
                let blockY = originY + localY
                guard blockX < cache.maxBlocksX, blockY < cache.maxBlocksY else { continue }
                if cache.variance(blockX: blockX, blockY: blockY) < varianceThreshold {
                    smoothLocalCells.append((localX, localY))
                }
            }
        }

        let activeLocalX = reticleBlockX - originX
        let activeLocalY = reticleBlockY - originY
        let pixelSize = max(1, Int((loupeSize * displayScale).rounded()))
        let maskOverlayImage = renderMaskOverlay(
            smoothLocalCells: smoothLocalCells,
            activeLocalX: activeLocalX,
            activeLocalY: activeLocalY,
            gridSpan: gridSpan,
            pixelSize: pixelSize
        )

        return Model(
            croppedImage: crop.image,
            maskOverlayImage: maskOverlayImage,
            originBlockX: originX,
            originBlockY: originY,
            smoothLocalCells: smoothLocalCells,
            activeLocalX: activeLocalX,
            activeLocalY: activeLocalY
        )
    }

    nonisolated private static func renderMaskOverlay(
        smoothLocalCells: [(x: Int, y: Int)],
        activeLocalX: Int,
        activeLocalY: Int,
        gridSpan: Int,
        pixelSize: Int
    ) -> UIImage {
        let size = CGSize(width: pixelSize, height: pixelSize)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false

        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        return renderer.image { rendererContext in
            let cg = rendererContext.cgContext
            let cellSize = CGFloat(pixelSize) / CGFloat(gridSpan)

            cg.setFillColor(UIColor.systemBlue.withAlphaComponent(0.35).cgColor)
            for cell in smoothLocalCells {
                cg.fill(
                    CGRect(
                        x: CGFloat(cell.x) * cellSize,
                        y: CGFloat(cell.y) * cellSize,
                        width: cellSize,
                        height: cellSize
                    )
                )
            }

            guard (0..<gridSpan).contains(activeLocalX), (0..<gridSpan).contains(activeLocalY) else { return }

            let highlight = CGRect(
                x: CGFloat(activeLocalX) * cellSize,
                y: CGFloat(activeLocalY) * cellSize,
                width: cellSize,
                height: cellSize
            )
            cg.setStrokeColor(UIColor.systemYellow.withAlphaComponent(0.95).cgColor)
            cg.setLineWidth(1.25)
            cg.stroke(highlight)
        }
    }
}
