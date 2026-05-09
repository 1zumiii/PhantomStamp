//
//  SelectedPhotoItem.swift
//  PhantomStamp
//
//  Picked photo with stable identity for thumbnail strips and removal lists.
//

import UIKit

struct SelectedPhotoItem: Identifiable {
    let id: UUID
    let image: UIImage

    init(id: UUID = UUID(), image: UIImage) {
        self.id = id
        self.image = image
    }
}
