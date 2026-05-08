//
//  WatermarkService.swift
//  PhantomStamp
//

import UIKit
import Accelerate

class WatermarkService: WatermarkServiceProtocol {
    
    // ==========================================
    // Embedding Watermark
    // ==========================================
    func embedWatermark(into image: UIImage, text: String) async throws -> UIImage {
        
        debugTestDataLayer()
        
        // Internal helper method to report progress
        func reportProgress(step: AppConstants.WatermarkStep, percentage: Double) {
            let clamped = min(max(percentage, 0), 1)
            let payload = ProgressPayload(step: step, percentage: clamped)
            NotificationCenter.default.post(
                name: AppConstants.Notifications.watermarkProgress,
                object: nil,
                userInfo: ["payload": payload]
            )
        }
        

        // Overall budget (must sum to 1.0): strip work dominates CPU time.
        let prepEnd = 0.10          // 10% — validation + payload / macroblock
        let colorEnd = 0.18         // 8% — YCbCr + slicing
        let stripsEnd = 0.90        // 72% — concurrent strip embedding (largest share)
        // remaining 10% — reassemble Y + RGB rebuild
        
        // ==========================================
        // Step 1: Data preparation → [0, prepEnd]
        // ==========================================
        reportProgress(step: .preparation, percentage: 0)
        let minSize: CGFloat = 128.0
        if image.size.width < minSize || image.size.height < minSize {
            throw WatermarkError.imageTooSmall
        }
        reportProgress(step: .preparation, percentage: prepEnd * 0.35)

        // Convert the text to binary and apply Forward Error Correction (FEC)
        let eccBits = encodeFEC(text: text)
        reportProgress(step: .preparation, percentage: prepEnd * 0.65)

        // Concatenate the sync header, and form a complete single watermark period
        let syncBits = getSyncMarkerBits()
        let payloadBits = syncBits + eccBits
        // Convert the one-dimensional data stream to a two-dimensional macroblock (to prevent raster断裂问题)
        let macroblock = build2DTile(from: payloadBits)
        reportProgress(step: .preparation, percentage: prepEnd)

        // ==========================================
        // Step 2: Color / layout → (prepEnd, colorEnd]
        // ==========================================
        reportProgress(step: .colorConversion, percentage: prepEnd)
        guard var ycbcrImage = convertToYCbCr(image: image) else {
            throw WatermarkError.processingError
        }
        let yChannel = ycbcrImage.Y
        reportProgress(step: .colorConversion, percentage: prepEnd + (colorEnd - prepEnd) * 0.55)

        // slice the Y channel into multiple strips (the height must be a multiple of 8)
        let stripHeight = 80
        var imageStrips = sliceImage(yChannel, heightPerStrip: stripHeight)
        reportProgress(step: .colorConversion, percentage: colorEnd)

        // ==========================================
        // Step 3: Strip processing → (colorEnd, stripsEnd]  (main cost)
        // ==========================================
        let stripSpan = stripsEnd - colorEnd
        reportProgress(step: .processingStrips, percentage: colorEnd)

        let stripCount = imageStrips.count
        try await withThrowingTaskGroup(of: ImageStrip.self) { group in
            for strip in imageStrips {
                group.addTask {
                    // force memory recycling to prevent OOM silent crash caused by large image slicing computation
                    autoreleasepool {
                        self.processSingleStripForEmbedding(strip: strip, macroblock: macroblock)
                    }
                }
            }

            var completedStrips = 0
            for try await processedStrip in group {
                // TODO: 根据条带的全局坐标，将其写回总的 Y 通道矩阵结构中
                updateStripInPlace(&imageStrips, with: processedStrip)
                completedStrips += 1
                if stripCount > 0 {
                    let t = colorEnd + stripSpan * Double(completedStrips) / Double(stripCount)
                    reportProgress(step: .processingStrips, percentage: t)
                }
            }
        }
        reportProgress(step: .processingStrips, percentage: stripsEnd)

        // ==========================================
        // Step 4: Reassemble → (stripsEnd, 1.0]
        // ==========================================
        reportProgress(step: .reassembling, percentage: stripsEnd)
        
        // overwrite the processed strips back to the original Y channel matrix.
        // the extra 1~7 pixels on the right side and bottom of the original matrix will be kept intact, and not be destroyed.
        reassembleStrips(imageStrips, into: &ycbcrImage.Y)
        
        reportProgress(step: .reassembling, percentage: stripsEnd + (1 - stripsEnd) * 0.55)

        guard let finalImage = convertToUIImage(from: ycbcrImage) else {
            throw WatermarkError.processingError
        }
        reportProgress(step: .reassembling, percentage: 1)

        return finalImage
    }
    
    // ==========================================
    // Extract Watermark
    // ==========================================
    func extractWatermark(from image: UIImage) async throws -> String {
        // 1. image preprocessing
        guard let ycbcrImage = convertToYCbCr(image: image) else {
            throw WatermarkError.processingError
        }
        let yChannel = ycbcrImage.Y
        
        // 2. physical and logical alignment (to handle translation and cropping attacks)
        // TODO: execute 64 grid offset scans, and use sliding window to find the sync header
        guard let gridOffset = findGridOffsetAndSyncMarker(in: yChannel) else {
            throw WatermarkError.extractFailed
        }
        
        // 3. data extraction
        // TODO: based on the exact grid base point found, extract the bit stream in all 8x8 blocks of the entire image
        let rawExtractedBits = extractBitsWithOffset(yChannel, offset: gridOffset)
        
        // 4. data recovery and decoding
        // TODO: merge redundant data through majority voting (Majority Voting)
        let votedBits = applyMajorityVoting(to: rawExtractedBits)
        
        // TODO: remove the sync header, and send the pure data to the FEC decoder for error correction
        guard let correctedText = decodeFEC(bits: votedBits) else {
            throw WatermarkError.extractFailed
        }
        
        return correctedText
    }
    
    func debugTestDataLayer() {
        let originalText = "hello"
        
        let fecBits = encodeFEC(text: originalText)
        let decodedText = decodeFEC(bits: fecBits)
        
        print("Original:", originalText)
        print("FEC bit count:", fecBits.count)
        print("Decoded:", decodedText ?? "nil")
        
        let sync = getSyncMarkerBits()
        let tile = build2DTile(from: sync + fecBits)
        
        print("Sync bit count:", sync.count)
        print("Tile bit count:", tile.bits.count)
        
        let tileStartsWithSync = Array(tile.bits.prefix(sync.count)) == sync
        print("Tile starts with sync:", tileStartsWithSync)
        
        let extractedPayload = Array(tile.bits.dropFirst(sync.count))
        let decodedFromTile = decodeFEC(bits: extractedPayload)
        
        print("Decoded from tile:", decodedFromTile ?? "nil")
    }
}
