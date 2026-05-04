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
        /// 仅控制「嵌入水印」是否写入历史（提取不记录）。
        static let autoLogWatermarkEmbed = "phantomstamp.settings.autoLogWatermarkEmbed"
        static let compactHistoryList = "phantomstamp.settings.compactHistoryList"
    }

    enum SettingsDefault {
        static let autoLogWatermarkEmbed = true
        static let compactHistoryList = false
    }

    // MARK: - 历史记录 kind（SwiftData `HistoryEntry.kind`）

    enum HistoryRecordKind {
        static let watermarkEmbedded = "watermark.embedded"
    }

    // MARK: - 水印（Mock / Real 延时与占位）

    enum Watermark {
        static let mockEmbedDelayNanoseconds: UInt64 = 2_000_000_000
        static let mockExtractDelayNanoseconds: UInt64 = 1_000_000_000
        /// 条带高度（像素）；完整实现要求图像高度为该值的整数倍且与 8 对齐策略一致。
        static let stripHeightPixels = 80
        /// 平滑块方差阈值，低于则跳过嵌入（隐蔽性）。
        static let smoothBlockVarianceThreshold: Float = 10.5
        /// 最小边长（点），小于则 `WatermarkService` 抛 `imageTooSmall`（与算法伪代码一致）。
        static let minimumImageSidePoints: CGFloat = 128
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
        static let watermarkSectionSpacing: CGFloat = 20
        static let watermarkPreviewMaxHeight: CGFloat = 280
        static let watermarkPreviewCornerRadius: CGFloat = 20
        static let watermarkCardPadding: CGFloat = 14
        static let watermarkActionsCardCornerRadius: CGFloat = 16
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
            static let navigationTitle = "水印"
            static let alertTitle = "提示"
            static let embedButton = "嵌入水印"
            static let extractButton = "提取水印"
            static let okButton = "好的"
            static let sectionPreview = "预览"
            static let sectionActions = "操作"
            static let sectionExtractResult = "提取结果"
            static let extractPlaceholder = "提取水印后，结果将显示在此"
            static let processing = "处理中…"
            static let embedChipFormat = "示例文案 · %@"
            static let tipArchitectureTitle = "依赖注入"
            static let tipHistoryTitle = "历史"
            static let captionDependencyInjection = "视图只依赖 WatermarkServiceProtocol；运行时使用 WatermarkService，SwiftUI Preview 使用 PreviewWatermarkService；单元测试使用 Tests 内 Mock。"
            static let captionHistoryHintWhenLogging = "仅「嵌入水印」成功时会写入历史（可在「设置」关闭）。"
            static let captionHistoryHintWhenNotLogging = "已关闭：嵌入水印成功时不会写入历史。"
        }
        // AppConstants.Copy.History.navigationTitle
        enum History {
            static let navigationTitle = "历史记录"
            static let clearButton = "清空"
            static let emptyTitle = "暂无历史"
            static let emptyDescription = "在水印页成功「嵌入水印」，且设置中开启「自动记录嵌入水印」后，会出现在这里。"
            static let logWatermarkEmbeddedFormat = "嵌入水印完成（文案：%@）"
        }

        enum Settings {
            static let navigationTitle = "设置"
            static let sectionHistory = "历史"
            static let sectionAppearance = "界面"
            static let toggleAutoLogWatermarkEmbed = "自动记录嵌入水印"
            static let footnoteAutoLogWatermarkEmbed = "开启后，仅在水印页「嵌入水印」成功时写入 SwiftData；提取水印不会记录。"
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
