//
//  ImageProcessing.swift
//  PhantomStamp
//
//  Created by Orion on 5/5/2026.
//

import Accelerate
import Foundation
import UIKit

extension WatermarkService {

    /// Converts an image to separate **Y**, **Cb**, and **Cr** planes (**full-resolution**, equivalent to **4:4:4** sampling).
    /// - Storage is **8-bit** per sample (`UInt8`), matching typical encoder layouts and reducing peak memory vs full-float planes.
    /// - Uses **vImage** (`ARGB8888` → **`kvImage444AYpCbCr8`**, ITU-R **BT.601**) when available; falls back to a **BT.601** scalar path parallelized with ``DispatchQueue/concurrentPerform(iterations:_:)``.
    /// - Rasterization keeps **`.up`** orientation via Core Graphics (see ``rasterizedBGRABytes(from:)``).
    func convertToYCbCr(image: UIImage) -> YCbCrImage? {
        guard let raster = rasterizedBGRABytes(from: image) else { return nil }
        let w = raster.width
        let h = raster.height
        let count = w * h

        let planes: (y: [UInt8], cb: [UInt8], cr: [UInt8])
        if let v = convertBGRAToYCbCrPlanesVImage444(bgra: raster.bytes, width: w, height: h) {
            planes = v
        } else {
            planes = convertBGRAToYCbCrPlanesBT601Concurrent(bgra: raster.bytes, pixelCount: count)
        }

        return YCbCrImage(
            Y: Matrix(width: w, height: h, data: planes.y),
            Cb: Matrix(width: w, height: h, data: planes.cb),
            Cr: Matrix(width: w, height: h, data: planes.cr)
        )
    }

    /// Reconstructs an **RGB** `UIImage` from **YCbCrImage** using **vImage** (**`kvImage444AYpCbCr8`** → **BGRA**) when possible; otherwise inverse **BT.601** via ``DispatchQueue/concurrentPerform(iterations:_:)``.
    /// - Uses **scale 1** and **orientation `.up`**; logical size in points equals pixel width/height.
    func convertToUIImage(from ycbcr: YCbCrImage) -> UIImage? {
        let yPlane = ycbcr.Y
        let cbPlane = ycbcr.Cb
        let crPlane = ycbcr.Cr
        guard yPlane.width > 0, yPlane.height > 0,
              yPlane.width == cbPlane.width, yPlane.height == cbPlane.height,
              yPlane.width == crPlane.width, yPlane.height == crPlane.height,
              yPlane.data.count == yPlane.width * yPlane.height else { return nil }

        let w = yPlane.width
        let h = yPlane.height

        let bgra: [UInt8]
        if let v = convertYCbCrPlanesToBGRAVImage444(y: yPlane.data, cb: cbPlane.data, cr: crPlane.data, width: w, height: h) {
            bgra = v
        } else {
            bgra = convertYCbCrPlanesToBGRABT601Concurrent(y: yPlane.data, cb: cbPlane.data, cr: crPlane.data, pixelCount: w * h)
        }

        return uiImageFromBGRA(width: w, height: h, bytes: bgra)
    }

    // MARK: - Private helpers (raster / UIImage)

    /// Rasterizes `image` into **BGRA** premultiplied-first bytes using **sRGB**.
    private func rasterizedBGRABytes(from image: UIImage) -> (width: Int, height: Int, bytes: [UInt8])? {
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
        return (pixelWidth, pixelHeight, buffer)
    }

    /// Wraps raw **BGRA** pixels in a `UIImage` (**scale 1**, **up** orientation).
    private func uiImageFromBGRA(width: Int, height: Int, bytes: [UInt8]) -> UIImage? {
        guard width > 0, height > 0, bytes.count == width * height * 4 else { return nil }
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        let bitmapInfo = CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue
        let bytesPerRow = width * 4

        var copy = bytes
        let cgImage: CGImage? = copy.withUnsafeMutableBytes { rawPtr in
            guard let ctx = CGContext(
                data: rawPtr.baseAddress,
                width: width,
                height: height,
                bitsPerComponent: 8,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: bitmapInfo
            ) else { return nil }
            return ctx.makeImage()
        }

        guard let cgImage else { return nil }
        return UIImage(cgImage: cgImage, scale: 1.0, orientation: .up)
    }
}

// MARK: - vImage 4:4:4 (non-420) + concurrent BT.601 fallback

/// Apple’s documented **full-range** 8-bit example (`vImage_YpCbCrPixelRange`).
private let phantomStampFullRangeYCbCr8 = vImage_YpCbCrPixelRange(
    Yp_bias: 0, CbCr_bias: 128, YpRangeMax: 255, CbCrRangeMax: 255,
    YpMax: 255, YpMin: 1, CbCrMax: 255, CbCrMin: 0
)

/// Memory order **BGRA** → `permuteMap` for APIs that label channels **A,R,G,B** (`449AYpCbCr8` path treats indices `[A,R,G,B]`).
private let phantomStampBGRAPermuteToARGBChannelOrder: [UInt8] = [3, 2, 1, 0]

private func convertBGRAToYCbCrPlanesVImage444(bgra: [UInt8], width w: Int, height h: Int) -> (y: [UInt8], cb: [UInt8], cr: [UInt8])? {
    let count = w * h
    var pixelRange = phantomStampFullRangeYCbCr8
    var argbToYpCbCr = vImage_ARGBToYpCbCr()
    var genErr = vImageConvert_ARGBToYpCbCr_GenerateConversion(
        kvImage_ARGBToYpCbCrMatrix_ITU_R_601_4,
        &pixelRange,
        &argbToYpCbCr,
        kvImageARGB8888,
        kvImage444AYpCbCr8,
        vImage_Flags(kvImageNoFlags)
    )
    guard genErr == kvImageNoError else { return nil }

    var interleaved444 = [UInt8](repeating: 0, count: count * 4)

    let convErr = bgra.withUnsafeBufferPointer { srcPtr -> vImage_Error in
        var srcBuffer = vImage_Buffer(
            data: UnsafeMutableRawPointer(mutating: srcPtr.baseAddress!),
            height: vImagePixelCount(h),
            width: vImagePixelCount(w),
            rowBytes: w * 4
        )
        return interleaved444.withUnsafeMutableBytes { dstRaw -> vImage_Error in
            var dstBuffer = vImage_Buffer(
                data: dstRaw.baseAddress!,
                height: vImagePixelCount(h),
                width: vImagePixelCount(w),
                rowBytes: w * 4
            )
            return phantomStampBGRAPermuteToARGBChannelOrder.withUnsafeBufferPointer { pmap in
                vImageConvert_ARGB8888To444AYpCbCr8(
                    &srcBuffer,
                    &dstBuffer,
                    &argbToYpCbCr,
                    pmap.baseAddress!,
                    vImage_Flags(kvImageNoFlags)
                )
            }
        }
    }
    guard convErr == kvImageNoError else { return nil }

    var y = [UInt8](repeating: 0, count: count)
    var cb = [UInt8](repeating: 0, count: count)
    var cr = [UInt8](repeating: 0, count: count)

    let extractErr = interleaved444.withUnsafeMutableBytes { srcRaw -> vImage_Error in
        var srcBuffer = vImage_Buffer(
            data: srcRaw.baseAddress!,
            height: vImagePixelCount(h),
            width: vImagePixelCount(w),
            rowBytes: w * 4
        )
        return y.withUnsafeMutableBytes { yRaw -> vImage_Error in
            var yBuf = vImage_Buffer(
                data: yRaw.baseAddress!,
                height: vImagePixelCount(h),
                width: vImagePixelCount(w),
                rowBytes: w
            )
            let eY = vImageExtractChannel_ARGB8888(&srcBuffer, &yBuf, 1, vImage_Flags(kvImageNoFlags))
            guard eY == kvImageNoError else { return eY }
            return cb.withUnsafeMutableBytes { cbRaw -> vImage_Error in
                var cbBuf = vImage_Buffer(
                    data: cbRaw.baseAddress!,
                    height: vImagePixelCount(h),
                    width: vImagePixelCount(w),
                    rowBytes: w
                )
                let eCb = vImageExtractChannel_ARGB8888(&srcBuffer, &cbBuf, 2, vImage_Flags(kvImageNoFlags))
                guard eCb == kvImageNoError else { return eCb }
                return cr.withUnsafeMutableBytes { crRaw -> vImage_Error in
                    var crBuf = vImage_Buffer(
                        data: crRaw.baseAddress!,
                        height: vImagePixelCount(h),
                        width: vImagePixelCount(w),
                        rowBytes: w
                    )
                    return vImageExtractChannel_ARGB8888(&srcBuffer, &crBuf, 3, vImage_Flags(kvImageNoFlags))
                }
            }
        }
    }
    guard extractErr == kvImageNoError else { return nil }

    return (y, cb, cr)
}

private func convertYCbCrPlanesToBGRAVImage444(y: [UInt8], cb: [UInt8], cr: [UInt8], width w: Int, height h: Int) -> [UInt8]? {
    let count = w * h
    guard y.count == count, cb.count == count, cr.count == count else { return nil }

    var pixelRange = phantomStampFullRangeYCbCr8
    var ypCbCrToARGB = vImage_YpCbCrToARGB()
    let genErr = vImageConvert_YpCbCrToARGB_GenerateConversion(
        kvImage_YpCbCrToARGBMatrix_ITU_R_601_4,
        &pixelRange,
        &ypCbCrToARGB,
        kvImage444AYpCbCr8,
        kvImageARGB8888,
        vImage_Flags(kvImageNoFlags)
    )
    guard genErr == kvImageNoError else { return nil }

    var interleaved444 = [UInt8](repeating: 0, count: count * 4)

    DispatchQueue.concurrentPerform(iterations: count) { i in
        let o = i * 4
        interleaved444[o] = 255
        interleaved444[o + 1] = y[i]
        interleaved444[o + 2] = cb[i]
        interleaved444[o + 3] = cr[i]
    }

    var bgra = [UInt8](repeating: 0, count: count * 4)

    let convErr = interleaved444.withUnsafeMutableBytes { srcRaw -> vImage_Error in
        var srcBuffer = vImage_Buffer(
            data: srcRaw.baseAddress!,
            height: vImagePixelCount(h),
            width: vImagePixelCount(w),
            rowBytes: w * 4
        )
        return bgra.withUnsafeMutableBytes { dstRaw -> vImage_Error in
            var dstBuffer = vImage_Buffer(
                data: dstRaw.baseAddress!,
                height: vImagePixelCount(h),
                width: vImagePixelCount(w),
                rowBytes: w * 4
            )
            return phantomStampBGRAPermuteToARGBChannelOrder.withUnsafeBufferPointer { pmap in
                vImageConvert_444AYpCbCr8ToARGB8888(
                    &srcBuffer,
                    &dstBuffer,
                    &ypCbCrToARGB,
                    pmap.baseAddress!,
                    vImage_Flags(kvImageNoFlags)
                )
            }
        }
    }

    guard convErr == kvImageNoError else { return nil }
    return bgra
}

private func convertBGRAToYCbCrPlanesBT601Concurrent(bgra: [UInt8], pixelCount count: Int) -> (y: [UInt8], cb: [UInt8], cr: [UInt8]) {
    var yData = [UInt8](repeating: 0, count: count)
    var cbData = [UInt8](repeating: 0, count: count)
    var crData = [UInt8](repeating: 0, count: count)

    DispatchQueue.concurrentPerform(iterations: count) { i in
        let base = i * 4
        let b = Float(bgra[base])
        let g = Float(bgra[base + 1])
        let r = Float(bgra[base + 2])

        let y = 0.299 * r + 0.587 * g + 0.114 * b
        let cb = -0.168_736 * r - 0.331_264 * g + 0.5 * b + 128
        let cr = 0.5 * r - 0.418_688 * g - 0.081_312 * b + 128

        yData[i] = UInt8(clamping: Int(y.rounded()))
        cbData[i] = UInt8(clamping: Int(cb.rounded()))
        crData[i] = UInt8(clamping: Int(cr.rounded()))
    }

    return (yData, cbData, crData)
}

private func convertYCbCrPlanesToBGRABT601Concurrent(y: [UInt8], cb: [UInt8], cr: [UInt8], pixelCount count: Int) -> [UInt8] {
    var bgra = [UInt8](repeating: 0, count: count * 4)

    DispatchQueue.concurrentPerform(iterations: count) { i in
        let yv = Float(y[i])
        let cbv = Float(cb[i]) - 128
        let crv = Float(cr[i]) - 128

        let rf = yv + 1.402 * crv
        let gf = yv - 0.344_136 * cbv - 0.714_136 * crv
        let bf = yv + 1.772 * cbv

        let o = i * 4
        bgra[o] = UInt8(clamping: Int(bf.rounded()))
        bgra[o + 1] = UInt8(clamping: Int(gf.rounded()))
        bgra[o + 2] = UInt8(clamping: Int(rf.rounded()))
        bgra[o + 3] = 255
    }

    return bgra
}
