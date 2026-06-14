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
        let syncPatterns = (8...18).map { PackedSyncMarkerPattern(bits: syncMarker, width: $0) }

        // Performance guardrail:
        // Doing 64 offset scans over the whole image is expensive (each block requires DCT).
        // We restrict to the top-left region (in macroblocks) which is sufficient to locate at least one
        // complete sync header in typical crop/translate scenarios.
        // JPEG recompression tends to increase bit noise; expanding the search window improves the odds
        // of finding a higher-quality sync hit (at the cost of more DCT work).
        let searchBlockLimit = 45
        let normalFastPathAccept = 31

        // Return the globally best match across all 64 pixel offsets.
        // We *do not* return the first window that crosses the tolerance threshold, because synthetic or noisy
        // bit grids can produce early false positives. Instead, we keep the best match globally.
        var bestMatchCount = -1
        var bestOffset: CGPoint?
        var bestTopology: ScoreGridTopologyHypothesis = .normal
        #if DEBUG
        var bestDetails: (offsetX: Int, offsetY: Int, bx: Int, by: Int, w: Int, topology: ScoreGridTopologyHypothesis) = (0, 0, 0, 0, 0, .normal)
        #endif

        struct OffsetScoreGrid {
            let offsetX: Int
            let offsetY: Int
            let scores: [[Float]]
            let normalMatch: SyncScanMatch?
        }

        struct SyncScanMatch {
            let matchCount: Int
            let bx: Int
            let by: Int
            let w: Int
            let hypothesis: ScoreGridTopologyHypothesis
        }

        func scanScoreGrid(
            _ scoreGrid: [[Float]],
            hypothesis: ScoreGridTopologyHypothesis
        ) -> SyncScanMatch? {
            let transformedScores = transformedSoftScoreGrid(scoreGrid, hypothesis: hypothesis)
            let topologyRows = transformedScores.count
            let topologyCols = transformedScores.first?.count ?? 0
            if topologyRows < 4 || topologyCols < 8 { return nil }

            let packedHardBits = PackedHardBitGrid(scores: transformedScores)

            var localBest: SyncScanMatch?
            for by in 0..<topologyRows {
                for bx in 0..<topologyCols {
                    for pattern in syncPatterns {
                        let w = pattern.width
                        // Reading 32 bits row-major with stride W needs enough columns/rows.
                        let maxRowNeeded = by + pattern.chunks.count
                        let maxColNeeded = bx + pattern.chunkLengths[0]
                        if maxRowNeeded > topologyRows || maxColNeeded > topologyCols { continue }

                        let matchCount = packedHardBits.matchCount(
                            pattern: pattern,
                            originX: bx,
                            originY: by
                        )

                        if localBest == nil || matchCount > (localBest?.matchCount ?? -1) {
                            localBest = SyncScanMatch(
                                matchCount: matchCount,
                                bx: bx,
                                by: by,
                                w: w,
                                hypothesis: hypothesis
                            )
                        }
                        if matchCount == 32 { return localBest }
                    }
                }
            }
            return localBest
        }

        let offsetCount = DCTMatrix8x8.side * DCTMatrix8x8.side
        var offsetResults = [OffsetScoreGrid?](repeating: nil, count: offsetCount)
        let progressLock = NSLock()
        var completedOffsets = 0

        // Each physical offset reads the immutable deskewed plane and writes one disjoint result
        // slot. GCD bounds actual parallelism to the device's available worker threads.
        offsetResults.withUnsafeMutableBufferPointer { resultPtr in
            DispatchQueue.concurrentPerform(iterations: offsetCount) { idx in
                let offsetY = idx / DCTMatrix8x8.side
                let offsetX = idx % DCTMatrix8x8.side
                let maxRows = min(searchBlockLimit, (matrix.height - offsetY) / DCTMatrix8x8.side)
                let maxCols = min(searchBlockLimit, (matrix.width - offsetX) / DCTMatrix8x8.side)

                if maxRows >= 4, maxCols >= 8 {
                    var scoreGrid = [[Float]](
                        repeating: [Float](repeating: .nan, count: maxCols),
                        count: maxRows
                    )
                    for r in 0..<maxRows {
                        for c in 0..<maxCols {
                            let block = extractSpatialBlock(
                                from: matrix,
                                x: offsetX + c * DCTMatrix8x8.side,
                                y: offsetY + r * DCTMatrix8x8.side
                            )
                            if isBlockPolluted(block) { continue }
                            scoreGrid[r][c] = extractBitConfidence(performDCT(block))
                        }
                    }

                    resultPtr[idx] = OffsetScoreGrid(
                        offsetX: offsetX,
                        offsetY: offsetY,
                        scores: scoreGrid,
                        normalMatch: scanScoreGrid(scoreGrid, hypothesis: .normal)
                    )
                }

                progressLock.lock()
                completedOffsets += 1
                let completed = completedOffsets
                if let onOffsetProgress, completed % 4 == 0 || completed == offsetCount {
                    onOffsetProgress(Double(completed) / Double(offsetCount))
                }
                progressLock.unlock()
            }
        }

        let cachedOffsetScores = offsetResults.compactMap { $0 }
        for cached in cachedOffsetScores {
            guard let match = cached.normalMatch else { continue }
            if match.matchCount > bestMatchCount {
                bestMatchCount = match.matchCount
                bestOffset = CGPoint(x: cached.offsetX, y: cached.offsetY)
                bestTopology = match.hypothesis
                #if DEBUG
                bestDetails = (cached.offsetX, cached.offsetY, match.bx, match.by, match.w, match.hypothesis)
                #endif
            }
            if match.matchCount == 32 {
                #if DEBUG
                print("[WatermarkService] DEBUG gridOffset best=32/32 offset=(\(cached.offsetX),\(cached.offsetY)) bx=\(match.bx) by=\(match.by) w=\(match.w) topology=\(match.hypothesis.rawValue)")
                #endif
                return GridOffsetScanResult(
                    offset: CGPoint(x: cached.offsetX, y: cached.offsetY),
                    bestSyncBitsMatched: 32,
                    topologyHypothesis: match.hypothesis
                )
            }
        }

        if bestMatchCount >= normalFastPathAccept, let bestOffset {
            #if DEBUG
            print("[WatermarkService] DEBUG gridOffset normal-fast best=\(bestMatchCount)/32 offset=(\(bestDetails.offsetX),\(bestDetails.offsetY)) bx=\(bestDetails.bx) by=\(bestDetails.by) w=\(bestDetails.w)")
            #endif
            return GridOffsetScanResult(
                offset: bestOffset,
                bestSyncBitsMatched: bestMatchCount,
                topologyHypothesis: .normal
            )
        }

        var fallbackMatches = [SyncScanMatch?](repeating: nil, count: cachedOffsetScores.count)
        fallbackMatches.withUnsafeMutableBufferPointer { matchPtr in
            DispatchQueue.concurrentPerform(iterations: cachedOffsetScores.count) { idx in
                let cached = cachedOffsetScores[idx]
                var localBest: SyncScanMatch?
                for hypothesis in ScoreGridTopologyHypothesis.allCases where hypothesis != .normal {
                    guard let match = scanScoreGrid(cached.scores, hypothesis: hypothesis) else { continue }
                    if localBest == nil || match.matchCount > (localBest?.matchCount ?? -1) {
                        localBest = match
                    }
                    if match.matchCount == 32 { break }
                }
                matchPtr[idx] = localBest
            }
        }

        for (idx, cached) in cachedOffsetScores.enumerated() {
            if let match = fallbackMatches[idx] {
                if match.matchCount > bestMatchCount {
                    bestMatchCount = match.matchCount
                    bestOffset = CGPoint(x: cached.offsetX, y: cached.offsetY)
                    bestTopology = match.hypothesis
                    #if DEBUG
                    bestDetails = (cached.offsetX, cached.offsetY, match.bx, match.by, match.w, match.hypothesis)
                    #endif
                }
                if match.matchCount == 32 {
                    #if DEBUG
                    print("[WatermarkService] DEBUG gridOffset best=32/32 offset=(\(cached.offsetX),\(cached.offsetY)) bx=\(match.bx) by=\(match.by) w=\(match.w) topology=\(match.hypothesis.rawValue)")
                    #endif
                    return GridOffsetScanResult(
                        offset: CGPoint(x: cached.offsetX, y: cached.offsetY),
                        bestSyncBitsMatched: 32,
                        topologyHypothesis: match.hypothesis
                    )
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
