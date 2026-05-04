//
//  Components.swift
//  PhantomStamp
//
//  可复用 SwiftUI 片段（示例：`SectionCaption` 在 HomeView / RootView 中使用）。
//

import SwiftUI

/// 次要说明文案，用于页面底部或分组标题下。
struct SectionCaption: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity)
    }
}

#Preview("SectionCaption") {
    SectionCaption(text: "示例说明文案")
        .padding()
}
