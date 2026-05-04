//
//  HistoryEntry.swift
//  PhantomStamp
//

import Foundation
import SwiftData

/// 应用内操作历史（SwiftData 持久化）。
@Model
final class HistoryEntry {
    var createdAt: Date
    /// 分类标识，如 `item.added`、`item.removed`。
    var kind: String
    var message: String

    init(createdAt: Date = Date(), kind: String, message: String) {
        self.createdAt = createdAt
        self.kind = kind
        self.message = message
    }
}
