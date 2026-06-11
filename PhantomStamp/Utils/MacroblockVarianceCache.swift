//
//  MacroblockVarianceCache.swift
//  PhantomStamp
//
//  Pre-computed 8×8 block population-variance grid for Advanced Mode UI (O(1) lookups).
//

import Accelerate
import UIKit

/// Row-major variance grid: `grid[blockY][blockX]` matches the embed pipeline's 8×8 tiling.
struct MacroblockVarianceCache: Sendable {
    let maxBlocksX: Int
    let maxBlocksY: Int
    let grid: [[Float]]

    func variance(blockX: Int, blockY: Int) -> Float {
        guard blockY >= 0, blockY < maxBlocksY, blockX >= 0, blockX < maxBlocksX else {
            return .infinity
        }
        return grid[blockY][blockX]
    }

    /// Builds population variance for every full 8×8 block in the luma plane (same formula as ``WatermarkService/calculateVariance(_:)``).
    static func build(from yChannel: Matrix) -> MacroblockVarianceCache? {
        let maxBlocksX = yChannel.width / DCTMatrix8x8.side
        let maxBlocksY = yChannel.height / DCTMatrix8x8.side
        guard maxBlocksX > 0, maxBlocksY > 0 else { return nil }

        var grid = [[Float]](repeating: [Float](repeating: 0, count: maxBlocksX), count: maxBlocksY)
        for blockY in 0..<maxBlocksY {
            for blockX in 0..<maxBlocksX {
                let block = extract8x8Block(from: yChannel, blockX: blockX, blockY: blockY)
                grid[blockY][blockX] = populationVariance(of: block)
            }
        }
        return MacroblockVarianceCache(maxBlocksX: maxBlocksX, maxBlocksY: maxBlocksY, grid: grid)
    }

    private static func extract8x8Block(from matrix: Matrix, blockX: Int, blockY: Int) -> DCTMatrix8x8 {
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

    private static func populationVariance(of block: DCTMatrix8x8) -> Float {
        var mean: Float = 0
        var meanSquare: Float = 0
        let length = vDSP_Length(DCTMatrix8x8.elementCount)
        block.values.withUnsafeBufferPointer { ptr in
            guard let base = ptr.baseAddress else { return }
            vDSP_meanv(base, 1, &mean, length)
            vDSP_measqv(base, 1, &meanSquare, length)
        }
        let variance = meanSquare - (mean * mean)
        return max(0, variance)
    }
}

extension WatermarkService {
    /// One-shot variance grid for Advanced Mode preview (uses the same Y-plane path as embedding).
    nonisolated func buildMacroblockVarianceCache(from image: UIImage) -> MacroblockVarianceCache? {
        guard let ycbcr = convertToYCbCr(image: image) else { return nil }
        return MacroblockVarianceCache.build(from: ycbcr.Y)
    }
}
