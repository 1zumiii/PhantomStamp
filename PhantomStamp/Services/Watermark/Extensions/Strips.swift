//
//  Strips.swift
//  PhantomStamp
//
//  Strip slicing + write-back/reassembly.
//

import Foundation

extension WatermarkService {
    /// Slices an image into strips of a specified height (height is rounded down to a multiple of 8).
    /// Extra pixels on the right/bottom that do not fit an 8×8 grid are discarded in the strips.
    func sliceImage(_ channel: Matrix, heightPerStrip: Int) -> [ImageStrip] {
        // We only process full 8×8 blocks. Any remainder (1..7 pixels) on right/bottom is left untouched
        // in the original matrix and never enters the watermark pipeline.
        let validWidth = (channel.width / Matrix8x8.side) * Matrix8x8.side
        let validHeight = (channel.height / Matrix8x8.side) * Matrix8x8.side
        guard validWidth >= 8, validHeight >= 8 else { return [] }

        // Strip height must also be 8-aligned to keep block iteration simple.
        let safeStripHeight = (heightPerStrip / Matrix8x8.side) * Matrix8x8.side
        guard safeStripHeight >= 8 else { return [] }

        var strips: [ImageStrip] = []
        var currentY = 0
        while currentY < validHeight {
            let actualStripHeight = min(safeStripHeight, validHeight - currentY)

            var strip = ImageStrip()
            strip.width = validWidth
            strip.height = actualStripHeight
            strip.globalXOffset = 0
            strip.globalYOffset = currentY

            var stripPixels = [UInt8](repeating: 0, count: validWidth * actualStripHeight)
            stripPixels.withUnsafeMutableBufferPointer { stripPtr in
                channel.data.withUnsafeBufferPointer { channelPtr in
                    guard let dstBase = stripPtr.baseAddress, let srcBase = channelPtr.baseAddress else { return }
                    for row in 0..<actualStripHeight {
                        let srcRowStart = (currentY + row) * channel.width
                        let dstRowStart = row * validWidth
                        // Copy only the validWidth region; right remainder is intentionally discarded here.
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

    /// Overwrite the processed strip back to the original strips array (located by `globalYOffset`).
    func updateStripInPlace(_ strips: inout [ImageStrip], with processedStrip: ImageStrip) {
        // TaskGroup returns strips out-of-order; use the global Y offset as the stable key.
        if let index = strips.firstIndex(where: { $0.globalYOffset == processedStrip.globalYOffset }) {
            strips[index] = processedStrip
        }
    }

    /// Overwrite the processed strips back to the original Y channel matrix.
    /// Extra pixels on the right/bottom that were not part of the 8×8 grid remain intact.
    func reassembleStrips(_ strips: [ImageStrip], into originalMatrix: inout Matrix) {
        // Only writes into the 8-aligned region covered by strips.
        // Anything outside (e.g. right/bottom remainder) remains as it was in the original.
        let originalWidth = originalMatrix.width
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
}

