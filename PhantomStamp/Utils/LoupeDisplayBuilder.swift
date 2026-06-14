//
//  LoupeDisplayBuilder.swift
//  PhantomStamp
//
//  Off-main-thread loupe crop + overlay precompute for Advanced Mode.
//

import UIKit

enum LoupeDisplayBuilder {
    struct Model: Sendable {
        let croppedImage: UIImage
        let maskOverlayImage: UIImage
        let originBlockX: Int
        let originBlockY: Int
        let activeLocalX: Int
        let activeLocalY: Int
    }

    struct Key: Hashable {
        let mode: LoupeOverlayMode
        let reticleBlockX: Int
        let reticleBlockY: Int
        let maxBlocksX: Int
        let maxBlocksY: Int
        let imagePixelWidth: Int
        let imagePixelHeight: Int
        let gridSpan: Int
        let loupePixelSize: Int
    }

    enum LoupeOverlayMode: Hashable {
        case smoothMask(varianceThresholdBits: UInt32)
        case gainHeatmap(curveKey: VarianceGainCurve.PackedKey)
        case amplitudeHeatmap(curveKey: VarianceGainCurve.PackedKey, embeddingIntensityBits: UInt32)
    }

    static func key(
        mode: LoupeOverlayMode,
        image: UIImage,
        cache: MacroblockVarianceCache,
        reticleBlockX: Int,
        reticleBlockY: Int,
        gridSpan: Int,
        loupeSize: CGFloat,
        displayScale: CGFloat
    ) -> Key {
        Key(
            mode: mode,
            reticleBlockX: reticleBlockX,
            reticleBlockY: reticleBlockY,
            maxBlocksX: cache.maxBlocksX,
            maxBlocksY: cache.maxBlocksY,
            imagePixelWidth: Int(image.size.width * image.scale),
            imagePixelHeight: Int(image.size.height * image.scale),
            gridSpan: gridSpan,
            loupePixelSize: Int((loupeSize * displayScale).rounded())
        )
    }

    nonisolated static func build(
        mode: LoupeOverlayMode,
        image: UIImage,
        varianceCache: MacroblockVarianceCache,
        baseQCache: MacroblockBaseQuantizationCache?,
        reticleBlockX: Int,
        reticleBlockY: Int,
        gridSpan: Int,
        loupeSize: CGFloat,
        displayScale: CGFloat
    ) -> Model? {
        guard let crop = CanvasPreviewMapping.cropLoupeRegion(
            from: image,
            reticleBlockX: reticleBlockX,
            reticleBlockY: reticleBlockY,
            maxBlocksX: varianceCache.maxBlocksX,
            maxBlocksY: varianceCache.maxBlocksY,
            gridSpan: gridSpan
        ) else { return nil }

        let originX = crop.originBlockX
        let originY = crop.originBlockY
        let activeLocalX = reticleBlockX - originX
        let activeLocalY = reticleBlockY - originY
        let pixelSize = max(1, Int((loupeSize * displayScale).rounded()))

        let maskOverlayImage: UIImage
        switch mode {
        case .smoothMask(let thresholdBits):
            let threshold = Float(bitPattern: thresholdBits)
            var smoothLocalCells: [(x: Int, y: Int)] = []
            for localY in 0..<gridSpan {
                for localX in 0..<gridSpan {
                    let blockX = originX + localX
                    let blockY = originY + localY
                    guard blockX < varianceCache.maxBlocksX, blockY < varianceCache.maxBlocksY else { continue }
                    if varianceCache.variance(blockX: blockX, blockY: blockY) < threshold {
                        smoothLocalCells.append((localX, localY))
                    }
                }
            }
            maskOverlayImage = renderSmoothMaskOverlay(
                smoothLocalCells: smoothLocalCells,
                activeLocalX: activeLocalX,
                activeLocalY: activeLocalY,
                gridSpan: gridSpan,
                pixelSize: pixelSize
            )

        case .gainHeatmap(let curveKey):
            let curve = VarianceGainCurve.decoded(from: curveKey)
            var gains = [Float](repeating: 0, count: gridSpan * gridSpan)
            for localY in 0..<gridSpan {
                for localX in 0..<gridSpan {
                    let blockX = originX + localX
                    let blockY = originY + localY
                    guard blockX < varianceCache.maxBlocksX, blockY < varianceCache.maxBlocksY else { continue }
                    let variance = varianceCache.variance(blockX: blockX, blockY: blockY)
                    gains[localY * gridSpan + localX] = curve.gain(atVariance: variance)
                }
            }
            maskOverlayImage = renderGainHeatmapOverlay(
                gains: gains,
                gridSpan: gridSpan,
                activeLocalX: activeLocalX,
                activeLocalY: activeLocalY,
                pixelSize: pixelSize
            )

        case .amplitudeHeatmap(let curveKey, let intensityBits):
            let curve = VarianceGainCurve.decoded(from: curveKey)
            let intensity = Float(bitPattern: intensityBits)
            guard let baseQCache else {
                maskOverlayImage = renderGainHeatmapOverlay(
                    gains: [Float](repeating: 0, count: gridSpan * gridSpan),
                    gridSpan: gridSpan,
                    activeLocalX: activeLocalX,
                    activeLocalY: activeLocalY,
                    pixelSize: pixelSize
                )
                break
            }
            let normalizationCeiling = baseQCache.heatmapNormalizationCeiling
            var amplitudes = [Float](repeating: 0, count: gridSpan * gridSpan)
            for localY in 0..<gridSpan {
                for localX in 0..<gridSpan {
                    let blockX = originX + localX
                    let blockY = originY + localY
                    guard blockX < varianceCache.maxBlocksX, blockY < varianceCache.maxBlocksY else { continue }
                    let amp = BlockEmbedAmplitude.targetAmplitude(
                        baseAdaptiveQ: baseQCache.baseQ(blockX: blockX, blockY: blockY),
                        variance: varianceCache.variance(blockX: blockX, blockY: blockY),
                        embeddingIntensity: intensity,
                        varianceGainCurve: curve
                    )
                    amplitudes[localY * gridSpan + localX] = amp
                }
            }
            maskOverlayImage = renderAmplitudeHeatmapOverlay(
                amplitudes: amplitudes,
                gridSpan: gridSpan,
                normalizationCeiling: normalizationCeiling,
                activeLocalX: activeLocalX,
                activeLocalY: activeLocalY,
                pixelSize: pixelSize
            )
        }

        return Model(
            croppedImage: crop.image,
            maskOverlayImage: maskOverlayImage,
            originBlockX: originX,
            originBlockY: originY,
            activeLocalX: activeLocalX,
            activeLocalY: activeLocalY
        )
    }

    nonisolated private static func renderSmoothMaskOverlay(
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
            strokeActiveCell(cg: cg, activeLocalX: activeLocalX, activeLocalY: activeLocalY, gridSpan: gridSpan, cellSize: cellSize)
        }
    }

    nonisolated private static func renderGainHeatmapOverlay(
        gains: [Float],
        gridSpan: Int,
        activeLocalX: Int,
        activeLocalY: Int,
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

            for localY in 0..<gridSpan {
                for localX in 0..<gridSpan {
                    let index = localY * gridSpan + localX
                    guard index < gains.count else { continue }
                    let gain = gains[index]
                    guard gain > 0.04 else { continue }
                    cg.setFillColor(
                        BlockEmbedAmplitude.gainHeatmapUIColor(gain: gain).cgColor
                    )
                    cg.fill(
                        CGRect(
                            x: CGFloat(localX) * cellSize,
                            y: CGFloat(localY) * cellSize,
                            width: cellSize,
                            height: cellSize
                        )
                    )
                }
            }
            strokeActiveCell(cg: cg, activeLocalX: activeLocalX, activeLocalY: activeLocalY, gridSpan: gridSpan, cellSize: cellSize)
        }
    }

    nonisolated private static func renderAmplitudeHeatmapOverlay(
        amplitudes: [Float],
        gridSpan: Int,
        normalizationCeiling: Float,
        activeLocalX: Int,
        activeLocalY: Int,
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

            for localY in 0..<gridSpan {
                for localX in 0..<gridSpan {
                    let index = localY * gridSpan + localX
                    guard index < amplitudes.count else { continue }
                    let amp = amplitudes[index]
                    guard amp > 0 else { continue }
                    cg.setFillColor(
                        BlockEmbedAmplitude.heatmapUIColor(
                            amplitude: amp,
                            normalizationCeiling: normalizationCeiling
                        ).cgColor
                    )
                    cg.fill(
                        CGRect(
                            x: CGFloat(localX) * cellSize,
                            y: CGFloat(localY) * cellSize,
                            width: cellSize,
                            height: cellSize
                        )
                    )
                }
            }
            strokeActiveCell(cg: cg, activeLocalX: activeLocalX, activeLocalY: activeLocalY, gridSpan: gridSpan, cellSize: cellSize)
        }
    }

    nonisolated private static func strokeActiveCell(
        cg: CGContext,
        activeLocalX: Int,
        activeLocalY: Int,
        gridSpan: Int,
        cellSize: CGFloat
    ) {
        guard (0..<gridSpan).contains(activeLocalX), (0..<gridSpan).contains(activeLocalY) else { return }
        let highlight = CGRect(
            x: CGFloat(activeLocalX) * cellSize,
            y: CGFloat(activeLocalY) * cellSize,
            width: cellSize,
            height: cellSize
        )
        cg.setStrokeColor(UIColor.black.withAlphaComponent(0.62).cgColor)
        cg.setLineWidth(3.25)
        cg.stroke(highlight.insetBy(dx: 1, dy: 1))

        cg.setStrokeColor(
            UIColor(red: 0.90, green: 0.60, blue: 0.02, alpha: 1.0).cgColor
        )
        cg.setLineWidth(1.75)
        cg.stroke(highlight)
    }
}
