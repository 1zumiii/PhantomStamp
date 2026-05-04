//
//  ItemListView.swift
//  PhantomStamp
//

import SwiftData
import SwiftUI

struct ItemListView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel: ItemListViewModel?

    var body: some View {
        NavigationStack {
            Group {
                if let viewModel {
                    listContent(viewModel: viewModel)
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("Timestamp List")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        withAnimation {
                            viewModel?.addItem()
                        }
                    } label: {
                        Label("Add", systemImage: "plus")
                    }
                    .disabled(viewModel == nil)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 8) {
                SectionCaption(text: "Rows use Item.rowLabel → TimestampText (Utils).")
            }
            .task {
                if viewModel == nil {
                    let vm = ItemListViewModel(modelContext: modelContext)
                    viewModel = vm
                    try? vm.loadItems()
                }
            }
        }
    }

    @ViewBuilder
    private func listContent(viewModel: ItemListViewModel) -> some View {
        List {
            ForEach(viewModel.items) { item in
                NavigationLink {
                    Text(item.rowLabel)
                        .padding()
                } label: {
                    Text(item.rowLabel)
                }
            }
            .onDelete { offsets in
                withAnimation {
                    viewModel.deleteItems(at: offsets)
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                EditButton()
            }
        }
    }
}

#Preview {
    ItemListView()
        .modelContainer(for: Item.self, inMemory: true)
}
