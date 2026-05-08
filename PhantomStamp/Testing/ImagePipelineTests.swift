//
//  ImagePipelineTests.swift
//  PhantomStamp
//
//  Centralized validation helpers for the image pipeline (asset-driven checks).
//

import UIKit

/// Manual / DEBUG-entry validation for raster → **YCbCr** → raster paths.
///
/// Source PNG on disk (for editors only): `PhantomStamp/Assets.xcassets/TestImg.imageset/TestImg.png`  
/// At runtime the catalog exposes this asset as ``bundledTestAssetName``.
enum ImagePipelineTests {

    /// Matches **Assets.xcassets / TestImg.imageset**.
    static let bundledTestAssetName = "TestImg"

    /// Result of comparing **BGRA** pixels before vs after ``WatermarkService/convertToYCbCr(image:)`` + ``WatermarkService/convertToUIImage(from:)``.
    struct YCbCrRoundTripReport: Sendable {
        var width: Int
        var height: Int
        /// Mean absolute error over **B,G,R** (alpha ignored), range **0…255**.
        var meanAbsoluteErrorRGB: Double
        /// Worst channel difference on **B,G,R** at any pixel.
        var maxAbsoluteErrorRGB: Int
        /// Whether metrics stay within ``meanAbsPassThreshold`` / ``maxAbsPassThreshold``.
        var passedHeuristic: Bool

        static let meanAbsPassThreshold: Double = 4
        static let maxAbsPassThreshold: Int = 28
    }

    /// Loads **TestImg** from the main bundle (compiled asset catalog).
    static func loadBundledTestUIImage() -> UIImage? {
        UIImage(named: bundledTestAssetName, in: .main, compatibleWith: nil)
    }

    /// Runs **YCbCr → RGB** shuttle on the bundled **TestImg** and compares pixels to the original rasterization.
    static func runBundledTestImgYCbCrRoundTrip() -> YCbCrRoundTripReport? {
        guard let image = loadBundledTestUIImage() else { return nil }
        return validateYCbCrRoundTrip(image: image)
    }

    /// Full shuttle via ``WatermarkService`` plus **BGRA** difference metrics (must match pipeline raster conventions).
    static func validateYCbCrRoundTrip(image: UIImage) -> YCbCrRoundTripReport? {
        guard let before = rasterizeBGRAUpSrgb(image: image) else { return nil }
        let service = WatermarkService()
        guard let ycbcr = service.convertToYCbCr(image: image),
              let reconstructed = service.convertToUIImage(from: ycbcr),
              let after = rasterizeBGRAUpSrgb(image: reconstructed),
              before.width == after.width,
              before.height == after.height,
              before.bytes.count == after.bytes.count else { return nil }

        let w = before.width
        let h = before.height
        let pixelCount = w * h
        var sum: Double = 0
        var worst = 0
        for i in 0..<pixelCount {
            let o = i * 4
            for c in 0..<3 {
                let d = abs(Int(before.bytes[o + c]) - Int(after.bytes[o + c]))
                sum += Double(d)
                worst = max(worst, d)
            }
        }
        let denom = Double(pixelCount * 3)
        let mae = sum / denom

        let passed = mae <= YCbCrRoundTripReport.meanAbsPassThreshold
            && worst <= YCbCrRoundTripReport.maxAbsPassThreshold

        return YCbCrRoundTripReport(
            width: w,
            height: h,
            meanAbsoluteErrorRGB: mae,
            maxAbsoluteErrorRGB: worst,
            passedHeuristic: passed
        )
    }

    /// Runs all bundled validations and prints one line per check (**DEBUG**).
    static func runAllBundledAndPrint() {
        #if DEBUG
        if let r = runBundledTestImgYCbCrRoundTrip() {
            let status = r.passedHeuristic ? "PASS" : "FAIL"
            print("[ImagePipelineTests] \(status) YCbCr Round-Trip — \(bundledTestAssetName) \(r.width)×\(r.height)")
            print("  - MAE_rgb: \(String(format: "%.4f", r.meanAbsoluteErrorRGB)) (≤ \(String(format: "%.1f", YCbCrRoundTripReport.meanAbsPassThreshold)))")
            print("  - max_rgb: \(r.maxAbsoluteErrorRGB) (≤ \(YCbCrRoundTripReport.maxAbsPassThreshold))")
        } else {
            print("[ImagePipelineTests] FAIL YCbCr Round-Trip — missing \(bundledTestAssetName) or round-trip / raster mismatch")
        }
        #endif
    }

    // MARK: - Raster (aligned with ImageProcessing)

    private struct RasterBGRA {
        var width: Int
        var height: Int
        var bytes: [UInt8]
    }

    /// **BGRA**, premultiplied-first, **sRGB**, UIKit-style vertical orientation for sampling (**`.up`** matrix row order).
    private static func rasterizeBGRAUpSrgb(image: UIImage) -> RasterBGRA? {
        let pixelWidth = Int(image.size.width * image.scale)
        let pixelHeight = Int(image.size.height * image.scale)
        guard pixelWidth > 0, pixelHeight > 0 else { return nil }

        let bytesPerPixel = 4
        let bytesPerRow = pixelWidth * bytesPerPixel
        var buffer = [UInt8](repeating: 0, count: pixelHeight * bytesPerRow)

        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        let bitmapInfo = CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue

        let ok = buffer.withUnsafeMutableBytes { rawPtr -> Bool in
            guard let ctx = CGContext(
                data: rawPtr.baseAddress,
                width: pixelWidth,
                height: pixelHeight,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: bitmapInfo
            ) else { return false }
            ctx.translateBy(x: 0, y: CGFloat(pixelHeight))
            ctx.scaleBy(x: 1, y: -1)
            UIGraphicsPushContext(ctx)
            image.draw(in: CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))
            UIGraphicsPopContext()
            return true
        }

        guard ok else { return nil }
        return RasterBGRA(width: pixelWidth, height: pixelHeight, bytes: buffer)
    }
}
