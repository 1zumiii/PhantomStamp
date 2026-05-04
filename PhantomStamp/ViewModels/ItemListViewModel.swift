//
//  ItemListViewModel.swift
//  PhantomStamp
//

import Foundation
import Observation
import SwiftData

/// 列表数据与增删逻辑；保存走 `PersistenceService`（见 Services）。
@MainActor
@Observable
final class ItemListViewModel {
    private let modelContext: ModelContext
    private(set) var items: [Item] = []

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func loadItems() throws {
        var descriptor = FetchDescriptor<Item>(
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = 500
        items = try modelContext.fetch(descriptor)
    }

    func addItem() {
        modelContext.insert(Item(timestamp: Date()))
        PersistenceService.save(modelContext)
        try? loadItems()
    }

    func deleteItems(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(items[index])
        }
        PersistenceService.save(modelContext)
        try? loadItems()
    }
}
