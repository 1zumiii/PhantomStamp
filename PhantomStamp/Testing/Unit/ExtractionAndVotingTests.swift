//
//  ExtractionAndVotingTests.swift
//  PhantomStamp
//
//  Manual / DEBUG validations for:
//  - extractBitsWithOffset
//  - applyMajorityVoting
//

import CoreGraphics
import Foundation

enum ExtractionAndVotingTests {
    struct Report: Sendable {
        var extractBitsAndVotingPassed: Bool
        var extractBitsAndVotingCheckCount: Int
    }

    static func runAll() -> Report {
        let service = WatermarkService()
        let r = validateExtractBitsAndMajorityVoting(service: service)
        return Report(extractBitsAndVotingPassed: r.passed, extractBitsAndVotingCheckCount: r.checkCount)
    }

    static func runAllAndPrint() {
        #if DEBUG
        let r = runAll()
        let status = r.extractBitsAndVotingPassed ? "PASS" : "FAIL"
        print("[ExtractionAndVotingTests] \(status) Extract + majority vote  checks=\(r.extractBitsAndVotingCheckCount)")
        #endif
    }

    private static func validateExtractBitsAndMajorityVoting(service: WatermarkService) -> (passed: Bool, checkCount: Int) {
        var checks = 0
        func check(_ cond: Bool) -> Bool { checks += 1; return cond }

        // Part A: extractBitsWithOffset
        do {
            let offsetX = 4
            let offsetY = 1
            let rows = 12
            let cols = 10
            let width = offsetX + cols * 8
            let height = offsetY + rows * 8

            var m = Matrix(width: width, height: height, data: [UInt8](repeating: 0, count: width * height))
            var rng = WatermarkTestUtils.SplitMix64(state: 0x1357_2468)
            for i in 0..<m.data.count {
                m.data[i] = UInt8(clamping: Int((rng.nextUnitFloat() * 90.0 + 80.0).rounded()))
            }

            func expectedBit(r: Int, c: Int) -> Int { ((r * 17 + c * 31 + 1) & 1) }

            for r in 0..<rows {
                for c in 0..<cols {
                    if (r + c) % 3 != 0 { continue }
                    let bit = expectedBit(r: r, c: c)
                    let px = offsetX + c * 8
                    let py = offsetY + r * 8
                    let spatial = makeSpatialBlockForEmbeddedBit(service: service, bit: bit, seed: UInt64(0xEE00_0000 + r * 256 + c))
                    writeSpatialBlock(&m, spatial, x: px, y: py)
                }
            }

            let grid = service.extractBitsWithOffset(m, offset: CGPoint(x: offsetX, y: offsetY))
            guard check(grid.count == rows) else { return (false, checks) }
            guard check(grid.first?.count == cols) else { return (false, checks) }

            for r in 0..<rows {
                for c in 0..<cols {
                    if (r + c) % 3 != 0 { continue }
                    guard check(grid[r][c] == expectedBit(r: r, c: c)) else { return (false, checks) }
                }
            }
        }

        // Part B: applyMajorityVoting
        do {
            let sync = getSyncMarkerBits()
            let w = 11
            let originX = 2
            let originY = 4
            let macro = makeMacroTileBits(w: w, sync: sync, seed: 0xCAFE_BEEF)

            let rows = 40
            let cols = 43
            var grid = [[Int]](repeating: [Int](repeating: 0, count: cols), count: rows)
            for r in 0..<rows {
                for c in 0..<cols {
                    let tr = (r - originY).positiveMod(w)
                    let tc = (c - originX).positiveMod(w)
                    grid[r][c] = macro[tr * w + tc]
                }
            }

            var noiseRng = WatermarkTestUtils.SplitMix64(state: 0xDEAD_BEEF)
            for r in 0..<rows {
                for c in 0..<cols {
                    if noiseRng.nextUnitFloat() < 0.02 { grid[r][c] ^= 1 }
                }
            }

            let voted = service.applyMajorityVoting(to: grid)
            guard check(voted.count == w * w) else { return (false, checks) }
            for i in 0..<(w * w) {
                guard check(voted[i] == macro[i]) else { return (false, checks) }
            }
        }

        // Part C: fail closed if sync missing
        do {
            let grid = [[Int]](repeating: [Int](repeating: 0, count: 20), count: 20)
            guard check(service.applyMajorityVoting(to: grid).isEmpty) else { return (false, checks) }
        }

        return (true, checks)
    }

    private static func makeMacroTileBits(w: Int, sync: [Int], seed: UInt64) -> [Int] {
        var rng = WatermarkTestUtils.SplitMix64(state: seed)
        var out = [Int](repeating: 0, count: w * w)
        for i in 0..<32 { out[i] = sync[i] }
        for i in 32..<out.count { out[i] = rng.nextUnitFloat() < 0.5 ? 0 : 1 }
        return out
    }

    private static func makeSpatialBlockForEmbeddedBit(service: WatermarkService, bit: Int, seed: UInt64) -> Matrix8x8 {
        var rng = WatermarkTestUtils.SplitMix64(state: seed)
        var spatial = Matrix8x8(values: [Float](repeating: 0, count: Matrix8x8.elementCount))
        for i in 0..<spatial.values.count {
            spatial.values[i] = rng.nextUnitFloat() * 160.0 + 40.0
        }
        var freq = service.performDCT(spatial)
        service.embedBitIntoFrequencies(&freq, bit: bit)
        return service.performIDCT(freq)
    }

    private static func writeSpatialBlock(_ matrix: inout Matrix, _ block: Matrix8x8, x: Int, y: Int) {
        for row in 0..<Matrix8x8.side {
            for col in 0..<Matrix8x8.side {
                matrix.data[(y + row) * matrix.width + (x + col)] = UInt8(clamping: Int(block[row, col].rounded()))
            }
        }
    }
}

