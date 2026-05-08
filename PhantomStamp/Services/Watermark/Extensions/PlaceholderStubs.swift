//
//  WatermarkService+PlaceholderStubs.swift
//  PhantomStamp
//

import UIKit

extension WatermarkService {
    
    // ==========================================
    // TODO 占位桩 (内部工具方法抽象)
    // 内部方法全部实现之后会删除此文件
    // ==========================================
    
    
    
    // 色彩与矩阵
    // func convertToYCbCr(image: UIImage) -> YCbCrImage? { return nil } 已移至ImageProcessing
    // func convertToUIImage(from ycbcr: YCbCrImage) -> UIImage? { return nil } 已移至ImageProcessing
    // func sliceImage(_ channel: Matrix, heightPerStrip: Int) -> [ImageStrip] { return [] }
    func updateStripInPlace(_ strips: inout [ImageStrip], with processedStrip: ImageStrip) { }
    func reassembleStrips(_ strips: [ImageStrip]) -> Matrix { return Matrix() }
    
    // 数学运算
    //func calculateVariance(_ block: Matrix8x8) -> Float { return 0.0 } 已移至MatrixOperations
    //func performDCT(_ block: Matrix8x8) -> Matrix8x8 { return block }
    //func performIDCT(_ freqBlock: Matrix8x8) -> Matrix8x8 { return freqBlock }
    // embedBitIntoFrequencies implemented in StripProcessing.swift
    //func embedBitIntoFrequencies(_ freqBlock: inout Matrix8x8, bit: Int) { }
    
    // 提取专用
    func findGridOffsetAndSyncMarker(in matrix: Matrix) -> CGPoint? { return nil }
    func extractBitsWithOffset(_ matrix: Matrix, offset: CGPoint) -> [[Int]] { return [] }
    func applyMajorityVoting(to bits: [[Int]]) -> [Int] { return [] }
}
