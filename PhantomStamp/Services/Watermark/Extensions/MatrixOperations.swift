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
        // Population variance: Var(X) = E[X^2] - (E[X])^2
        // Using vDSP primitives avoids scalar loops and vectorizes well.
        var mean: Float = 0
        var meanSquare: Float = 0
        let length = vDSP_Length(Matrix8x8.elementCount)

        block.values.withUnsafeBufferPointer { ptr in
            guard let base = ptr.baseAddress else { return }
            vDSP_meanv(base, 1, &mean, length)
            vDSP_measqv(base, 1, &meanSquare, length)
        }

        let variance = meanSquare - (mean * mean)
        // Protect against tiny negative values from floating-point cancellation.
        return max(0, variance)
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
    private static let lengthN = vDSP_Length(n)

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
        // Use stack-backed temporary storage to avoid per-block heap allocations.
        withUnsafeTemporaryAllocation(of: Float.self, capacity: Matrix8x8.elementCount) { tempBuf in
            withUnsafeTemporaryAllocation(of: Float.self, capacity: Matrix8x8.elementCount) { outBuf in
                let tempPtr = tempBuf.baseAddress!
                let outPtr = outBuf.baseAddress!

                basisC.withUnsafeBufferPointer { c in
                    matrix.withUnsafeBufferPointer { x in
                        vDSP_mmul(
                            c.baseAddress!, 1,
                            x.baseAddress!, 1,
                            tempPtr, 1,
                            lengthN, lengthN, lengthN
                        )
                    }
                }

                basisCT.withUnsafeBufferPointer { ct in
                    vDSP_mmul(
                        tempPtr, 1,
                        ct.baseAddress!, 1,
                        outPtr, 1,
                        lengthN, lengthN, lengthN
                    )
                }

                matrix.withUnsafeMutableBufferPointer { dst in
                    dst.baseAddress!.assign(from: outPtr, count: Matrix8x8.elementCount)
                }
            }
        }
    }

    static func apply2DIDCTInPlace(_ matrix: inout [Float]) {
        precondition(matrix.count == Matrix8x8.elementCount)
        // X = C^T * F * C   (since C is orthonormal)
        // Use stack-backed temporary storage to avoid per-block heap allocations.
        withUnsafeTemporaryAllocation(of: Float.self, capacity: Matrix8x8.elementCount) { tempBuf in
            withUnsafeTemporaryAllocation(of: Float.self, capacity: Matrix8x8.elementCount) { outBuf in
                let tempPtr = tempBuf.baseAddress!
                let outPtr = outBuf.baseAddress!

                basisCT.withUnsafeBufferPointer { ct in
                    matrix.withUnsafeBufferPointer { f in
                        vDSP_mmul(
                            ct.baseAddress!, 1,
                            f.baseAddress!, 1,
                            tempPtr, 1,
                            lengthN, lengthN, lengthN
                        )
                    }
                }

                basisC.withUnsafeBufferPointer { c in
                    vDSP_mmul(
                        tempPtr, 1,
                        c.baseAddress!, 1,
                        outPtr, 1,
                        lengthN, lengthN, lengthN
                    )
                }

                matrix.withUnsafeMutableBufferPointer { dst in
                    dst.baseAddress!.assign(from: outPtr, count: Matrix8x8.elementCount)
                }
            }
        }
    }
}
