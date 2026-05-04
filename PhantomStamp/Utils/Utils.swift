//
//  Utils.swift
//  PhantomStamp
//
//  通用工具、扩展（示例：`AppVersion`、`TimestampText` 在 App / RootView / Item 中使用）。
//

import Foundation

/// 读取 Info.plist 中的版本号（`PhantomStampApp` 调试输出、`RootView` 底部展示用）。
enum AppVersion {
    static var marketing: String {
        (Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String) ?? "0"
    }
}

/// 与列表行展示一致的日期字符串（`Item.rowLabel`、`ItemListView` 使用）。
enum TimestampText {
    static func rowLabel(for date: Date) -> String {
        date.formatted(.dateTime.year().month().day().hour().minute().second())
    }
}
