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
    
    func extractBitsWithOffset(_ matrix: Matrix, offset: CGPoint) -> [[Int]] {
        let startX = Int(offset.x)
        let startY = Int(offset.y)
        
        // calculate how many complete 8x8 blocks can be framed under the current physical offset
        let maxRows = (matrix.height - startY) / Matrix8x8.side
        let maxCols = (matrix.width - startX) / Matrix8x8.side
        
        guard maxRows > 0, maxCols > 0 else { return [] }
        
        // pre-allocate a flat array, for multi-threaded concurrent safe writing
        var flatBits = [Int](repeating: 0, count: maxRows * maxCols)
        
        flatBits.withUnsafeMutableBufferPointer { bitPtr in
            // use GCD to concurrently extract by row, maximize CPU multi-core performance, avoid UI freeze
            DispatchQueue.concurrentPerform(iterations: maxRows) { r in
                for c in 0..<maxCols {
                    let block = extractSpatialBlock(from: matrix, x: startX + c * Matrix8x8.side, y: startY + r * Matrix8x8.side)
                    let freqBlock = performDCT(block)
                    let bit = extractBitFromFrequencies(freqBlock)
                    bitPtr[r * maxCols + c] = bit
                }
            }
        }
        
        // reassemble the concurrently extracted flat data back into a 2D matrix
        var bitGrid = [[Int]](repeating: [], count: maxRows)
        for r in 0..<maxRows {
            let start = r * maxCols
            bitGrid[r] = Array(flatBits[start..<(start + maxCols)])
        }
        
        return bitGrid
    }

    func applyMajorityVoting(to bits: [[Int]]) -> [Int] {
        guard !bits.isEmpty, !bits[0].isEmpty else { return [] }
        let maxRows = bits.count
        let maxCols = bits[0].count
        let syncMarker = getSyncMarkerBits()
        
        var bestMatchCount = -1
        var bestBx = 0
        var bestBy = 0
        var bestW = 8
        
        // 1. quickly relocate the sync header in memory (no need to do DCT again, run instantly)
        for by in 0..<maxRows {
            for bx in 0..<maxCols {
                for w in 8...18 {
                    let maxRowNeeded = by + (32 / w) + 1
                    let maxColNeeded = bx + min(32, w)
                    if maxRowNeeded > maxRows || maxColNeeded > maxCols { continue }
                    
                    var matchCount = 0
                    for i in 0..<32 {
                        let r = by + (i / w)
                        let c = bx + (i % w)
                        if bits[r][c] == syncMarker[i] {
                            matchCount += 1
                        }
                    }
                    
                    if matchCount > bestMatchCount {
                        bestMatchCount = matchCount
                        bestBx = bx
                        bestBy = by
                        bestW = w
                    }
                    if matchCount == 32 { break }
                }
                if bestMatchCount == 32 { break }
            }
            if bestMatchCount == 32 { break }
        }
        
        // if the basic tolerance line is not reached, it means there is no watermark in the image, break directly
        guard bestMatchCount >= (32 - 4) else { return [] }
        
        let w = bestW
        var votedMacroblock = [Int](repeating: 0, count: w * w)
        
        // 2. core logic: calculate the absolute anchor point of the macroblock
        // (bestBx, bestBy) is just the *one* complete macroblock starting point we happened to find.
        // by taking the modulo, we calculate the theoretical absolute starting point of the entire grid (between 0 and W)
        let originX = bestBx % w
        let originY = bestBy % w
        
        // 3. squeeze-style majority voting (Majority Voting)
        for i in 0..<(w * w) {
            let tileRow = i / w
            let tileCol = i % w
            
            var ones = 0
            var total = 0
            
            // traverse the entire image to find all redundant bits belonging to this position.
            // deliberately start k and m from -1, to "borrow" the top and left halves of the cut-off macroblock at the top and left of the image.
            for k in -1...(maxRows / w + 1) {
                let globalY = originY + tileRow + k * w
                if globalY >= 0 && globalY < maxRows {
                    
                    for m in -1...(maxCols / w + 1) {
                        let globalX = originX + tileCol + m * w
                        if globalX >= 0 && globalX < maxCols {
                            
                            let bit = bits[globalY][globalX]
                            if bit == 1 { ones += 1 }
                            total += 1
                        }
                    }
                }
            }
            
            // count ends, voting to determine the unique truth at this position
            votedMacroblock[i] = (ones * 2 >= total) ? 1 : 0
        }
        
        return votedMacroblock
    }
}
