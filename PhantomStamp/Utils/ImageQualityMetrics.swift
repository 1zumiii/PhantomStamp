//
//  ImageQualityMetrics.swift
//  PhantomStamp
//

import UIKit

enum ImageQualityMetrics {
    struct Result: Sendable {
        let width: Int
        let height: Int
        let pixelCount: Int
        let mseRGB: Double
        let maeRGB: Double
        let maxAbsRGB: Int
        let psnrDB: Double
        let ssimLuma: Double

        var formattedPSNR: String {
            psnrDB.isFinite ? String(format: "%.2f dB", psnrDB) : "∞ dB"
        }

        var formattedSSIM: String {
            String(format: "%.5f", ssimLuma)
        }

        var formattedMSE: String {
            String(format: "%.3f", mseRGB)
        }

        var formattedMAE: String {
            String(format: "%.3f", maeRGB)
        }
    }

    enum MetricError: LocalizedError {
        case invalidImage
        case sizeMismatch(original: (w: Int, h: Int), compared: (w: Int, h: Int))

        var errorDescription: String? {
            switch self {
            case .invalidImage:
                return "Could not decode image pixels for quality measurement."
            case let .sizeMismatch(original, compared):
                return "Images must have identical dimensions. Original: \(original.w)×\(original.h), compared: \(compared.w)×\(compared.h)."
            }
        }
    }

    static func compare(original: UIImage, compared: UIImage) throws -> Result {
        guard let a = rgbaBuffer(from: original),
              let b = rgbaBuffer(from: compared)
        else {
            throw MetricError.invalidImage
        }

        guard a.width == b.width, a.height == b.height else {
            throw MetricError.sizeMismatch(
                original: (a.width, a.height),
                compared: (b.width, b.height)
            )
        }

        let pixelCount = a.width * a.height
        guard pixelCount > 0 else { throw MetricError.invalidImage }

        var sumSquaredRGB = 0.0
        var sumAbsRGB = 0.0
        var maxAbsRGB = 0

        var sumY1 = 0.0
        var sumY2 = 0.0
        var sumY1Squared = 0.0
        var sumY2Squared = 0.0
        var sumYProduct = 0.0

        for offset in stride(from: 0, to: a.rgba.count, by: 4) {
            let r1 = Double(a.rgba[offset])
            let g1 = Double(a.rgba[offset + 1])
            let b1 = Double(a.rgba[offset + 2])
            let r2 = Double(b.rgba[offset])
            let g2 = Double(b.rgba[offset + 1])
            let b2 = Double(b.rgba[offset + 2])

            let dr = r1 - r2
            let dg = g1 - g2
            let db = b1 - b2

            sumSquaredRGB += dr * dr + dg * dg + db * db
            sumAbsRGB += abs(dr) + abs(dg) + abs(db)
            maxAbsRGB = max(maxAbsRGB, Int(abs(dr)), Int(abs(dg)), Int(abs(db)))

            let y1 = 0.299 * r1 + 0.587 * g1 + 0.114 * b1
            let y2 = 0.299 * r2 + 0.587 * g2 + 0.114 * b2
            sumY1 += y1
            sumY2 += y2
            sumY1Squared += y1 * y1
            sumY2Squared += y2 * y2
            sumYProduct += y1 * y2
        }

        let rgbSampleCount = Double(pixelCount * 3)
        let mse = sumSquaredRGB / rgbSampleCount
        let mae = sumAbsRGB / rgbSampleCount
        let psnr = mse == 0 ? Double.infinity : 20.0 * log10(255.0 / sqrt(mse))

        let n = Double(pixelCount)
        let meanY1 = sumY1 / n
        let meanY2 = sumY2 / n
        let varianceY1 = max(0, sumY1Squared / n - meanY1 * meanY1)
        let varianceY2 = max(0, sumY2Squared / n - meanY2 * meanY2)
        let covariance = sumYProduct / n - meanY1 * meanY2
        let c1 = pow(0.01 * 255.0, 2.0)
        let c2 = pow(0.03 * 255.0, 2.0)
        let ssim = ((2 * meanY1 * meanY2 + c1) * (2 * covariance + c2))
            / ((meanY1 * meanY1 + meanY2 * meanY2 + c1) * (varianceY1 + varianceY2 + c2))

        return Result(
            width: a.width,
            height: a.height,
            pixelCount: pixelCount,
            mseRGB: mse,
            maeRGB: mae,
            maxAbsRGB: maxAbsRGB,
            psnrDB: psnr,
            ssimLuma: min(max(ssim, 0), 1)
        )
    }

    private struct RGBABuffer {
        let width: Int
        let height: Int
        let rgba: [UInt8]
    }

    private static func rgbaBuffer(from image: UIImage) -> RGBABuffer? {
        let width = max(1, Int((image.size.width * image.scale).rounded()))
        let height = max(1, Int((image.size.height * image.scale).rounded()))
        let rect = CGRect(x: 0, y: 0, width: width, height: height)

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true

        let normalized = UIGraphicsImageRenderer(size: rect.size, format: format).image { context in
            UIColor.black.setFill()
            context.fill(rect)
            image.draw(in: rect)
        }

        guard let cgImage = normalized.cgImage,
              let colorSpace = CGColorSpace(name: CGColorSpace.sRGB)
        else { return nil }

        var rgba = [UInt8](repeating: 0, count: width * height * 4)
        let ok = rgba.withUnsafeMutableBytes { ptr in
            guard let baseAddress = ptr.baseAddress,
                  let context = CGContext(
                    data: baseAddress,
                    width: width,
                    height: height,
                    bitsPerComponent: 8,
                    bytesPerRow: width * 4,
                    space: colorSpace,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                  )
            else {
                return false
            }
            context.interpolationQuality = .high
            context.draw(cgImage, in: rect)
            return true
        }

        guard ok else { return nil }
        return RGBABuffer(width: width, height: height, rgba: rgba)
    }
}

