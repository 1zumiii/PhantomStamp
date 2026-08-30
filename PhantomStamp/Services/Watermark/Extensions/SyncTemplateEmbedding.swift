//
//  DFTSyncTemplate.swift
//  PhantomStamp
//
//  Created by Orion on 8/6/2026.
//

import Foundation
import UIKit


nonisolated extension WatermarkAlgorithmCore {
    
    // ==========================================
    // MARK: - Core Function 1: Spatial Tiling
    // ==========================================
    
    /// Tiles the 512x512 synchronization template infinitely across the host image's Y-channel.
    ///
    /// IMPLEMENTATION GUIDE:
    /// 1. Loop over every pixel in `yChannel` (which is UInt8).
    /// 2. For each pixel, get the corresponding template value using modulo math.
    /// 3. Convert the UInt8 pixel to Float, add the scaled template value.
    /// 4. Clamp the final result strictly between 0.0 and 255.0, then cast back to UInt8.
    func applySpatialTiling(to yChannel: inout Matrix, template: FFTFloatMatrix, intensity: Float) {
        let width = yChannel.width
        let height = yChannel.height
        let tWidth = template.width
        let tHeight = template.height

        precondition(tWidth > 0 && tHeight > 0, "Template dimensions must be positive")
        precondition(yChannel.data.count == width * height, "Y channel data size does not match width * height")

        // Bind both buffers to raw pointers so the inner loop avoids per-pixel
        // subscript bound-checks and copy-on-write probing on the [Float] storage.
        template.values.withUnsafeBufferPointer { tPtr in
            yChannel.data.withUnsafeMutableBufferPointer { yPtr in
                for y in 0..<height {
                    let templateY = y % tHeight
                    let templateRowBase = templateY * tWidth
                    let rowOffset = y * width

                    for x in 0..<width {
                        let templateX = x % tWidth
                        let pixelIndex = rowOffset + x

                        let originalPixel = Float(yPtr[pixelIndex])
                        let tValue = tPtr[templateRowBase + templateX]

                        let newPixel = originalPixel + tValue * intensity

                        // Round-to-nearest (instead of truncating) keeps the ±ripple energy symmetric.
                        // Plain `UInt8(Float)` truncates toward zero and would suppress the positive half
                        // of the template wave, destroying the FFT peak symmetry the extractor relies on.
                        let clamped = min(max(newPixel, 0.0), 255.0)
                        yPtr[pixelIndex] = UInt8(clamping: Int(clamped.rounded()))
                    }
                }
            }
        }
    }
    
    // ==========================================
    // MARK: - Helper Functions for Tiling
    // ==========================================
    
    /// Loads the pre-computed 512x512 spatial domain synchronization template from the bundle.
    func loadSpatialSyncTemplate() -> FFTFloatMatrix {
        return WatermarkAlgorithmCore.cachedSyncTemplate
    }

    /// Headless callers do not have an app bundle. They must provide the exact template artifact
    /// explicitly so a benchmark cannot silently use a generated or different resource.
    func loadSpatialSyncTemplate(from url: URL) throws -> FFTFloatMatrix {
        try WatermarkAlgorithmCore.readSpatialSyncTemplate(from: url)
    }
    
    /// Maps global image coordinates to local 512x512 template coordinates.
    ///
    /// Uses Euclidean modulo so callers can safely pass negative coordinates
    /// (e.g. when probing pixels around a deskew anchor point).
    @inline(__always)
    func getTemplateValue(from template: FFTFloatMatrix, globalX: Int, globalY: Int) -> Float {
        let tWidth = template.width
        let tHeight = template.height
        precondition(tWidth > 0 && tHeight > 0, "Template dimensions must be positive")

        // Swift's `%` keeps the sign of the dividend, so wrap into [0, t-1] explicitly.
        let tx = ((globalX % tWidth) + tWidth) % tWidth
        let ty = ((globalY % tHeight) + tHeight) % tHeight
        return template[ty, tx]
    }

    /// Ensures the pixel value safely stays within valid grayscale bounds [0.0, 255.0].
    ///
    /// WARNING (Gotchas):
    /// - DO NOT use standard integer casting without checking, as floats > 255 or < 0 will crash Swift.
    @inline(__always)
    func clampToUInt8Range(_ value: Float) -> Float {
        return min(max(value, 0.0), 255.0)
    }
    
    
    // =================================================
    // MARK: - Pre-computed 512x512 Sync Template Cache
    // =================================================
    
    private static let cachedSyncTemplate: FFTFloatMatrix = {
        let fileName = "sync_template_512"
        let ext = "bin"
        
        // Find the binary file in the App Bundle
        guard let url = Bundle.main.url(forResource: fileName, withExtension: ext) else {
            fatalError("Fatal error: Could not find \(fileName).\(ext) in the App Bundle! Please check the Target selection in Xcode.")
        }
        
        do {
            return try readSpatialSyncTemplate(from: url)
        } catch {
            fatalError("Fatal error: Failed to load sync template binary file - \(error)")
        }
    }()

    private static func readSpatialSyncTemplate(from url: URL) throws -> FFTFloatMatrix {
        let data = try Data(contentsOf: url)
        let expectedBytes = 512 * 512 * MemoryLayout<Float>.size
        guard data.count == expectedBytes else {
            throw SpatialSyncTemplateError.invalidByteCount(
                expected: expectedBytes,
                actual: data.count
            )
        }
        let values = data.withUnsafeBytes { buffer -> [Float] in
            Array(buffer.bindMemory(to: Float.self))
        }
        return FFTFloatMatrix(width: 512, height: 512, values: values)
    }
}

private enum SpatialSyncTemplateError: LocalizedError {
    case invalidByteCount(expected: Int, actual: Int)

    var errorDescription: String? {
        switch self {
        case let .invalidByteCount(expected, actual):
            return "Sync template has \(actual) bytes; expected \(expected)."
        }
    }
}
