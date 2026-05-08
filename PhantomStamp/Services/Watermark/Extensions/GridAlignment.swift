//
//  GridAlignment.swift
//  PhantomStamp
//
//  Grid alignment under crop/translation:
//  - Pixel-level misalignment (crop not multiple of 8): enumerate 8×8 = 64 physical offsets.
//  - Block-level misalignment (large crop/shift): sliding window over the aligned block grid to find sync header.
//  - Unknown tile side W (payload-dependent): enumerate W ∈ [8, 18] while scanning the 32-bit sync marker.
//

import CoreGraphics
import Foundation

extension WatermarkService {
    /// Find the physical 8×8 grid offset by scanning 64 pixel offsets and locating the sync marker
    /// via a sliding window over the extracted bit grid.
    func findGridOffsetAndSyncMarker(in matrix: Matrix) -> CGPoint? {
        let syncMarker = getSyncMarkerBits()
        let tolerance = 4

        // Performance guardrail:
        // Doing 64 offset scans over the whole image is expensive (each block requires DCT).
        // We restrict to the top-left region (in macroblocks) which is sufficient to locate at least one
        // complete sync header in typical crop/translate scenarios.
        let searchBlockLimit = 30

        // Return the globally best match across all 64 pixel offsets.
        // We *do not* return the first window that crosses the tolerance threshold, because synthetic or noisy
        // bit grids can produce early false positives. Instead, we keep the best match globally.
        var bestMatchCount = -1
        var bestOffset: CGPoint?
        #if DEBUG
        var bestDetails: (offsetX: Int, offsetY: Int, bx: Int, by: Int, w: Int) = (0, 0, 0, 0, 0)
        #endif

        for offsetY in 0..<Matrix8x8.side {
            for offsetX in 0..<Matrix8x8.side {
                let maxRows = min(searchBlockLimit, (matrix.height - offsetY) / Matrix8x8.side)
                let maxCols = min(searchBlockLimit, (matrix.width - offsetX) / Matrix8x8.side)
                if maxRows < 4 || maxCols < 8 { continue }

                // Pre-extract all bits under this (offsetX, offsetY) once, then run sliding windows purely in memory.
                // This is the single biggest speedup: without it we'd redo DCT for every (bx,by,w) candidate.
                var bitGrid = [[Int]](repeating: [Int](repeating: 0, count: maxCols), count: maxRows)
                for r in 0..<maxRows {
                    for c in 0..<maxCols {
                        let block = extractSpatialBlock(from: matrix, x: offsetX + c * Matrix8x8.side, y: offsetY + r * Matrix8x8.side)
                        let freqBlock = performDCT(block)
                        bitGrid[r][c] = extractBitFromFrequencies(freqBlock)
                    }
                }

                for by in 0..<maxRows {
                    for bx in 0..<maxCols {
                        for w in 8...18 {
                            // Reading 32 bits row-major with stride W needs enough columns/rows.
                            let maxRowNeeded = by + (32 / w) + 1
                            let maxColNeeded = bx + min(32, w)
                            if maxRowNeeded > maxRows || maxColNeeded > maxCols { continue }

                            var matchCount = 0
                            for i in 0..<32 {
                                let r = by + (i / w)
                                let c = bx + (i % w)
                                if bitGrid[r][c] == syncMarker[i] { matchCount += 1 }
                            }

                            if matchCount > bestMatchCount {
                                bestMatchCount = matchCount
                                bestOffset = CGPoint(x: offsetX, y: offsetY)
                                #if DEBUG
                                bestDetails = (offsetX, offsetY, bx, by, w)
                                #endif
                            }

                            if matchCount == 32 {
                                #if DEBUG
                                print("[WatermarkService] DEBUG gridOffset best=32/32 offset=(\(offsetX),\(offsetY)) bx=\(bx) by=\(by) w=\(w)")
                                #endif
                                return CGPoint(x: offsetX, y: offsetY)
                            }
                        }
                    }
                }
            }
        }

        if bestMatchCount >= (32 - tolerance), let bestOffset {
            #if DEBUG
            print("[WatermarkService] DEBUG gridOffset best=\(bestMatchCount)/32 offset=(\(bestDetails.offsetX),\(bestDetails.offsetY)) bx=\(bestDetails.bx) by=\(bestDetails.by) w=\(bestDetails.w)")
            #endif
            return bestOffset
        }

        #if DEBUG
        if let bestOffset {
            print("[WatermarkService] DEBUG gridOffset no-hit best=\(bestMatchCount)/32 offset=(\(Int(bestOffset.x)),\(Int(bestOffset.y)))")
        } else {
            print("[WatermarkService] DEBUG gridOffset no-hit best=<none>")
        }
        #endif
        return nil
    }

    /// Extract the 8×8 spatial-domain block from the global Y channel matrix based on absolute coordinates.
    ///
    /// - Note:
    ///   Kept `internal` (not `private`) because multiple extension files need this primitive:
    ///   alignment scan, extraction grid building, and tests.
    func extractSpatialBlock(from matrix: Matrix, x: Int, y: Int) -> Matrix8x8 {
        var block = Matrix8x8()
        matrix.data.withUnsafeBufferPointer { ptr in
            block.values.withUnsafeMutableBufferPointer { blockPtr in
                for row in 0..<Matrix8x8.side {
                    let srcStart = (y + row) * matrix.width + x
                    let dstStart = row * Matrix8x8.side
                    for col in 0..<Matrix8x8.side {
                        blockPtr[dstStart + col] = Float(ptr[srcStart + col])
                    }
                }
            }
        }
        return block
    }
}

