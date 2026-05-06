//
//  DataProcessing.swift
//  PhantomStamp
//
//  Created by Orion on 6/5/2026.
//

import Foundation

func encodeFEC(text: String) -> [Int] {
    let bytes = Array(text.utf8)
    
    // Hard cap: keep payload small enough for a compact 2D tile.
    // This is a backend safety net even if the UI also limits input length.
    let maxPayloadBytes = 16
    guard bytes.count <= maxPayloadBytes else {
        return []
    }
    
    var rawBits: [Int] = []
    
    // 1 byte length header
    rawBits.append(contentsOf: byteToBits(UInt8(bytes.count)))
    
    // payload UTF-8 bytes
    for byte in bytes {
        rawBits.append(contentsOf: byteToBits(byte))
    }
    
    // FEC: Extended Hamming(8,4) (SECDED) + byte-level block interleaving.
    // - Hamming improves correction of isolated bit flips vs repetition code.
    // - Interleaving spreads burst errors across different codewords.
    let codewordBits = hamming84Encode(bitStream: rawBits)
    return interleaveBits(codewordBits, columns: 8)
}

func decodeFEC(bits: [Int]) -> String? {
    // At minimum we need one byte length header => 8 bits => two Hamming(8,4) codewords => 16 bits,
    // plus interleaving may pad to full blocks.
    guard bits.count >= 16 else {
        return nil
    }
    
    // Reverse interleaving first (must mirror `encodeFEC`).
    let deinterleaved = deinterleaveBits(bits, columns: 8)
    guard let decodedBits = hamming84Decode(bitStream: deinterleaved) else { return nil }
    
    // at least 1 byte length information
    guard decodedBits.count >= 8 else {
        return nil
    }
    
    let lengthBits = Array(decodedBits[0..<8])
    let messageLength = Int(bitsToByte(lengthBits))
    
    guard messageLength > 0 else {
        return ""
    }
    
    let requiredBitCount = 8 + messageLength * 8
    guard decodedBits.count >= requiredBitCount else {
        return nil
    }
    
    var bytes: [UInt8] = []
    
    for i in 0..<messageLength {
        let start = 8 + i * 8
        let end = start + 8
        let byteBits = Array(decodedBits[start..<end])
        bytes.append(bitsToByte(byteBits))
    }
    
    return String(bytes: bytes, encoding: .utf8)
}

func getSyncMarkerBits() -> [Int] {
    // fixed sync header, used to identify the start of the watermark
    // length 32 bits, use a pattern with obvious high/low changes
    return [
        1, 0, 1, 1, 0, 1, 0, 0,
        1, 1, 1, 0, 0, 0, 1, 0,
        1, 0, 0, 1, 1, 0, 1, 1,
        0, 1, 0, 1, 1, 1, 0, 0
    ]
}

func build2DTile(from bits: [Int]) -> Macroblock2D {
    var tile = Macroblock2D()
    
    guard !bits.isEmpty else {
        return tile
    }
    
    // The tile must carry its 2D dimensions. Leaving bitsWide/bitsHigh at 0
    // will later cause division/modulo by zero in `Macroblock2D.getBitAt(...)`.
    let side = Int(ceil(sqrt(Double(bits.count))))
    tile.bitsWide = side
    tile.bitsHigh = side

    // Pad to a perfect square so `(mx, my)` addressing never goes out of range.
    var paddedBits = bits
    let requiredCount = side * side
    if paddedBits.count < requiredCount {
        paddedBits.append(contentsOf: Array(repeating: 0, count: requiredCount - paddedBits.count))
    }
    tile.bits = paddedBits
    
    return tile
}

private func byteToBits(_ byte: UInt8) -> [Int] {
    var bits: [Int] = []
    
    for i in stride(from: 7, through: 0, by: -1) {
        let bit = (byte >> UInt8(i)) & 1
        bits.append(Int(bit))
    }
    
    return bits
}

private func bitsToByte(_ bits: [Int]) -> UInt8 {
    var byte: UInt8 = 0
    
    for bit in bits.prefix(8) {
        byte = byte << 1
        byte = byte | UInt8(bit == 1 ? 1 : 0)
    }
    
    return byte
}

// MARK: - FEC: Extended Hamming(8,4) + interleaving

/// Encodes a raw bitstream using extended Hamming(8,4) (SECDED).
/// Input length is padded to a multiple of 4 bits.
private func hamming84Encode(bitStream: [Int]) -> [Int] {
    var bits = bitStream
    let pad = (4 - (bits.count % 4)) % 4
    if pad != 0 { bits.append(contentsOf: Array(repeating: 0, count: pad)) }

    var out: [Int] = []
    out.reserveCapacity((bits.count / 4) * 8)

    var i = 0
    while i + 3 < bits.count {
        let d1 = clampBit(bits[i])
        let d2 = clampBit(bits[i + 1])
        let d3 = clampBit(bits[i + 2])
        let d4 = clampBit(bits[i + 3])

        // Bit positions (1-based): 1=p1, 2=p2, 3=d1, 4=p4, 5=d2, 6=d3, 7=d4, 8=p0(overall)
        let p1 = parityEven(d1, d2, d4)          // covers 1,3,5,7
        let p2 = parityEven(d1, d3, d4)          // covers 2,3,6,7
        let p4 = parityEven(d2, d3, d4)          // covers 4,5,6,7
        let p0 = parityEven(p1, p2, d1, p4, d2, d3, d4) // overall even parity over positions 1...7

        out.append(contentsOf: [p1, p2, d1, p4, d2, d3, d4, p0])
        i += 4
    }
    return out
}

/// Decodes an extended Hamming(8,4) bitstream. Returns `nil` on detected double-bit errors.
private func hamming84Decode(bitStream: [Int]) -> [Int]? {
    guard bitStream.count >= 8 else { return [] }

    let cwCount = bitStream.count / 8
    var out: [Int] = []
    out.reserveCapacity(cwCount * 4)

    for w in 0..<cwCount {
        let base = w * 8
        var b = (0..<8).map { clampBit(bitStream[base + $0]) } // 0-based, but maps to pos 1..8

        let p1 = b[0], p2 = b[1], d1 = b[2], p4 = b[3], d2 = b[4], d3 = b[5], d4 = b[6], p0 = b[7]

        // Syndrome bits for positions 1..7
        let s1 = parityEven(p1, d1, d2, d4)
        let s2 = parityEven(p2, d1, d3, d4)
        let s4 = parityEven(p4, d2, d3, d4)
        let syndrome = (s4 << 2) | (s2 << 1) | s1 // 1...7 indicates which bit is wrong (1-based)

        // Overall parity check over positions 1..8 (even parity expected)
        let overall = parityEven(p1, p2, d1, p4, d2, d3, d4, p0)

        if overall == 1 && syndrome != 0 {
            // Single-bit error in positions 1..7, correct it.
            let ix = syndrome - 1
            b[ix] ^= 1
        } else if overall == 1 && syndrome == 0 {
            // Error in the overall parity bit itself (position 8).
            b[7] ^= 1
        } else if overall == 0 && syndrome != 0 {
            // Detected a double-bit error (or an uncorrectable pattern).
            return nil
        }

        out.append(contentsOf: [b[2], b[4], b[5], b[6]])
    }
    return out
}

/// Simple block interleaver at codeword granularity.
/// Treats the stream as `codewordCount` codewords, each `codewordBitWidth` bits.
/// Bit-level block interleaver (Row-in, Column-out)
private func interleaveBits(_ bits: [Int], columns: Int) -> [Int] {
    guard !bits.isEmpty, columns > 1 else { return bits }
    
    // each row stores a complete Hamming code (columns = 8)
    // rows is the number of Hamming codes
    let rows = Int(ceil(Double(bits.count) / Double(columns)))
    let paddedCount = rows * columns
    
    var padded = bits
    if padded.count < paddedCount {
        padded.append(contentsOf: Array(repeating: 0, count: paddedCount - padded.count))
    }
    
    var out = [Int](repeating: 0, count: paddedCount)
    
    // traverse by row, calculate the write position by column
    for r in 0..<rows {
        for c in 0..<columns {
            let readInIndex = r * columns + c
            let writeOutIndex = c * rows + r // transpose mapping
            out[writeOutIndex] = padded[readInIndex]
        }
    }
    return out
}

private func deinterleaveBits(_ bits: [Int], columns: Int) -> [Int] {
    guard !bits.isEmpty, columns > 1 else { return bits }
    
    let rows = bits.count / columns
    var out = [Int](repeating: 0, count: bits.count)
    
    // traverse by column, calculate the restore position by row (reverse operation)
    for r in 0..<rows {
        for c in 0..<columns {
            let readInIndex = c * rows + r // read the bit stream continuously on the image
            let writeOutIndex = r * columns + c
            out[writeOutIndex] = bits[readInIndex]
        }
    }
    return out
}

@inline(__always)
private func clampBit(_ x: Int) -> Int { x == 0 ? 0 : 1 }

@inline(__always)
private func parityEven(_ bits: Int...) -> Int {
    var p = 0
    // calculate the parity of the bits
    for b in bits { p ^= (b & 1) }
    return p
}
