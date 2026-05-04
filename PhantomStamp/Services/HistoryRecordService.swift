//
//  HistoryRecordService.swift
//  PhantomStamp
//
//  向 SwiftData 追加一条历史记录（与 `HistoryEntry` 模型配合使用）。
//

import Foundation
import SwiftData

@MainActor
enum HistoryRecordService {
    static func append(_ context: ModelContext, kind: String, message: String) {
        context.insert(HistoryEntry(createdAt: Date(), kind: kind, message: message))
        PersistenceService.save(context)
    }
}
