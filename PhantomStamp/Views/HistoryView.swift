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
        List {
            if viewModel.entries.isEmpty {
                ContentUnavailableView(
                    AppConstants.Copy.History.emptyTitle,
                    systemImage: AppConstants.Symbol.tabHistory,
                    description: Text(AppConstants.Copy.History.emptyDescription)
                )
            } else {
                ForEach(viewModel.entries) { entry in
                    VStack(alignment: .leading, spacing: AppConstants.Layout.historyRowInnerSpacing) {
                        HStack {
                            Text(entry.kind)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Spacer()
                            Text(entry.createdAt, format: .dateTime.month().day().hour().minute())
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                        Text(entry.message)
                            .font(settingsStore.compactHistoryList ? .caption : .body)
                    }
                    .padding(
                        .vertical,
                        settingsStore.compactHistoryList
                            ? AppConstants.Layout.historyRowPaddingCompact
                            : AppConstants.Layout.historyRowPaddingRegular
                    )
                }
            }
        }
    }
}

#Preview {
    let store = UserSettingsStore()
    return HistoryView(settingsStore: store)
        .modelContainer(for: HistoryEntry.self, inMemory: true)
}
