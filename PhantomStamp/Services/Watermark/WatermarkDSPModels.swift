//
//  WatermarkDSPModels.swift
//  PhantomStamp
//

// ==========================================
// 辅助模型结构定义 (Dummy Models)
// ==========================================
struct Matrix { }
struct Matrix8x8 { }
struct YCbCrImage { var Y: Matrix = Matrix() }
struct ImageStrip {
    var width: Int = 0
    var height: Int = 0
    var globalXOffset: Int = 0
    var globalYOffset: Int = 0
    func get8x8Block(x: Int, y: Int) -> Matrix8x8 { return Matrix8x8() }
    mutating func write8x8Block(_ block: Matrix8x8, x: Int, y: Int) { }
}
struct Macroblock2D {
    func getBitAt(imageX: Int, imageY: Int) -> Int { return 0 }
}
