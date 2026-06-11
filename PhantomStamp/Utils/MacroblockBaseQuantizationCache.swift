//
//  MacroblockBaseQuantizationCache.swift
//  PhantomStamp
//
//  Per-block adaptive Q (globalMultiplier = 1) for embed-amplitude preview.
//

import UIKit

/// Row-major base adaptive quantization step per 8×8 block (before strength / global multiplier).
struct MacroblockBaseQuantizationCache: Sendable {
    let maxBlocksX: Int
    let maxBlocksY: Int
    let grid: [[Float]]

    func baseQ(blockX: Int, blockY: Int) -> Float {
        guard blockY >= 0, blockY < maxBlocksY, blockX >= 0, blockX < maxBlocksX else { return 0 }
        return grid[blockY][blockX]
    }

    /// Reference ceiling at global intensity `1.0×` (full-strength block, no smooth attenuation).
    /// Used as a fixed color-map denominator so slider changes affect heatmap saturation.
    var imageBaselineMaxAmplitude: Float {
        var peakBaseQ: Float = 0
        for row in grid {
            for baseQ in row {
                peakBaseQ = max(peakBaseQ, baseQ)
            }
        }
        return max(peakBaseQ * BlockEmbedAmplitude.payloadStrength, 0.001)
    }
}

extension WatermarkService {
    nonisolated func buildMacroblockBaseQuantizationCache(from image: UIImage) -> MacroblockBaseQuantizationCache? {
        guard let ycbcr = convertToYCbCr(image: image) else { return nil }
        let yChannel = ycbcr.Y
        let maxBlocksX = yChannel.width / DCTMatrix8x8.side
        let maxBlocksY = yChannel.height / DCTMatrix8x8.side
        guard maxBlocksX > 0, maxBlocksY > 0 else { return nil }

        var grid = [[Float]](repeating: [Float](repeating: 0, count: maxBlocksX), count: maxBlocksY)
        for blockY in 0..<maxBlocksY {
            for blockX in 0..<maxBlocksX {
                let pixelBlock = extract8x8BlockForPreview(from: yChannel, blockX: blockX, blockY: blockY)
                let freqBlock = performDCT(pixelBlock)
                grid[blockY][blockX] = previewAdaptiveQuantizationStep(for: freqBlock, globalMultiplier: 1.0)
            }
        }
        return MacroblockBaseQuantizationCache(maxBlocksX: maxBlocksX, maxBlocksY: maxBlocksY, grid: grid)
    }

    nonisolated func previewAdaptiveQuantizationStep(
        for freqBlock: DCTMatrix8x8,
        globalMultiplier: Float = 1.0
    ) -> Float {
        var sumAbs: Float = 0
        for u in 0..<DCTMatrix8x8.side {
            for v in 0..<DCTMatrix8x8.side {
                if u == 0 && v == 0 { continue }
                sumAbs += abs(freqBlock[u, v])
            }
        }
        let acMean = sumAbs / 63.0
        let baseQ = 9.0 + min(10.0, acMean * 0.18)
        let clampedBaseQ = max(9.0, min(18.0, baseQ))
        return clampedBaseQ * globalMultiplier
    }

    private nonisolated func extract8x8BlockForPreview(from matrix: Matrix, blockX: Int, blockY: Int) -> DCTMatrix8x8 {
        let originX = blockX * DCTMatrix8x8.side
        let originY = blockY * DCTMatrix8x8.side
        var block = DCTMatrix8x8()
        block.values.withUnsafeMutableBufferPointer { blockPtr in
            matrix.data.withUnsafeBufferPointer { matrixPtr in
                for row in 0..<DCTMatrix8x8.side {
                    let sy = originY + row
                    let matrixRowLeft = sy * matrix.width + originX
                    let blockRowStart = row * DCTMatrix8x8.side
                    for col in 0..<DCTMatrix8x8.side {
                        blockPtr[blockRowStart + col] = Float(matrixPtr[matrixRowLeft + col])
                    }
                }
            }
        }
        return block
    }
}
