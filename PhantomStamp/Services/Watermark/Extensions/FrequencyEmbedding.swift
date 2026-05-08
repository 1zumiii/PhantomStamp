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
    func processSingleStripForEmbedding(strip: ImageStrip, macroblock: Macroblock2D) -> ImageStrip {
        var resultStrip = strip

        for blockY in stride(from: 0, to: strip.height, by: 8) {
            for blockX in stride(from: 0, to: strip.width, by: 8) {
                var pixelBlock = strip.get8x8Block(x: blockX, y: blockY)

                let variance = calculateVariance(pixelBlock)
                let thresholdSmooth: Float = 10.5
                if variance < thresholdSmooth { continue }

                var freqBlock = performDCT(pixelBlock)

                let targetBit = macroblock.getBitAt(
                    imageX: blockX + strip.globalXOffset,
                    imageY: blockY + strip.globalYOffset
                )

                embedBitIntoFrequencies(&freqBlock, bit: targetBit)
                pixelBlock = performIDCT(freqBlock)
                resultStrip.write8x8Block(pixelBlock, x: blockX, y: blockY)
            }
        }

        return resultStrip
    }

    /// Embeds one payload bit into the mid-frequency band of an 8×8 DCT block.
    func embedBitIntoFrequencies(_ freqBlock: inout Matrix8x8, bit: Int) {
        let p1 = (u: 3, v: 4)
        let p2 = (u: 4, v: 3)

        let a = freqBlock[p1.u, p1.v]
        let b = freqBlock[p2.u, p2.v]

        let qa = adaptiveQuantizationStep(for: freqBlock)

        let absA = abs(a)
        let absB = abs(b)

        if bit == 1 {
            let diff = absA - absB
            if diff < qa {
                let delta = (qa - diff) / 2
                let newAbsA = absA + delta
                let newAbsB = max(0, absB - delta)
                freqBlock[p1.u, p1.v] = applyMagnitude(newAbsA, keepingSignOf: a)
                freqBlock[p2.u, p2.v] = applyMagnitude(newAbsB, keepingSignOf: b)
            }
        } else {
            let diff = absB - absA
            if diff < qa {
                let delta = (qa - diff) / 2
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
        let q = 6.0 + min(8.0, acMean * 0.15)
        return max(6.0, min(14.0, q))
    }

    private func applyMagnitude(_ magnitude: Float, keepingSignOf value: Float) -> Float {
        let m = max(0, magnitude)
        return value < 0 ? -m : m
    }
}

