//
//  MatrixOperations.swift
//  PhantomStamp
//
//  Created by Orion on 5/5/2026.
//

import Foundation
import UIKit
import Accelerate
extension WatermarkService{
    /// Computes the population variance of an 8×8 spatial block (Float samples).
    ///
    /// - Note: This uses population variance (divide by N=64), which is what we typically want
    ///   for block activity/energy heuristics in DSP pipelines.
    func calculateVariance(_ block: Matrix8x8) -> Float {
        let n = Float(Matrix8x8.elementCount)
        var mean: Float = 0
        for v in block.values {
            mean += v
        }
        mean /= n

        var sumSq: Float = 0
        for v in block.values {
            let d = v - mean
            sumSq += d * d
        }
        return sumSq / n
    }

    /// Performs an 8×8 2D DCT-II using Accelerate/vDSP.
    ///
    /// `vDSP.DCT` (1D) has length constraints and commonly refuses `count == 8`.
    /// To keep using Accelerate while supporting **exact 8×8 blocks**, we compute:
    ///
    /// \(F = C \cdot X \cdot C^T\)
    ///
    /// where `C` is the orthonormal 8×8 DCT-II basis matrix, and multiplications are
    /// performed by `vDSP_mmul` (vectorized / Accelerate-optimized).
    func performDCT(_ block: Matrix8x8) -> Matrix8x8 {
        var buf = block.values
        DCT8x8vDSP.apply2DDCTInPlace(&buf)
        return Matrix8x8(values: buf)
    }

    /// Performs an 8×8 2D IDCT (inverse of ``performDCT(_:)``) using Accelerate/vDSP.
    func performIDCT(_ freqBlock: Matrix8x8) -> Matrix8x8 {
        var buf = freqBlock.values
        DCT8x8vDSP.apply2DIDCTInPlace(&buf)

        return Matrix8x8(values: buf)
    }
}

// MARK: - vDSP-based 8×8 DCT/IDCT

private enum DCT8x8vDSP {
    private static let n = Matrix8x8.side

    /// Orthonormal 8×8 DCT-II basis matrix in row-major order.
    /// C[u,x] = alpha(u) * cos((2x+1)uπ / (2N)), with alpha(0)=sqrt(1/N), alpha(u>0)=sqrt(2/N)
    static let basisC: [Float] = {
        let nf = Float(n)
        let pi = Float.pi
        func alpha(_ u: Int) -> Float {
            u == 0 ? sqrt(1.0 / nf) : sqrt(2.0 / nf)
        }
        var c = [Float](repeating: 0, count: n * n)
        for u in 0..<n {
            for x in 0..<n {
                c[u * n + x] = alpha(u) * cos(((2.0 * Float(x) + 1.0) * Float(u) * pi) / (2.0 * nf))
            }
        }
        return c
    }()

    /// Transpose of the orthonormal basis (row-major).
    static let basisCT: [Float] = {
        var out = [Float](repeating: 0, count: n * n)
        basisC.withUnsafeBufferPointer { a in
            out.withUnsafeMutableBufferPointer { b in
                vDSP_mtrans(a.baseAddress!, 1, b.baseAddress!, 1, vDSP_Length(n), vDSP_Length(n))
            }
        }
        return out
    }()

    static func apply2DDCTInPlace(_ matrix: inout [Float]) {
        precondition(matrix.count == Matrix8x8.elementCount)
        // F = C * X * C^T
        // temp = C * X
        var temp = [Float](repeating: 0, count: n * n)
        basisC.withUnsafeBufferPointer { c in
            matrix.withUnsafeBufferPointer { x in
                temp.withUnsafeMutableBufferPointer { t in
                    vDSP_mmul(
                        c.baseAddress!, 1,
                        x.baseAddress!, 1,
                        t.baseAddress!, 1,
                        vDSP_Length(n), vDSP_Length(n), vDSP_Length(n)
                    )
                }
            }
        }

        // out = temp * C^T
        var out = [Float](repeating: 0, count: n * n)
        temp.withUnsafeBufferPointer { t in
            basisCT.withUnsafeBufferPointer { ct in
                out.withUnsafeMutableBufferPointer { o in
                    vDSP_mmul(
                        t.baseAddress!, 1,
                        ct.baseAddress!, 1,
                        o.baseAddress!, 1,
                        vDSP_Length(n), vDSP_Length(n), vDSP_Length(n)
                    )
                }
            }
        }
        matrix = out
    }

    static func apply2DIDCTInPlace(_ matrix: inout [Float]) {
        precondition(matrix.count == Matrix8x8.elementCount)
        // X = C^T * F * C   (since C is orthonormal)
        var temp = [Float](repeating: 0, count: n * n)
        basisCT.withUnsafeBufferPointer { ct in
            matrix.withUnsafeBufferPointer { f in
                temp.withUnsafeMutableBufferPointer { t in
                    vDSP_mmul(
                        ct.baseAddress!, 1,
                        f.baseAddress!, 1,
                        t.baseAddress!, 1,
                        vDSP_Length(n), vDSP_Length(n), vDSP_Length(n)
                    )
                }
            }
        }

        var out = [Float](repeating: 0, count: n * n)
        temp.withUnsafeBufferPointer { t in
            basisC.withUnsafeBufferPointer { c in
                out.withUnsafeMutableBufferPointer { o in
                    vDSP_mmul(
                        t.baseAddress!, 1,
                        c.baseAddress!, 1,
                        o.baseAddress!, 1,
                        vDSP_Length(n), vDSP_Length(n), vDSP_Length(n)
                    )
                }
            }
        }
        matrix = out
    }
}
