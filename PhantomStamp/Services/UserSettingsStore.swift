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

    /// 仅当「嵌入水印」成功时是否写入 `HistoryEntry`（提取不记录）。
    var autoLogWatermarkEmbedToHistory: Bool {
        didSet { defaults.set(autoLogWatermarkEmbedToHistory, forKey: AppConstants.UserDefaultsKey.autoLogWatermarkEmbed) }
    }

    var compactHistoryList: Bool {
        didSet { defaults.set(compactHistoryList, forKey: AppConstants.UserDefaultsKey.compactHistoryList) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let v = defaults.object(forKey: AppConstants.UserDefaultsKey.autoLogWatermarkEmbed) as? Bool {
            self.autoLogWatermarkEmbedToHistory = v
        } else if let legacy = defaults.object(forKey: "phantomstamp.settings.autoLogWatermark") as? Bool {
            self.autoLogWatermarkEmbedToHistory = legacy
            defaults.set(legacy, forKey: AppConstants.UserDefaultsKey.autoLogWatermarkEmbed)
        } else {
            self.autoLogWatermarkEmbedToHistory = AppConstants.SettingsDefault.autoLogWatermarkEmbed
        }
        if let v = defaults.object(forKey: AppConstants.UserDefaultsKey.compactHistoryList) as? Bool {
            self.compactHistoryList = v
        } else {
            self.compactHistoryList = AppConstants.SettingsDefault.compactHistoryList
        }
    }
}
