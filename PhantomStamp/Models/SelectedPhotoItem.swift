//
//  SelectedPhotoItem.swift
//  PhantomStamp
//
//  Picked photo with stable identity for thumbnail strips and removal lists.
//

import UIKit
import ImageIO

struct SelectedPhotoItem: Identifiable {
    /// Shown when the system does not provide a file name (e.g. limited photo access). Replaced with `Image N` when appending to the draft.
    static let missingFileNamePlaceholder = "Untitled"

    let id: UUID
    let image: UIImage
    /// Human-readable file name from the picker when available (e.g. `IMG_1234.JPG`).
    let displayName: String
    let width: Int
    let height: Int

    init(id: UUID = UUID(), image: UIImage, width:Int, height:Int, suggestedName: String? = nil) {
        self.id = id
        self.image = image
        self.width = width
        self.height = height
        let trimmed = suggestedName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if trimmed.isEmpty {
            self.displayName = Self.missingFileNamePlaceholder
        } else {
            let last = (trimmed as NSString).lastPathComponent
            self.displayName = last.isEmpty ? Self.missingFileNamePlaceholder : last
        }
    }
}
