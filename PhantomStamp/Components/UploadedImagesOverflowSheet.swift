//
//  UploadedImagesOverflowSheet.swift
//  PhantomStamp
//
//  Scrollable sheet listing all picked images with per-row removal.
//

import SwiftUI

struct UploadedImagesOverflowSheet: View {
    let items: [SelectedPhotoItem]
    let onRemove: (UUID) -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        HStack(spacing: 12) {
                            Image(uiImage: item.image)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 56, height: 56)
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                            Text("Image \(index + 1)")
                                .font(.subheadline.weight(.medium))

                            Spacer()

                            Button(role: .destructive) {
                                onRemove(item.id)
                            } label: {
                                Image(systemName: "trash.circle.fill")
                                    .font(.title2)
                                    .symbolRenderingMode(.palette)
                                    .foregroundStyle(.red, Color(uiColor: .tertiarySystemFill))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Remove image \(index + 1)")
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(Color(uiColor: .secondarySystemGroupedBackground))
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .navigationTitle("All uploads")
            .navigationBarTitleDisplayMode(.inline)
        }
        .presentationDragIndicator(.visible)
    }
}
