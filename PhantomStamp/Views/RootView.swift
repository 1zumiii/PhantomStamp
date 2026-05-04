//
//  RootView.swift
//  PhantomStamp
//

import SwiftUI

/// 应用根视图：用 Tab 串联各功能模块；底部展示版本号（Utils + Components）。
struct RootView: View {
    var body: some View {
        TabView {
            HomeView()
                .tabItem {
                    Label("首页", systemImage: "house.fill")
                }

            ItemListView()
                .tabItem {
                    Label("记录", systemImage: "list.bullet")
                }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            SectionCaption(text: "PhantomStamp v\(AppVersion.marketing)")
        }
    }
}

#Preview {
    RootView()
}
