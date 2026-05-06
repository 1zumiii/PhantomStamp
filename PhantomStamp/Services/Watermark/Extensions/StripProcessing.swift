//
//  WatermarkService+StripProcessing.swift
//  PhantomStamp
//

import UIKit

extension WatermarkService {
    
    // ==========================================
    // 私有子线程运算逻辑 (单条带处理)
    // ==========================================
    func processSingleStripForEmbedding(strip: ImageStrip, macroblock: Macroblock2D) -> ImageStrip {
        var resultStrip = strip
        
        // 遍历条带内的每一个 8x8 像素块
        for blockY in stride(from: 0, to: strip.height, by: 8) {
        for blockX in stride(from: 0, to: strip.width, by: 8) {
                
                // TODO: 获取当前的 8x8 像素块矩阵
                var pixelBlock = strip.get8x8Block(x: blockX, y: blockY)
                
                // TODO: 计算方差，判断是否为平滑块
                let variance = calculateVariance(pixelBlock)
                let thresholdSmooth: Float = 10.5
                if variance < thresholdSmooth {
                    continue // 跳过平滑区以保证隐蔽性
                }
                
                // 1. 正向二维离散余弦变换 (vDSP_DCT2D)
                // TODO: 执行 DCT
                var freqBlock = performDCT(pixelBlock)
                
                // 2. 映射二维邮戳数据
                // 结合全局偏移量，计算该图像块对应宏块中的哪一个比特
                let targetBit = macroblock.getBitAt(imageX: blockX + strip.globalXOffset,
                                                    imageY: blockY + strip.globalYOffset)
                
                // 3. 修改中频系数
                // TODO: 修改指定的两对中频系数大小关系，嵌入 targetBit
                embedBitIntoFrequencies(&freqBlock, bit: targetBit)
                
                // 4. 逆向二维离散余弦变换 (vDSP_IDCT2D)
                // TODO: 执行 IDCT
                pixelBlock = performIDCT(freqBlock)
                
                // 5. 将处理好的块写回条带
                // TODO: 将 pixelBlock 数据覆盖到 resultStrip 的对应位置
                resultStrip.write8x8Block(pixelBlock, x: blockX, y: blockY)
            }
        }
        
        return resultStrip
    }
    /// Embeds one payload bit into the mid-frequency band of an 8×8 DCT block.
    ///
    /// Strategy:
    /// - Pick two mid-frequency coefficients `(u1, v1)` and `(u2, v2)`.
    /// - Encode the bit by enforcing a strict ordering on their magnitudes with margin `Q`:
    ///   - bit == 1  => |A| - |B| >= Q
    ///   - bit == 0  => |B| - |A| >= Q
    /// - If adjustment is needed, apply a *bidirectional split* (increase one, decrease the other
    ///   by half the required delta) to minimize total energy perturbation.
    func embedBitIntoFrequencies(_ freqBlock: inout Matrix8x8, bit: Int) {
        // A small symmetric pair around the diagonal tends to be stable and visually subtle.
        let p1 = (u: 3, v: 4)
        let p2 = (u: 4, v: 3)

        let a = freqBlock[p1.u, p1.v]
        let b = freqBlock[p2.u, p2.v]

        let qa = adaptiveQuantizationStep(for: freqBlock)

        let absA = abs(a)
        let absB = abs(b)

        if bit == 1 {
            // Want |A| - |B| >= Q
            let diff = absA - absB
            if diff < qa {
                let delta = (qa - diff) / 2
                let newAbsA = absA + delta
                let newAbsB = max(0, absB - delta)
                freqBlock[p1.u, p1.v] = applyMagnitude(newAbsA, keepingSignOf: a)
                freqBlock[p2.u, p2.v] = applyMagnitude(newAbsB, keepingSignOf: b)
            }
        } else {
            // Want |B| - |A| >= Q
            let diff = absB - absA
            if diff < qa {
                let delta = (qa - diff) / 2
                let newAbsB = absB + delta
                let newAbsA = max(0, absA - delta)
                freqBlock[p2.u, p2.v] = applyMagnitude(newAbsB, keepingSignOf: b)
                freqBlock[p1.u, p1.v] = applyMagnitude(newAbsA, keepingSignOf: a)
            }
        }
    }

    /// Extracts one payload bit from the mid-frequency band of an 8×8 DCT block.
    ///
    /// This is the inverse decision rule of ``embedBitIntoFrequencies(_:bit:)``:
    /// - returns 1 if |A| >= |B|
    /// - returns 0 otherwise
    func extractBitFromFrequencies(_ freqBlock: Matrix8x8) -> Int {
        let p1 = (u: 3, v: 4)
        let p2 = (u: 4, v: 3)
        let absA = abs(freqBlock[p1.u, p1.v])
        let absB = abs(freqBlock[p2.u, p2.v])
        return absA >= absB ? 1 : 0
    }

    /// Picks a Q in a conservative range for 8×8 DCT on 0…255-ish pixels, adapted by block activity.
    private func adaptiveQuantizationStep(for freqBlock: Matrix8x8) -> Float {
        // Use mean absolute AC magnitude as a cheap activity proxy.
        var sumAbs: Float = 0
        for u in 0..<Matrix8x8.side {
            for v in 0..<Matrix8x8.side {
                if u == 0 && v == 0 { continue } // exclude DC
                sumAbs += abs(freqBlock[u, v])
            }
        }
        let acMean = sumAbs / 63.0

        // Map activity into [6, 14].
        let q = 6.0 + min(8.0, acMean * 0.15)
        return max(6.0, min(14.0, q))
    }

    private func applyMagnitude(_ magnitude: Float, keepingSignOf value: Float) -> Float {
        let m = max(0, magnitude)
        return value < 0 ? -m : m
    }
}
