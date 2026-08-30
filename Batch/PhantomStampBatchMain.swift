import Foundation
import UIKit

private struct BatchRequest: Decodable {
    var requestID: String
    var operation: String
    var inputPath: String?
    var outputPath: String?
    var payloadText: String?
    var embeddingStrength: Double?
    var syncTemplateIntensity: Double?
    var syncTemplatePath: String?
    var textureVarianceThreshold: Double?

    enum CodingKeys: String, CodingKey {
        case requestID = "request_id"
        case operation
        case inputPath = "input_path"
        case outputPath = "output_path"
        case payloadText = "payload_text"
        case embeddingStrength = "embedding_strength"
        case syncTemplateIntensity = "sync_template_intensity"
        case syncTemplatePath = "sync_template_path"
        case textureVarianceThreshold = "texture_variance_threshold"
    }
}

@main
private struct PhantomStampBatchMain {
    static func main() async {
        let service = BenchmarkWatermarkService()
        while let line = readLine(strippingNewline: true) {
            guard !line.isEmpty else { continue }
            do {
                let request = try JSONDecoder().decode(BatchRequest.self, from: Data(line.utf8))
                do {
                    let response = try await handle(request, with: service)
                    emit(response)
                } catch {
                    emit([
                        "protocol_version": 1,
                        "request_id": request.requestID,
                        "status": "error",
                        "error_type": String(describing: type(of: error)),
                        "error": error.localizedDescription,
                    ])
                }
            } catch {
                emit([
                    "protocol_version": 1,
                    "status": "error",
                    "error_type": String(describing: type(of: error)),
                    "error": error.localizedDescription,
                ])
            }
        }
    }

    private static func handle(
        _ request: BatchRequest,
        with service: BenchmarkWatermarkService
    ) async throws -> [String: Any] {
        if request.operation == "capabilities" {
            return [
                "protocol_version": 1,
                "request_id": request.requestID,
                "status": "ok",
                "operations": ["embed", "extract"],
                "minimum_payload_characters": WatermarkPayloadLimits.minimumCharacterCount,
                "maximum_payload_characters": WatermarkPayloadLimits.maximumCharacterCount,
                "payload_encoding": "restricted_ascii_text",
                "image_transport": "lossless_png_files",
                "ui_dependencies_enabled": false,
            ]
        }

        guard let inputPath = request.inputPath,
              let inputImage = UIImage(contentsOfFile: inputPath)
        else {
            throw BatchProtocolError.invalidInputPath
        }

        switch request.operation {
        case "embed":
            guard let outputPath = request.outputPath else {
                throw BatchProtocolError.missingOutputPath
            }
            guard let payloadText = request.payloadText else {
                throw BatchProtocolError.missingPayload
            }
            guard let syncTemplatePath = request.syncTemplatePath else {
                throw BatchProtocolError.missingSyncTemplatePath
            }
            let options = BenchmarkWatermarkService.EmbedOptions(
                embeddingStrength: request.embeddingStrength ?? 10,
                syncTemplateIntensity: request.syncTemplateIntensity ?? 5,
                textureVarianceThreshold: request.textureVarianceThreshold ?? 0
            )
            let started = CFAbsoluteTimeGetCurrent()
            let result = try await service.embed(
                image: inputImage,
                text: payloadText,
                options: options,
                syncTemplateURL: URL(fileURLWithPath: syncTemplatePath)
            )
            let seconds = CFAbsoluteTimeGetCurrent() - started
            try writePNG(result.image, to: outputPath)
            return [
                "protocol_version": 1,
                "request_id": request.requestID,
                "status": "ok",
                "operation": "embed",
                "seconds": seconds,
                "diagnostics": [
                    "embedding_strength": options.embeddingStrength,
                    "sync_template_intensity": options.syncTemplateIntensity,
                    "texture_variance_threshold": options.textureVarianceThreshold,
                    "visited_8x8_blocks": result.visited8x8BlockCount,
                    "smooth_reduced_8x8_blocks": result.smoothReduced8x8BlockCount,
                ],
            ]

        case "extract":
            let started = CFAbsoluteTimeGetCurrent()
            let result = try service.extract(image: inputImage)
            let seconds = CFAbsoluteTimeGetCurrent() - started
            var response: [String: Any] = [
                "protocol_version": 1,
                "request_id": request.requestID,
                "status": "ok",
                "operation": "extract",
                "seconds": seconds,
                "detected": result.detected,
                "diagnostics": diagnosticsDictionary(result.diagnostics),
            ]
            if let text = result.text {
                response["recovered_text"] = text
                response["recovered_utf8_hex"] = Data(text.utf8)
                    .map { String(format: "%02x", $0) }
                    .joined()
            }
            return response

        default:
            throw BatchProtocolError.unsupportedOperation
        }
    }

    private static func diagnosticsDictionary(
        _ value: BenchmarkWatermarkService.ExtractionDiagnostics
    ) -> [String: Any] {
        var result: [String: Any] = [
            "sync_match_count": value.syncMatchCount,
            "deskew_angle_degrees": value.deskewAngleDegrees,
            "deskew_scale": value.deskewScale,
        ]
        if let item = value.topologyHypothesis { result["topology_hypothesis"] = item }
        if let item = value.gridOffsetX { result["grid_offset_x_px"] = item }
        if let item = value.gridOffsetY { result["grid_offset_y_px"] = item }
        if let item = value.majoritySyncBits { result["majority_sync_bits"] = item }
        if let item = value.macroTileWidth { result["macro_tile_width"] = item }
        if let item = value.rawBitGridRows { result["raw_bit_grid_rows"] = item }
        if let item = value.rawBitGridCols { result["raw_bit_grid_cols"] = item }
        return result
    }

    private static func writePNG(_ image: UIImage, to path: String) throws {
        guard let data = image.pngData() else { throw BatchProtocolError.pngEncodingFailed }
        let url = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: url, options: .atomic)
    }

    private static func emit(_ response: [String: Any]) {
        guard JSONSerialization.isValidJSONObject(response),
              let data = try? JSONSerialization.data(withJSONObject: response, options: [.sortedKeys])
        else { return }
        FileHandle.standardOutput.write(data)
        FileHandle.standardOutput.write(Data([0x0a]))
    }
}

private enum BatchProtocolError: LocalizedError {
    case invalidInputPath
    case missingOutputPath
    case missingPayload
    case missingSyncTemplatePath
    case unsupportedOperation
    case pngEncodingFailed

    var errorDescription: String? {
        switch self {
        case .invalidInputPath: return "input_path does not contain a readable image."
        case .missingOutputPath: return "embed requires output_path."
        case .missingPayload: return "embed requires payload_text."
        case .missingSyncTemplatePath: return "embed requires sync_template_path."
        case .unsupportedOperation: return "operation must be capabilities, embed, or extract."
        case .pngEncodingFailed: return "Unable to encode the output image as PNG."
        }
    }
}
