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
        do {
            try context.save()
        } catch {
            #if DEBUG
            print("[PersistenceService] context.save failed: \(error)")
            #endif
        }
    }
}
