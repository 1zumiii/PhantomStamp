//
//  WatermarkService.swift
//  PhantomStamp
//

import UIKit
import Accelerate

class WatermarkService: WatermarkServiceProtocol {
    private func awaitPerFileProgressDrain(current: Int, timeoutSeconds: Double = 60.0) async -> Bool {
        // If the overlay isn't listening (e.g. tests or headless runs), don't block forever.
        let deadlineNs = UInt64(timeoutSeconds * 1_000_000_000)

        return await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                // `AppConstants.Notifications` may be main-actor isolated under Swift 6 default isolation.
                let name = await MainActor.run { AppConstants.Notifications.watermarkPerFileProgressDidDrain }
                let stream = NotificationCenter.default.notifications(
                    named: name,
                    object: nil
                )
                for await n in stream {
                    guard let payload = n.userInfo?["payload"] as? PerFileProgressDrainPayload else { continue }
                    if payload.current == current {
                        return true
                    }
                }
                return false
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: deadlineNs)
                return false
            }
            let first = await group.next() ?? false
            group.cancelAll()
            return first
        }
    }
    
    // ==========================================
    // Embedding Watermark
    // ==========================================
    func embedWatermark(into image: UIImage, text: String) async throws -> UIImage {
        try await embedWatermark(into: image, text: text, shouldHideProgressbar: true)
    }

    /// Embed watermark into a single image.
    /// - Parameter shouldHideProgressbar: If false, the overlay will stay visible (useful for multi-file sequential processing).
    func embedWatermark(into image: UIImage, text: String, shouldHideProgressbar: Bool = true) async throws -> UIImage {
        #if DEBUG
        // Debug-only: prints internal data-layer checks. Disable by default to avoid noisy logs in demos.
        // debugTestDataLayer()
        #endif
        
        if shouldHideProgressbar {
            NotificationCenter.default.post(name: AppConstants.Notifications.watermarkProgressOverlayDidStart, object: nil)
        }

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
        

        // Progress budget (roughly sums to 1.0).
        //
        // Empirically on large images, the "reassemble + RGB rebuild" stage can dominate,
        // so we reserve a meaningful slice of the bar for it to avoid the UI looking "stuck".
        let prepEnd = 0.10          // validation + payload / macroblock
        let colorEnd = 0.20         // YCbCr + slicing
        let stripsEnd = 0.70        // concurrent strip embedding
        // remaining 30% — reassemble Y + RGB rebuild
        
        do {
            // ==========================================
            // Step 1: Prepare payload + build 2D tile → [0, prepEnd]
            // ==========================================
            reportProgress(step: .preparation, percentage: 0)
            let minSize: CGFloat = 128.0
            if image.size.width < minSize || image.size.height < minSize {
                throw WatermarkError.imageTooSmall
            }
            reportProgress(step: .preparation, percentage: prepEnd * 0.20)

            // Convert the text to binary and apply Forward Error Correction (FEC)
            reportProgress(step: .fecEncoding, percentage: prepEnd * 0.35)
            let eccBits = encodeFEC(text: text)
            reportProgress(step: .fecEncoding, percentage: prepEnd * 0.55)

            // Concatenate the sync header, and form a complete single watermark period
            let syncBits = getSyncMarkerBits()
            let payloadBits = syncBits + eccBits
            reportProgress(step: .macroblockBuild, percentage: prepEnd * 0.80)
            // Convert the one-dimensional data stream to a two-dimensional macroblock (to prevent raster断裂问题)
            let macroblock = build2DTile(from: payloadBits)
            reportProgress(step: .macroblockBuild, percentage: prepEnd)

            // ==========================================
            // Step 2: Color / layout → (prepEnd, colorEnd]
            // ==========================================
            reportProgress(step: .colorConversion, percentage: prepEnd)
            // `convertToYCbCr` can take a long time on large images. Without an intermediate tick, the UI may
            // appear to "start" around ~14–15% (next post after Y is ready) because the bar never paints 10%.
            let colorMidDuringConvert = prepEnd + (colorEnd - prepEnd) * 0.22
            reportProgress(step: .colorConversion, percentage: colorMidDuringConvert)
            guard var ycbcrImage = convertToYCbCr(image: image) else {
                #if DEBUG
                let pxW = Int(image.size.width * image.scale)
                let pxH = Int(image.size.height * image.scale)
                print("[WatermarkService] convertToYCbCr failed (image=\(pxW)x\(pxH)px scale=\(image.scale) orientation=\(image.imageOrientation.rawValue))")
                #endif
                throw WatermarkError.processingError
            }
            let yChannel = ycbcrImage.Y
            reportProgress(step: .colorConversion, percentage: prepEnd + (colorEnd - prepEnd) * 0.45)

            // slice the Y channel into multiple strips (the height must be a multiple of 8)
            let stripHeight = 80
            var imageStrips = sliceImage(yChannel, heightPerStrip: stripHeight)
            reportProgress(step: .stripSlicing, percentage: colorEnd)

            // ==========================================
            // Step 3: Strip processing → (colorEnd, stripsEnd]
            // ==========================================
            let stripSpan = stripsEnd - colorEnd
            reportProgress(step: .processingStrips, percentage: colorEnd)

            let stripCount = imageStrips.count
            try await withThrowingTaskGroup(of: ImageStrip.self) { group in
                for strip in imageStrips {
                    group.addTask {
                        await MainActor.run {
                            autoreleasepool {
                                self.processSingleStripForEmbedding(strip: strip, macroblock: macroblock)
                            }
                        }
                    }
                }

                var completedStrips = 0
                for try await processedStrip in group {
                    // overwrite the processed strip back to the original strips array (located by `globalYOffset`).
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
            reportProgress(step: .reassembling, percentage: stripsEnd + (1 - stripsEnd) * 0.18)
            reassembleStrips(imageStrips, into: &ycbcrImage.Y)
            reportProgress(step: .reassembling, percentage: stripsEnd + (1 - stripsEnd) * 0.52)
            
            // Final color conversion back to UIImage.
            reportProgress(step: .rgbRebuild, percentage: stripsEnd + (1 - stripsEnd) * 0.72)

            guard let finalImage = convertToUIImage(from: ycbcrImage) else {
                #if DEBUG
                print("[WatermarkService] convertToUIImage failed (Y=\(ycbcrImage.Y.width)x\(ycbcrImage.Y.height), Cb=\(ycbcrImage.Cb.width)x\(ycbcrImage.Cb.height), Cr=\(ycbcrImage.Cr.width)x\(ycbcrImage.Cr.height))")
                #endif
                throw WatermarkError.processingError
            }
            reportProgress(step: .reassembling, percentage: 1)

            if shouldHideProgressbar {
                NotificationCenter.default.post(name: AppConstants.Notifications.watermarkProgressOverlayDidEnd, object: nil)
            }
            return finalImage
        } catch {
            if shouldHideProgressbar {
                NotificationCenter.default.post(name: AppConstants.Notifications.watermarkProgressOverlayDidEnd, object: nil)
            }
            throw error
        }
    }
    
    // ==========================================
    // Extract Watermark
    // ==========================================
    func extractWatermark(from image: UIImage) async throws -> String {
        try await extractWatermark(from: image, shouldHideProgressbar: true)
    }

    /// Extract watermark from a single image.
    /// - Parameter shouldHideProgressbar: If false, the overlay will stay visible (useful for multi-file sequential processing).
    func extractWatermark(from image: UIImage, shouldHideProgressbar: Bool = true) async throws -> String {
        if shouldHideProgressbar {
            NotificationCenter.default.post(name: AppConstants.Notifications.watermarkProgressOverlayDidStart, object: nil)
        }

        func reportProgress(step: AppConstants.WatermarkStep, percentage: Double) {
            let clamped = min(max(percentage, 0), 1)
            let payload = ProgressPayload(step: step, percentage: clamped)
            NotificationCenter.default.post(
                name: AppConstants.Notifications.watermarkProgress,
                object: nil,
                userInfo: ["payload": payload]
            )
        }

        do {
            reportProgress(step: .preparation, percentage: 0)
            // Same issue as embedding: the first heavy step is YCbCr conversion. If we only report 0 and then
            // jump straight to ~18%, single-file runs look like the bar starts "in the middle".
            reportProgress(step: .preparation, percentage: 0.06)

        // 1. image preprocessing
        guard let ycbcrImage = convertToYCbCr(image: image) else {
            throw WatermarkError.processingError
        }
        let yChannel = ycbcrImage.Y
            reportProgress(step: .colorConversion, percentage: 0.12)
        
        // 2. physical and logical alignment (to handle translation and cropping attacks)
        // execute 64 grid offset scans, and use sliding window to find the sync header
        guard let gridOffset = findGridOffsetAndSyncMarker(in: yChannel) else {
            throw WatermarkError.extractFailed
        }
            reportProgress(step: .processingStrips, percentage: 0.55)
        
        // 3. data extraction
        // based on the exact grid base point found, extract the bit stream in all 8x8 blocks of the entire image
        let rawExtractedBits = extractBitsWithOffset(yChannel, offset: gridOffset)
            reportProgress(step: .processingStrips, percentage: 0.72)
        
        // 4. data recovery and decoding
        // merge redundant data through majority voting (Majority Voting)
        let votedBits = applyMajorityVoting(to: rawExtractedBits)
            reportProgress(step: .reassembling, percentage: 0.85)

        #if DEBUG
        let rows = rawExtractedBits.count
        let cols = rawExtractedBits.first?.count ?? 0
        print("[WatermarkService] DEBUG extract: gridOffset=(\(Int(gridOffset.x)),\(Int(gridOffset.y))) rawBits=\(rows)x\(cols) votedBits=\(votedBits.count)")
        #endif
        
        // remove the sync header, and send the pure data to the FEC decoder for error correction
        let syncCount = getSyncMarkerBits().count
        let payloadBits = votedBits.count >= syncCount ? Array(votedBits.dropFirst(syncCount)) : []

        #if DEBUG
        if !payloadBits.isEmpty {
            func bitsToByteLocal(_ bits: [Int]) -> Int {
                var v = 0
                for b in bits.prefix(8) { v = (v << 1) | (b & 1) }
                return v
            }
            let lenByte = payloadBits.count >= 8 ? bitsToByteLocal(Array(payloadBits.prefix(8))) : -1
            let payloadPreview = payloadBits.prefix(24).map(String.init).joined()
            print("[WatermarkService] DEBUG extract: syncCount=\(syncCount) payloadBits=\(payloadBits.count) lenByte(raw)=\(lenByte) payloadPreview=\(payloadPreview)")
        } else {
            print("[WatermarkService] DEBUG extract: payloadBits empty (votedBits too short)")
        }
        #endif
        // Decode FEC with length-guessed truncation.
        // Reason:
        // `payloadBits` comes from a `w*w` macro-tile, which can contain padding zeros beyond the real eccBits.
        // Feeding those extra bits into Hamming84 decode can introduce additional erroneous codewords and
        // cause decodeFEC to fail.
        func eccBitCount(messageLengthBytes: Int) -> Int {
            let rawBits = 8 + messageLengthBytes * 8
            let paddedRaw = ((rawBits + 3) / 4) * 4
            let codewordBits = (paddedRaw / 4) * 8
            return codewordBits
        }

        for lenGuess in 1...16 {
            let eccCount = eccBitCount(messageLengthBytes: lenGuess)
            guard payloadBits.count >= eccCount else { continue }
            let eccBits = Array(payloadBits.prefix(eccCount))
            if let correctedText = decodeFEC(bits: eccBits) {
                reportProgress(step: .reassembling, percentage: 1.0)
                if shouldHideProgressbar {
                    NotificationCenter.default.post(name: AppConstants.Notifications.watermarkProgressOverlayDidEnd, object: nil)
                }
                return correctedText
            }
        }

        throw WatermarkError.extractFailed
        } catch {
            if shouldHideProgressbar {
                NotificationCenter.default.post(name: AppConstants.Notifications.watermarkProgressOverlayDidEnd, object: nil)
            }
            throw error
        }
    }

    // ==========================================
    // Multi-file (sequential) APIs
    // ==========================================

    /// Sequentially embed watermark into multiple images (no outer concurrency).
    func embedWatermark(into images: [UIImage], text: String) async throws -> [UIImage] {
        NotificationCenter.default.post(name: AppConstants.Notifications.watermarkProgressOverlayDidStart, object: nil)
        NotificationCenter.default.post(
            name: AppConstants.Notifications.watermarkBatchProgress,
            object: nil,
            userInfo: ["payload": BatchProgressPayload(completed: 0, total: images.count, current: 0)]
        )

        var outputs: [UIImage] = []
        outputs.reserveCapacity(images.count)

        do {
            for (idx, img) in images.enumerated() {
                NotificationCenter.default.post(
                    name: AppConstants.Notifications.watermarkBatchProgress,
                    object: nil,
                    userInfo: ["payload": BatchProgressPayload(completed: idx, total: images.count, current: idx)]
                )
                let watermarked = try await embedWatermark(into: img, text: text, shouldHideProgressbar: false)
                outputs.append(watermarked)
                // Pace batch: wait until the per-file progress bar is fully displayed.
                _ = await awaitPerFileProgressDrain(current: idx)
                NotificationCenter.default.post(
                    name: AppConstants.Notifications.watermarkBatchProgress,
                    object: nil,
                    userInfo: ["payload": BatchProgressPayload(completed: idx + 1, total: images.count, current: idx + 1)]
                )
            }

            NotificationCenter.default.post(name: AppConstants.Notifications.watermarkProgressOverlayDidEnd, object: nil)
            return outputs
        } catch {
            NotificationCenter.default.post(name: AppConstants.Notifications.watermarkProgressOverlayDidEnd, object: nil)
            throw error
        }
    }

    /// Sequentially extract watermark from multiple images (no outer concurrency).
    func extractWatermark(from images: [UIImage]) async throws -> [String] {
        NotificationCenter.default.post(name: AppConstants.Notifications.watermarkProgressOverlayDidStart, object: nil)
        NotificationCenter.default.post(
            name: AppConstants.Notifications.watermarkBatchProgress,
            object: nil,
            userInfo: ["payload": BatchProgressPayload(completed: 0, total: images.count, current: 0)]
        )

        var outputs: [String] = []
        outputs.reserveCapacity(images.count)

        do {
            for (idx, img) in images.enumerated() {
                NotificationCenter.default.post(
                    name: AppConstants.Notifications.watermarkBatchProgress,
                    object: nil,
                    userInfo: ["payload": BatchProgressPayload(completed: idx, total: images.count, current: idx)]
                )
                let extracted = try await extractWatermark(from: img, shouldHideProgressbar: false)
                outputs.append(extracted)
                _ = await awaitPerFileProgressDrain(current: idx)
                NotificationCenter.default.post(
                    name: AppConstants.Notifications.watermarkBatchProgress,
                    object: nil,
                    userInfo: ["payload": BatchProgressPayload(completed: idx + 1, total: images.count, current: idx + 1)]
                )
            }

            NotificationCenter.default.post(name: AppConstants.Notifications.watermarkProgressOverlayDidEnd, object: nil)
            return outputs
        } catch {
            NotificationCenter.default.post(name: AppConstants.Notifications.watermarkProgressOverlayDidEnd, object: nil)
            throw error
        }
    }

    /// Sequentially extract watermark from multiple images (best effort).
    /// - Returns: `[String?]` aligned with input order; failures produce `nil` but do not stop the batch.
    func extractWatermarkBestEffort(from images: [UIImage]) async -> [String?] {
        NotificationCenter.default.post(name: AppConstants.Notifications.watermarkProgressOverlayDidStart, object: nil)
        NotificationCenter.default.post(
            name: AppConstants.Notifications.watermarkBatchProgress,
            object: nil,
            userInfo: ["payload": BatchProgressPayload(completed: 0, total: images.count, current: 0)]
        )

        var outputs: [String?] = Array(repeating: nil, count: images.count)

        for (idx, img) in images.enumerated() {
            NotificationCenter.default.post(
                name: AppConstants.Notifications.watermarkBatchProgress,
                object: nil,
                userInfo: ["payload": BatchProgressPayload(completed: idx, total: images.count, current: idx)]
            )
            do {
                let extracted = try await extractWatermark(from: img, shouldHideProgressbar: false)
                outputs[idx] = extracted
            } catch {
                outputs[idx] = nil
            }
            _ = await awaitPerFileProgressDrain(current: idx)
            NotificationCenter.default.post(
                name: AppConstants.Notifications.watermarkBatchProgress,
                object: nil,
                userInfo: ["payload": BatchProgressPayload(completed: idx + 1, total: images.count, current: idx + 1)]
            )
        }

        NotificationCenter.default.post(name: AppConstants.Notifications.watermarkProgressOverlayDidEnd, object: nil)
        return outputs
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
