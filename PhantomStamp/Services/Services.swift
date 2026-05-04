//
//  Services.swift
//  PhantomStamp
//
//  业务服务示例：`GreetingServicing` 供 HomeViewModel；`PersistenceService` 供 ItemListViewModel。
//

import Foundation
import SwiftData

// MARK: - Greeting（Home）

/// 根据时刻生成问候语，便于单测时替换为固定实现。
protocol GreetingServicing: Sendable {
    func greeting(at date: Date) -> String
}

struct SystemGreetingService: GreetingServicing {
    func greeting(at date: Date) -> String {
        let hour = Calendar.current.component(.hour, from: date)
        switch hour {
        case 5 ..< 12:
            return "Good morning"
        case 12 ..< 18:
            return "Good afternoon"
        default:
            return "Good evening"
        }
    }
}

// MARK: - Persistence（SwiftData）

@MainActor
enum PersistenceService {
    /// 统一封装 `save()`，避免在多个 ViewModel 里散落 `try? context.save()`。
    static func save(_ context: ModelContext) {
        try? context.save()
    }
}
