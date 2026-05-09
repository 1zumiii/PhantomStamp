//
//  ImagePickerSupport.swift
//  PhantomStamp
//
//  Helpers for presenting system photo picking limited to still images.
//

import PhotosUI
import SwiftUI
import UIKit

enum ImagePickerSupport {
    /// PHPicker / PhotosPicker filter: photos only (no videos).
    static var imagesOnlyFilter: PHPickerFilter { .images }

    /// Load UIImages from picker items (order preserved). Unsupported or corrupt items are skipped.
    static func loadImages(from items: [PhotosPickerItem]) async -> [UIImage] {
        var result: [UIImage] = []
        result.reserveCapacity(items.count)

        for item in items {
            guard let data = try? await item.loadTransferable(type: Data.self) else { continue }
            guard let image = UIImage(data: data) else { continue }
            result.append(image)
        }

        return result
    }
}
