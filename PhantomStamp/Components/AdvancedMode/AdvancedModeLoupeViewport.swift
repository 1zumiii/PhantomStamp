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

    private var halfSpan: Int { gridSpan / 2 }

    var body: some View {
        let origin = subGridOrigin()
        let pixelOrigin = CGPoint(x: origin.blockX * DCTMatrix8x8.side, y: origin.blockY * DCTMatrix8x8.side)
        let pixelSpan = gridSpan * DCTMatrix8x8.side
        let imagePixelWidth = max(1, Int(image.size.width * image.scale))
        let imagePixelHeight = max(1, Int(image.size.height * image.scale))
        let cropWidth = min(pixelSpan, max(1, imagePixelWidth - Int(pixelOrigin.x)))
        let cropHeight = min(pixelSpan, max(1, imagePixelHeight - Int(pixelOrigin.y)))
        let cellSize = loupeSize / CGFloat(gridSpan)

        ZStack {
            loupeImageCrop(
                pixelOrigin: pixelOrigin,
                cropWidth: cropWidth,
                cropHeight: cropHeight
            )
            .frame(width: loupeSize, height: loupeSize)
            .clipped()

            Canvas { context, size in
                let threshold = varianceThreshold
                for localY in 0..<gridSpan {
                    for localX in 0..<gridSpan {
                        let blockX = origin.blockX + localX
                        let blockY = origin.blockY + localY
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

                let activeLocalX = reticleBlockX - origin.blockX
                let activeLocalY = reticleBlockY - origin.blockY
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

    @ViewBuilder
    private func loupeImageCrop(pixelOrigin: CGPoint, cropWidth: Int, cropHeight: Int) -> some View {
        let scale = image.scale
        let fullPixelWidth = image.size.width * scale
        let fullPixelHeight = image.size.height * scale
        let zoomScale = loupeSize / CGFloat(max(cropWidth, 1))

        Image(uiImage: image)
            .resizable()
            .aspectRatio(contentMode: .fill)
            .frame(width: fullPixelWidth * zoomScale, height: fullPixelHeight * zoomScale)
            .offset(
                x: -pixelOrigin.x * zoomScale,
                y: -pixelOrigin.y * zoomScale
            )
    }

    private func subGridOrigin() -> (blockX: Int, blockY: Int) {
        var originX = reticleBlockX - halfSpan
        var originY = reticleBlockY - halfSpan
        originX = max(0, min(originX, cache.maxBlocksX - gridSpan))
        originY = max(0, min(originY, cache.maxBlocksY - gridSpan))
        return (max(0, originX), max(0, originY))
    }
}
