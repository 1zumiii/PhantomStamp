//
//  Services.swift
//  PhantomStamp
//
//  
//

import Foundation
import SwiftData

@MainActor
enum PersistenceService {
    static func save(_ context: ModelContext) {
        try? context.save()
    }
}
