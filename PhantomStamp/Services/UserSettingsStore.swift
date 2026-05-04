//
//  UserSettingsStore.swift
//  PhantomStamp
//

import Foundation
import Observation

@MainActor
@Observable
final class UserSettingsStore {
    private let defaults: UserDefaults

    /// 水印 Demo 成功操作是否写入 `HistoryEntry`。
    var autoLogWatermarkToHistory: Bool {
        didSet { defaults.set(autoLogWatermarkToHistory, forKey: AppConstants.UserDefaultsKey.autoLogWatermark) }
    }

    var compactHistoryList: Bool {
        didSet { defaults.set(compactHistoryList, forKey: AppConstants.UserDefaultsKey.compactHistoryList) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let v = defaults.object(forKey: AppConstants.UserDefaultsKey.autoLogWatermark) as? Bool {
            self.autoLogWatermarkToHistory = v
        } else {
            self.autoLogWatermarkToHistory = AppConstants.SettingsDefault.autoLogWatermark
        }
        if let v = defaults.object(forKey: AppConstants.UserDefaultsKey.compactHistoryList) as? Bool {
            self.compactHistoryList = v
        } else {
            self.compactHistoryList = AppConstants.SettingsDefault.compactHistoryList
        }
    }
}
