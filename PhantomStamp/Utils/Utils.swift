//
//  Utils.swift
//  PhantomStamp
//

import Foundation

/// 读取 Info.plist 中的版本号（启动日志、`RootView` 底部展示用）。
enum AppVersion {
    static var marketing: String {
        (Bundle.main.object(forInfoDictionaryKey: AppConstants.InfoPlistKey.marketingVersion) as? String)
            ?? AppConstants.VersionFallback.marketingUnknown
    }
}
