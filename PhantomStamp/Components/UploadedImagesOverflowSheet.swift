//
//  UploadedImagesOverflowSheet.swift
//  PhantomStamp
//
//  Full list of picked images with per-row removal.
//  Uses a solid grouped presentation background so the medium detent does not read as
//  “frosted glass + floating white tiles”; rows follow system inset-grouped List styling.
//

import SwiftUI

struct UploadedImagesOverflowSheet: View {
    let items: [SelectedPhotoItem]
    let onRemove: (UUID) -> Void

    /// Stable list rows with human-readable ordinals (not tied to array position after edits).
    private struct IndexedRow: Identifiable {
        let id: UUID
        let ordinal: Int
        let item: SelectedPhotoItem
    }

    private var indexedRows: [IndexedRow] {
        items.enumerated().map { idx, item in
            IndexedRow(id: item.id, ordinal: idx + 1, item: item)
        }
    }

    var body: some View {
        NavigationStack {
            sheetInnerBody
                .navigationTitle("All uploads")
                .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDetents([.medium, .large])
        // Opaque grouped chrome matches half-height sheet; avoids contrast clash with row surfaces.
        .presentationBackground(Color(uiColor: .systemGroupedBackground))
        .presentationDragIndicator(.visible)
    }

    @ViewBuilder
    private var sheetInnerBody: some View {
        if items.isEmpty {
            ContentUnavailableView(
                "No photos",
                systemImage: "photo.on.rectangle.angled",
                description: Text("Add images from the upload screen.")
            )
        } else {
            List {
                Section {
                    ForEach(indexedRows) { row in
                        uploadedRow(indexDisplay: row.ordinal, item: row.item)
                    }
                } header: {
                    Text("\(items.count) photo\(items.count == 1 ? "" : "s")")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.secondary)
                        .textCase(nil)
                } footer: {
                    Text("Trash removes the image from this session only.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .listStyle(.insetGrouped)
        }
    }

    private func uploadedRow(indexDisplay: Int, item: SelectedPhotoItem) -> some View {
        HStack(spacing: 14) {
            Image(uiImage: item.image)
                .resizable()
                .scaledToFill()
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            Text("Image \(indexDisplay)")
                .font(.body.weight(.medium))

            Spacer(minLength: 8)

            Button(role: .destructive) {
                onRemove(item.id)
            } label: {
                Image(systemName: "trash")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.red)
                    .frame(width: 40, height: 40)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Remove image \(indexDisplay)")
        }
        .padding(.vertical, 4)
    }
}
