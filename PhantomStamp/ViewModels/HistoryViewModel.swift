// ViewModels/HistoryViewModel.swift
// PhantomStamp
//
// Adapter between the SwiftData persistence layer and the History UI.
// All data access goes through HistoryRecordService — the ViewModel
// holds no persistent state of its own.
// Marked @MainActor so all @Published updates are delivered on the main thread.

import Combine
import Foundation
import SwiftData
import SwiftUI
import UIKit

// MARK: - Filter

/// Filter options shown in the History screen filter bar.
/// CaseIterable lets the view iterate all cases without a hardcoded array.
enum HistoryFilter: String, CaseIterable, Identifiable {
    case all       = "All"
    case embedded  = "Embedded"
    case extracted = "Extracted"
    case failed    = "Not Found"

    var id: String { rawValue }
}

/// One dated section in the history list (stable `id` for SwiftUI even if the calendar heading repeats across years).
struct HistoryRecordSection: Identifiable {
    let id: String
    let sectionTitle: String
    let records: [WatermarkHistoryRecord]
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

    /// When set, the list presents a delete-confirmation alert for that record id.
    @Published var pendingDeleteRecordId: UUID?

    /// Shown by the save-to-Photos failure alert.
    @Published var saveErrorMessage: String?

    /// Brief “Saved to Photos” toast after a successful library export.
    @Published var showSaveSuccessToast: Bool = false

    /// Drives `.sensoryFeedback(.success, trigger:)` from the view on successful save.
    @Published private(set) var saveSuccessFeedbackTrigger: Int = 0

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
    var groupedRecords: [(key: String, value: [WatermarkHistoryRecord])] {
        groupedRecordSections.map { (key: $0.sectionTitle, value: $0.records) }
    }

    /// Same grouping as `groupedRecords` with a stable per-section identifier for `ForEach`.
    var groupedRecordSections: [HistoryRecordSection] {
        let grouped = Dictionary(grouping: filteredRecords) { record in
            HistoryFormatters.sectionHeader(for: record.timestamp)
        }

        return grouped
            .map { title, records in
                let sorted = records.sorted { $0.timestamp > $1.timestamp }
                let idSeed = sorted.map(\.id.uuidString).sorted().joined(separator: ",")
                return HistoryRecordSection(
                    id: "\(title)|\(idSeed)",
                    sectionTitle: title,
                    records: sorted
                )
            }
            .sorted { lhs, rhs in
                let lDate = lhs.records.first?.timestamp ?? .distantPast
                let rDate = rhs.records.first?.timestamp ?? .distantPast
                return lDate > rDate
            }
    }

    // MARK: - Single-entry delete confirmation

    var deleteEntryConfirmationMessage: String {
        guard let id = pendingDeleteRecordId,
              let record = records.first(where: { $0.id == id }) else {
            return "This cannot be undone."
        }
        let name = OperationDetailDisplay.historyListFileName(for: record)
        return "“\(name)” will be removed from history on this device. This cannot be undone."
    }

    func requestDeleteConfirmation(for record: WatermarkHistoryRecord) {
        pendingDeleteRecordId = record.id
    }

    func cancelPendingDelete() {
        pendingDeleteRecordId = nil
    }

    /// Performs delete after user confirms in the alert; clears pending state.
    func confirmPendingDelete(context: ModelContext) {
        guard let id = pendingDeleteRecordId,
              let record = records.first(where: { $0.id == id }) else {
            pendingDeleteRecordId = nil
            return
        }
        delete(record: record, context: context)
        pendingDeleteRecordId = nil
    }

    func dismissSaveError() {
        saveErrorMessage = nil
    }

    // MARK: - Save to Photos

    func saveRecordToPhotoLibrary(_ record: WatermarkHistoryRecord) {
        Task { @MainActor in
            await PhotoLibraryExporter.preflightAddOnlyAuthorizationIfNeeded()
            let data = record.detailPreviewData ?? record.thumbnailData
            guard let data, let image = UIImage(data: data) else {
                saveErrorMessage = "There is no preview image to save."
                return
            }
            do {
                try await PhotoLibraryExporter.saveToPhotoLibrary(image)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                saveSuccessFeedbackTrigger += 1
                withAnimation { showSaveSuccessToast = true }
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(2.2))
                    withAnimation { showSaveSuccessToast = false }
                }
            } catch {
                saveErrorMessage = error.localizedDescription
            }
        }
    }

    /// Label for the list card confidence hint (sync match bands).
    static func confidenceLabel(for record: WatermarkHistoryRecord) -> String {
        guard let sync = record.syncMatchCount else { return "High" }
        if sync > 28 { return "High" }
        if sync > 16 { return "Medium" }
        return "Low"
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
