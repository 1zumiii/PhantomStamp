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

/// Result of the 64-pixel-offset scan plus sliding-window sync search on the bit grid.
struct GridOffsetScanResult: Sendable {
    /// Physical top-left offset of the 8×8 DCT grid when alignment succeeds.
    var offset: CGPoint?
    /// Best sync-header match (out of 32 bits) observed across all offsets and windows.
    var bestSyncBitsMatched: Int
    /// Topology hypothesis that produced the best sync match during offset search.
    var topologyHypothesis: ScoreGridTopologyHypothesis = .normal
}

extension WatermarkService {
    /// Convenience overload for 8-bit planes (tests / non-deskewed paths): promotes to Float once,
    /// then runs the precision-preserving scan below.
    func findGridOffsetAndSyncMarker(in matrix: Matrix, onOffsetProgress: ((Double) -> Void)? = nil) -> GridOffsetScanResult {
        findGridOffsetAndSyncMarker(in: FloatMatrix(promoting: matrix), onOffsetProgress: onOffsetProgress)
    }

    /// Find the physical 8×8 grid offset by scanning 64 pixel offsets and locating the sync marker
    /// via a sliding window over the extracted bit grid.
    ///
    /// Operates on the `Float` plane produced by `deskewImage` so sub-intensity AC variations
    /// survive into the DCT (see `FloatMatrix` docs for why UInt8 quantization is fatal here).
    /// - Parameter onOffsetProgress: Called occasionally during the 64-offset scan; value is 0...1.
    func findGridOffsetAndSyncMarker(in matrix: FloatMatrix, onOffsetProgress: ((Double) -> Void)? = nil) -> GridOffsetScanResult {
        let syncMarker = getSyncMarkerBits()
        let tolerance = 4

        // Performance guardrail:
        // Doing 64 offset scans over the whole image is expensive (each block requires DCT).
        // We restrict to the top-left region (in macroblocks) which is sufficient to locate at least one
        // complete sync header in typical crop/translate scenarios.
        // JPEG recompression tends to increase bit noise; expanding the search window improves the odds
        // of finding a higher-quality sync hit (at the cost of more DCT work).
        let searchBlockLimit = 45

        // Return the globally best match across all 64 pixel offsets.
        // We *do not* return the first window that crosses the tolerance threshold, because synthetic or noisy
        // bit grids can produce early false positives. Instead, we keep the best match globally.
        var bestMatchCount = -1
        var bestOffset: CGPoint?
        var bestTopology: ScoreGridTopologyHypothesis = .normal
        #if DEBUG
        var bestDetails: (offsetX: Int, offsetY: Int, bx: Int, by: Int, w: Int, topology: ScoreGridTopologyHypothesis) = (0, 0, 0, 0, 0, .normal)
        #endif

        for offsetY in 0..<DCTMatrix8x8.side {
            for offsetX in 0..<DCTMatrix8x8.side {
                if let onOffsetProgress {
                    let idx = offsetY * DCTMatrix8x8.side + offsetX
                    // Throttle: 64 offsets are enough; ~16 ticks feels smooth without flooding UI.
                    if idx % 4 == 0 || idx == 63 {
                        onOffsetProgress(Double(idx) / 63.0)
                    }
                }
                let maxRows = min(searchBlockLimit, (matrix.height - offsetY) / DCTMatrix8x8.side)
                let maxCols = min(searchBlockLimit, (matrix.width - offsetX) / DCTMatrix8x8.side)
                if maxRows < 4 || maxCols < 8 { continue }

                // Pre-extract all signed scores under this (offsetX, offsetY) once, then run
                // topology hypotheses and sliding windows purely in memory.
                // This is the single biggest speedup: without it we'd redo DCT for every (bx,by,w) candidate.
                var scoreGrid = [[Float]](repeating: [Float](repeating: .nan, count: maxCols), count: maxRows)
                for r in 0..<maxRows {
                    for c in 0..<maxCols {
                        let block = extractSpatialBlock(from: matrix, x: offsetX + c * DCTMatrix8x8.side, y: offsetY + r * DCTMatrix8x8.side)
                        // Poison-skip (same rule as `extractBitsWithOffset`): a block touched by the
                        // deskew OOB sentinel is (near-)constant, so ALL its AC coefficients are ~0 and
                        // `extractBitFromFrequencies` would return a deterministic, fabricated `1`.
                        // Mark it NaN instead — it becomes a hard-bit abstention, so windows
                        // overlapping the dead frame lose score instead of gaining fake matches.
                        if isBlockPolluted(block) {
                            scoreGrid[r][c] = .nan
                            continue
                        }
                        let freqBlock = performDCT(block)
                        scoreGrid[r][c] = extractBitConfidence(freqBlock)
                    }
                }

                for hypothesis in ScoreGridTopologyHypothesis.allCases {
                    let transformedScores = transformedSoftScoreGrid(scoreGrid, hypothesis: hypothesis)
                    let topologyRows = transformedScores.count
                    let topologyCols = transformedScores.first?.count ?? 0
                    if topologyRows < 4 || topologyCols < 8 { continue }

                    var bitGrid = [[Int]](repeating: [], count: topologyRows)
                    for r in 0..<topologyRows {
                        bitGrid[r] = transformedScores[r].map { $0.isNaN ? -1 : ($0 >= 0 ? 1 : 0) }
                    }

                    for by in 0..<topologyRows {
                        for bx in 0..<topologyCols {
                            for w in 8...18 {
                                // Reading 32 bits row-major with stride W needs enough columns/rows.
                                let maxRowNeeded = by + (32 / w) + 1
                                let maxColNeeded = bx + min(32, w)
                                if maxRowNeeded > topologyRows || maxColNeeded > topologyCols { continue }

                                var matchCount = 0
                                for i in 0..<32 {
                                    let r = by + (i / w)
                                    let c = bx + (i % w)
                                    if bitGrid[r][c] == syncMarker[i] { matchCount += 1 }
                                }

                                if matchCount > bestMatchCount {
                                    bestMatchCount = matchCount
                                    bestOffset = CGPoint(x: offsetX, y: offsetY)
                                    bestTopology = hypothesis
                                    #if DEBUG
                                    bestDetails = (offsetX, offsetY, bx, by, w, hypothesis)
                                    #endif
                                }

                                if matchCount == 32 {
                                    #if DEBUG
                                    print("[WatermarkService] DEBUG gridOffset best=32/32 offset=(\(offsetX),\(offsetY)) bx=\(bx) by=\(by) w=\(w) topology=\(hypothesis.rawValue)")
                                    #endif
                                    return GridOffsetScanResult(
                                        offset: CGPoint(x: offsetX, y: offsetY),
                                        bestSyncBitsMatched: 32,
                                        topologyHypothesis: hypothesis
                                    )
                                }
                            }
                        }
                    }
                }
            }
        }

        if bestMatchCount >= (32 - tolerance), let bestOffset {
            #if DEBUG
            print("[WatermarkService] DEBUG gridOffset best=\(bestMatchCount)/32 offset=(\(bestDetails.offsetX),\(bestDetails.offsetY)) bx=\(bestDetails.bx) by=\(bestDetails.by) w=\(bestDetails.w) topology=\(bestDetails.topology.rawValue)")
            #endif
            return GridOffsetScanResult(
                offset: bestOffset,
                bestSyncBitsMatched: bestMatchCount,
                topologyHypothesis: bestTopology
            )
        }

        #if DEBUG
        if let bestOffset {
            print("[WatermarkService] DEBUG gridOffset no-hit best=\(bestMatchCount)/32 offset=(\(Int(bestOffset.x)),\(Int(bestOffset.y)))")
        } else {
            print("[WatermarkService] DEBUG gridOffset no-hit best=<none>")
        }
        #endif
        return GridOffsetScanResult(
            offset: nil,
            bestSyncBitsMatched: max(0, bestMatchCount),
            topologyHypothesis: bestTopology
        )
    }

    /// Extract the 8×8 spatial-domain block from the global Y channel matrix based on absolute coordinates.
    ///
    /// - Note:
    ///   Kept `internal` (not `private`) because multiple extension files need this primitive:
    ///   alignment scan, extraction grid building, and tests.
    func extractSpatialBlock(from matrix: Matrix, x: Int, y: Int) -> DCTMatrix8x8 {
        var block = DCTMatrix8x8()
        matrix.data.withUnsafeBufferPointer { ptr in
            block.values.withUnsafeMutableBufferPointer { blockPtr in
                for row in 0..<DCTMatrix8x8.side {
                    let srcStart = (y + row) * matrix.width + x
                    let dstStart = row * DCTMatrix8x8.side
                    for col in 0..<DCTMatrix8x8.side {
                        blockPtr[dstStart + col] = Float(ptr[srcStart + col])
                    }
                }
            }
        }
        return block
    }

    /// True when any sample of the 8×8 block carries the deskew OOB poison sentinel (-1000).
    ///
    /// Poisoned blocks MUST NOT cast bit votes: a constant block has every AC coefficient equal
    /// to EXACTLY 0.0, so `abs(C1) >= abs(C2)` ties and decodes as a deterministic `1`. After an
    /// upscale attack the deskewed plane has a full dead frame around the content; letting it
    /// vote floods the macro-tile fold with fabricated 1s (the classic `lenByte=255` symptom).
    func isBlockPolluted(_ block: DCTMatrix8x8) -> Bool {
        for v in block.values where v < -500.0 {
            return true
        }
        return false
    }

    /// Float-plane overload: copies the un-truncated `Float` samples straight into the DCT buffer,
    /// preserving the sub-pixel energy carried over from `deskewImage`'s bilinear interpolation.
    func extractSpatialBlock(from matrix: FloatMatrix, x: Int, y: Int) -> DCTMatrix8x8 {
        var block = DCTMatrix8x8()
        matrix.data.withUnsafeBufferPointer { ptr in
            block.values.withUnsafeMutableBufferPointer { blockPtr in
                for row in 0..<DCTMatrix8x8.side {
                    let srcStart = (y + row) * matrix.width + x
                    let dstStart = row * DCTMatrix8x8.side
                    for col in 0..<DCTMatrix8x8.side {
                        blockPtr[dstStart + col] = ptr[srcStart + col]
                    }
                }
            }
        }
        return block
    }
}
