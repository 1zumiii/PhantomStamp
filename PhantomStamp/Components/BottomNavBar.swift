//
//  BottomNavBar.swift
//  PhantomStamp
//
//  Custom bottom navigation bar (TabView replacement).
//
//  Why this exists:
//  - SwiftUI's system Tab Bar is not reliably styleable across iOS versions / appearances.
//  - This component gives you full control over background opacity, dividers, typography,
//    and layout without fighting the system material.
//

import SwiftUI

/// One item in a custom bottom navigation bar.
///
/// This is intentionally **data-driven** so adding a new screen doesn't require changes
/// inside `BottomNavBar` — you only append another `BottomNavItem` where you configure your root layout.
///
/// - Parameters:
///   - id: Stable identifier for selection / routing.
///   - title: Label shown under the SF Symbol.
///   - systemImage: SF Symbol name.
///   - content: The destination screen view (type-erased to keep the API simple at call sites).
struct BottomNavItem<ID: Hashable>: Identifiable {
    let id: ID
    let title: String
    let systemImage: String
    let content: AnyView

    init(id: ID, title: String, systemImage: String, content: AnyView) {
        self.id = id
        self.title = title
        self.systemImage = systemImage
        self.content = content
    }

    init<Content: View>(id: ID, title: String, systemImage: String, @ViewBuilder content: () -> Content) {
        self.id = id
        self.title = title
        self.systemImage = systemImage
        self.content = AnyView(content())
    }
}

/// A docked, full-width bottom navigation bar.
///
/// Visual goals:
/// - Full-width, bottom-docked
/// - Less transparent background (near-opaque)
/// - No top-left / top-right rounding (unlike floating toolbars)
///
/// Integration notes:
/// - This view is meant to be placed in a root container `VStack { content; BottomNavBar(...) }`,
///   so the content area naturally reserves space for the bar (no scroll obstruction).
struct BottomNavBar: View {
    /// Fixed bar height. Keep in sync with any floating controls that need to sit above it.
    static let barHeight: CGFloat = 58

    /// Ordered navigation items.
    let items: [BottomNavItem<AnyHashable>]
    /// Currently selected item id.
    @Binding var selection: AnyHashable

    var body: some View {
        VStack(spacing: 0) {
            Divider().opacity(0.55)

            HStack(spacing: 8) {
                ForEach(items) { item in
                    tabButton(item)
                }
            }
            .padding(.horizontal, 12)
            .frame(height: Self.barHeight)
            .frame(maxWidth: .infinity)
            .background(Color(uiColor: .systemBackground).opacity(0.98))
        }
        .frame(maxWidth: .infinity)
    }

    private func tabButton(_ item: BottomNavItem<AnyHashable>) -> some View {
        let isSelected = (selection == item.id)
        return Button {
            withAnimation(.easeOut(duration: 0.16)) {
                selection = item.id
            }
        } label: {
            VStack(spacing: 4) {
                Image(systemName: item.systemImage)
                    .font(.system(size: 18, weight: .semibold))
                    .frame(height: 22)

                Text(item.title)
                    .font(.caption2.weight(.semibold))
                    .lineLimit(1)
            }
            .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(item.title)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

#Preview {
    // =========================================================
    // UI handoff: minimal usage example
    //
    // 1) Define your tabs as an array of BottomNavItem:
    //    - id: AnyHashable("your-id")
    //    - title: "Title"
    //    - systemImage: "sf.symbol"
    //    - content: your screen view
    //
    // 2) Render screens in a ZStack and toggle visibility by selection:
    //    - opacity( selected ? 1 : 0 )
    //    - allowsHitTesting( selected )
    //
    // 3) Place BottomNavBar at the bottom of a VStack to reserve layout space
    //    (so scroll views won't be covered by the bar).
    // =========================================================
    @Previewable @State var sel: AnyHashable = "watermark"
    let items: [BottomNavItem<AnyHashable>] = [
        BottomNavItem(id: AnyHashable("watermark"), title: "Watermark", systemImage: "wand.and.stars") { Text("Watermark") },
        BottomNavItem(id: AnyHashable("history"), title: "History", systemImage: "clock.arrow.circlepath") { Text("History") },
        BottomNavItem(id: AnyHashable("settings"), title: "Settings", systemImage: "gearshape.fill") { Text("Settings") },
    ]

    return VStack(spacing: 0) {
        ZStack {
            ForEach(items) { item in
                item.content
                    .opacity(sel == item.id ? 1 : 0)
                    .allowsHitTesting(sel == item.id)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)

        BottomNavBar(items: items, selection: $sel)
    }
}

