//
//  WatermarkDSPModels.swift
//  PhantomStamp
//

// ==========================================
// DSP-friendly models (luma-only watermark path)
// ==========================================

/// Row-major **8-bit** samples (`data[y * width + x]`). Used for full **Y** (and pass-through **Cb**/**Cr**) planes.
/// Promote to `Float` only inside **8×8** blocks before **DCT**.
struct Matrix {
    var width: Int = 0
    var height: Int = 0
    var data: [UInt8] = []
}

/// One **8×8** tile of `Float` samples in **row-major** order: index `r * 8 + c` is spatial row `r`, column `c`.
///
/// The same layout holds **DCT coefficients** after ``WatermarkService/performDCT(_:)``, with `(u, v)` mapped to `(row, col)`.
struct Matrix8x8 {
    static let side = 8
    static let elementCount = 64

    /// Row-major **64** coefficients.
    var values: [Float]

    init(values: [Float] = [Float](repeating: 0, count: Matrix8x8.elementCount)) {
        precondition(values.count == Matrix8x8.elementCount)
        self.values = values
    }

    subscript(row: Int, col: Int) -> Float {
        get {
            precondition((0..<Matrix8x8.side).contains(row) && (0..<Matrix8x8.side).contains(col))
            return values[row * Matrix8x8.side + col]
        }
        set {
            precondition((0..<Matrix8x8.side).contains(row) && (0..<Matrix8x8.side).contains(col))
            values[row * Matrix8x8.side + col] = newValue
        }
    }
}

/// Full-resolution **YCbCr** planes for RGB round-trip. All frequency-domain embedding runs on **`Y` only**; **Cb**/**Cr** stay untouched.
struct YCbCrImage {
    var Y: Matrix = Matrix()
    var Cb: Matrix = Matrix()
    var Cr: Matrix = Matrix()
}

/// One strip of **luma (Y)** pixels for parallel tile processing. **Chrominance is not stored here.**
struct ImageStrip {
    var width: Int = 0
    var height: Int = 0
    /// Absolute **x** origin of this strip in the parent **Y** plane (pixels).
    var globalXOffset: Int = 0
    /// Absolute **y** origin of this strip in the parent **Y** plane (pixels).
    var globalYOffset: Int = 0
    /// Row-major **luma** (`pixels[y * width + x]`), same encoding as ``Matrix.data``.
    var pixels: [UInt8] = []

    func get8x8Block(x blockX: Int, y blockY: Int) -> Matrix8x8 {
        precondition(pixels.count == width * height)
        precondition(blockX >= 0 && blockY >= 0 && blockX + Matrix8x8.side <= width && blockY + Matrix8x8.side <= height)
        var block = Matrix8x8()
        block.values.withUnsafeMutableBufferPointer { blockPtr in
            pixels.withUnsafeBufferPointer { stripPtr in
                for row in 0..<Matrix8x8.side {
                    let sy = blockY + row
                    let stripRowLeft = sy * width + blockX
                    let blockRowStart = row * Matrix8x8.side
                    for col in 0..<Matrix8x8.side {
                        blockPtr[blockRowStart + col] = Float(stripPtr[stripRowLeft + col])
                    }
                }
            }
        }
        return block
    }

    mutating func write8x8Block(_ block: Matrix8x8, x blockX: Int, y blockY: Int) {
        precondition(pixels.count == width * height)
        precondition(blockX >= 0 && blockY >= 0 && blockX + Matrix8x8.side <= width && blockY + Matrix8x8.side <= height)
        for row in 0..<Matrix8x8.side {
            for col in 0..<Matrix8x8.side {
                let sx = blockX + col
                let sy = blockY + row
                pixels[sy * width + sx] = UInt8(clamping: Int(block[row, col].rounded()))
            }
        }
    }
}

/// Payload bits laid on an **8×8 macro-cell** grid (one bit index per **8×8** image cell). Used with absolute image coordinates from strips.
struct Macroblock2D {
    /// Macro lattice width in **cells** (each cell spans **8×8** pixels).
    var bitsWide: Int = 0
    /// Macro lattice height in **cells**.
    var bitsHigh: Int = 0
    /// Row-major payload: `bits[my * bitsWide + mx]` for macro indices `(mx, my)`.
    var bits: [Int] = []

    init(bitsWide: Int = 0, bitsHigh: Int = 0, bits: [Int] = []) {
        self.bitsWide = bitsWide
        self.bitsHigh = bitsHigh
        self.bits = bits
    }

    func getBitAt(imageX: Int, imageY: Int) -> Int {
        guard bitsWide > 0, bitsHigh > 0, !bits.isEmpty else { return 0 }
        let mx = imageX / Matrix8x8.side
        let my = imageY / Matrix8x8.side
        let ix = mx % bitsWide
        let iy = my % bitsHigh
        let idx = iy * bitsWide + ix
        guard bits.indices.contains(idx) else { return 0 }
        return bits[idx]
    }
}
