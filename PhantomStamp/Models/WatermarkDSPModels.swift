//
//  WatermarkDSPModels.swift
//  PhantomStamp
//
//  水印算法用到的矩阵 / 条带 / 宏块占位模型（随算法实现逐步充实）。
//

import UIKit

/// Y 通道或其它二维标量场占位。
struct Matrix: Sendable {
    init() {}
}

struct Matrix8x8: Sendable {
    init() {}
}

/// YCbCr 中间表示；当前桩实现用 `roundtripImage` 直接回传，便于 UI 在未接好矩阵前仍可工作。
struct YCbCrImage {
    var Y: Matrix
    var roundtripImage: UIImage
}

struct ImageStrip: Sendable {
    var width: Int = 0
    var height: Int = 0
    var globalXOffset: Int = 0
    var globalYOffset: Int = 0

    func get8x8Block(x: Int, y: Int) -> Matrix8x8 {
        Matrix8x8()
    }

    mutating func write8x8Block(_ block: Matrix8x8, x: Int, y: Int) {
        _ = block
        _ = x
        _ = y
    }
}

struct Macroblock2D: Sendable {
    func getBitAt(imageX: Int, imageY: Int) -> Int {
        _ = imageX
        _ = imageY
        return 0
    }
}
