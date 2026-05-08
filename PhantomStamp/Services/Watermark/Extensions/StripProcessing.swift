//
//  WatermarkService+StripProcessing.swift
//  PhantomStamp
//

import UIKit

extension WatermarkService {
    
    // ==========================================
    // Private sub-thread computation logic (single strip processing)
    // ==========================================
    func processSingleStripForEmbedding(strip: ImageStrip, macroblock: Macroblock2D) -> ImageStrip {
        var resultStrip = strip
        
        // Iterate through each 8x8 pixel block in the strip
        for blockY in stride(from: 0, to: strip.height, by: 8) {
            for blockX in stride(from: 0, to: strip.width, by: 8) {
                
                // Get the current 8x8 pixel block matrix
                var pixelBlock = strip.get8x8Block(x: blockX, y: blockY)
                
                // Calculate the variance, and check if it is a smooth block
                let variance = calculateVariance(pixelBlock)
                let thresholdSmooth: Float = 10.5
                if variance < thresholdSmooth {
                    continue // skip the smooth area to ensure invisibility
                }
                
                // 1. Forward 2D Discrete Cosine Transform (vDSP_DCT2D)
                // Perform the Forward 2D Discrete Cosine Transform
                var freqBlock = performDCT(pixelBlock)
                
                // 2. Map the 2D stamp data
                // Combine the global offset, and calculate the bit in the macroblock corresponding to the image block
                let targetBit = macroblock.getBitAt(
                    imageX: blockX + strip.globalXOffset,
                    imageY: blockY + strip.globalYOffset
                )
                
                // 3. Modify the mid-frequency coefficients
                // Modify the size relationship of the specified two mid-frequency coefficients, and embed the targetBit
                embedBitIntoFrequencies(&freqBlock, bit: targetBit)
                
                // 4. Inverse 2D Discrete Cosine Transform (vDSP_IDCT2D)
                // Perform the Inverse 2D Discrete Cosine Transform
                pixelBlock = performIDCT(freqBlock)
                
                // 5. Write the processed block back to the strip
                // Overwrite the pixelBlock data to the corresponding position in the resultStrip
                resultStrip.write8x8Block(pixelBlock, x: blockX, y: blockY)
            }
        }
        
        return resultStrip
    }
    /// Embeds one payload bit into the mid-frequency band of an 8×8 DCT block.
    ///
    /// Strategy:
    /// - Pick two mid-frequency coefficients `(u1, v1)` and `(u2, v2)`.
    /// - Encode the bit by enforcing a strict ordering on their magnitudes with margin `Q`:
    ///   - bit == 1  => |A| - |B| >= Q
    ///   - bit == 0  => |B| - |A| >= Q
    /// - If adjustment is needed, apply a *bidirectional split* (increase one, decrease the other
    ///   by half the required delta) to minimize total energy perturbation.
    func embedBitIntoFrequencies(_ freqBlock: inout Matrix8x8, bit: Int) {
        // A small symmetric pair around the diagonal tends to be stable and visually subtle.
        let p1 = (u: 3, v: 4)
        let p2 = (u: 4, v: 3)

        let a = freqBlock[p1.u, p1.v]
        let b = freqBlock[p2.u, p2.v]

        let qa = adaptiveQuantizationStep(for: freqBlock)

        let absA = abs(a)
        let absB = abs(b)

        if bit == 1 {
            // Want |A| - |B| >= Q
            let diff = absA - absB
            if diff < qa {
                let delta = (qa - diff) / 2
                let newAbsA = absA + delta
                let newAbsB = max(0, absB - delta)
                freqBlock[p1.u, p1.v] = applyMagnitude(newAbsA, keepingSignOf: a)
                freqBlock[p2.u, p2.v] = applyMagnitude(newAbsB, keepingSignOf: b)
            }
        } else {
            // Want |B| - |A| >= Q
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
    ///
    /// This is the inverse decision rule of ``embedBitIntoFrequencies(_:bit:)``:
    /// - returns 1 if |A| >= |B|
    /// - returns 0 otherwise
    func extractBitFromFrequencies(_ freqBlock: Matrix8x8) -> Int {
        let p1 = (u: 3, v: 4)
        let p2 = (u: 4, v: 3)
        let absA = abs(freqBlock[p1.u, p1.v])
        let absB = abs(freqBlock[p2.u, p2.v])
        return absA >= absB ? 1 : 0
    }

    /// Picks a Q in a conservative range for 8×8 DCT on 0…255-ish pixels, adapted by block activity.
    private func adaptiveQuantizationStep(for freqBlock: Matrix8x8) -> Float {
        // Use mean absolute AC magnitude as a cheap activity proxy.
        var sumAbs: Float = 0
        for u in 0..<Matrix8x8.side {
            for v in 0..<Matrix8x8.side {
                if u == 0 && v == 0 { continue } // exclude DC
                sumAbs += abs(freqBlock[u, v])
            }
        }
        let acMean = sumAbs / 63.0

        // Map activity into [6, 14].
        let q = 6.0 + min(8.0, acMean * 0.15)
        return max(6.0, min(14.0, q))
    }

    private func applyMagnitude(_ magnitude: Float, keepingSignOf value: Float) -> Float {
        let m = max(0, magnitude)
        return value < 0 ? -m : m
    }
}
