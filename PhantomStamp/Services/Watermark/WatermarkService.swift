//
//  WatermarkService.swift
//  PhantomStamp
//

import UIKit
import Accelerate
import SwiftData

class WatermarkService: WatermarkServiceProtocol {
    /// When set from the UI host (see `RootView.onAppear`), completed embed/extract attempts append a `WatermarkHistoryRecord`.
    var historyModelContext: ModelContext?

    /// When set from `RootView`, embed/extract honors notification + embed-history toggles in `UserSettingsStore`.
    weak var settingsStore: UserSettingsStore?

    /// When > 0, single-file embed/extract APIs suppress per-image local notifications; batch APIs send one summary at the end.
    private var batchUserNotificationDepth = 0

    private var shouldSuppressSingleOperationNotification: Bool {
        batchUserNotificationDepth > 0
    }

    /// Heavy-matrix extract phase: payload after sync strip, plus optional diagnostics for history UI.
    private struct ExtractMatrixWorkResult: Sendable {
        var payloadBitsWithoutSync: [Int]
        var offsetScanBestSyncBits: Int
        var gridOffsetX: Int?
        var gridOffsetY: Int?
        var rawBitGridRows: Int
        var rawBitGridCols: Int
        var majorityBestSyncBits: Int?
        var majorityMacroTileWidth: Int?
    }

    private func userAllowsWatermarkNotifications() async -> Bool {
        await MainActor.run {
            settingsStore?.watermarkOperationNotificationsEnabled ?? AppConstants.SettingsDefault.watermarkOperationNotifications
        }
    }

    private func userAllowsEmbedHistoryRecords() async -> Bool {
        await MainActor.run {
            settingsStore?.autoLogWatermarkEmbedToHistory ?? AppConstants.SettingsDefault.autoLogWatermarkEmbed
        }
    }

    /// Delivers `UserNotifications` only when the user enabled alerts in Settings (system authorization is still required inside the notification service).
    private func deliverWatermarkNotificationIfAllowed(_ work: () async -> Void) async {
        guard await userAllowsWatermarkNotifications() else { return }
        await work()
    }
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
        try await embedWatermark(into: image, text: text, sourceImageName: nil, shouldHideProgressbar: true)
    }

    func embedWatermark(into image: UIImage, text: String, sourceImageName: String?) async throws -> UIImage {
        try await embedWatermark(into: image, text: text, sourceImageName: sourceImageName, shouldHideProgressbar: true)
    }

    /// Embed watermark into a single image.
    /// - Parameter shouldHideProgressbar: If false, the overlay will stay visible (useful for multi-file sequential processing).
    func embedWatermark(into image: UIImage, text: String, shouldHideProgressbar: Bool = true) async throws -> UIImage {
        try await embedWatermark(into: image, text: text, sourceImageName: nil, shouldHideProgressbar: shouldHideProgressbar)
    }

    /// Embed watermark into a single image with source file name for history display.
    func embedWatermark(into image: UIImage, text: String, sourceImageName: String?, shouldHideProgressbar: Bool = true) async throws -> UIImage {
        #if DEBUG
        // Debug-only: prints internal data-layer checks. Disable by default to avoid noisy logs in demos.
        // debugTestDataLayer()
        #endif
        
        if shouldHideProgressbar {
            NotificationCenter.default.post(name: AppConstants.Notifications.watermarkProgressOverlayDidStart, object: nil)
        }
        
        let throttler = ProgressThrottler()
        
        func reportProgress(step: AppConstants.WatermarkStep, percentage: Double) {
            let clamped = min(max(percentage, 0), 1)
            
            guard throttler.shouldReport(clamped) else { return }
            
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

        let historyStarted = CFAbsoluteTimeGetCurrent()
        let thresholdSnapshot: Double = await MainActor.run {
            settingsStore?.textureVarianceThreshold ?? AppConstants.SettingsDefault.textureVarianceThreshold
        }

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
            // Convert the one-dimensional data stream to a two-dimensional macroblock (to prevent rasterization issues)
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

            let thresholdSmooth: Float = Float(thresholdSnapshot)

            let stripCount = imageStrips.count
            var embedVisited8x8Blocks = 0
            var embedSmoothSkipped8x8Blocks = 0
            try await withThrowingTaskGroup(of: (ImageStrip, Int, Int).self) { group in
                for strip in imageStrips {
                    group.addTask {
                        // force memory recycling to prevent OOM silent crash caused by large image slicing computation
                        autoreleasepool {
                            let out = self.processSingleStripForEmbedding(strip: strip, macroblock: macroblock, thresholdSmooth: thresholdSmooth)
                            return (out.strip, out.visited8x8Blocks, out.smoothSkipped8x8Blocks)
                        }
                    }
                }

                var completedStrips = 0
                for try await triple in group {
                    let (processedStrip, visited, skipped) = triple
                    // overwrite the processed strip back to the original strips array (located by `globalYOffset`).
                    updateStripInPlace(&imageStrips, with: processedStrip)
                    embedVisited8x8Blocks += visited
                    embedSmoothSkipped8x8Blocks += skipped
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
            await persistEmbedHistoryIfNeeded(
                succeeded: true,
                text: text,
                inputImage: image,
                outputImage: finalImage,
                error: nil,
                startedAt: historyStarted,
                sourceImageName: sourceImageName,
                embedTextureVarianceThreshold: thresholdSnapshot,
                embedVisited8x8BlockCount: embedVisited8x8Blocks,
                embedSmoothSkipped8x8BlockCount: embedSmoothSkipped8x8Blocks
            )
            if !shouldSuppressSingleOperationNotification {
                await deliverWatermarkNotificationIfAllowed {
                    await WatermarkOperationNotificationService.notifySingleEmbedFinished(success: true, error: nil)
                }
            }
            return finalImage
        } catch {
            if shouldHideProgressbar {
                NotificationCenter.default.post(name: AppConstants.Notifications.watermarkProgressOverlayDidEnd, object: nil)
            }
            await persistEmbedHistoryIfNeeded(
                succeeded: false,
                text: text,
                inputImage: image,
                outputImage: nil,
                error: error,
                startedAt: historyStarted,
                sourceImageName: sourceImageName,
                embedTextureVarianceThreshold: thresholdSnapshot,
                embedVisited8x8BlockCount: nil,
                embedSmoothSkipped8x8BlockCount: nil
            )
            if !shouldSuppressSingleOperationNotification {
                await deliverWatermarkNotificationIfAllowed {
                    await WatermarkOperationNotificationService.notifySingleEmbedFinished(success: false, error: error)
                }
            }
            throw error
        }
    }
    
    // ==========================================
    // Extract Watermark
    // ==========================================
    func extractWatermark(from image: UIImage) async throws -> String {
        try await extractWatermark(from: image, sourceImageName: nil, shouldHideProgressbar: true)
    }

    func extractWatermark(from image: UIImage, sourceImageName: String?) async throws -> String {
        try await extractWatermark(from: image, sourceImageName: sourceImageName, shouldHideProgressbar: true)
    }

    /// Extract watermark from a single image.
    /// - Parameter shouldHideProgressbar: If false, the overlay will stay visible (useful for multi-file sequential processing).
    func extractWatermark(from image: UIImage, shouldHideProgressbar: Bool = true) async throws -> String {
        try await extractWatermark(from: image, sourceImageName: nil, shouldHideProgressbar: shouldHideProgressbar)
    }

    /// Extract watermark from a single image with source file name for history display.
    func extractWatermark(from image: UIImage, sourceImageName: String?, shouldHideProgressbar: Bool = true) async throws -> String {
        if shouldHideProgressbar {
            NotificationCenter.default.post(name: AppConstants.Notifications.watermarkProgressOverlayDidStart, object: nil)
        }
        // ensure the ViewModel has enough time to process the AsyncSequence notifications, and let SwiftUI completely render the progress bar on the screen.
        try? await Task.sleep(nanoseconds: 300_000_000)

        let throttler = ProgressThrottler()
        
        func reportProgress(step: AppConstants.WatermarkStep, percentage: Double) {
            let clamped = min(max(percentage, 0), 1)
            
            guard throttler.shouldReport(clamped) else { return }
            
            let payload = ProgressPayload(step: step, percentage: clamped)
            NotificationCenter.default.post(
                name: AppConstants.Notifications.watermarkProgress,
                object: nil,
                userInfo: ["payload": payload]
            )
        }
                

        let historyStarted = CFAbsoluteTimeGetCurrent()
        var extractWorkForHistory: ExtractMatrixWorkResult?

        do {
            reportProgress(step: .extractPreparation, percentage: 0)
            reportProgress(step: .extractPreparation, percentage: 0.06)

            // important fix: use Task.detached to force the heavy matrix computation to run in the background concurrency pool
            let work = try await Task.detached(priority: .userInitiated) { [weak self] in
                guard let self = self else { throw WatermarkError.processingError }

                // 1. image preprocessing
                guard let ycbcrImage = await self.convertToYCbCr(image: image) else {
                    throw WatermarkError.processingError
                }
                let yChannel = ycbcrImage.Y
                await reportProgress(step: .extractConvertToYCbCr, percentage: 0.12)

                // 2. physical and logical alignment
                let gridScan = await self.findGridOffsetAndSyncMarker(in: yChannel, onOffsetProgress: { t in
                    // Map alignment scan into [0.12, 0.55].
                    let pct = 0.12 + (0.55 - 0.12) * min(max(t, 0), 1)
                    reportProgress(step: .extractOffsetScan, percentage: pct)
                })
                await reportProgress(step: .extractOffsetScan, percentage: 0.55)

                guard let gridOffset = gridScan.offset else {
                    return ExtractMatrixWorkResult(
                        payloadBitsWithoutSync: [],
                        offsetScanBestSyncBits: gridScan.bestSyncBitsMatched,
                        gridOffsetX: nil,
                        gridOffsetY: nil,
                        rawBitGridRows: 0,
                        rawBitGridCols: 0,
                        majorityBestSyncBits: nil,
                        majorityMacroTileWidth: nil
                    )
                }

                // 3. data extraction
                let rawExtractedBits = await self.extractBitsWithOffset(yChannel, offset: gridOffset)
                await reportProgress(step: .extractBitGrid, percentage: 0.72)

                // 4. data recovery and decoding
                let voting = await self.applyMajorityVotingWithDiagnostics(to: rawExtractedBits)
                let votedBits = voting.bits
                await reportProgress(step: .extractMajorityVoting, percentage: 0.85)

                #if DEBUG
                let rows = rawExtractedBits.count
                let cols = rawExtractedBits.first?.count ?? 0
                print("[WatermarkService] DEBUG extract: gridOffset=(\(Int(gridOffset.x)),\(Int(gridOffset.y))) rawBits=\(rows)x\(cols) votedBits=\(votedBits.count)")
                #endif

                let syncCount = getSyncMarkerBits().count
                let payload = votedBits.count >= syncCount ? Array(votedBits.dropFirst(syncCount)) : []
                let maj = voting.diagnostics
                return ExtractMatrixWorkResult(
                    payloadBitsWithoutSync: payload,
                    offsetScanBestSyncBits: gridScan.bestSyncBitsMatched,
                    gridOffsetX: Int(gridOffset.x),
                    gridOffsetY: Int(gridOffset.y),
                    rawBitGridRows: rawExtractedBits.count,
                    rawBitGridCols: rawExtractedBits.first?.count ?? 0,
                    majorityBestSyncBits: maj?.bestSyncBitsMatched,
                    majorityMacroTileWidth: maj?.macroTileWidth
                )
            }.value // wait for the background computation result
            extractWorkForHistory = work

            if work.gridOffsetX == nil || work.gridOffsetY == nil {
                throw WatermarkError.extractFailed
            }

            let payloadBits = work.payloadBitsWithoutSync

            #if DEBUG
            if !payloadBits.isEmpty {
                func bitsToByteLocal(_ bits: [Int]) -> Int {
                    var v = 0
                    for b in bits.prefix(8) { v = (v << 1) | (b & 1) }
                    return v
                }
                let lenByte = payloadBits.count >= 8 ? bitsToByteLocal(Array(payloadBits.prefix(8))) : -1
                let payloadPreview = payloadBits.prefix(24).map(String.init).joined()
                print("[WatermarkService] DEBUG extract: syncCount=\(getSyncMarkerBits().count) payloadBits=\(payloadBits.count) lenByte(raw)=\(lenByte) payloadPreview=\(payloadPreview)")
            } else {
                print("[WatermarkService] DEBUG extract: payloadBits empty (votedBits too short)")
            }
            #endif

            func eccBitCount(messageLengthBytes: Int) -> Int {
                let rawBits = 8 + messageLengthBytes * 8
                let paddedRaw = ((rawBits + 3) / 4) * 4
                let codewordBits = (paddedRaw / 4) * 8
                return codewordBits
            }

            reportProgress(step: .extractDecodeFEC, percentage: 0.90)
            
            for lenGuess in 1...16 {
                let eccCount = eccBitCount(messageLengthBytes: lenGuess)
                guard payloadBits.count >= eccCount else { continue }
                let eccBits = Array(payloadBits.prefix(eccCount))
                if let correctedText = decodeFEC(bits: eccBits) {
                    reportProgress(step: .extractDecodeFEC, percentage: 1.0)
                    if shouldHideProgressbar {
                        NotificationCenter.default.post(name: AppConstants.Notifications.watermarkProgressOverlayDidEnd, object: nil)
                    }
                    await persistExtractHistoryIfNeeded(
                        succeeded: true,
                        image: image,
                        sourceImageName: sourceImageName,
                        extractedText: correctedText,
                        error: nil,
                        startedAt: historyStarted,
                        work: work
                    )
                    if !shouldSuppressSingleOperationNotification {
                        await deliverWatermarkNotificationIfAllowed {
                            await WatermarkOperationNotificationService.notifySingleExtractFinished(
                                success: true,
                                extractedText: correctedText,
                                error: nil
                            )
                        }
                    }
                    return correctedText
                }
            }

            throw WatermarkError.extractFailed
        } catch {
            if shouldHideProgressbar {
                NotificationCenter.default.post(name: AppConstants.Notifications.watermarkProgressOverlayDidEnd, object: nil)
            }
            // Ensure the bar completes before ending for UX.
            reportProgress(step: .extractDecodeFEC, percentage: 1.0)
            await persistExtractHistoryIfNeeded(
                succeeded: false,
                image: image,
                sourceImageName: sourceImageName,
                extractedText: nil,
                error: error,
                startedAt: historyStarted,
                work: extractWorkForHistory
            )
            if !shouldSuppressSingleOperationNotification {
                await deliverWatermarkNotificationIfAllowed {
                    await WatermarkOperationNotificationService.notifySingleExtractFinished(success: false, extractedText: nil, error: error)
                }
            }
            throw error
        }
    }

    // ==========================================
    // Multi-file (sequential) APIs
    // ==========================================

    /// Sequentially embed watermark into multiple images (no outer concurrency).
    func embedWatermark(into images: [UIImage], text: String) async throws -> [UIImage] {
        try await embedWatermark(into: images, text: text, sourceImageNames: nil)
    }

    func embedWatermark(into images: [UIImage], text: String, sourceImageNames: [String]?) async throws -> [UIImage] {
        guard !images.isEmpty else { return [] }

        batchUserNotificationDepth += 1
        defer { batchUserNotificationDepth -= 1 }

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
                let name = sourceImageNames?.indices.contains(idx) == true ? sourceImageNames?[idx] : nil
                let watermarked = try await embedWatermark(into: img, text: text, sourceImageName: name, shouldHideProgressbar: false)
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
            await deliverWatermarkNotificationIfAllowed {
                await WatermarkOperationNotificationService.notifyBatchEmbedFinished(succeeded: outputs.count, failed: 0)
            }
            return outputs
        } catch {
            NotificationCenter.default.post(name: AppConstants.Notifications.watermarkProgressOverlayDidEnd, object: nil)
            let failed = max(0, images.count - outputs.count)
            await deliverWatermarkNotificationIfAllowed {
                await WatermarkOperationNotificationService.notifyBatchEmbedFinished(succeeded: outputs.count, failed: failed)
            }
            throw error
        }
    }

    /// Sequentially extract watermark from multiple images (no outer concurrency).
    func extractWatermark(from images: [UIImage]) async throws -> [String] {
        try await extractWatermark(from: images, sourceImageNames: nil)
    }

    func extractWatermark(from images: [UIImage], sourceImageNames: [String]?) async throws -> [String] {
        guard !images.isEmpty else { return [] }

        batchUserNotificationDepth += 1
        defer { batchUserNotificationDepth -= 1 }

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
                let name = sourceImageNames?.indices.contains(idx) == true ? sourceImageNames?[idx] : nil
                let extracted = try await extractWatermark(from: img, sourceImageName: name, shouldHideProgressbar: false)
                outputs.append(extracted)
                _ = await awaitPerFileProgressDrain(current: idx)
                NotificationCenter.default.post(
                    name: AppConstants.Notifications.watermarkBatchProgress,
                    object: nil,
                    userInfo: ["payload": BatchProgressPayload(completed: idx + 1, total: images.count, current: idx + 1)]
                )
            }

            NotificationCenter.default.post(name: AppConstants.Notifications.watermarkProgressOverlayDidEnd, object: nil)
            await deliverWatermarkNotificationIfAllowed {
                await WatermarkOperationNotificationService.notifyBatchExtractFinished(succeeded: outputs.count, failed: 0)
            }
            return outputs
        } catch {
            NotificationCenter.default.post(name: AppConstants.Notifications.watermarkProgressOverlayDidEnd, object: nil)
            let failed = max(0, images.count - outputs.count)
            await deliverWatermarkNotificationIfAllowed {
                await WatermarkOperationNotificationService.notifyBatchExtractFinished(succeeded: outputs.count, failed: failed)
            }
            throw error
        }
    }

    /// Sequentially extract watermark from multiple images (best effort).
    /// - Returns: `[String?]` aligned with input order; failures produce `nil` but do not stop the batch.
    func extractWatermarkBestEffort(from images: [UIImage]) async -> [String?] {
        await extractWatermarkBestEffort(from: images, sourceImageNames: nil)
    }

    func extractWatermarkBestEffort(from images: [UIImage], sourceImageNames: [String]?) async -> [String?] {
        guard !images.isEmpty else { return [] }

        batchUserNotificationDepth += 1
        defer { batchUserNotificationDepth -= 1 }

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
                let name = sourceImageNames?.indices.contains(idx) == true ? sourceImageNames?[idx] : nil
                let extracted = try await extractWatermark(from: img, sourceImageName: name, shouldHideProgressbar: false)
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
        let succeeded = outputs.compactMap { $0 }.count
        let failed = outputs.count - succeeded
        await deliverWatermarkNotificationIfAllowed {
            await WatermarkOperationNotificationService.notifyBatchExtractFinished(succeeded: succeeded, failed: failed)
        }
        return outputs
    }

    private func persistEmbedHistoryIfNeeded(
        succeeded: Bool,
        text: String,
        inputImage: UIImage,
        outputImage: UIImage?,
        error: Error?,
        startedAt: CFAbsoluteTime,
        sourceImageName: String? = nil,
        embedTextureVarianceThreshold: Double? = nil,
        embedVisited8x8BlockCount: Int? = nil,
        embedSmoothSkipped8x8BlockCount: Int? = nil
    ) async {
        guard await userAllowsEmbedHistoryRecords() else { return }
        guard let ctx = historyModelContext else { return }
        let durationMs = (CFAbsoluteTimeGetCurrent() - startedAt) * 1000
        let thumbnailSource = succeeded ? (outputImage ?? inputImage) : inputImage
        let record = HistoryRecordService.makeEmbedRecord(
            succeeded: succeeded,
            payloadText: text,
            sourceImageForThumbnail: thumbnailSource,
            sourceImageName: sourceImageName,
            error: error,
            durationMs: durationMs,
            embedVisited8x8BlockCount: embedVisited8x8BlockCount,
            embedSmoothSkipped8x8BlockCount: embedSmoothSkipped8x8BlockCount,
            embedTextureVarianceThreshold: embedTextureVarianceThreshold
        )
        await MainActor.run {
            HistoryRecordService.insertAndSave(record, context: ctx)
        }
    }

    private func persistExtractHistoryIfNeeded(
        succeeded: Bool,
        image: UIImage,
        sourceImageName: String? = nil,
        extractedText: String?,
        error: Error?,
        startedAt: CFAbsoluteTime,
        work: ExtractMatrixWorkResult? = nil
    ) async {
        guard await userAllowsEmbedHistoryRecords() else { return }
        guard let ctx = historyModelContext else { return }
        let durationMs = (CFAbsoluteTimeGetCurrent() - startedAt) * 1000
        let rawRows: Int? = {
            guard let w = work, w.rawBitGridRows > 0 else { return nil }
            return w.rawBitGridRows
        }()
        let rawCols: Int? = {
            guard let w = work, w.rawBitGridCols > 0 else { return nil }
            return w.rawBitGridCols
        }()
        let record = HistoryRecordService.makeExtractRecord(
            succeeded: succeeded,
            extractedText: extractedText,
            sourceImage: image,
            sourceImageName: sourceImageName,
            error: error,
            durationMs: durationMs,
            syncMatchCount: work?.offsetScanBestSyncBits,
            extractGridOffsetXPx: work?.gridOffsetX,
            extractGridOffsetYPx: work?.gridOffsetY,
            extractMajoritySyncBits: work?.majorityBestSyncBits,
            extractMacroTileWidth: work?.majorityMacroTileWidth,
            extractRawBitGridRows: rawRows,
            extractRawBitGridCols: rawCols
        )
        await MainActor.run {
            HistoryRecordService.insertAndSave(record, context: ctx)
        }
    }
    
    // MARK: - Progress Throttler
    final class ProgressThrottler: @unchecked Sendable {
        private var lastTime: CFAbsoluteTime = 0
        private var lastPct: Double = -1
        private let lock = NSLock()
        
        func shouldReport(_ pct: Double) -> Bool {
        
            if pct <= 0.0 || pct >= 1.0 { return true }
            
            lock.lock()
            defer { lock.unlock() }
            
            let now = CFAbsoluteTimeGetCurrent()
            if now - lastTime > 0.05 || (pct - lastPct) >= 0.01 {
                lastTime = now
                lastPct = pct
                return true
            }
            return false
        }
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
