//
//  GridAlignmentTests.swift
//  PhantomStamp
//
//  Manual / DEBUG validations for `findGridOffsetAndSyncMarker`.
//

import CoreGraphics
import Foundation

enum GridAlignmentTests {
    struct Report: Sendable {
        var gridOffsetAndSyncMarkerPassed: Bool
        var gridOffsetAndSyncMarkerCheckCount: Int
    }

    static func runAll() -> Report {
        let service = WatermarkService()
        let r = validateFindGridOffsetAndSyncMarker(service: service)
        return Report(gridOffsetAndSyncMarkerPassed: r.passed, gridOffsetAndSyncMarkerCheckCount: r.checkCount)
    }

    static func runAllAndPrint() {
        #if DEBUG
        let r = runAll()
        let status = r.gridOffsetAndSyncMarkerPassed ? "PASS" : "FAIL"
        print("[GridAlignmentTests] \(status) Grid offset + sync scan  checks=\(r.gridOffsetAndSyncMarkerCheckCount)")
        #endif
    }

    private static func validateFindGridOffsetAndSyncMarker(service: WatermarkService) -> (passed: Bool, checkCount: Int) {
        let sync = getSyncMarkerBits()
        var checks = 0
        func check(_ cond: Bool) -> Bool { checks += 1; return cond }

        struct Case: Sendable {
            var name: String
            var expectedOffsetX: Int
            var expectedOffsetY: Int
            var bx: Int
            var by: Int
            var w: Int
            var blockCount: Int
            var seed: UInt64
            var mismatchedBits: Set<Int>
        }

        let cases: [Case] = [
            Case(name: "offset(3,5) w=13 bx/by=7/6", expectedOffsetX: 3, expectedOffsetY: 5, bx: 7, by: 6, w: 13, blockCount: 30, seed: 0xD00D_F00D, mismatchedBits: []),
            Case(name: "offset(0,0) w=8  bx/by=0/0", expectedOffsetX: 0, expectedOffsetY: 0, bx: 0, by: 0, w: 8, blockCount: 30, seed: 0xBADC0FFE, mismatchedBits: []),
            Case(name: "offset(7,7) w=18 bx/by=9/11", expectedOffsetX: 7, expectedOffsetY: 7, bx: 9, by: 11, w: 18, blockCount: 30, seed: 0xA11CE5E, mismatchedBits: []),
            Case(name: "offset(2,6) w=11 bx/by=5/8 (3 bit flips)", expectedOffsetX: 2, expectedOffsetY: 6, bx: 5, by: 8, w: 11, blockCount: 30, seed: 0xC001D00D, mismatchedBits: [1, 9, 27]),
        ]

        for tc in cases {
            let width = tc.expectedOffsetX + tc.blockCount * Matrix8x8.side + 8
            let height = tc.expectedOffsetY + tc.blockCount * Matrix8x8.side + 8

            var m = Matrix(width: width, height: height, data: [])
            m.data = [UInt8](repeating: 0, count: width * height)
            var rng = WatermarkTestUtils.SplitMix64(state: tc.seed)
            for i in 0..<m.data.count {
                let u = rng.nextUnitFloat()
                m.data[i] = UInt8(clamping: Int((u * 90.0 + 80.0).rounded()))
            }

            for i in 0..<32 {
                let r = tc.by + (i / tc.w)
                let c = tc.bx + (i % tc.w)
                let px = tc.expectedOffsetX + c * Matrix8x8.side
                let py = tc.expectedOffsetY + r * Matrix8x8.side
                let stampedBit = tc.mismatchedBits.contains(i) ? (1 - sync[i]) : sync[i]
                let spatial = makeSpatialBlockForEmbeddedBit(service: service, bit: stampedBit, seed: UInt64(0xABC000 + i) ^ tc.seed)
                writeSpatialBlock(&m, spatial, x: px, y: py)
            }

            let got = service.findGridOffsetAndSyncMarker(in: m)
            guard check(got.offset != nil) else { return (false, checks) }
            guard let p = got.offset else { return (false, checks) }
            guard check(got.bestSyncBitsMatched == 32) else { return (false, checks) }
            if Int(p.x) != tc.expectedOffsetX || Int(p.y) != tc.expectedOffsetY {
                #if DEBUG
                print("[GridAlignmentTests] DEBUG case: \(tc.name)")
                debugPrintMatrixWindow(
                    m,
                    x: max(0, tc.expectedOffsetX + tc.bx * 8 - 4),
                    y: max(0, tc.expectedOffsetY + tc.by * 8 - 4),
                    w: 16,
                    h: 16,
                    label: "pixel window near sync start"
                )
                print("[GridAlignmentTests] DEBUG mismatch: got (\(Int(p.x)),\(Int(p.y))) expected (\(tc.expectedOffsetX),\(tc.expectedOffsetY))")
                #endif
                return (false, checks)
            }
            guard check(Int(p.x) == tc.expectedOffsetX) else { return (false, checks) }
            guard check(Int(p.y) == tc.expectedOffsetY) else { return (false, checks) }
        }

        return (true, checks)
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

    #if DEBUG
    private static func debugPrintMatrixWindow(_ matrix: Matrix, x: Int, y: Int, w: Int, h: Int, label: String) {
        let x0 = max(0, min(x, matrix.width))
        let y0 = max(0, min(y, matrix.height))
        let x1 = max(0, min(x0 + w, matrix.width))
        let y1 = max(0, min(y0 + h, matrix.height))
        print("[GridAlignmentTests] DEBUG matrix \(label): x=\(x0)..<\(x1) y=\(y0)..<\(y1)")
        for yy in y0..<y1 {
            var row = ""
            row.reserveCapacity((x1 - x0) * 3)
            for xx in x0..<x1 {
                row += String(format: "%03d ", matrix.data[yy * matrix.width + xx])
            }
            print("  \(row)")
        }
    }
    #endif
}

