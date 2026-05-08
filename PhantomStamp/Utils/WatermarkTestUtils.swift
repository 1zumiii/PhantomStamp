//
//  WatermarkTestUtils.swift
//  PhantomStamp
//
//  Shared helpers for manual debug tests (non-XCTest).
//

import Foundation

enum WatermarkTestUtils {
    // MARK: - Numeric helpers

    static func approxEqual(_ a: Float, _ b: Float, eps: Float) -> Bool {
        abs(a - b) <= eps
    }

    static func errorMetrics(a: [Float], b: [Float]) -> (maxAbs: Float, mae: Float) {
        precondition(a.count == b.count)
        var maxAbs: Float = 0
        var sum: Float = 0
        for i in 0..<a.count {
            let d = abs(a[i] - b[i])
            maxAbs = max(maxAbs, d)
            sum += d
        }
        return (maxAbs, sum / Float(a.count))
    }

    // MARK: - Deterministic RNG

    struct SplitMix64 {
        var state: UInt64

        mutating func next() -> UInt64 {
            state &+= 0x9E3779B97F4A7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
            z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
            return z ^ (z >> 31)
        }

        mutating func nextUnitFloat() -> Float {
            let x = next() >> 40
            return Float(x) / Float(1 << 24) // [0, 1)
        }
    }

    static func makeDeterministicBlock(seed: UInt64) -> [Float] {
        var rng = SplitMix64(state: seed)
        var out = [Float]()
        out.reserveCapacity(Matrix8x8.elementCount)
        for _ in 0..<Matrix8x8.elementCount {
            out.append(rng.nextUnitFloat() * 255.0)
        }
        return out
    }
}

extension Int {
    func positiveMod(_ m: Int) -> Int {
        let r = self % m
        return r >= 0 ? r : (r + m)
    }
}

