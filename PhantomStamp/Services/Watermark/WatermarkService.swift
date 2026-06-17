//
//  WatermarkService.swift
//  PhantomStamp
//

import UIKit
import Accelerate
import SwiftData

class WatermarkService: WatermarkServiceProtocol {
    nonisolated private final class ProgressDrainObserver: @unchecked Sendable {
        private let lock = NSLock()
        private var token: NSObjectProtocol?
        private var isCancelled = false

        func install(_ token: NSObjectProtocol) {
            lock.lock()
            if isCancelled {
                lock.unlock()
                NotificationCenter.default.removeObserver(token)
                return
            }
            self.token = token
            lock.unlock()
        }

        func cancel() {
            lock.lock()
            isCancelled = true
            let token = self.token
            self.token = nil
            lock.unlock()
            if let token {
                NotificationCenter.default.removeObserver(token)
            }
        }

        deinit {
            cancel()
        }
    }

    /// Stateless image/DSP implementation. Keeping it outside the service prevents UI-facing
    /// orchestration state from leaking into detached algorithm work.
    nonisolated let algorithms = WatermarkAlgorithmCore()

    /// SwiftData store for watermark history rows. Prefer this over caching a `ModelContext` directly —
    /// `ModelContext` is MainActor-bound and must not be read from background watermark work.
    /// Wired from `RootView` via `modelContext.container`.
    var modelContainer: ModelContainer?

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
        var deskewAngleRadians: Float
        var deskewScale: Float
        var offsetScanBestSyncBits: Int
        var gridOffsetX: Int?
        var gridOffsetY: Int?
        var rawBitGridRows: Int
        var rawBitGridCols: Int
        var majorityBestSyncBits: Int?
        var majorityMacroTileWidth: Int?
        var topologyHypothesis: ScoreGridTopologyHypothesis?
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

    /// Queues `UserNotifications` without delaying the watermark result.
    private func deliverWatermarkNotificationIfAllowed(
        _ work: @escaping @MainActor () async -> Void
    ) async {
        guard await userAllowsWatermarkNotifications() else { return }
        Task { @MainActor in
            await work()
        }
    }
    private func makePerFileProgressDrainEvents(current: Int) -> AsyncStream<Void> {
        let name = AppConstants.Notifications.watermarkPerFileProgressDidDrain
        return AsyncStream(bufferingPolicy: .bufferingNewest(1)) { continuation in
            let observer = ProgressDrainObserver()
            let token = NotificationCenter.default.addObserver(
                forName: name,
                object: nil,
                queue: nil
            ) { notification in
                guard let payload = notification.userInfo?["payload"] as? PerFileProgressDrainPayload,
                      payload.current == current
                else { return }
                continuation.yield(())
                continuation.finish()
            }
            observer.install(token)
            continuation.onTermination = { @Sendable _ in
                observer.cancel()
            }
        }
    }

    private func awaitPerFileProgressDrain(
        events: AsyncStream<Void>,
        timeoutSeconds: Double = 5.0
    ) async -> Bool {
        // The stream is created before processing starts, so an early UI ACK is buffered instead
        // of being lost. The short timeout only protects tests/headless runs.
        let deadlineNs = UInt64(timeoutSeconds * 1_000_000_000)

        return await withTaskGroup(of: Bool.self) { group in
            group.addTask {
                for await _ in events {
                    return true
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

    private func awaitProgressOverlayPresentation(timeoutNanoseconds: UInt64 = 500_000_000) async {
        let name = AppConstants.Notifications.watermarkProgressOverlayDidPresent
        await withTaskGroup(of: Void.self) { group in
            group.addTask {
                for await _ in NotificationCenter.default.notifications(named: name, object: nil) {
                    return
                }
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: timeoutNanoseconds)
            }
            await group.next()
            group.cancelAll()
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
        try await embedWatermark(
            into: image,
            text: text,
            sourceImageName: sourceImageName,
            shouldHideProgressbar: shouldHideProgressbar,
            parameterOverrides: nil,
            reportsProgressNotifications: true
        )
    }

    /// Advanced Mode: one-shot embed parameters that bypass persisted `UserSettingsStore` values.
    func embedWatermark(
        into image: UIImage,
        text: String,
        sourceImageName: String?,
        parameterOverrides: AdvancedEmbedOverrides
    ) async throws -> UIImage {
        try await embedWatermark(
            into: image,
            text: text,
            sourceImageName: sourceImageName,
            shouldHideProgressbar: true,
            parameterOverrides: parameterOverrides,
            reportsProgressNotifications: true
        )
    }

    /// Embed without posting production overlay / per-step progress notifications.
    /// Intended for robustness tests and other headless validation runs.
    func embedWatermarkSilently(
        into image: UIImage,
        text: String,
        embeddingStrengthOverride: Double? = nil
    ) async throws -> UIImage {
        try await embedWatermark(
            into: image,
            text: text,
            sourceImageName: nil,
            shouldHideProgressbar: false,
            parameterOverrides: nil,
            reportsProgressNotifications: false,
            embeddingStrengthOverride: embeddingStrengthOverride
        )
    }

    private func embedWatermark(
        into image: UIImage,
        text: String,
        sourceImageName: String?,
        shouldHideProgressbar: Bool,
        parameterOverrides: AdvancedEmbedOverrides?,
        reportsProgressNotifications: Bool,
        embeddingStrengthOverride: Double? = nil
    ) async throws -> UIImage {
        #if DEBUG
        // Debug-only: prints internal data-layer checks. Disable by default to avoid noisy logs in demos.
        // debugTestDataLayer()
        #endif
        
        if shouldHideProgressbar, reportsProgressNotifications {
            NotificationCenter.default.post(name: AppConstants.Notifications.watermarkProgressOverlayDidStart, object: nil)
        }
        
        let throttler = ProgressThrottler()
        
        func reportProgress(step: AppConstants.WatermarkStep, percentage: Double) {
            guard reportsProgressNotifications else { return }
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
        let prepEnd = 0.25
        let colorEnd = 0.50
        let stripsEnd = 0.75

        let historyStarted = CFAbsoluteTimeGetCurrent()
        let varianceGainCurveSnapshot: VarianceGainCurve? = await MainActor.run {
            parameterOverrides?.varianceGainCurve
        }
        let thresholdSnapshot: Double = await MainActor.run {
            if let overrides = parameterOverrides {
                return overrides.varianceGainCurve.maxVariance
            }
            return settingsStore?.textureVarianceThreshold ?? AppConstants.SettingsDefault.textureVarianceThreshold
        }
        let syncIntensitySnapshot: Double = await MainActor.run {
            settingsStore?.syncTemplateIntensity ?? AppConstants.SettingsDefault.syncTemplateIntensity
        }
        let embeddingStrengthSnapshot: Double = await MainActor.run {
            if let embeddingStrengthOverride {
                return embeddingStrengthOverride
            }
            if let overrides = parameterOverrides {
                return overrides.embeddingIntensity
            }
            return AppConstants.SettingsDefault.embeddingStrength
        }

        do {
            #if DEBUG
            let inputPixelWidth = Int((image.size.width * image.scale).rounded())
            let inputPixelHeight = Int((image.size.height * image.scale).rounded())
            print(
                "[WatermarkService] embed begin: source=\(sourceImageName ?? "<unknown>") "
                    + "pixels=\(inputPixelWidth)x\(inputPixelHeight) "
                    + "orientation=\(image.imageOrientation.rawValue)"
            )
            #endif

            // ==========================================
            // Step 1: Prepare payload + build 2D tile → [0, prepEnd]
            // ==========================================
            reportProgress(step: .preparation, percentage: 0)
            let minSize: CGFloat = 128.0
            if image.size.width < minSize || image.size.height < minSize {
                throw WatermarkError.imageTooSmall
            }
            guard WatermarkPayloadLimits.isValidUserPayload(text) else {
                throw WatermarkError.invalidPayloadLength
            }

            // Convert the text to binary and apply Forward Error Correction (FEC)
            let eccBits = encodeFEC(text: text)

            // Concatenate the sync header, and form a complete single watermark period
            let syncBits = getSyncMarkerBits()
            let payloadBits = syncBits + eccBits
            // Convert the one-dimensional data stream to a two-dimensional macroblock (to prevent rasterization issues)
            let macroblock = build2DTile(from: payloadBits)
            reportProgress(step: .preparation, percentage: prepEnd)

            // ==========================================
            // Step 2: Color / layout → (prepEnd, colorEnd]
            // ==========================================
            reportProgress(step: .colorConversion, percentage: prepEnd)
            guard var ycbcrImage = algorithms.convertToYCbCr(image: image) else {
                #if DEBUG
                let pxW = Int(image.size.width * image.scale)
                let pxH = Int(image.size.height * image.scale)
                print("[WatermarkService] convertToYCbCr failed (image=\(pxW)x\(pxH)px scale=\(image.scale) orientation=\(image.imageOrientation.rawValue))")
                #endif
                throw WatermarkError.processingError
            }
            let yChannel = ycbcrImage.Y

            // slice the Y channel into multiple strips (the height must be a multiple of 8)
            let stripHeight = 80
            var imageStrips = algorithms.sliceImage(yChannel, heightPerStrip: stripHeight)
            reportProgress(step: .colorConversion, percentage: colorEnd)

            // ==========================================
            // Step 3: Strip processing → (colorEnd, stripsEnd]
            // ==========================================
            let stripSpan = stripsEnd - colorEnd
            reportProgress(step: .processingStrips, percentage: colorEnd)

            let thresholdSmooth: Float = Float(thresholdSnapshot)
            let embeddingStrengthMultiplier = AppConstants.embeddingStrengthMultiplier(
                for: embeddingStrengthSnapshot
            )

            let stripCount = imageStrips.count
            let stripProgressStride = max(1, (stripCount + 4) / 5)
            var embedVisited8x8Blocks = 0
            var embedSmoothSkipped8x8Blocks = 0
            let algorithms = algorithms
            try await withThrowingTaskGroup(of: (ImageStrip, Int, Int).self) { group in
                for strip in imageStrips {
                    group.addTask {
                        // force memory recycling to prevent OOM silent crash caused by large image slicing computation
                        autoreleasepool {
                            let out = algorithms.processSingleStripForEmbedding(
                                strip: strip,
                                macroblock: macroblock,
                                thresholdSmooth: thresholdSmooth,
                                embeddingStrengthMultiplier: embeddingStrengthMultiplier,
                                varianceGainCurve: varianceGainCurveSnapshot
                            )
                            return (out.strip, out.visited8x8Blocks, out.smoothSkipped8x8Blocks)
                        }
                    }
                }

                var completedStrips = 0
                for try await triple in group {
                    let (processedStrip, visited, skipped) = triple
                    // overwrite the processed strip back to the original strips array (located by `globalYOffset`).
                    algorithms.updateStripInPlace(&imageStrips, with: processedStrip)
                    embedVisited8x8Blocks += visited
                    embedSmoothSkipped8x8Blocks += skipped
                    completedStrips += 1
                    if stripCount > 0,
                       completedStrips % stripProgressStride == 0 || completedStrips == stripCount
                    {
                        let t = colorEnd + stripSpan * Double(completedStrips) / Double(stripCount)
                        reportProgress(step: .processingStrips, percentage: t)
                    }
                }
            }
            reportProgress(step: .processingStrips, percentage: stripsEnd)

            // ==========================================
            // Step 4: Reassemble → (stripsEnd, 1.0]
            // ==========================================
            reportProgress(step: .reassembling, percentage: 0.80)
            
            // overwrite the processed strips back to the original Y channel matrix.
            // the extra 1~7 pixels on the right side and bottom of the original matrix will be kept intact, and not be destroyed.
            algorithms.reassembleStrips(imageStrips, into: &ycbcrImage.Y)
            

            // ==========================================
            // New Feature: Upgrade to Hybrid Architecture
            // Add DFT Frequency-Domain Sync Template to protect Geometric Attacks
            // ==========================================
            // Intensity is user-configurable via `UserSettingsStore.syncTemplateIntensity` so the
            // robustness-vs-visibility trade-off can be tuned without rebuilding. Snapshot was
            // taken at the top of this method to avoid mid-pipeline races.
            let syncTemplate = algorithms.loadSpatialSyncTemplate()
            let templateIntensity = Float(syncIntensitySnapshot)
            algorithms.applySpatialTiling(to: &ycbcrImage.Y, template: syncTemplate, intensity: templateIntensity)


            // Final color conversion back to UIImage.
            reportProgress(step: .rgbRebuild, percentage: 0.90)

            guard let finalImage = algorithms.convertToUIImage(from: ycbcrImage) else {
                #if DEBUG
                print("[WatermarkService] convertToUIImage failed (Y=\(ycbcrImage.Y.width)x\(ycbcrImage.Y.height), Cb=\(ycbcrImage.Cb.width)x\(ycbcrImage.Cb.height), Cr=\(ycbcrImage.Cr.width)x\(ycbcrImage.Cr.height))")
                #endif
                throw WatermarkError.processingError
            }
            reportProgress(step: .rgbRebuild, percentage: 1)

            if shouldHideProgressbar, reportsProgressNotifications {
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
                embedEmbeddingStrength: embeddingStrengthSnapshot,
                embedVisited8x8BlockCount: embedVisited8x8Blocks,
                embedSmoothSkipped8x8BlockCount: embedSmoothSkipped8x8Blocks
            )
            if reportsProgressNotifications, !shouldSuppressSingleOperationNotification {
                await deliverWatermarkNotificationIfAllowed {
                    await WatermarkOperationNotificationService.notifySingleEmbedFinished(success: true, error: nil)
                }
            }
            return finalImage
        } catch {
            if shouldHideProgressbar, reportsProgressNotifications {
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
                embedEmbeddingStrength: embeddingStrengthSnapshot,
                embedVisited8x8BlockCount: nil,
                embedSmoothSkipped8x8BlockCount: nil
            )
            if reportsProgressNotifications, !shouldSuppressSingleOperationNotification {
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
        try await performExtraction(
            from: image,
            sourceImageName: nil,
            shouldHideProgressbar: true,
            reportsProgressNotifications: true
        ).text
    }

    func extractWatermark(from image: UIImage, sourceImageName: String?) async throws -> String {
        try await performExtraction(
            from: image,
            sourceImageName: sourceImageName,
            shouldHideProgressbar: true,
            reportsProgressNotifications: true
        ).text
    }

    /// Extract watermark from a single image.
    /// - Parameter shouldHideProgressbar: If false, the overlay will stay visible (useful for multi-file sequential processing).
    func extractWatermark(from image: UIImage, shouldHideProgressbar: Bool = true) async throws -> String {
        try await performExtraction(
            from: image,
            sourceImageName: nil,
            shouldHideProgressbar: shouldHideProgressbar,
            reportsProgressNotifications: true
        ).text
    }

    /// Extract watermark from a single image with source file name for history display.
    func extractWatermark(from image: UIImage, sourceImageName: String?, shouldHideProgressbar: Bool = true) async throws -> String {
        try await performExtraction(
            from: image,
            sourceImageName: sourceImageName,
            shouldHideProgressbar: shouldHideProgressbar,
            reportsProgressNotifications: true
        ).text
    }

    func extractWatermarkWithDiagnostics(
        from image: UIImage,
        sourceImageName: String?
    ) async throws -> WatermarkExtractionResult {
        try await performExtraction(
            from: image,
            sourceImageName: sourceImageName,
            shouldHideProgressbar: true,
            reportsProgressNotifications: true
        )
    }

    /// Extract without posting production overlay / per-step progress notifications.
    func extractWatermarkSilently(from image: UIImage) async throws -> String {
        try await performExtraction(
            from: image,
            sourceImageName: nil,
            shouldHideProgressbar: false,
            reportsProgressNotifications: false
        ).text
    }

    private func performExtraction(
        from image: UIImage,
        sourceImageName: String?,
        shouldHideProgressbar: Bool,
        reportsProgressNotifications: Bool
    ) async throws -> WatermarkExtractionResult {
        #if DEBUG
        let inputPixelWidth = Int((image.size.width * image.scale).rounded())
        let inputPixelHeight = Int((image.size.height * image.scale).rounded())
        print(
            "[WatermarkService] extract begin: source=\(sourceImageName ?? "<unknown>") "
                + "pixels=\(inputPixelWidth)x\(inputPixelHeight) "
                + "orientation=\(image.imageOrientation.rawValue)"
        )
        #endif

        if shouldHideProgressbar, reportsProgressNotifications {
            NotificationCenter.default.post(name: AppConstants.Notifications.watermarkProgressOverlayDidStart, object: nil)
            await awaitProgressOverlayPresentation()
        }

        let throttler = ProgressThrottler()
        
        func reportProgress(step: AppConstants.WatermarkStep, percentage: Double) {
            guard reportsProgressNotifications else { return }
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

            let algorithms = algorithms
            // The stateless algorithm core is Sendable, so this entire matrix pipeline remains
            // on the background concurrency pool instead of inheriting service/UI isolation.
            let work = try await Task.detached(priority: .userInitiated) {
                let pipelineStarted = CFAbsoluteTimeGetCurrent()

                // 1. image preprocessing
                guard let ycbcrImage = algorithms.convertToYCbCr(image: image) else {
                    throw WatermarkError.processingError
                }
                let yChannel = ycbcrImage.Y
                #if DEBUG
                print(
                    "[WatermarkService] timing: YCbCr "
                        + "\(String(format: "%.1f", (CFAbsoluteTimeGetCurrent() - pipelineStarted) * 1000))ms"
                )
                #endif
                await reportProgress(step: .extractConvertToYCbCr, percentage: 0.20)


                // ==========================================
                // New Feature: Upgrade to Hybrid Architecture
                // Added correction for geometric attacks such as scaling and rotation
                // ==========================================


                // DFT is a proposal generator, not an authority. Spatially separated FFT windows
                // form transform consensuses, while identity is always retained as a fallback.
                let detectionStarted = CFAbsoluteTimeGetCurrent()
                let transformCandidates = algorithms.detectGeometricTransformCandidates(in: yChannel)
                #if DEBUG
                print(
                    "[WatermarkService] timing: geometric detection "
                        + "\(String(format: "%.1f", (CFAbsoluteTimeGetCurrent() - detectionStarted) * 1000))ms "
                        + "candidates=\(transformCandidates.count)"
                )
                #endif
                await reportProgress(step: .extractDetectTransforms, percentage: 0.40)

                func validationScore(_ work: ExtractMatrixWorkResult) -> Int {
                    let majority = work.majorityBestSyncBits ?? 0
                    return majority * 100 + work.offsetScanBestSyncBits
                }

                var bestFailedWork: ExtractMatrixWorkResult?

                // A candidate earns the right to control the full image only after the existing
                // DCT sync marker and real FEC decoder validate it.
                for (candidateIndex, transformParams) in transformCandidates.enumerated() {
                    let candidateStarted = CFAbsoluteTimeGetCurrent()
                    #if DEBUG
                    print(
                        "[WatermarkService] validating geometric candidate "
                            + "\(candidateIndex + 1)/\(transformCandidates.count): "
                            + "angle=\(transformParams.angle * 180 / .pi)deg "
                            + "scale=\(transformParams.scale) "
                            + "identity=\(transformParams.isIdentity)"
                    )
                    #endif

                    let deskewedYChannel = algorithms.deskewImage(
                        yChannel,
                        angle: transformParams.angle,
                        scale: transformParams.scale
                    )
                    let deskewFinished = CFAbsoluteTimeGetCurrent()

                    // 2. physical and logical alignment. Each offset now probes multiple spatial
                    // regions, so a local edit cannot blind validation merely by covering one corner.
                    let gridScan = algorithms.findGridOffsetAndSyncMarker(
                        in: deskewedYChannel,
                        onOffsetProgress: { t in
                            let coarse = floor(min(max(t, 0), 1) * 4) / 4
                            let candidateSpan = 0.40 / Double(max(transformCandidates.count, 1))
                            let candidateStart = 0.40 + Double(candidateIndex) * candidateSpan
                            Task { @MainActor in
                                reportProgress(
                                    step: .extractOffsetScan,
                                    percentage: candidateStart + candidateSpan * coarse
                                )
                            }
                        }
                    )
                    let gridScanFinished = CFAbsoluteTimeGetCurrent()

                    guard let gridOffset = gridScan.offset else {
                        #if DEBUG
                        print(
                            "[WatermarkService] timing candidate \(candidateIndex + 1): "
                                + "deskew=\(String(format: "%.1f", (deskewFinished - candidateStarted) * 1000))ms "
                                + "grid=\(String(format: "%.1f", (gridScanFinished - deskewFinished) * 1000))ms "
                                + "total=\(String(format: "%.1f", (gridScanFinished - candidateStarted) * 1000))ms "
                                + "(no grid)"
                        )
                        #endif
                        let failed = ExtractMatrixWorkResult(
                            payloadBitsWithoutSync: [],
                            deskewAngleRadians: transformParams.angle,
                            deskewScale: transformParams.scale,
                            offsetScanBestSyncBits: gridScan.bestSyncBitsMatched,
                            gridOffsetX: nil,
                            gridOffsetY: nil,
                            rawBitGridRows: 0,
                            rawBitGridCols: 0,
                            majorityBestSyncBits: nil,
                            majorityMacroTileWidth: nil,
                            topologyHypothesis: nil
                        )
                        if bestFailedWork == nil || validationScore(failed) > validationScore(bestFailedWork!) {
                            bestFailedWork = failed
                        }
                        continue
                    }

                    // 3. data extraction from this candidate's corrected plane.
                    let rawExtractedScores = algorithms.extractSoftBitsWithOffset(
                        deskewedYChannel,
                        offset: gridOffset
                    )
                    let extractionFinished = CFAbsoluteTimeGetCurrent()

                    // 4. sync-gated recovery and FEC validation.
                    let voting = algorithms.applySoftMajorityVotingWithDiagnostics(
                        to: rawExtractedScores,
                        preferredHypothesis: gridScan.topologyHypothesis,
                        preferredHypothesisIsExact: gridScan.bestSyncBitsMatched == 32
                    )
                    let votingFinished = CFAbsoluteTimeGetCurrent()
                    let votedBits = voting.bits
                    let syncCount = getSyncMarkerBits().count
                    let payload = votedBits.count >= syncCount
                        ? Array(votedBits.dropFirst(syncCount))
                        : []
                    let maj = voting.diagnostics
                    let fecPassed = maj?.fecValidated == true
                    let candidateWork = ExtractMatrixWorkResult(
                        payloadBitsWithoutSync: payload,
                        deskewAngleRadians: transformParams.angle,
                        deskewScale: transformParams.scale,
                        offsetScanBestSyncBits: gridScan.bestSyncBitsMatched,
                        gridOffsetX: Int(gridOffset.x),
                        gridOffsetY: Int(gridOffset.y),
                        rawBitGridRows: rawExtractedScores.count,
                        rawBitGridCols: rawExtractedScores.first?.count ?? 0,
                        majorityBestSyncBits: maj?.bestSyncBitsMatched,
                        majorityMacroTileWidth: maj?.macroTileWidth,
                        // Sync-only matches are search hypotheses. Report orientation only after
                        // the folded payload passes the real FEC decoder.
                        topologyHypothesis: fecPassed ? maj?.topologyHypothesis : nil
                    )

                    #if DEBUG
                    let rows = rawExtractedScores.count
                    let cols = rawExtractedScores.first?.count ?? 0
                    let topologySummary = fecPassed
                        ? (maj?.topologyHypothesis.rawValue ?? "unknown")
                        : "unvalidated(\(maj?.topologyHypothesis.rawValue ?? gridScan.topologyHypothesis.rawValue))"
                    print(
                        "[WatermarkService] candidate result: gridOffset="
                            + "(\(Int(gridOffset.x)),\(Int(gridOffset.y))) "
                            + "rawBits=\(rows)x\(cols) votedBits=\(votedBits.count) "
                            + "sync=\(gridScan.bestSyncBitsMatched)/32 "
                            + "FEC=\(fecPassed ? "PASS" : "FAIL") "
                            + "topology=\(topologySummary)"
                    )
                    print(
                        "[WatermarkService] timing candidate \(candidateIndex + 1): "
                            + "deskew=\(String(format: "%.1f", (deskewFinished - candidateStarted) * 1000))ms "
                            + "grid=\(String(format: "%.1f", (gridScanFinished - deskewFinished) * 1000))ms "
                            + "DCT=\(String(format: "%.1f", (extractionFinished - gridScanFinished) * 1000))ms "
                            + "voting=\(String(format: "%.1f", (votingFinished - extractionFinished) * 1000))ms "
                            + "total=\(String(format: "%.1f", (votingFinished - candidateStarted) * 1000))ms"
                    )
                    #endif

                    if fecPassed {
                        #if DEBUG
                        print(
                            "[WatermarkService] timing: extraction matrix pipeline "
                                + "\(String(format: "%.1f", (CFAbsoluteTimeGetCurrent() - pipelineStarted) * 1000))ms"
                        )
                        #endif
                        await reportProgress(step: .extractOffsetScan, percentage: 0.80)
                        await reportProgress(step: .extractBitGrid, percentage: 0.90)
                        return candidateWork
                    }

                    if bestFailedWork == nil || validationScore(candidateWork) > validationScore(bestFailedWork!) {
                        bestFailedWork = candidateWork
                    }
                }

                await reportProgress(step: .extractOffsetScan, percentage: 0.80)
                await reportProgress(step: .extractBitGrid, percentage: 0.90)
                return bestFailedWork ?? ExtractMatrixWorkResult(
                    payloadBitsWithoutSync: [],
                    deskewAngleRadians: 0,
                    deskewScale: 1,
                    offsetScanBestSyncBits: 0,
                    gridOffsetX: nil,
                    gridOffsetY: nil,
                    rawBitGridRows: 0,
                    rawBitGridCols: 0,
                    majorityBestSyncBits: nil,
                    majorityMacroTileWidth: nil,
                    topologyHypothesis: nil
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

            reportProgress(step: .extractDecodeFEC, percentage: 0.95)
            
            for lenGuess in 1...16 {
                let eccCount = eccBitCount(messageLengthBytes: lenGuess)
                guard payloadBits.count >= eccCount else { continue }
                let eccBits = Array(payloadBits.prefix(eccCount))
                if let correctedText = decodeFEC(
                    bits: eccBits,
                    expectedMessageLengthBytes: lenGuess
                ) {
                    await persistExtractHistoryIfNeeded(
                        succeeded: true,
                        image: image,
                        sourceImageName: sourceImageName,
                        extractedText: correctedText,
                        error: nil,
                        startedAt: historyStarted,
                        work: work
                    )
                    // History thumbnail generation and persistence are part of the operation.
                    // Only publish 100% after that work is complete.
                    reportProgress(step: .extractDecodeFEC, percentage: 1.0)
                    if shouldHideProgressbar, reportsProgressNotifications {
                        NotificationCenter.default.post(name: AppConstants.Notifications.watermarkProgressOverlayDidEnd, object: nil)
                    }
                    if reportsProgressNotifications, !shouldSuppressSingleOperationNotification {
                        await deliverWatermarkNotificationIfAllowed {
                            await WatermarkOperationNotificationService.notifySingleExtractFinished(
                                success: true,
                                extractedText: correctedText,
                                error: nil
                            )
                        }
                    }
                    return WatermarkExtractionResult(
                        text: correctedText,
                        diagnostics: extractionDiagnostics(
                            from: work,
                            durationMs: (CFAbsoluteTimeGetCurrent() - historyStarted) * 1000
                        )
                    )
                }
            }

            throw WatermarkError.extractFailed
        } catch {
            await persistExtractHistoryIfNeeded(
                succeeded: false,
                image: image,
                sourceImageName: sourceImageName,
                extractedText: nil,
                error: error,
                startedAt: historyStarted,
                work: extractWorkForHistory
            )
            // Ensure finalization is reflected before the overlay reaches completion.
            reportProgress(step: .extractDecodeFEC, percentage: 1.0)
            if shouldHideProgressbar, reportsProgressNotifications {
                NotificationCenter.default.post(name: AppConstants.Notifications.watermarkProgressOverlayDidEnd, object: nil)
            }
            if reportsProgressNotifications, !shouldSuppressSingleOperationNotification {
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
        await awaitProgressOverlayPresentation()

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
                let drainEvents = makePerFileProgressDrainEvents(current: idx)
                let watermarked = try await embedWatermark(into: img, text: text, sourceImageName: name, shouldHideProgressbar: false)
                outputs.append(watermarked)
                // Pace batch: wait until the per-file progress bar is fully displayed.
                _ = await awaitPerFileProgressDrain(events: drainEvents)
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
        await awaitProgressOverlayPresentation()

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
                let drainEvents = makePerFileProgressDrainEvents(current: idx)
                let extracted = try await extractWatermark(from: img, sourceImageName: name, shouldHideProgressbar: false)
                outputs.append(extracted)
                _ = await awaitPerFileProgressDrain(events: drainEvents)
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
        await extractWatermarkBestEffortWithDiagnostics(from: images, sourceImageNames: nil)
            .map { $0?.text }
    }

    func extractWatermarkBestEffort(from images: [UIImage], sourceImageNames: [String]?) async -> [String?] {
        await extractWatermarkBestEffortWithDiagnostics(from: images, sourceImageNames: sourceImageNames)
            .map { $0?.text }
    }

    func extractWatermarkBestEffortWithDiagnostics(
        from images: [UIImage],
        sourceImageNames: [String]?
    ) async -> [WatermarkExtractionResult?] {
        guard !images.isEmpty else { return [] }

        batchUserNotificationDepth += 1
        defer { batchUserNotificationDepth -= 1 }

        NotificationCenter.default.post(name: AppConstants.Notifications.watermarkProgressOverlayDidStart, object: nil)
        NotificationCenter.default.post(
            name: AppConstants.Notifications.watermarkBatchProgress,
            object: nil,
            userInfo: ["payload": BatchProgressPayload(completed: 0, total: images.count, current: 0)]
        )
        await awaitProgressOverlayPresentation()

        var outputs: [WatermarkExtractionResult?] = Array(repeating: nil, count: images.count)

        for (idx, img) in images.enumerated() {
            NotificationCenter.default.post(
                name: AppConstants.Notifications.watermarkBatchProgress,
                object: nil,
                userInfo: ["payload": BatchProgressPayload(completed: idx, total: images.count, current: idx)]
            )
            let drainEvents = makePerFileProgressDrainEvents(current: idx)
            do {
                let name = sourceImageNames?.indices.contains(idx) == true ? sourceImageNames?[idx] : nil
                let extracted = try await performExtraction(
                    from: img,
                    sourceImageName: name,
                    shouldHideProgressbar: false,
                    reportsProgressNotifications: true
                )
                outputs[idx] = extracted
            } catch {
                outputs[idx] = nil
            }
            _ = await awaitPerFileProgressDrain(events: drainEvents)
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
        embedEmbeddingStrength: Double? = nil,
        embedVisited8x8BlockCount: Int? = nil,
        embedSmoothSkipped8x8BlockCount: Int? = nil
    ) async {
        guard await userAllowsEmbedHistoryRecords() else {
            #if DEBUG
            print("[WatermarkService] embed history skipped: auto-log disabled in settings")
            #endif
            return
        }

        let durationMs = (CFAbsoluteTimeGetCurrent() - startedAt) * 1000
        let thumbnailSource = succeeded ? (outputImage ?? inputImage) : inputImage

        // Build + insert on MainActor using the container's mainContext so SwiftData sees the same
        // store that HistoryView reads — never touch a cached ModelContext from a background task.
        await MainActor.run {
            guard let container = self.modelContainer else {
                #if DEBUG
                print("[WatermarkService] embed history skipped: modelContainer not wired (see RootView)")
                #endif
                return
            }
            let ctx = container.mainContext
            let record = HistoryRecordService.makeEmbedRecord(
                succeeded: succeeded,
                payloadText: text,
                sourceImageForThumbnail: thumbnailSource,
                sourceImageName: sourceImageName,
                error: error,
                durationMs: durationMs,
                embedVisited8x8BlockCount: embedVisited8x8BlockCount,
                embedSmoothSkipped8x8BlockCount: embedSmoothSkipped8x8BlockCount,
                embedTextureVarianceThreshold: embedTextureVarianceThreshold,
                embedEmbeddingStrength: embedEmbeddingStrength
            )
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
        guard await userAllowsEmbedHistoryRecords() else {
            #if DEBUG
            print("[WatermarkService] extract history skipped: auto-log disabled in settings")
            #endif
            return
        }

        let durationMs = (CFAbsoluteTimeGetCurrent() - startedAt) * 1000
        let rawRows: Int? = {
            guard let w = work, w.rawBitGridRows > 0 else { return nil }
            return w.rawBitGridRows
        }()
        let rawCols: Int? = {
            guard let w = work, w.rawBitGridCols > 0 else { return nil }
            return w.rawBitGridCols
        }()

        await MainActor.run {
            guard let container = self.modelContainer else {
                #if DEBUG
                print("[WatermarkService] extract history skipped: modelContainer not wired (see RootView)")
                #endif
                return
            }
            let ctx = container.mainContext
            let record = HistoryRecordService.makeExtractRecord(
                succeeded: succeeded,
                extractedText: extractedText,
                sourceImage: image,
                sourceImageName: sourceImageName,
                error: error,
                durationMs: durationMs,
                syncMatchCount: work?.offsetScanBestSyncBits,
                extractDeskewAngleDegrees: work.map {
                    Double($0.deskewAngleRadians) * 180.0 / .pi
                },
                extractDeskewScale: work.map { Double($0.deskewScale) },
                extractTopologyHypothesisRawValue: work?.topologyHypothesis?.rawValue,
                extractGridOffsetXPx: work?.gridOffsetX,
                extractGridOffsetYPx: work?.gridOffsetY,
                extractMajoritySyncBits: work?.majorityBestSyncBits,
                extractMacroTileWidth: work?.majorityMacroTileWidth,
                extractRawBitGridRows: rawRows,
                extractRawBitGridCols: rawCols
            )
            HistoryRecordService.insertAndSave(record, context: ctx)
        }
    }

    private func extractionDiagnostics(
        from work: ExtractMatrixWorkResult,
        durationMs: Double
    ) -> ExtractionDiagnosticsSnapshot {
        ExtractionDiagnosticsSnapshot(
            durationMs: durationMs,
            syncMatchCount: work.offsetScanBestSyncBits,
            deskewAngleDegrees: Double(work.deskewAngleRadians) * 180.0 / .pi,
            deskewScale: Double(work.deskewScale),
            topologyHypothesisRawValue: work.topologyHypothesis?.rawValue,
            gridOffsetXPx: work.gridOffsetX,
            gridOffsetYPx: work.gridOffsetY,
            majoritySyncBits: work.majorityBestSyncBits,
            macroTileWidth: work.majorityMacroTileWidth,
            rawBitGridRows: work.rawBitGridRows > 0 ? work.rawBitGridRows : nil,
            rawBitGridCols: work.rawBitGridCols > 0 ? work.rawBitGridCols : nil
        )
    }
    
    // MARK: - Progress Throttler
    final class ProgressThrottler: @unchecked Sendable {
        private var lastTime: CFAbsoluteTime = 0
        private var lastPct: Double = -1
        private let lock = NSLock()
        
        func shouldReport(_ pct: Double) -> Bool {
            lock.lock()
            defer { lock.unlock() }

            guard pct > lastPct + 1e-9 else { return false }
            if pct <= 0.0 || pct >= 1.0 {
                lastTime = CFAbsoluteTimeGetCurrent()
                lastPct = pct
                return true
            }
            
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
