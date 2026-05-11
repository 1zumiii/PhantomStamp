//
//  HistoryView.swift
//  PhantomStamp
//

import Combine
import SwiftData
import SwiftUI
import UIKit

struct HistoryView: View {
    @Environment(\.modelContext) private var modelContext
    var settingsStore: UserSettingsStore
    var listRefreshToken: Int = 0

    @StateObject private var viewModel = HistoryViewModel()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                filterBar
                historyContent
            }
            .navigationTitle("History")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Clear all") {
                        viewModel.showClearConfirmation = true
                    }
                    .disabled(viewModel.records.isEmpty)
                }
            }
        
            .alert("Clear all history?", isPresented: $viewModel.showClearConfirmation) {
                Button("Cancel", role: .cancel) {
                    viewModel.showClearConfirmation = false
                }
                Button("Clear All", role: .destructive) {
                    viewModel.clearHistory(context: modelContext)
                }
            } message: {
                Text("This removes every saved watermark operation from this device.")
            }
            .onAppear {
                viewModel.loadRecords(context: modelContext)
            }
            .onChange(of: listRefreshToken) { _, _ in
                viewModel.loadRecords(context: modelContext)
            }
            .onReceive(NotificationCenter.default.publisher(for: AppConstants.Notifications.watermarkHistoryRecordsDidChange)) { _ in
                viewModel.loadRecords(context: modelContext)
            }
        }
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(HistoryFilter.allCases) { filter in
                    let selected = viewModel.selectedFilter == filter
                    Button {
                        withAnimation(.snappy) {
                            viewModel.selectedFilter = filter
                        }
                    } label: {
                        Text(filter.rawValue)
                            .font(.subheadline.weight(.medium))
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background {
                                Capsule(style: .continuous)
                                    .fill(selected ? Color.accentColor : Color.clear)
                            }
                            .overlay {
                                Capsule(style: .continuous)
                                    .strokeBorder(selected ? Color.clear : Color.primary.opacity(0.15), lineWidth: 1)
                            }
                            .foregroundStyle(selected ? Color.white : Color.primary.opacity(0.6))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 20)
        }
        .frame(maxWidth: .infinity)
        .background(Color(uiColor: .systemGroupedBackground))
    }

    @ViewBuilder
    private var historyContent: some View {
        Group {
            if viewModel.filteredRecords.isEmpty {
                ContentUnavailableView(
                    AppConstants.Copy.History.emptyTitle,
                    systemImage: AppConstants.Symbol.tabHistory,
                    description: Text(AppConstants.Copy.History.emptyDescription)
                )
            } else {
                List {
                    ForEach(viewModel.groupedRecordSections) { section in
                        Section {
                            ForEach(section.records, id: \.id) { record in
                            
                                ZStack {
                                    WatermarkHistoryCardRow(record: record)
                                    
                                    NavigationLink {
                                        ExtractionDetailView(display: OperationDetailDisplay(history: record))
                                    } label: {
                                        EmptyView()
                                    }
                                    .opacity(0)
                                }
                                .listRowInsets(EdgeInsets(top: 8, leading: 20, bottom: 8, trailing: 20))
                                .listRowSeparator(.hidden)
                                .listRowBackground(Color.clear)
                                .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                    Button(role: .destructive) {
                                        viewModel.delete(record: record, context: modelContext)
                                    } label: {
                                        Label("Delete", systemImage: "trash")
                                    }
                                }
                            }
                        } header: {
                            Text(section.sectionTitle)
                                .font(.caption.weight(.bold))
                                .foregroundStyle(.secondary)
                                .textCase(.uppercase)
                                .padding(.horizontal, 4)
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(Color(uiColor: .systemGroupedBackground))
            }
        }
    }
}

// MARK: - Row

private struct WatermarkHistoryCardRow: View {
    let record: WatermarkHistoryRecord

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            thumbnail

            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .firstTextBaseline) {
                    Text(displayFileName)
                        .font(.headline.weight(.semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(1)

                    Spacer(minLength: 10)

                    Text(HistoryFormatters.relativeTimeString(for: record.timestamp))
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                }

                HStack(spacing: 8) {
                    statusTag
                    
                    if record.status == .success {
                        Text("•")
                            .foregroundStyle(.secondary)
                            .font(.caption)
                        Text(confidenceLevel)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 2)
                
                Spacer(minLength: 0)
                
                HStack(spacing: 12) {
                    Spacer()
                    if record.status == .failed {
                        actionButton(icon: "arrow.counterclockwise")
                        actionButton(icon: "trash", isDestructive: true)
                    } else {
                        actionButton(icon: "square.and.arrow.up")
                        actionButton(icon: "square.and.arrow.down")
                    }
                }
            }
            .padding(.vertical, 14)
            .padding(.leading, 14)
            .padding(.trailing, 14)
        }
        .frame(height: 110)
        .background(Color(uiColor: .secondarySystemGroupedBackground))
        .overlay(alignment: .trailing) {
            Rectangle()
                .fill(record.status == .success ? Color.green.opacity(0.6) : Color.orange)
                .frame(width: 3)
        }
    
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .contentShape(Rectangle())
    }
    
    private var displayFileName: String {
        return "IMG_\(String(record.id.uuidString.prefix(4))).jpg"
    }
    
    private var confidenceLevel: String {
        guard let sync = record.syncMatchCount else { return "High" }
        if sync > 28 { return "High" }
        if sync > 16 { return "Medium" }
        return "Low"
    }

    @ViewBuilder
    private var thumbnail: some View {
        let isFailed = record.status == .failed
        
        ZStack(alignment: .bottomLeading) {
            if let data = record.thumbnailData, let ui = UIImage(data: data) {
                Image(uiImage: ui)
                    .resizable()
                    .scaledToFill()
                    
                    .frame(width: 85, height: 96)
                
                    .clipShape(UnevenRoundedRectangle(topLeadingRadius: 14))
            } else {
                UnevenRoundedRectangle(topLeadingRadius: 18)
                    .fill(Color.gray.opacity(0.1))
                    .frame(width: 85, height: 96)
                    .overlay {
                        Image(systemName: "photo")
                            .foregroundStyle(.secondary)
                    }
            }
            
            Text("PNG")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background {
                    Capsule(style: .continuous)
                        .fill(Color.black.opacity(0.6))
                }
                .padding(8)
        }
        .grayscale(isFailed ? 0.3 : 0)
    }

    private var statusTag: some View {
        let isSuccess = record.status == .success
        let opType = record.operationType == .embed ? "Exported" : "Extracted"
        let text = isSuccess ? opType : "Failed"
        let fgColor: Color = isSuccess ? (record.operationType == .embed ? .green : .blue) : .red
        let bgColor: Color = fgColor.opacity(0.12)
        
        return HStack(spacing: 4) {
            Circle()
                .fill(fgColor)
                .frame(width: 4, height: 4)
            Text(text)
                .font(.caption2.weight(.bold))
                .foregroundStyle(fgColor)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background {
            Capsule(style: .continuous)
                .fill(bgColor)
        }
    }
    
    private func actionButton(icon: String, isDestructive: Bool = false) -> some View {
        Image(systemName: icon)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(isDestructive ? .red : .primary.opacity(0.8))
            .frame(width: 40, height: 34)
            .background {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .strokeBorder(isDestructive ? Color.red.opacity(0.3) : Color.primary.opacity(0.15), lineWidth: 1)
            }
    }
}

#Preview {
    HistoryViewPreviewHost()
}

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
