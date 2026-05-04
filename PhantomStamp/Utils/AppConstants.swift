//
//  AppConstants.swift
//  PhantomStamp
//
//  集中存放魔法数字、文案、UserDefaults Key、SF Symbol 名等，便于统一修改与检索。
//

import CoreGraphics
import Foundation

enum AppConstants {

    // MARK: - SwiftData

    enum Fetch {
        static let historyListLimit = 1_000
    }

    // MARK: - UserDefaults

    enum UserDefaultsKey {
        static let autoLogWatermark = "phantomstamp.settings.autoLogWatermark"
        static let compactHistoryList = "phantomstamp.settings.compactHistoryList"
    }

    enum SettingsDefault {
        static let autoLogWatermark = true
        static let compactHistoryList = false
    }

    // MARK: - 历史记录 kind（SwiftData `HistoryEntry.kind`）

    enum HistoryRecordKind {
        static let watermarkEmbedded = "watermark.embedded"
        static let watermarkExtracted = "watermark.extracted"
    }

    // MARK: - 水印（Mock / Real 延时与占位）

    enum Watermark {
        static let mockEmbedDelayNanoseconds: UInt64 = 2_000_000_000
        static let mockExtractDelayNanoseconds: UInt64 = 1_000_000_000
        static let realEmbedDelayNanoseconds: UInt64 = 300_000_000
        static let realExtractDelayNanoseconds: UInt64 = 200_000_000
        /// 最小边长（点），小于则 `RealWatermarkService` 抛 `imageTooSmall`。
        static let minimumImageSidePoints: CGFloat = 64
        static let mockExtractResultText = "Test_Copyright_2026"
        static let embedSampleText = "MyText"
        static let sampleSystemSymbolName = "photo.fill"
    }

    // MARK: - Info.plist

    enum InfoPlistKey {
        static let marketingVersion = "CFBundleShortVersionString"
    }

    enum VersionFallback {
        static let marketingUnknown = "0"
    }

    // MARK: - 调试 / 错误

    enum Debug {
        static let launchLogPrefix = "[PhantomStamp] launch, marketing version = "
    }

    enum ErrorMessage {
        static let modelContainerPrefix = "Could not create ModelContainer: "
    }

    // MARK: - 布局

    enum Layout {
        static let watermarkSectionSpacing: CGFloat = 16
        static let watermarkPreviewMaxHeight: CGFloat = 220
        static let historyRowInnerSpacing: CGFloat = 4
        static let historyRowPaddingCompact: CGFloat = 2
        static let historyRowPaddingRegular: CGFloat = 6
    }

    // MARK: - SF Symbols

    enum Symbol {
        static let tabWatermark = "wand.and.stars"
        static let tabHistory = "clock.arrow.circlepath"
        static let tabSettings = "gearshape.fill"
    }

    // MARK: - 文案（UI）

    enum Copy {

        enum Tab {
            static let watermark = "水印"
            static let history = "历史"
            static let settings = "设置"
        }

        enum Watermark {
            static let navigationTitle = "水印 Demo"
            static let alertTitle = "提示"
            static let embedButton = "嵌入水印"
            static let extractButton = "提取水印"
            static let okButton = "好的"
            static let captionDependencyInjection = "视图只依赖 WatermarkServiceProtocol；DEBUG 使用 Mock，Release 使用 Real。"
            static let captionHistoryHintWhenLogging = "成功操作将写入 SwiftData 历史（可在「设置」关闭）。"
            static let captionHistoryHintWhenNotLogging = "自动写入历史已关闭。"
        }

        enum History {
            static let navigationTitle = "历史记录"
            static let clearButton = "清空"
            static let emptyTitle = "暂无历史"
            static let emptyDescription = "在水印页完成嵌入或提取，且设置中开启「自动记录水印操作」后，会出现在这里。"
            static let logWatermarkEmbeddedFormat = "嵌入水印完成（文案：%@）"
            static let logWatermarkExtractedFormat = "提取水印：%@"
        }

        enum Settings {
            static let navigationTitle = "设置"
            static let sectionHistory = "历史"
            static let sectionAppearance = "界面"
            static let toggleAutoLogWatermark = "自动记录水印操作"
            static let footnoteAutoLogWatermark = "开启后，水印 Demo 嵌入 / 提取成功时会写入 SwiftData 历史表。"
            static let toggleCompactHistory = "紧凑显示历史列表"
            static let footnoteCompactHistory = "使用 UserDefaults 持久化，重启应用后仍保留。"
        }

        enum Footer {
            static let versionPrefix = "PhantomStamp v"
        }

        enum Preview {
            static let sectionCaption = "示例说明文案"
        }
    }
}
