//
//  HistoryEntry.swift
//  PhantomStamp
//

import Foundation
import SwiftData

/// Application history (persistent with SwiftData).
@Model
final class HistoryEntry {
    var createdAt: Date
    /// Classification identifier, such as `item.added`、`item.removed`.
    var kind: String
    var message: String

    init(createdAt: Date = Date(), kind: String, message: String) {
        self.createdAt = createdAt
        self.kind = kind
        self.message = message
    }
}
