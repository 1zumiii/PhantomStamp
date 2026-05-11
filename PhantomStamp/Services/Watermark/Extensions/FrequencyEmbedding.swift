//
//  WatermarkService+FrequencyEmbedding.swift
//  PhantomStamp
//
//  Per-strip embedding + mid-frequency bit embed/extract.
//

import Foundation
import UIKit

extension WatermarkService {
    // ==========================================
    // Strip embedding
    // ==========================================
    func processSingleStripForEmbedding(strip: ImageStrip, macroblock: Macroblock2D) -> (strip: ImageStrip, visited8x8Blocks: Int, smoothSkipped8x8Blocks: Int) {
        var resultStrip = strip
        var visited8x8Blocks = 0
        var smoothSkipped8x8Blocks = 0

        // The macro-tile starts with: sync(32) + lengthHeader(8) + payload...
        let syncBitCount = getSyncMarkerBits().count
        let headerBitCount = syncBitCount + 8

        for blockY in stride(from: 0, to: strip.height, by: 8) {
            for blockX in stride(from: 0, to: strip.width, by: 8) {
                visited8x8Blocks += 1
                var pixelBlock = strip.get8x8Block(x: blockX, y: blockY)

                let variance = calculateVariance(pixelBlock)
                // In practice (especially on smooth photos), skipping low-variance blocks can
                // reduce repetition so much that sync match becomes marginal (e.g. 28/32).
                // Use a lower threshold to improve robustness; the adaptive `Q` still keeps
                // changes small on smooth blocks.
                // Embed as many blocks as possible to maximize redundancy for majority voting.
                // Previously we skipped low-variance blocks which can leave some macro-cells
                // under-embedded, making extraction bits too noisy.
                // let thresholdSmooth: Float = 20.0
                let thresholdSmooth: Float = -1.0
                if variance < thresholdSmooth {
                    smoothSkipped8x8Blocks += 1
                    continue
                }

                var freqBlock = performDCT(pixelBlock)

                let imageX = blockX + strip.globalXOffset
                let imageY = blockY + strip.globalYOffset
                let mx = imageX / Matrix8x8.side
                let my = imageY / Matrix8x8.side
                let ix = (macroblock.bitsWide > 0) ? (mx % macroblock.bitsWide) : 0
                let iy = (macroblock.bitsHigh > 0) ? (my % macroblock.bitsHigh) : 0
                let tileIndex = iy * max(1, macroblock.bitsWide) + ix
                let targetBit = macroblock.getBitAt(imageX: imageX, imageY: imageY)

                // JPEG compression tends to destroy small mid-frequency differences first.
                // Make the sync + length header cells significantly stronger than the rest.
                let strength: Float
                if tileIndex < syncBitCount {
                    strength = 2.25
                } else if tileIndex < headerBitCount {
                    strength = 2.00
                } else {
                    strength = 1.45
                }

                embedBitIntoFrequencies(&freqBlock, bit: targetBit, strength: strength)
                pixelBlock = performIDCT(freqBlock)
                resultStrip.write8x8Block(pixelBlock, x: blockX, y: blockY)
            }
        }

        return (resultStrip, visited8x8Blocks, smoothSkipped8x8Blocks)
    }

    /// Embeds one payload bit into the mid-frequency band of an 8×8 DCT block.
    func embedBitIntoFrequencies(_ freqBlock: inout Matrix8x8, bit: Int, strength: Float = 1.45) {
        let p1 = (u: 3, v: 4)
        let p2 = (u: 4, v: 3)

        let a = freqBlock[p1.u, p1.v]
        let b = freqBlock[p2.u, p2.v]

        let qa = adaptiveQuantizationStep(for: freqBlock)
        // Increase the target separation between (3,4) and (4,3) so the decision survives
        // IDCT/quantization round-trips, and optionally boost header bits for compression robustness.
        let s = max(1.0, strength)
        let targetQa = qa * s

        let absA = abs(a)
        let absB = abs(b)

        if bit == 1 {
            let diff = absA - absB
            if diff < targetQa {
                let delta = (targetQa - diff) / 2
                let newAbsA = absA + delta
                let newAbsB = max(0, absB - delta)
                freqBlock[p1.u, p1.v] = applyMagnitude(newAbsA, keepingSignOf: a)
                freqBlock[p2.u, p2.v] = applyMagnitude(newAbsB, keepingSignOf: b)
            }
        } else {
            let diff = absB - absA
            if diff < targetQa {
                let delta = (targetQa - diff) / 2
                let newAbsB = absB + delta
                let newAbsA = max(0, absA - delta)
                freqBlock[p2.u, p2.v] = applyMagnitude(newAbsB, keepingSignOf: b)
                freqBlock[p1.u, p1.v] = applyMagnitude(newAbsA, keepingSignOf: a)
            }
        }
    }

    /// Extracts one payload bit from the mid-frequency band of an 8×8 DCT block.
    func extractBitFromFrequencies(_ freqBlock: Matrix8x8) -> Int {
        let p1 = (u: 3, v: 4)
        let p2 = (u: 4, v: 3)
        let absA = abs(freqBlock[p1.u, p1.v])
        let absB = abs(freqBlock[p2.u, p2.v])
        return absA >= absB ? 1 : 0
    }

    private func adaptiveQuantizationStep(for freqBlock: Matrix8x8) -> Float {
        var sumAbs: Float = 0
        for u in 0..<Matrix8x8.side {
            for v in 0..<Matrix8x8.side {
                if u == 0 && v == 0 { continue }
                sumAbs += abs(freqBlock[u, v])
            }
        }
        let acMean = sumAbs / 63.0
        // Stronger baseline helps sync recovery on real images (E2E).
        let q = 9.0 + min(10.0, acMean * 0.18)
        return max(9.0, min(18.0, q))
    }

    private func applyMagnitude(_ magnitude: Float, keepingSignOf value: Float) -> Float {
        let m = max(0, magnitude)
        return value < 0 ? -m : m
    }
}

