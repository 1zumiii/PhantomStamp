//
//  MinHeap.swift
//  PhantomStamp
//  Created by Orion on 9/5/2026.
//

import Foundation

// MARK: - Min-heap

/// A tiny min-heap implementation used for progress buffering.
///
/// This replaces repeated `array.sort + removeFirst` on each tick, improving the hot path from
/// \(O(n \log n) + O(n)\) to amortized \(O(\log n)\) per event.
struct MinHeap<Element> {
    private var storage: [Element] = []
    private let areSorted: (Element, Element) -> Bool

    init(areSorted: @escaping (Element, Element) -> Bool) {
        self.areSorted = areSorted
    }

    var isEmpty: Bool { storage.isEmpty }
    var count: Int { storage.count }

    mutating func removeAll(keepingCapacity: Bool) {
        storage.removeAll(keepingCapacity: keepingCapacity)
    }

    mutating func insert(_ element: Element) {
        storage.append(element)
        siftUp(from: storage.count - 1)
    }

    mutating func popMin() -> Element? {
        guard !storage.isEmpty else { return nil }
        if storage.count == 1 { return storage.removeLast() }

        storage.swapAt(0, storage.count - 1)
        let min = storage.removeLast()
        siftDown(from: 0)
        return min
    }

    private mutating func siftUp(from index: Int) {
        var child = index
        while child > 0 {
            let parent = (child - 1) / 2
            if areSorted(storage[child], storage[parent]) {
                storage.swapAt(child, parent)
                child = parent
            } else {
                break
            }
        }
    }

    private mutating func siftDown(from index: Int) {
        var parent = index
        while true {
            let left = parent * 2 + 1
            let right = left + 1
            var candidate = parent

            if left < storage.count, areSorted(storage[left], storage[candidate]) {
                candidate = left
            }
            if right < storage.count, areSorted(storage[right], storage[candidate]) {
                candidate = right
            }
            if candidate == parent { return }
            storage.swapAt(parent, candidate)
            parent = candidate
        }
    }
}
