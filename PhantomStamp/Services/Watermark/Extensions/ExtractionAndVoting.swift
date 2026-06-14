//
//  ExtractionAndVoting.swift
//  PhantomStamp
//
//  Bit extraction on an aligned grid + macro-tile SOFT majority voting.
//
//  This file assumes you already found the correct *pixel-level* 8×8 alignment (via `findGridOffsetAndSyncMarker`).
//  It then:
//  - extracts one signed confidence score per 8×8 DCT block over the image,
//  - relocates the sync header in the (hard-thresholded) bit grid (in-memory, no DCT),
//  - folds repeated tiles by SUMMING signed scores (soft decision) to recover one canonical `W×W` macro-tile,
//  - validates candidates by actually FEC-decoding them (the only structurally sound check, since the
//    payload after sync is Hamming(8,4)-coded AND bit-interleaved — there is no raw "length byte" on the grid).
//

import CoreGraphics
import Foundation

/// In-memory topology hypotheses for the recovered macro-cell score grid.
///
/// The DCT payload bit is encoded as `abs(C(1,2)) - abs(C(2,1))`. A 90-degree axis swap
/// exchanges those two coefficients, so all 90/270-degree hypotheses must invert score polarity.
enum ScoreGridTopologyHypothesis: String, CaseIterable, Sendable {
    case normal
    case normalFlipped
    case rotated90
    case rotated90Flipped
    case rotated180
    case rotated180Flipped
    case rotated270
    case rotated270Flipped

    var invertsPolarity: Bool {
        switch self {
        case .rotated90, .rotated90Flipped, .rotated270, .rotated270Flipped:
            return true
        case .normal, .normalFlipped, .rotated180, .rotated180Flipped:
            return false
        }
    }
}

/// Bit-packed hard-decision view used by sync-marker correlation.
///
/// Each candidate sync window previously performed 32 nested-array lookups. Packing each row into
/// `UInt64` words reduces that hot loop to 2...4 XOR/popcount operations (depending on tile width).
struct PackedSyncMarkerPattern {
    let width: Int
    let chunks: [UInt64]
    let chunkLengths: [Int]

    init(bits: [Int], width: Int) {
        self.width = width
        var chunks: [UInt64] = []
        var lengths: [Int] = []
        var start = 0
        while start < bits.count {
            let length = min(width, bits.count - start)
            var packed: UInt64 = 0
            for i in 0..<length where bits[start + i] == 1 {
                packed |= UInt64(1) << UInt64(i)
            }
            chunks.append(packed)
            lengths.append(length)
            start += length
        }
        self.chunks = chunks
        self.chunkLengths = lengths
    }
}

struct PackedHardBitGrid {
    let rows: Int
    let cols: Int
    private let wordsPerRow: Int
    private let values: [UInt64]
    private let valid: [UInt64]

    init(scores: [[Float]]) {
        rows = scores.count
        cols = scores.first?.count ?? 0
        wordsPerRow = (cols + 63) / 64
        var packedValues = [UInt64](repeating: 0, count: rows * wordsPerRow)
        var packedValid = [UInt64](repeating: 0, count: rows * wordsPerRow)

        for r in 0..<rows {
            for c in 0..<cols {
                let score = scores[r][c]
                guard !score.isNaN else { continue }
                let index = r * wordsPerRow + c / 64
                let mask = UInt64(1) << UInt64(c % 64)
                packedValid[index] |= mask
                if score >= 0 {
                    packedValues[index] |= mask
                }
            }
        }

        values = packedValues
        valid = packedValid
    }

    @inline(__always)
    private func extract(_ words: [UInt64], row: Int, col: Int, length: Int) -> UInt64 {
        let wordIndex = col / 64
        let shift = col % 64
        let base = row * wordsPerRow + wordIndex
        var result = words[base] >> UInt64(shift)
        if shift + length > 64 {
            result |= words[base + 1] << UInt64(64 - shift)
        }
        let mask = (UInt64(1) << UInt64(length)) - 1
        return result & mask
    }

    @inline(__always)
    func matchCount(
        pattern: PackedSyncMarkerPattern,
        originX: Int,
        originY: Int
    ) -> Int {
        var matched = 0
        for chunkIndex in pattern.chunks.indices {
            let length = pattern.chunkLengths[chunkIndex]
            let observed = extract(values, row: originY + chunkIndex, col: originX, length: length)
            let validMask = extract(valid, row: originY + chunkIndex, col: originX, length: length)
            let mismatched = (observed ^ pattern.chunks[chunkIndex]) & validMask
            matched += validMask.nonzeroBitCount - mismatched.nonzeroBitCount
        }
        return matched
    }
}

/// Diagnostics from the macro-tile sync relocation + majority-voting fold.
struct MajorityVotingDiagnostics: Sendable {
    /// Best 32-bit sync match score on the extracted bit grid (same scale as offset scan: out of 32).
    var bestSyncBitsMatched: Int
    var macroTileWidth: Int
    var votedMacroblockBitCount: Int
}

extension WatermarkService {
    /// Applies one of the eight D4 topology hypotheses to a score grid.
    ///
    /// The `Flipped` variants are horizontal mirrors after the corresponding rotation. Combined
    /// with 0/90/180/270-degree rotations, that single mirror axis spans both horizontal and
    /// vertical reflections.
    func transformedSoftScoreGrid(
        _ scores: [[Float]],
        hypothesis: ScoreGridTopologyHypothesis
    ) -> [[Float]] {
        guard !scores.isEmpty, let firstRow = scores.first, !firstRow.isEmpty else { return [] }
        let rows = scores.count
        let cols = firstRow.count
        let sign: Float = hypothesis.invertsPolarity ? -1.0 : 1.0

        func value(_ r: Int, _ c: Int) -> Float {
            let v = scores[r][c]
            return v.isNaN ? .nan : (v * sign)
        }

        switch hypothesis {
        case .normal:
            return scores

        case .normalFlipped:
            var out = [[Float]](repeating: [Float](repeating: .nan, count: cols), count: rows)
            for r in 0..<rows {
                for c in 0..<cols {
                    out[r][c] = value(r, cols - 1 - c)
                }
            }
            return out

        case .rotated90:
            var out = [[Float]](repeating: [Float](repeating: .nan, count: rows), count: cols)
            for r in 0..<cols {
                for c in 0..<rows {
                    out[r][c] = value(rows - 1 - c, r)
                }
            }
            return out

        case .rotated90Flipped:
            var out = [[Float]](repeating: [Float](repeating: .nan, count: rows), count: cols)
            for r in 0..<cols {
                for c in 0..<rows {
                    out[r][c] = value(c, r)
                }
            }
            return out

        case .rotated180:
            var out = [[Float]](repeating: [Float](repeating: .nan, count: cols), count: rows)
            for r in 0..<rows {
                for c in 0..<cols {
                    out[r][c] = value(rows - 1 - r, cols - 1 - c)
                }
            }
            return out

        case .rotated180Flipped:
            var out = [[Float]](repeating: [Float](repeating: .nan, count: cols), count: rows)
            for r in 0..<rows {
                for c in 0..<cols {
                    out[r][c] = value(rows - 1 - r, c)
                }
            }
            return out

        case .rotated270:
            var out = [[Float]](repeating: [Float](repeating: .nan, count: rows), count: cols)
            for r in 0..<cols {
                for c in 0..<rows {
                    out[r][c] = value(c, cols - 1 - r)
                }
            }
            return out

        case .rotated270Flipped:
            var out = [[Float]](repeating: [Float](repeating: .nan, count: rows), count: cols)
            for r in 0..<cols {
                for c in 0..<rows {
                    out[r][c] = value(rows - 1 - c, cols - 1 - r)
                }
            }
            return out
        }
    }

    /// Convenience overload for 8-bit planes (tests / non-deskewed paths): promotes to Float once,
    /// then runs the precision-preserving extraction below.
    func extractBitsWithOffset(_ matrix: Matrix, offset: CGPoint) -> [[Int]] {
        extractBitsWithOffset(FloatMatrix(promoting: matrix), offset: offset)
    }

    /// Hard-decision view of `extractSoftBitsWithOffset`: sign → bit, NaN → -1 (abstain).
    func extractBitsWithOffset(_ matrix: FloatMatrix, offset: CGPoint) -> [[Int]] {
        extractSoftBitsWithOffset(matrix, offset: offset).map { row in
            row.map { $0.isNaN ? -1 : ($0 >= 0 ? 1 : 0) }
        }
    }

    /// Extracts one SIGNED CONFIDENCE SCORE (`abs(C(1,2)) − abs(C(2,1))`) per aligned 8×8 block
    /// from a `Float` Y-plane (output of `deskewImage`). `.nan` marks polluted (dead-frame)
    /// blocks that must abstain from voting.
    ///
    /// WHY SOFT SCORES: after a geometric attack + deskew, interpolation/JPEG shrink the diffs
    /// (e.g. ±90 clean → ±5..±40). Hard majority voting gives a |diff|=0.3 coin-flip block the
    /// same weight as a |diff|=40 block, so smooth-skipped and attenuated blocks can out-vote
    /// the reliable ones. Summing signed scores (a matched-filter fold) weighs each repetition
    /// by its actual evidence and dramatically lowers the post-vote bit error rate.
    func extractSoftBitsWithOffset(_ matrix: FloatMatrix, offset: CGPoint) -> [[Float]] {
        let startX = Int(offset.x)
        let startY = Int(offset.y)

        // Under this physical offset, how many complete 8×8 blocks fit?
        let maxRows = (matrix.height - startY) / DCTMatrix8x8.side
        let maxCols = (matrix.width - startX) / DCTMatrix8x8.side
        guard maxRows > 0, maxCols > 0 else { return [] }

        // Flat buffer so concurrent rows write disjoint slices without reallocation.
        // NaN = "invalid/abstain" (polluted by the deskew dead frame).
        var flatScores = [Float](repeating: .nan, count: maxRows * maxCols)

        flatScores.withUnsafeMutableBufferPointer { scorePtr in
            DispatchQueue.concurrentPerform(iterations: maxRows) { r in
                for c in 0..<maxCols {
                    let block = extractSpatialBlock(from: matrix, x: startX + c * DCTMatrix8x8.side, y: startY + r * DCTMatrix8x8.side)

                    if !isBlockPolluted(block) {
                        let freqBlock = performDCT(block)
                        // DEBUG probe: sample the first 40 blocks in the "middle row" of the grid (the image center survives any rotation/scaling deskew)
                        let enableDebug = (r == maxRows / 2 && c < 40)
                        scorePtr[r * maxCols + c] = extractBitConfidence(freqBlock, isDebug: enableDebug)
                    }
                }
            }
        }

        #if DEBUG
        let pollutedCount = flatScores.lazy.filter { $0.isNaN }.count
        print("[WatermarkService] DEBUG extractBits: grid=\(maxRows)x\(maxCols) polluted(dead-frame)=\(pollutedCount)/\(maxRows * maxCols)")
        #endif

        var scoreGrid = [[Float]](repeating: [], count: maxRows)
        for r in 0..<maxRows {
            let start = r * maxCols
            scoreGrid[r] = Array(flatScores[start..<(start + maxCols)])
        }
        return scoreGrid
    }

    /// Hard-bit compatibility wrapper (tests / legacy callers): ±1 equal-weight votes reproduce
    /// the classic majority-vote semantics exactly (`sum >= 0` ⇔ `ones*2 >= total`, ties → 1).
    func applyMajorityVotingWithDiagnostics(to bits: [[Int]]) -> (bits: [Int], diagnostics: MajorityVotingDiagnostics?) {
        let scores: [[Float]] = bits.map { row in
            row.map { b -> Float in
                switch b {
                case 1: return 1.0
                case 0: return -1.0
                default: return .nan // -1 = abstain
                }
            }
        }
        return applySoftMajorityVotingWithDiagnostics(to: scores)
    }

    /// Soft-decision macro-tile recovery:
    /// 1. relocate the 32-bit sync header by correlating HARD bits (sign of each score),
    /// 2. fold all tile repetitions by SUMMING signed scores per cell (confidence-weighted vote),
    /// 3. validate candidates by genuinely FEC-decoding them, best sync match first.
    ///
    /// NOTE ON THE REMOVED "LENGTH BYTE" CHECK: `encodeFEC` lays out
    /// `interleave(hamming84(lengthByte + payload))` after the sync marker, so the 8 grid bits
    /// following sync are interleaved CODEWORD bits — never a raw length byte. The old quick
    /// check therefore failed even on clean images (e.g. lenByte=121) and could PREFER a worse
    /// sync window whose garbage byte happened to land in 1...16. Real `decodeFEC` (SECDED:
    /// detects double-bit errors per codeword) is the only meaningful validator.
    func applySoftMajorityVotingWithDiagnostics(
        to scores: [[Float]],
        preferredHypothesis: ScoreGridTopologyHypothesis? = nil
    ) -> (bits: [Int], diagnostics: MajorityVotingDiagnostics?) {
        var bestFallback: SoftMajorityVotingAttempt?

        let hypotheses: [ScoreGridTopologyHypothesis] = {
            guard let preferredHypothesis else {
                return Array(ScoreGridTopologyHypothesis.allCases)
            }
            return [preferredHypothesis] + ScoreGridTopologyHypothesis.allCases.filter { $0 != preferredHypothesis }
        }()

        for hypothesis in hypotheses {
            let transformedScores = transformedSoftScoreGrid(scores, hypothesis: hypothesis)
            let attempt = applySoftMajorityVotingSingleTopologyWithDiagnostics(
                to: transformedScores,
                hypothesis: hypothesis
            )

            if attempt.fecDecoded {
                return (attempt.bits, attempt.diagnostics)
            } else if bestFallback == nil ||
                        (attempt.diagnostics?.bestSyncBitsMatched ?? -1) > (bestFallback?.diagnostics?.bestSyncBitsMatched ?? -1) {
                bestFallback = attempt
            }
        }

        return (bestFallback?.bits ?? [], bestFallback?.diagnostics)
    }

    private struct SoftMajorityVotingAttempt {
        var bits: [Int]
        var diagnostics: MajorityVotingDiagnostics?
        var fecDecoded: Bool
    }

    /// Runs the existing sync relocation + soft fold + FEC validation for one already-normalized
    /// topology. The public wrapper above tries all eight orthogonal hypotheses and lets FEC pick
    /// the physically correct one.
    private func applySoftMajorityVotingSingleTopologyWithDiagnostics(
        to scores: [[Float]],
        hypothesis: ScoreGridTopologyHypothesis
    ) -> SoftMajorityVotingAttempt {
        guard !scores.isEmpty, !scores[0].isEmpty else {
            return SoftMajorityVotingAttempt(
                bits: [],
                diagnostics: nil,
                fecDecoded: false
            )
        }
        let maxRows = scores.count
        let maxCols = scores[0].count
        let syncMarker = getSyncMarkerBits()
        let tolerance = 4
        let syncCount = syncMarker.count // 32
        let syncPatterns = (8...18).map { PackedSyncMarkerPattern(bits: syncMarker, width: $0) }
        let packedHardBits = PackedHardBitGrid(scores: scores)

        // Hard view for sync-header correlation; -1 (abstain) never matches a marker bit.
        var hardBits = [[Int]](repeating: [], count: maxRows)
        for r in 0..<maxRows {
            hardBits[r] = scores[r].map { $0.isNaN ? -1 : ($0 >= 0 ? 1 : 0) }
        }

        struct Candidate {
            let matchCount: Int
            let w: Int
            let bx: Int
            let by: Int
        }
        // Collected in ALL build configurations (the old list was #if DEBUG-only, which silently
        // disabled the decode fallback in Release builds).
        var topCandidates: [Candidate] = []
        func pushTopCandidate(_ c: Candidate, topN: Int = 6) {
            topCandidates.append(c)
            topCandidates.sort { $0.matchCount > $1.matchCount }
            if topCandidates.count > topN { topCandidates.removeLast(topCandidates.count - topN) }
        }

        // SYNC-GATED confidence-weighted fold of the full W×W macro-tile.
        //
        // WHY GATING: the deskew is only as accurate as the FFT peak detector. A residual scale
        // error of just 3e-4 (or ~0.1° of rotation) accumulates to >1px of grid drift across a
        // 4000+ px image. The 64-offset scan calibrates the integer offset for ONE region; tile
        // repetitions far from it gradually fall out of phase and read near-random bits. Folding
        // those in destroys the vote (observed: single-window sync 32/32 raw, yet the folded
        // payload was ~46% wrong after a scale attack).
        //
        // Every repetition carries the 32-bit sync header at its tile origin, so each repetition
        // can self-certify its own alignment: only repetitions whose LOCAL sync agreement is high
        // enough get to vote. This is purely data-driven — no drift model needed — and uniformly
        // handles drift, dead frames, local JPEG damage and partial crops.
        // `minSyncAgreement`: fraction of visible sync cells a repetition must match to vote.
        // 0.75 is the default operating point; 0.90 is a strict gate used as the first attempt
        // when the residual geometric drift is large and only a handful of repetitions remain
        // truly aligned (marginal 75%-ers would drag the fold's BER over the FEC budget).
        func computeVotedMacroblock(w: Int, bx: Int, by: Int, minSyncAgreement: Float = 0.75) -> [Int] {
            let originX = bx % w
            let originY = by % w

            struct Repetition {
                let gy0: Int
                let gx0: Int
            }

            // Enumerate all (even partially visible) tile repetitions.
            var allReps: [Repetition] = []
            var gatedReps: [Repetition] = []
            for k in -1...(maxRows / w + 1) {
                let gy0 = originY + k * w
                if gy0 + w <= 0 || gy0 >= maxRows { continue }
                for m in -1...(maxCols / w + 1) {
                    let gx0 = originX + m * w
                    if gx0 + w <= 0 || gx0 >= maxCols { continue }
                    let rep = Repetition(gy0: gy0, gx0: gx0)
                    allReps.append(rep)

                    // Local sync agreement for this repetition.
                    var valid = 0
                    var matched = 0
                    for i in 0..<syncCount {
                        let gy = gy0 + i / w
                        let gx = gx0 + i % w
                        guard gy >= 0, gy < maxRows, gx >= 0, gx < maxCols else { continue }
                        let hb = hardBits[gy][gx]
                        guard hb != -1 else { continue }
                        valid += 1
                        if hb == syncMarker[i] { matched += 1 }
                    }
                    // Need enough visible sync cells to judge, plus the requested agreement.
                    // Aligned repetitions sit at ~90-100% even under JPEG; drifted ones at ~50%.
                    if valid >= 24 && Float(matched) >= minSyncAgreement * Float(valid) {
                        gatedReps.append(rep)
                    }
                }
            }

            // Degenerate fallback (e.g. heavy crop leaves almost no certifiable repetition):
            // fold everything rather than nothing.
            let reps = gatedReps.count >= 3 ? gatedReps : allReps
            #if DEBUG
            print("[WatermarkService] DEBUG voting: sync-gated fold w=\(w) bx=\(bx) by=\(by) gate=\(String(format: "%.2f", minSyncAgreement)): accepted \(gatedReps.count)/\(allReps.count) repetitions\(gatedReps.count >= 3 ? "" : " (gate too sparse — folding ALL)")")
            #endif

            var votedMacroblock = [Int](repeating: 0, count: w * w)
            for i in 0..<(w * w) {
                let tileRow = i / w
                let tileCol = i % w

                var sum: Float = 0
                var validVotes = 0
                for rep in reps {
                    let gy = rep.gy0 + tileRow
                    let gx = rep.gx0 + tileCol
                    guard gy >= 0, gy < maxRows, gx >= 0, gx < maxCols else { continue }
                    let s = scores[gy][gx]
                    if !s.isNaN {
                        sum += s
                        validVotes += 1
                    }
                }

                // All repetitions abstained (e.g. fully inside the dead frame) → guess 0.
                votedMacroblock[i] = (validVotes > 0 && sum >= 0) ? 1 : 0
            }
            return votedMacroblock
        }

        // 1) Relocate sync header in-memory.
        //
        // We do not know:
        // - where the macro tile starts (block-level crop/translation),
        // - what W is (depends on payload size; extractor doesn't know length until it finds sync),
        // so we scan (bx,by,w) and keep the best matches.
        var bestMatchCount = -1
        var bestBx = 0
        var bestBy = 0
        var bestW = 8

        scan: for by in 0..<maxRows {
            for bx in 0..<maxCols {
                for pattern in syncPatterns {
                    let w = pattern.width
                    let maxRowNeeded = by + pattern.chunks.count
                    let maxColNeeded = bx + pattern.chunkLengths[0]
                    if maxRowNeeded > maxRows || maxColNeeded > maxCols { continue }

                    let matchCount = packedHardBits.matchCount(
                        pattern: pattern,
                        originX: bx,
                        originY: by
                    )

                    if matchCount >= (syncCount - tolerance) {
                        pushTopCandidate(Candidate(matchCount: matchCount, w: w, bx: bx, by: by))
                    }
                    if matchCount > bestMatchCount {
                        bestMatchCount = matchCount
                        bestBx = bx
                        bestBy = by
                        bestW = w
                    }
                    if matchCount == 32 { break scan }
                }
            }
        }

        guard bestMatchCount >= (syncCount - tolerance) else {
            let diag = MajorityVotingDiagnostics(
                bestSyncBitsMatched: max(0, bestMatchCount),
                macroTileWidth: bestW,
                votedMacroblockBitCount: 0
            )
            return SoftMajorityVotingAttempt(
                bits: [],
                diagnostics: diag,
                fecDecoded: false
            )
        }

        // 2) Validate candidates by ACTUAL FEC decode, best sync match first.
        // `w*w` may include padded zeros beyond the real eccBits length, which would feed garbage
        // Hamming codewords into decodeFEC — so we truncate per guessed message length instead.
        //
        // Gate cascade: try the strict 0.90 fold first (only the unquestionably aligned
        // repetitions vote — decisive when residual drift leaves few aligned tiles), then the
        // standard 0.75 fold (more redundancy when alignment is globally good).
        for c in topCandidates {
            for gate: Float in [0.90, 0.75] {
                let votedMacroblock = computeVotedMacroblock(w: c.w, bx: c.bx, by: c.by, minSyncAgreement: gate)
                let payloadBits = Array(votedMacroblock.dropFirst(syncCount))

                for messageLenGuess in 1...16 {
                    let eccCount = expectedEccBitCount(messageLengthBytes: messageLenGuess)
                    guard (syncCount + eccCount) <= (c.w * c.w), payloadBits.count >= eccCount else { continue }
                    if decodeFEC(bits: Array(payloadBits.prefix(eccCount))) != nil {
                        #if DEBUG
                        print("[WatermarkService] DEBUG voting: decode SUCCESS topology=\(hypothesis.rawValue) sync=\(c.matchCount)/32 w=\(c.w) bx=\(c.bx) by=\(c.by) gate=\(gate) guessLen=\(messageLenGuess)")
                        #endif
                        let diag = MajorityVotingDiagnostics(
                            bestSyncBitsMatched: c.matchCount,
                            macroTileWidth: c.w,
                            votedMacroblockBitCount: votedMacroblock.count
                        )
                        return SoftMajorityVotingAttempt(
                            bits: votedMacroblock,
                            diagnostics: diag,
                            fecDecoded: true
                        )
                    }
                }
            }
        }

        // 3) Nothing decoded — return the best-sync macroblock so the caller can still try its
        // own decode strategies (e.g. length-guessed truncation).
        #if DEBUG
        print("[WatermarkService] DEBUG voting: no candidate FEC-decoded; returning best-sync macroblock topology=\(hypothesis.rawValue) sync=\(bestMatchCount)/32 w=\(bestW) bx=\(bestBx) by=\(bestBy)")
        print("[WatermarkService] DEBUG voting: top candidates (sync/w/bx/by):")
        for c in topCandidates.prefix(6) {
            print("  - sync=\(c.matchCount)/32 w=\(c.w) bx=\(c.bx) by=\(c.by)")
        }
        #endif
        let voted = computeVotedMacroblock(w: bestW, bx: bestBx, by: bestBy)
        let diag = MajorityVotingDiagnostics(
            bestSyncBitsMatched: bestMatchCount,
            macroTileWidth: bestW,
            votedMacroblockBitCount: voted.count
        )
        return SoftMajorityVotingAttempt(
            bits: voted,
            diagnostics: diag,
            fecDecoded: false
        )
    }

    func applyMajorityVoting(to bits: [[Int]]) -> [Int] {
        applyMajorityVotingWithDiagnostics(to: bits).bits
    }
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
