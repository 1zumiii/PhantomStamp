//
//  AdvancedModeLoupeViewport.swift
//  PhantomStamp
//

import SwiftUI
import UIKit

/// Floating magnifier: zoomed preview crop + 15×15 smooth-block mask from the variance cache.
struct AdvancedModeLoupeViewport: View {
    let image: UIImage
    let cache: MacroblockVarianceCache
    let reticleBlockX: Int
    let reticleBlockY: Int
    let varianceThreshold: Float
    let gridSpan: Int
    let loupeSize: CGFloat

    var body: some View {
        let crop = CanvasPreviewMapping.cropLoupeRegion(
            from: image,
            reticleBlockX: reticleBlockX,
            reticleBlockY: reticleBlockY,
            maxBlocksX: cache.maxBlocksX,
            maxBlocksY: cache.maxBlocksY,
            gridSpan: gridSpan
        )
        let origin = (crop?.originBlockX ?? 0, crop?.originBlockY ?? 0)
        let cellSize = loupeSize / CGFloat(gridSpan)

        ZStack {
            if let crop {
                Image(uiImage: crop.image)
                    .resizable()
                    .interpolation(.none)
                    .frame(width: loupeSize, height: loupeSize)
            }

            Canvas { context, size in
                let threshold = varianceThreshold
                for localY in 0..<gridSpan {
                    for localX in 0..<gridSpan {
                        let blockX = origin.0 + localX
                        let blockY = origin.1 + localY
                        guard blockX < cache.maxBlocksX, blockY < cache.maxBlocksY else { continue }
                        guard cache.variance(blockX: blockX, blockY: blockY) < threshold else { continue }

                        let rect = CGRect(
                            x: CGFloat(localX) * cellSize,
                            y: CGFloat(localY) * cellSize,
                            width: cellSize,
                            height: cellSize
                        )
                        context.fill(Path(rect), with: .color(.blue.opacity(0.35)))
                    }
                }

                let activeLocalX = reticleBlockX - origin.0
                let activeLocalY = reticleBlockY - origin.1
                if (0..<gridSpan).contains(activeLocalX), (0..<gridSpan).contains(activeLocalY) {
                    let highlight = CGRect(
                        x: CGFloat(activeLocalX) * cellSize,
                        y: CGFloat(activeLocalY) * cellSize,
                        width: cellSize,
                        height: cellSize
                    )
                    context.stroke(
                        Path(highlight),
                        with: .color(.yellow.opacity(0.95)),
                        style: StrokeStyle(lineWidth: 1.25)
                    )
                }
            }
            .frame(width: loupeSize, height: loupeSize)
            .allowsHitTesting(false)
        }
        .frame(width: loupeSize, height: loupeSize)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .strokeBorder(Color.primary.opacity(0.22), lineWidth: 1)
        }
        .background {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.ultraThinMaterial)
        }
        .shadow(color: .black.opacity(0.18), radius: 8, x: 0, y: 4)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
