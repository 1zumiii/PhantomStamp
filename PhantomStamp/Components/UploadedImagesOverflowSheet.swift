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
                    ForEach(items) { item in
                        uploadedRow(item: item)
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

    private func uploadedRow(item: SelectedPhotoItem) -> some View {
        HStack(spacing: 14) {
            Image(uiImage: item.image)
                .resizable()
                .scaledToFill()
                .frame(width: 56, height: 56)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            Text(item.displayName)
                .font(.body.weight(.medium))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
                .layoutPriority(0)

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
            .layoutPriority(1)
            .accessibilityLabel("Remove \(item.displayName)")
        }
        .padding(.vertical, 4)
    }
}
