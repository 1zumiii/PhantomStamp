//
//  ExtractionAndVoting.swift
//  PhantomStamp
//
//  Bit extraction on an aligned grid + macro-tile majority voting.
//
//  This file assumes you already found the correct *pixel-level* 8×8 alignment (via `findGridOffsetAndSyncMarker`).
//  It then:
//  - extracts one bit per 8×8 DCT block over the image (or search region),
//  - relocates the sync header in that bit grid (in-memory, no DCT),
//  - folds repeated tiles and performs majority voting to recover one canonical `W×W` macro-tile.
//

import CoreGraphics
import Foundation

extension WatermarkService {
    func extractBitsWithOffset(_ matrix: Matrix, offset: CGPoint) -> [[Int]] {
        let startX = Int(offset.x)
        let startY = Int(offset.y)

        // Under this physical offset, how many complete 8×8 blocks fit?
        let maxRows = (matrix.height - startY) / Matrix8x8.side
        let maxCols = (matrix.width - startX) / Matrix8x8.side
        guard maxRows > 0, maxCols > 0 else { return [] }

        // Write into a flat buffer so concurrent rows can write without reallocations.
        var flatBits = [Int](repeating: 0, count: maxRows * maxCols)
        flatBits.withUnsafeMutableBufferPointer { bitPtr in
            // Concurrency: process rows in parallel. Each row writes to a disjoint slice of `flatBits`.
            // This can still be CPU-heavy; callers should not run this on the main thread.
            DispatchQueue.concurrentPerform(iterations: maxRows) { r in
                for c in 0..<maxCols {
                    let block = extractSpatialBlock(from: matrix, x: startX + c * Matrix8x8.side, y: startY + r * Matrix8x8.side)
                    let freqBlock = performDCT(block)
                    bitPtr[r * maxCols + c] = extractBitFromFrequencies(freqBlock)
                }
            }
        }

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

        // 1) Relocate sync header in-memory.
        //
        // We do not know:
        // - where the macro tile starts (block-level crop/translation),
        // - what W is (depends on payload size; extractor doesn't know length until it finds sync),
        // so we scan (bx,by,w) and pick the best match.
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
                        if bits[r][c] == syncMarker[i] { matchCount += 1 }
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

        guard bestMatchCount >= (32 - 4) else { return [] }

        let w = bestW
        var votedMacroblock = [Int](repeating: 0, count: w * w)

        // 2) Absolute anchor point (fold repeats).
        //
        // `(bestBx, bestBy)` is one observed sync start, not necessarily the "true" tile origin.
        // Taking modulo W gives the canonical phase (0..W-1) for the entire repeated lattice.
        let originX = bestBx % w
        let originY = bestBy % w

        // 3) Majority voting.
        //
        // For each tile cell (tileRow,tileCol), gather all occurrences across the image:
        //   global = origin + tile + (k,m) * W
        // and vote 0/1 by simple majority.
        for i in 0..<(w * w) {
            let tileRow = i / w
            let tileCol = i % w

            var ones = 0
            var total = 0

            // Start from -1 to "steal" partially-visible tiles at the top/left after cropping.
            for k in -1...(maxRows / w + 1) {
                let globalY = originY + tileRow + k * w
                if globalY >= 0 && globalY < maxRows {
                    for m in -1...(maxCols / w + 1) {
                        let globalX = originX + tileCol + m * w
                        if globalX >= 0 && globalX < maxCols {
                            if bits[globalY][globalX] == 1 { ones += 1 }
                            total += 1
                        }
                    }
                }
            }

            votedMacroblock[i] = (ones * 2 >= total) ? 1 : 0
        }

        return votedMacroblock
    }
}

