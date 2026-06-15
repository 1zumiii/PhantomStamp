//
//  WatermarkAlgorithmCore.swift
//  PhantomStamp
//
//  Stateless, concurrency-safe owner of watermark image/DSP algorithms.
//

import Foundation

nonisolated struct WatermarkAlgorithmCore: Sendable {}

/// Sendable view over a temporary buffer whose callers guarantee disjoint-index writes.
nonisolated struct DisjointWriteBuffer<Element>: @unchecked Sendable {
    let baseAddress: UnsafeMutablePointer<Element>

    init(_ buffer: UnsafeMutableBufferPointer<Element>) {
        precondition(buffer.baseAddress != nil)
        baseAddress = buffer.baseAddress!
    }

    subscript(index: Int) -> Element {
        get { baseAddress[index] }
        nonmutating set { baseAddress[index] = newValue }
    }
}
