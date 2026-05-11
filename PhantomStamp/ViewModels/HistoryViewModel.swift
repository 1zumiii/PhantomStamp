// ViewModels/HistoryViewModel.swift
// PhantomStamp
//
// Adapter between the SwiftData persistence layer and the History UI.
// All data access goes through HistoryRecordService — the ViewModel
// holds no persistent state of its own.
// Marked @MainActor so all @Published updates are delivered on the main thread.

import Foundation
import SwiftData
import Combine

// MARK: - Filter

/// Filter options shown in the History screen filter bar.
/// CaseIterable lets the view iterate all cases without a hardcoded array.
enum HistoryFilter: String, CaseIterable, Identifiable {
    case all       = "All"
    case embedded  = "Embedded"
    case extracted = "Extracted"
    case failed    = "Failed"

    var id: String { rawValue }
}

// MARK: - ViewModel

@MainActor
final class HistoryViewModel: ObservableObject {

    // MARK: Published state

    /// The full list of records loaded from SwiftData.
    /// Views read filteredRecords or groupedRecords — not this directly.
    @Published private(set) var records: [WatermarkHistoryRecord] = []

    /// The currently selected filter chip.
    @Published var selectedFilter: HistoryFilter = .all

    /// Controls visibility of the clear-history confirmation modal.
    @Published var showClearConfirmation: Bool = false

    /// Set to a record to trigger a share sheet in the parent view.
    @Published var shareItem: WatermarkHistoryRecord? = nil

    // MARK: Derived — filtered

    /// Records after applying the selected filter.
    /// Pure computed property — idempotent, no side effects.
    var filteredRecords: [WatermarkHistoryRecord] {
        switch selectedFilter {
        case .all:
            return records
        case .embedded:
            return records.filter { $0.operationType == .embed }
        case .extracted:
            return records.filter { $0.operationType == .extract }
        case .failed:
            return records.filter { $0.status == .failed }
        }
    }

    // MARK: Derived — grouped

    /// Filtered records grouped into dated sections, sorted newest-first.
    /// Returns an ordered array of (sectionTitle, records) pairs so the
    /// view can render section headers without any formatting logic of its own.
    var groupedRecords: [(key: String, value: [WatermarkHistoryRecord])] {
        let grouped = Dictionary(grouping: filteredRecords) { record in
            HistoryFormatters.sectionHeader(for: record.timestamp)
        }

        return grouped
            .map { (
                key: $0.key,
                value: $0.value.sorted { $0.timestamp > $1.timestamp }
            )}
            .sorted { lhs, rhs in
                let lDate = lhs.value.first?.timestamp ?? .distantPast
                let rDate = rhs.value.first?.timestamp ?? .distantPast
                return lDate > rDate
            }
    }

    // MARK: Intents

    /// Loads all records from SwiftData via HistoryRecordService.
    /// Call this from onAppear or when the view needs a fresh fetch.
    func loadRecords(context: ModelContext) {
        do {
            records = try HistoryRecordService.fetchRecords(
                context: context,
                sortNewestFirst: true
            )
        } catch {
            // Non-fatal: leave existing records in place and log the error
            print("[HistoryViewModel] loadRecords failed: \(error)")
        }
    }

    /// Deletes all records from SwiftData, then reloads from persistence
    /// so the UI reflects the true SwiftData state even if a deletion partially fails.
    func clearHistory(context: ModelContext) {
        for record in records {
            do {
                try HistoryRecordService.deleteRecord(id: record.id, context: context)
            } catch {
                print("[HistoryViewModel] clearHistory failed for \(record.id): \(error)")
            }
        }
        // Reload from SwiftData rather than assuming all deletes succeeded
        loadRecords(context: context)
        showClearConfirmation = false
    }

    /// Deletes a single record from SwiftData and removes it from the local list.
    func delete(record: WatermarkHistoryRecord, context: ModelContext) {
        do {
            try HistoryRecordService.deleteRecord(id: record.id, context: context)
            records.removeAll { $0.id == record.id }
        } catch {
            print("[HistoryViewModel] delete failed for \(record.id): \(error)")
        }
    }

    /// Retries a failed watermarking operation.
    /// TODO: Integrate with the WatermarkService pipeline to re-process the image.
    func retry(record: WatermarkHistoryRecord) {
        guard record.status == .failed else { return }
        // TODO: Pass record details back to WatermarkService to re-queue the job.
        print("[HistoryViewModel] retry requested for \(record.id) — not yet implemented.")
    }

    /// Returns a settings dictionary pre-filled from an existing record.
    /// The Watermark module reads this dictionary without depending on
    /// WatermarkHistoryRecord directly, keeping the modules loosely coupled.
    func reuseSettings(from record: WatermarkHistoryRecord) -> [String: String] {
        var settings: [String: String] = [
            "operationType": record.operationType.rawValue
        ]
        if let payload = record.payload {
            settings["watermarkText"] = payload
        }
        return settings
    }

    /// Sets shareItem, which the parent view observes to present a share sheet.
    func share(record: WatermarkHistoryRecord) {
        shareItem = record
    }
}
