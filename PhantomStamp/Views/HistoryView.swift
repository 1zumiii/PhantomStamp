//
//  HistoryView.swift
//  PhantomStamp
//

import SwiftData
import SwiftUI

struct HistoryView: View {
    @Environment(\.modelContext) private var modelContext
    var settingsStore: UserSettingsStore

    @State private var viewModel: HistoryListViewModel?

    var body: some View {
        NavigationStack {
            Group {
                if let viewModel {
                    historyList(viewModel: viewModel)
                } else {
                    ProgressView()
                }
            }
            .navigationTitle(AppConstants.Copy.History.navigationTitle)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(AppConstants.Copy.History.clearButton) {
                        viewModel?.clearAll()
                    }
                    .disabled(viewModel == nil || (viewModel?.entries.isEmpty ?? true))
                }
            }
            .task {
                if viewModel == nil {
                    let vm = HistoryListViewModel(modelContext: modelContext)
                    viewModel = vm
                    try? vm.loadEntries()
                }
            }
            .onAppear {
                try? viewModel?.loadEntries()
            }
        }
    }

    @ViewBuilder
    private func historyList(viewModel: HistoryListViewModel) -> some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    printSavedWatermarkRecordsToConsole()
                } label: {
                    Label(AppConstants.Copy.History.printWatermarkRecordsButton, systemImage: "doc.text.magnifyingglass")
                }
                .labelStyle(.titleAndIcon)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity)
            .background(Color(uiColor: .secondarySystemGroupedBackground))

            Group {
                if viewModel.entries.isEmpty {
                    ContentUnavailableView(
                        AppConstants.Copy.History.emptyTitle,
                        systemImage: AppConstants.Symbol.tabHistory,
                        description: Text(AppConstants.Copy.History.emptyDescription)
                    )
                } else {
                    List {
                        ForEach(viewModel.entries) { entry in
                            NavigationLink {
                                HistoryEntryDetailView(entry: entry)
                            } label: {
                                HistoryEntryCardRow(entry: entry, compact: settingsStore.compactHistoryList)
                            }
                            .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                    .background(Color(uiColor: .systemGroupedBackground))
                }
            }
        }
    }

    /// Debug: prints every persisted `WatermarkHistoryRecord` (Xcode console).
    private func printSavedWatermarkRecordsToConsole() {
        do {
            let records = try HistoryRecordService.fetchRecords(context: modelContext)
            print("[WatermarkHistoryRecord] total=\(records.count)")
            for r in records {
                let thumb = r.thumbnailData?.count ?? 0
                let sync = r.syncMatchCount.map { String($0) } ?? "nil"
                print(
                    """
                    [WatermarkHistoryRecord] id=\(r.id) ts=\(r.timestamp) op=\(r.operationType.rawValue) status=\(r.status.rawValue) payload=\(r.payload ?? "nil") err=\(r.errorMessage ?? "nil") size=\(r.imageWidth)x\(r.imageHeight) ms=\(r.processingDurationMs) thumbBytes=\(thumb) sync=\(sync)
                    """
                )
            }
        } catch {
            print("[WatermarkHistoryRecord] fetch failed: \(error)")
        }
    }
}

// MARK: - Detail

private struct HistoryEntryDetailView: View {
    let entry: HistoryEntry

    var body: some View {
        let meta = HistoryRowMeta(entry: entry)
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack(spacing: 14) {
                    HistoryPreviewTile(kind: entry.kind)

                    VStack(alignment: .leading, spacing: 6) {
                        Text(meta.fileName)
                            .font(.title3.weight(.semibold))
                        Text(entry.createdAt, format: .dateTime.year().month().day().hour().minute())
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(entry.kind)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()
                }

                if let watermarkName = meta.watermarkName {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Watermark")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Text(watermarkName)
                            .font(.body.weight(.semibold))
                    }
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color(uiColor: .secondarySystemGroupedBackground))
                    }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Message")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(entry.message)
                        .font(.body.monospaced())
                        .textSelection(.enabled)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color(uiColor: .secondarySystemGroupedBackground))
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("Details")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Parsing helpers (detail-only)

private struct HistoryRowMeta {
    var fileName: String
    var watermarkName: String?

    init(entry: HistoryEntry) {
        // We don't persist an actual file name yet; keep a stable placeholder.
        fileName = "Untitled image"
        watermarkName = HistoryRowMeta.parseWatermarkName(from: entry.message)
    }

    private static func parseWatermarkName(from message: String) -> String? {
        // Current app message formats:
        // - "嵌入水印完成（文案：%@）"
        // - Potential future English formats like "text: <...>"
        if let v = extractBetween(message, start: "文案：", end: "）") { return v }
        if let v = extractAfter(message, prefix: "text:") { return v.trimmingCharacters(in: .whitespacesAndNewlines) }
        return nil
    }

    private static func extractBetween(_ s: String, start: String, end: String) -> String? {
        guard let r1 = s.range(of: start) else { return nil }
        let tail = s[r1.upperBound...]
        guard let r2 = tail.range(of: end) else { return nil }
        let v = String(tail[..<r2.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        return v.isEmpty ? nil : v
    }

    private static func extractAfter(_ s: String, prefix: String) -> String? {
        guard let r = s.range(of: prefix, options: [.caseInsensitive]) else { return nil }
        let v = String(s[r.upperBound...])
        return v.isEmpty ? nil : v
    }
}

#Preview {
    HistoryViewPreviewHost()
}

/// SwiftData preview container must include every `@Model` type this screen touches.
private struct HistoryViewPreviewHost: View {
    private static let previewContainer: ModelContainer = {
        let schema = Schema([HistoryEntry.self, WatermarkHistoryRecord.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)
        return try! ModelContainer(for: schema, configurations: [config])
    }()

    var body: some View {
        HistoryView(settingsStore: UserSettingsStore())
            .modelContainer(Self.previewContainer)
    }
}
