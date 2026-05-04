//
//  HomeViewModel.swift
//  PhantomStamp
//

import Foundation
import Observation

/// 可与多个 View 共享；问候语由 `GreetingServicing` 提供（见 Services）。
@MainActor
@Observable
final class HomeViewModel {
    private let greetingService: GreetingServicing

    private(set) var greeting: String = ""
    private(set) var tapCount: Int = 0

    init(greetingService: GreetingServicing = SystemGreetingService()) {
        self.greetingService = greetingService
        refreshGreeting()
    }

    func refreshGreeting() {
        greeting = greetingService.greeting(at: Date())
    }

    func incrementTaps() {
        tapCount += 1
    }
}
