//
//  StripsTests.swift
//  PhantomStamp
//
//  Manual / DEBUG validations for strip slicing + reassembly.
//

import Foundation

enum StripsTests {
    struct Report: Sendable {
        var sliceImagePassed: Bool
        var stripUpdateAndReassemblePassed: Bool
        var sliceImageCheckCount: Int
        var stripUpdateAndReassembleCheckCount: Int
    }

    static func runAll() -> Report {
        let service = WatermarkService()
        let sliceResult = validateSliceImage(service: service)
        let stripWriteBackResult = validateStripUpdateAndReassemble(service: service)
        return Report(
            sliceImagePassed: sliceResult.passed,
            stripUpdateAndReassemblePassed: stripWriteBackResult.passed,
            sliceImageCheckCount: sliceResult.checkCount,
            stripUpdateAndReassembleCheckCount: stripWriteBackResult.checkCount
        )
    }

    static func runAllAndPrint() {
        #if DEBUG
        let r = runAll()
        let passed = r.sliceImagePassed && r.stripUpdateAndReassemblePassed
        let status = passed ? "PASS" : "FAIL"
        print("[StripsTests] \(status) Slice / Reassemble")
        print("  - sliceImage:       \(r.sliceImagePassed ? "PASS" : "FAIL")  checks=\(r.sliceImageCheckCount)")
        print("  - strip write-back: \(r.stripUpdateAndReassemblePassed ? "PASS" : "FAIL")  checks=\(r.stripUpdateAndReassembleCheckCount)")
        #endif
    }

    private static func validateSliceImage(service: WatermarkService) -> (passed: Bool, checkCount: Int) {
        var m = Matrix(width: 19, height: 26, data: [])
        m.data = [UInt8](repeating: 0, count: m.width * m.height)

        for y in 0..<m.height {
            for x in 0..<m.width {
                m.data[y * m.width + x] = UInt8((y * m.width + x) % 251)
            }
        }

        let strips = service.sliceImage(m, heightPerStrip: 10) // safeStripHeight should round down to 8

        var checks = 0
        func check(_ cond: Bool) -> Bool { checks += 1; return cond }

        guard check(strips.count == 3) else { return (false, checks) }

        for (i, s) in strips.enumerated() {
            let expectedYOffset = i * 8
            guard check(s.width == 16) else { return (false, checks) }
            guard check(s.height == 8) else { return (false, checks) }
            guard check(s.globalXOffset == 0) else { return (false, checks) }
            guard check(s.globalYOffset == expectedYOffset) else { return (false, checks) }
            guard check(s.pixels.count == 16 * 8) else { return (false, checks) }
        }

        let sampleXs = [0, 7, 15]
        let sampleYsInStrip = [0, 3, 7]
        for s in strips {
            for sy in sampleYsInStrip {
                for sx in sampleXs {
                    let globalY = s.globalYOffset + sy
                    let expected = m.data[globalY * m.width + sx]
                    let actual = s.pixels[sy * s.width + sx]
                    guard check(actual == expected) else { return (false, checks) }
                }
            }
        }

        for s in strips {
            for sy in 0..<s.height {
                let globalY = s.globalYOffset + sy
                let expectedLast = m.data[globalY * m.width + 15]
                let actualLast = s.pixels[sy * s.width + 15]
                guard check(actualLast == expectedLast) else { return (false, checks) }
            }
        }

        return (true, checks)
    }

    private static func validateStripUpdateAndReassemble(service: WatermarkService) -> (passed: Bool, checkCount: Int) {
        var original = Matrix(width: 19, height: 26, data: [])
        original.data = [UInt8](repeating: 0, count: original.width * original.height)

        for y in 0..<original.height {
            for x in 0..<original.width {
                if y >= 24 {
                    original.data[y * original.width + x] = 241
                } else if x >= 16 {
                    original.data[y * original.width + x] = 240
                } else {
                    original.data[y * original.width + x] = UInt8((y * original.width + x) % 251)
                }
            }
        }

        let validWidth = (original.width / 8) * 8
        let validHeight = (original.height / 8) * 8

        var strips = service.sliceImage(original, heightPerStrip: 10)

        var checks = 0
        func check(_ cond: Bool) -> Bool { checks += 1; return cond }

        guard check(strips.count == validHeight / 8) else { return (false, checks) }

        let processed = strips.enumerated().map { (i, s) -> ImageStrip in
            var out = s
            let marker = UInt8(10 + i)
            out.pixels = [UInt8](repeating: marker, count: s.width * s.height)
            return out
        }.reversed()

        for p in processed { service.updateStripInPlace(&strips, with: p) }

        var reassembled = original
        service.reassembleStrips(strips, into: &reassembled)

        for (i, s) in strips.enumerated() {
            let expected = UInt8(10 + i)
            let samplePoints = [(x: 0, y: 0), (x: 7, y: 3), (x: validWidth - 1, y: 7)]
            for sp in samplePoints {
                let globalY = s.globalYOffset + sp.y
                let idx = globalY * reassembled.width + sp.x
                guard check(reassembled.data[idx] == expected) else { return (false, checks) }
            }
        }

        if validWidth < original.width {
            for y in 0..<validHeight {
                for x in validWidth..<original.width {
                    let idx = y * original.width + x
                    guard check(reassembled.data[idx] == 240) else { return (false, checks) }
                }
            }
        }

        if validHeight < original.height {
            for y in validHeight..<original.height {
                for x in 0..<original.width {
                    let idx = y * original.width + x
                    guard check(reassembled.data[idx] == 241) else { return (false, checks) }
                }
            }
        }

        return (true, checks)
    }
}

