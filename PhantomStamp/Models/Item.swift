//
//  Item.swift
//  PhantomStamp
//
//  Created by Orion on 4/5/2026.
//

import Foundation
import SwiftData

@Model
final class Item {
    var timestamp: Date

    init(timestamp: Date) {
        self.timestamp = timestamp
    }

    /// 列表行与详情共用的展示文案（内部使用 `TimestampText`，见 Utils）。
    var rowLabel: String {
        TimestampText.rowLabel(for: timestamp)
    }
}
