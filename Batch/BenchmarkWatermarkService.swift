import Foundation
import UIKit

/// Headless benchmark-only orchestration around the production DSP implementation.
///
/// This type deliberately has no dependency on SwiftUI, SwiftData, UserDefaults,
/// notifications, progress overlays, or `WatermarkService`. The benchmark and app
/// therefore execute the same `WatermarkAlgorithmCore` and extension methods without
/// allowing UI handshakes or persistence work to contaminate algorithm timings.
nonisolated struct BenchmarkWatermarkService: Sendable {
    nonisolated struct EmbedOptions: Sendable {
        var embeddingStrength: Double
        var syncTemplateIntensity: Double
        var textureVarianceThreshold: Double

        func validated() throws -> EmbedOptions {
            guard embeddingStrength.isFinite, (0...10).contains(embeddingStrength) else {
                throw BenchmarkWatermarkError.invalidEmbeddingStrength
            }
            guard syncTemplateIntensity.isFinite, (0...10).contains(syncTemplateIntensity) else {
                throw BenchmarkWatermarkError.invalidSyncTemplateIntensity
            }
            guard textureVarianceThreshold.isFinite, textureVarianceThreshold >= 0 else {
                throw BenchmarkWatermarkError.invalidTextureVarianceThreshold
            }
            return self
        }
    }

    nonisolated struct EmbedResult: Sendable {
        var image: UIImage
        var visited8x8BlockCount: Int
        var smoothReduced8x8BlockCount: Int
    }

    nonisolated struct ExtractionDiagnostics: Sendable {
        var syncMatchCount: Int
        var deskewAngleDegrees: Double
        var deskewScale: Double
        var topologyHypothesis: String?
        var gridOffsetX: Int?
        var gridOffsetY: Int?
        var majoritySyncBits: Int?
        var macroTileWidth: Int?
        var rawBitGridRows: Int?
        var rawBitGridCols: Int?
    }

    nonisolated struct ExtractionResult: Sendable {
        var detected: Bool
        var text: String?
        var diagnostics: ExtractionDiagnostics
    }

    private struct ExtractionWork: Sendable {
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

    private let algorithms = WatermarkAlgorithmCore()

    func embed(
        image: UIImage,
        text: String,
        options uncheckedOptions: EmbedOptions,
        syncTemplateURL: URL
    ) async throws -> EmbedResult {
        let options = try uncheckedOptions.validated()
        guard image.size.width >= 128, image.size.height >= 128 else {
            throw BenchmarkWatermarkError.imageTooSmall
        }
        guard WatermarkPayloadLimits.isValidUserPayload(text) else {
            throw BenchmarkWatermarkError.invalidPayload
        }

        let payloadBits = getSyncMarkerBits() + encodeFEC(text: text)
        let macroblock = build2DTile(from: payloadBits)
        guard var ycbcrImage = algorithms.convertToYCbCr(image: image) else {
            throw BenchmarkWatermarkError.imageConversionFailed
        }

        var strips = algorithms.sliceImage(ycbcrImage.Y, heightPerStrip: 80)
        let threshold = Float(options.textureVarianceThreshold)
        let strength = AppConstants.embeddingStrengthMultiplier(for: options.embeddingStrength)
        let algorithms = algorithms

        var visited = 0
        var smoothReduced = 0
        await withTaskGroup(of: (ImageStrip, Int, Int).self) { group in
            for strip in strips {
                group.addTask {
                    autoreleasepool {
                        let result = algorithms.processSingleStripForEmbedding(
                            strip: strip,
                            macroblock: macroblock,
                            thresholdSmooth: threshold,
                            embeddingStrengthMultiplier: strength,
                            varianceGainCurve: nil
                        )
                        return (result.strip, result.visited8x8Blocks, result.smoothSkipped8x8Blocks)
                    }
                }
            }

            for await (processedStrip, stripVisited, stripSmoothReduced) in group {
                algorithms.updateStripInPlace(&strips, with: processedStrip)
                visited += stripVisited
                smoothReduced += stripSmoothReduced
            }
        }

        algorithms.reassembleStrips(strips, into: &ycbcrImage.Y)
        let syncTemplate = try algorithms.loadSpatialSyncTemplate(from: syncTemplateURL)
        algorithms.applySpatialTiling(
            to: &ycbcrImage.Y,
            template: syncTemplate,
            intensity: Float(options.syncTemplateIntensity)
        )
        guard let output = algorithms.convertToUIImage(from: ycbcrImage) else {
            throw BenchmarkWatermarkError.imageConversionFailed
        }
        return EmbedResult(
            image: output,
            visited8x8BlockCount: visited,
            smoothReduced8x8BlockCount: smoothReduced
        )
    }

    func extract(image: UIImage) throws -> ExtractionResult {
        guard let ycbcrImage = algorithms.convertToYCbCr(image: image) else {
            throw BenchmarkWatermarkError.imageConversionFailed
        }
        let yChannel = ycbcrImage.Y
        let transformCandidates = algorithms.detectGeometricTransformCandidates(in: yChannel)

        func validationScore(_ work: ExtractionWork) -> Int {
            (work.majorityBestSyncBits ?? 0) * 100 + work.offsetScanBestSyncBits
        }

        var selectedWork: ExtractionWork?
        var bestFailedWork: ExtractionWork?

        for transform in transformCandidates {
            let deskewed = algorithms.deskewImage(
                yChannel,
                angle: transform.angle,
                scale: transform.scale
            )
            let gridScan = algorithms.findGridOffsetAndSyncMarker(in: deskewed)

            guard let gridOffset = gridScan.offset else {
                let failed = ExtractionWork(
                    payloadBitsWithoutSync: [],
                    deskewAngleRadians: transform.angle,
                    deskewScale: transform.scale,
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

            let rawScores = algorithms.extractSoftBitsWithOffset(deskewed, offset: gridOffset)
            let voting = algorithms.applySoftMajorityVotingWithDiagnostics(
                to: rawScores,
                preferredHypothesis: gridScan.topologyHypothesis,
                preferredHypothesisIsExact: gridScan.bestSyncBitsMatched == 32
            )
            let syncCount = getSyncMarkerBits().count
            let payload = voting.bits.count >= syncCount
                ? Array(voting.bits.dropFirst(syncCount))
                : []
            let majority = voting.diagnostics
            let fecPassed = majority?.fecValidated == true
            let work = ExtractionWork(
                payloadBitsWithoutSync: payload,
                deskewAngleRadians: transform.angle,
                deskewScale: transform.scale,
                offsetScanBestSyncBits: gridScan.bestSyncBitsMatched,
                gridOffsetX: Int(gridOffset.x),
                gridOffsetY: Int(gridOffset.y),
                rawBitGridRows: rawScores.count,
                rawBitGridCols: rawScores.first?.count ?? 0,
                majorityBestSyncBits: majority?.bestSyncBitsMatched,
                majorityMacroTileWidth: majority?.macroTileWidth,
                topologyHypothesis: fecPassed ? majority?.topologyHypothesis : nil
            )

            if fecPassed {
                selectedWork = work
                break
            }
            if bestFailedWork == nil || validationScore(work) > validationScore(bestFailedWork!) {
                bestFailedWork = work
            }
        }

        let work = selectedWork ?? bestFailedWork ?? ExtractionWork(
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

        let diagnostics = ExtractionDiagnostics(
            syncMatchCount: work.offsetScanBestSyncBits,
            deskewAngleDegrees: Double(work.deskewAngleRadians) * 180 / .pi,
            deskewScale: Double(work.deskewScale),
            topologyHypothesis: work.topologyHypothesis?.rawValue,
            gridOffsetX: work.gridOffsetX,
            gridOffsetY: work.gridOffsetY,
            majoritySyncBits: work.majorityBestSyncBits,
            macroTileWidth: work.majorityMacroTileWidth,
            rawBitGridRows: work.rawBitGridRows > 0 ? work.rawBitGridRows : nil,
            rawBitGridCols: work.rawBitGridCols > 0 ? work.rawBitGridCols : nil
        )

        guard selectedWork != nil else {
            return ExtractionResult(detected: false, text: nil, diagnostics: diagnostics)
        }

        for length in 1...WatermarkPayloadLimits.maximumCharacterCount {
            let rawBitCount = 8 + length * 8
            let paddedRawBitCount = ((rawBitCount + 3) / 4) * 4
            let encodedBitCount = (paddedRawBitCount / 4) * 8
            guard work.payloadBitsWithoutSync.count >= encodedBitCount else { continue }
            let encodedBits = Array(work.payloadBitsWithoutSync.prefix(encodedBitCount))
            if let text = decodeFEC(bits: encodedBits, expectedMessageLengthBytes: length) {
                return ExtractionResult(detected: true, text: text, diagnostics: diagnostics)
            }
        }

        return ExtractionResult(detected: false, text: nil, diagnostics: diagnostics)
    }
}

nonisolated enum BenchmarkWatermarkError: LocalizedError {
    case imageTooSmall
    case invalidPayload
    case invalidEmbeddingStrength
    case invalidSyncTemplateIntensity
    case invalidTextureVarianceThreshold
    case imageConversionFailed

    var errorDescription: String? {
        switch self {
        case .imageTooSmall:
            return "Image must be at least 128 by 128 pixels."
        case .invalidPayload:
            return "Payload must contain 8 to 16 supported ASCII characters."
        case .invalidEmbeddingStrength:
            return "Embedding strength must be between 0 and 10."
        case .invalidSyncTemplateIntensity:
            return "Sync-template intensity must be between 0 and 10."
        case .invalidTextureVarianceThreshold:
            return "Texture-variance threshold must be finite and non-negative."
        case .imageConversionFailed:
            return "Image conversion failed."
        }
    }
}
