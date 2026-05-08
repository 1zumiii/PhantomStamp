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
    
    /// Slices an image into strips of a specified height.
    ///
    /// - Parameters:
    ///   - channel: The image to slice.
    ///   - heightPerStrip: The height of each strip.
    /// - Returns: An array of image strips.
    func sliceImage(_ channel: Matrix, heightPerStrip: Int) -> [ImageStrip] {
        // 1. set the valid width and height, and ensure the heightPerStrip is a multiple of 8
        let validWidth = (channel.width / Matrix8x8.side) * Matrix8x8.side
        let validHeight = (channel.height / Matrix8x8.side) * Matrix8x8.side
        
        // if the image is less than 8x8, return empty
        guard validWidth >= 8, validHeight >= 8 else { return [] }
        
        // ensure the heightPerStrip is a multiple of 8, otherwise round down to the nearest multiple of 8
        let safeStripHeight = (heightPerStrip / Matrix8x8.side) * Matrix8x8.side
        guard safeStripHeight >= 8 else { return [] }
        
        var strips: [ImageStrip] = []
        var currentY = 0
        
        // 2. only slice in the valid height validHeight
        while currentY < validHeight {
            // calculate the actual height of the current strip (the last strip may be less than safeStripHeight)
            let actualStripHeight = min(safeStripHeight, validHeight - currentY)
            
            var strip = ImageStrip()
            strip.width = validWidth
            strip.height = actualStripHeight
            strip.globalXOffset = 0
            strip.globalYOffset = currentY
            
            // pre-allocate the memory for the strip
            var stripPixels = [UInt8](repeating: 0, count: validWidth * actualStripHeight)
            
            // 3. copy the original image data to the strip
            stripPixels.withUnsafeMutableBufferPointer { stripPtr in
                channel.data.withUnsafeBufferPointer { channelPtr in
                    guard let dstBase = stripPtr.baseAddress, let srcBase = channelPtr.baseAddress else { return }
                    for row in 0..<actualStripHeight {
                        // note: when reading from the original image, the step is channel.width
                        let srcRowStart = (currentY + row) * channel.width
                        // when writing to the strip, the step is validWidth
                        let dstRowStart = row * validWidth
                        
                        // only copy the validWidth length, the extra 1~7 pixels on the right side of the original image are perfectly discarded
                        dstBase.advanced(by: dstRowStart).update(from: srcBase.advanced(by: srcRowStart), count: validWidth)
                    }
                }
            }
            
            strip.pixels = stripPixels
            strips.append(strip)
            
            currentY += actualStripHeight
        }
        
        return strips
    }
    
    /// overwrite the processed strip back to the original strips array.
    /// the extra 1~7 pixels on the right side and bottom of the original matrix will be kept intact, and not be destroyed.
    func updateStripInPlace(_ strips: inout [ImageStrip], with processedStrip: ImageStrip) {
        // find the strip in the original array by the globalYOffset, and replace the memory directly
        if let index = strips.firstIndex(where: { $0.globalYOffset == processedStrip.globalYOffset }) {
            strips[index] = processedStrip
        }
    }
    
    /// overwrite the processed strips back to the original Y channel matrix.
    /// the extra 1~7 pixels on the right side and bottom of the original matrix will be kept intact, and not be destroyed.
    func reassembleStrips(_ strips: [ImageStrip], into originalMatrix: inout Matrix) {
        let originalWidth = originalMatrix.width
        
        // use pointer to skip the Swift array out-of-bounds check, and maximize the loop performance
        originalMatrix.data.withUnsafeMutableBufferPointer { matrixPtr in
            for strip in strips {
                let stripWidth = strip.width
                let stripHeight = strip.height
                let startY = strip.globalYOffset
                
                strip.pixels.withUnsafeBufferPointer { stripPtr in
                    for row in 0..<stripHeight {
                        let dstRowStart = (startY + row) * originalWidth
                        let srcRowStart = row * stripWidth
                        
                        for col in 0..<stripWidth {
                            matrixPtr[dstRowStart + col] = stripPtr[srcRowStart + col]
                        }
                    }
                }
            }
        }
    }
    
    /// find the grid offset and sync marker in the matrix.
    /// the grid offset is the starting point of the sync marker.
    /// the sync marker is the sequence of bits that indicates the start of the watermark data.
    func findGridOffsetAndSyncMarker(in matrix: Matrix) -> CGPoint? {
        let syncMarker = getSyncMarkerBits()
        let tolerance = 4 // tolerance: allow up to 4 mismatches in 32 bits (to resist JPEG compression-induced noise)
        
        // to ensure we can slide and find at least one complete sync header, we define a search area.
        // extract up to 30x30 macroblocks (240x240 pixels) in the top-left corner for verification, enough to cover all W cases, avoid performance explosion by extracting the entire image 64 times.
        let searchBlockLimit = 30
        
        // Return the globally best match across all 64 pixel offsets.
        // Returning the first hit is fragile because local noise can satisfy the tolerance threshold early.
        var bestMatchCount = -1
        var bestOffset: CGPoint?
        #if DEBUG
        var bestDetails: (offsetX: Int, offsetY: Int, bx: Int, by: Int, w: Int) = (0, 0, 0, 0, 0)
        #endif
        
        // 1. pixel-level scan: 64 physical offset scans
        for offsetY in 0..<Matrix8x8.side {
            for offsetX in 0..<Matrix8x8.side {
                
                let maxRows = min(searchBlockLimit, (matrix.height - offsetY) / Matrix8x8.side)
                let maxCols = min(searchBlockLimit, (matrix.width - offsetX) / Matrix8x8.side)
                
                // if the minimum number of blocks is not enough, it means the image is too small or at the edge, skip directly
                if maxRows < 4 || maxCols < 8 { continue }
                
                // core optimization: pre-batch extract the bits under the current offset, avoid repeating the heavy DCT computation in the sliding window enumeration
                var bitGrid = [[Int]](repeating: [Int](repeating: 0, count: maxCols), count: maxRows)
                for r in 0..<maxRows {
                    for c in 0..<maxCols {
                        let block = extractSpatialBlock(from: matrix, x: offsetX + c * Matrix8x8.side, y: offsetY + r * Matrix8x8.side)
                        let freqBlock = performDCT(block)
                        bitGrid[r][c] = extractBitFromFrequencies(freqBlock)
                    }
                }
                
                // 2. block-level sliding window: find the starting point of the macroblock that is cut off (bx, by)
                for by in 0..<maxRows {
                    for bx in 0..<maxCols {
                        
                        // 3. enumerate possible macroblock side lengths W
                        // because the payload maximum is 16 bytes, plus FEC and sync header, the calculated side length W must fall between 8 and 18
                        for w in 8...18 {
                            // calculate the extreme row and column positions to read 32 bits under the current W, to prevent array out of bounds
                            let maxRowNeeded = by + (32 / w) + 1
                            let maxColNeeded = bx + min(32, w)
                            
                            if maxRowNeeded > maxRows || maxColNeeded > maxCols {
                                continue
                            }
                            
                            var matchCount = 0
                            for i in 0..<32 {
                                let r = by + (i / w)
                                let c = bx + (i % w)
                                if bitGrid[r][c] == syncMarker[i] {
                                    matchCount += 1
                                }
                            }
                            
                            if matchCount > bestMatchCount {
                                bestMatchCount = matchCount
                                bestOffset = CGPoint(x: offsetX, y: offsetY)
                                #if DEBUG
                                bestDetails = (offsetX, offsetY, bx, by, w)
                                #endif
                            }
                            
                            // Perfect hit: safe early-exit.
                            if matchCount == 32 {
                                #if DEBUG
                                print("[WatermarkService] DEBUG gridOffset best=32/32 offset=(\(offsetX),\(offsetY)) bx=\(bx) by=\(by) w=\(w)")
                                #endif
                                return CGPoint(x: offsetX, y: offsetY)
                            }
                        }
                    }
                }
            }
        }
        
        if bestMatchCount >= (32 - tolerance), let bestOffset {
            #if DEBUG
            print("[WatermarkService] DEBUG gridOffset best=\(bestMatchCount)/32 offset=(\(bestDetails.offsetX),\(bestDetails.offsetY)) bx=\(bestDetails.bx) by=\(bestDetails.by) w=\(bestDetails.w)")
            #endif
            return bestOffset
        }
        
        #if DEBUG
        if let bestOffset {
            print("[WatermarkService] DEBUG gridOffset no-hit best=\(bestMatchCount)/32 offset=(\(Int(bestOffset.x)),\(Int(bestOffset.y)))")
        } else {
            print("[WatermarkService] DEBUG gridOffset no-hit best=<none>")
        }
        #endif
        return nil
    }

    // MARK: - Helper

    /// extract the 8x8 spatial domain block from the global Y channel matrix based on the absolute coordinates
    private func extractSpatialBlock(from matrix: Matrix, x: Int, y: Int) -> Matrix8x8 {
        var block = Matrix8x8()
        matrix.data.withUnsafeBufferPointer { ptr in
            block.values.withUnsafeMutableBufferPointer { blockPtr in
                for row in 0..<Matrix8x8.side {
                    let srcStart = (y + row) * matrix.width + x
                    let dstStart = row * Matrix8x8.side
                    for col in 0..<Matrix8x8.side {
                        blockPtr[dstStart + col] = Float(ptr[srcStart + col])
                    }
                }
            }
        }
        return block
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
                    dst.baseAddress!.update(from: outPtr, count: Matrix8x8.elementCount)
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
                    dst.baseAddress!.update(from: outPtr, count: Matrix8x8.elementCount)
                }
            }
        }
    }
}
