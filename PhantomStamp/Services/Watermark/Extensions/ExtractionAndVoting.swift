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
        let tolerance = 4
        let syncCount = syncMarker.count // 32

        // When sync match is close to the tolerance threshold, length header bits can still be corrupted.
        // We keep a small top-N candidate list so that on failure we can try FEC-decoding instead of
        // hard-rejecting by the *uncorrected* length byte.
        struct Candidate {
            let matchCount: Int
            let w: Int
            let bx: Int
            let by: Int
            let lengthByte: Int
            let lengthValid: Bool
        }
        var topCandidates: [Candidate] = []
        func pushTopCandidate(_ c: Candidate, topN: Int = 5) {
            topCandidates.append(c)
            topCandidates.sort {
                if $0.lengthValid != $1.lengthValid { return $0.lengthValid && !$1.lengthValid }
                return $0.matchCount > $1.matchCount
            }
            if topCandidates.count > topN { topCandidates.removeLast(topCandidates.count - topN) }
        }

        // Candidate selection:
        // Matching the 32-bit sync header alone can be ambiguous when matchCount is close to threshold
        // (e.g. 28/32). To disambiguate W, we additionally validate the 8-bit length header that follows
        // the sync marker in the FEC payload:
        //   payloadBits = sync(32) + eccBits
        // and eccBits begins with a length byte (1...16).
        var bestMatchCount = -1
        var bestLengthValid = false
        var bestLengthByte: Int = -1
        var bestBx = 0
        var bestBy = 0
        var bestW = 8

        // Majority-vote the full W×W macro-tile for a given candidate.
        // Used both for the fast path (bestLengthValid) and the decode fallback.
        func computeVotedMacroblock(w: Int, bx: Int, by: Int) -> [Int] {
            var votedMacroblock = [Int](repeating: 0, count: w * w)
            let originX = bx % w
            let originY = by % w

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

                    // Quick extra signal: decode the 8-bit length header right after sync using majority vote
                    // across the repeated lattice phase implied by (bx,by,w).
                    var lengthValid = false
                    var lengthByte = -1
                    if matchCount >= (syncCount - tolerance) {
                        let originX = bx % w
                        let originY = by % w
                        var lengthBits: [Int] = []
                        lengthBits.reserveCapacity(8)
                        for j in 0..<8 {
                            let idx = syncCount + j // tile index right after sync
                            let tileRow = idx / w
                            let tileCol = idx % w
                            var ones = 0
                            var total = 0
                            for k in -1...(maxRows / w + 1) {
                                let gy = originY + tileRow + k * w
                                if gy >= 0 && gy < maxRows {
                                    for m in -1...(maxCols / w + 1) {
                                        let gx = originX + tileCol + m * w
                                        if gx >= 0 && gx < maxCols {
                                            if bits[gy][gx] == 1 { ones += 1 }
                                            total += 1
                                        }
                                    }
                                }
                            }
                            lengthBits.append((ones * 2 >= total) ? 1 : 0)
                        }
                        lengthByte = bitsToByte(lengthBits)
                        // Length header is the UTF-8 byte count of the original message.
                        // In addition to being within [1,16], the inferred `w` must be able to carry the full payload:
                        //   payloadBits = sync(32) + eccBits
                        // and `eccBits` length is fully determined by messageLength under our Hamming(8,4)+interleaving scheme.
                        if (1...16).contains(lengthByte) {
                            let eccCount = expectedEccBitCount(messageLengthBytes: lengthByte)
                            lengthValid = (syncCount + eccCount) <= (w * w)
                        } else {
                            lengthValid = false
                        }

                        #if DEBUG
                        if matchCount >= (syncCount - tolerance) {
                            pushTopCandidate(
                                Candidate(
                                    matchCount: matchCount,
                                    w: w,
                                    bx: bx,
                                    by: by,
                                    lengthByte: lengthByte,
                                    lengthValid: lengthValid
                                )
                            )
                        }
                        #endif
                    }

                    // Prefer candidates with a valid length header; then maximize matchCount.
                    let better =
                        (lengthValid && !bestLengthValid)
                        || (lengthValid == bestLengthValid && matchCount > bestMatchCount)

                    if better {
                        bestMatchCount = matchCount
                        bestLengthValid = lengthValid
                        bestLengthByte = lengthByte
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

        guard bestMatchCount >= (syncCount - tolerance) else { return [] }
        // If we found at least one candidate above sync tolerance but none yields a plausible payload length,
        // extraction is too noisy—fail closed.
        if !bestLengthValid {
            #if DEBUG
            print("[WatermarkService] DEBUG voting: sync ok (\(bestMatchCount)/32) but length header invalid (byte=\(bestLengthByte)) w=\(bestW) bx=\(bestBx) by=\(bestBy)")
            if !topCandidates.isEmpty {
                let shown = topCandidates.prefix(5)
                print("[WatermarkService] DEBUG voting: top candidates (sync/w/lenValid/lenByte/bx/by):")
                for c in shown {
                    print("  - sync=\(c.matchCount)/32 w=\(c.w) lenValid=\(c.lengthValid ? "true" : "false") lenByte=\(c.lengthByte) bx=\(c.bx) by=\(c.by)")
                }
            }
            #endif

            // Fallback: try FEC-decoding for top-N candidates.
            // This avoids false negatives caused by the raw (uncorrected) 8-bit length byte.
            #if DEBUG
            let candidatesToTry = topCandidates.sorted { $0.matchCount > $1.matchCount }.prefix(3)
            #else
            let candidatesToTry = topCandidates.sorted { $0.matchCount > $1.matchCount }.prefix(1)
            #endif
            for c in candidatesToTry {
                let w = c.w
                let votedMacroblock = computeVotedMacroblock(w: w, bx: c.bx, by: c.by)
                let payloadBits = votedMacroblock.count >= syncCount ? Array(votedMacroblock.dropFirst(syncCount)) : []
                #if DEBUG
                print("[WatermarkService] DEBUG voting: fallback macroblock sync=\(c.matchCount)/32 w=\(w) payloadBits=\(payloadBits.count) rawLenByte=\(c.lengthByte)")
                #endif

                // Critical: do NOT decode the entire payloadBits blindly.
                // `w*w` may include padded zeros beyond the real eccBits length, which can introduce
                // extra (garbage/noisy) Hamming codewords and cause decodeFEC to fail.
                // Instead, try truncating to the expected ecc bit-count for each possible message length.
                for messageLenGuess in 1...16 {
                    let eccCount = expectedEccBitCount(messageLengthBytes: messageLenGuess)
                    guard payloadBits.count >= eccCount else { continue }
                    let eccBits = Array(payloadBits.prefix(eccCount))
                    let decoded = decodeFEC(bits: eccBits)
                    #if DEBUG
                    if decoded != nil {
                        print("[WatermarkService] DEBUG voting: fallback decode SUCCESS sync=\(c.matchCount)/32 w=\(w) guessLen=\(messageLenGuess) decodedCount=\(decoded!.count)")
                    }
                    #endif
                    if decoded != nil {
                        return votedMacroblock
                    }
                }
            }

            // Even if length header is invalid, return the best-sync macroblock so the caller can
            // try a more robust decode strategy (e.g. length-guessed truncation).
            #if DEBUG
            print("[WatermarkService] DEBUG voting: all fallback decode attempts failed; returning best-sync macroblock (w=\(bestW) bx=\(bestBx) by=\(bestBy))")
            #endif
            return computeVotedMacroblock(w: bestW, bx: bestBx, by: bestBy)
        }
        #if DEBUG
        print("[WatermarkService] DEBUG voting: best sync=\(bestMatchCount)/32 w=\(bestW) len=\(bestLengthByte) bx=\(bestBx) by=\(bestBy)")
        #endif

        return computeVotedMacroblock(w: bestW, bx: bestBx, by: bestBy)
    }
}

private func bitsToByte(_ bits: [Int]) -> Int {
    var value = 0
    for b in bits.prefix(8) {
        value = (value << 1) | (b & 1)
    }
    return value
}

/// Computes `encodeFEC(text:)` output bit count for a given UTF-8 byte length, without constructing the text.
///
/// Encoding model:
/// - rawBits = 8 (length header) + 8*len
/// - pad rawBits to multiple of 4
/// - Hamming(8,4): 4 raw bits -> 8 coded bits
/// - interleaving keeps bit count unchanged (may pad to full blocks, but here coded bits are always multiple of 8)
private func expectedEccBitCount(messageLengthBytes: Int) -> Int {
    let rawBits = 8 + messageLengthBytes * 8
    let paddedRaw = ((rawBits + 3) / 4) * 4
    let codewordBits = (paddedRaw / 4) * 8
    return codewordBits
}

