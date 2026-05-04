//
//  Services.swift
//  PhantomStamp
//
//  SwiftData 保存封装（历史写入见 `HistoryRecordService`）。
//

import Foundation
import SwiftData

@MainActor
enum PersistenceService {
    static func save(_ context: ModelContext) {
        try? context.save()
    }
}
