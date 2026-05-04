//
//  HistoryListViewModel.swift
//  PhantomStamp
//

import Foundation
import Observation
import SwiftData

@MainActor
@Observable
final class HistoryListViewModel {
    private let modelContext: ModelContext
    private(set) var entries: [HistoryEntry] = []

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    func loadEntries() throws {
        var descriptor = FetchDescriptor<HistoryEntry>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        descriptor.fetchLimit = AppConstants.Fetch.historyListLimit
        entries = try modelContext.fetch(descriptor)
    }

    func clearAll() {
        for entry in entries {
            modelContext.delete(entry)
        }
        PersistenceService.save(modelContext)
        try? loadEntries()
    }
}
