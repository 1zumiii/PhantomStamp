//
//  PhantomTheme.swift
//  PhantomStamp
//
//  Shared semantic colors for the light and dark application themes.
//

import SwiftUI
import UIKit

enum PhantomTheme {
    static let actionGradient = LinearGradient(
        colors: [
            Color(red: 0.38, green: 0.22, blue: 0.72),
            Color(red: 0.18, green: 0.42, blue: 0.78),
        ],
        startPoint: .leading,
        endPoint: .trailing
    )

    static let brightActionGradient = LinearGradient(
        colors: [
            Color(red: 0.32, green: 0.55, blue: 1.00),
            Color(red: 0.35, green: 0.85, blue: 0.95),
            Color(red: 0.88, green: 0.42, blue: 0.98),
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

struct PhantomThemeBackdrop: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Color.phantomBackdropBase

                if colorScheme == .dark {
                    RadialGradient(
                        colors: [
                            Color(red: 0.43, green: 0.28, blue: 0.78).opacity(0.34),
                            .clear,
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: 260
                    )
                    .frame(width: 520, height: 520)
                    .blur(radius: 54)
                    .offset(x: -150, y: -150)

                    RadialGradient(
                        colors: [
                            Color(red: 0.18, green: 0.47, blue: 0.78).opacity(0.28),
                            .clear,
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: 250
                    )
                    .frame(width: 500, height: 500)
                    .blur(radius: 62)
                    .offset(x: 180, y: 180)

                    RadialGradient(
                        colors: [
                            Color(red: 0.62, green: 0.25, blue: 0.58).opacity(0.20),
                            .clear,
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: 280
                    )
                    .frame(width: 560, height: 560)
                    .blur(radius: 72)
                    .offset(x: -120, y: 560)

                    Rectangle()
                        .fill(.ultraThinMaterial)
                        .opacity(0.14)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .clipped()
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

extension Color {
    static let phantomAccent = adaptiveColor(
        light: UIColor(red: 0.47, green: 0.38, blue: 0.85, alpha: 1),
        dark: UIColor(red: 0.69, green: 0.62, blue: 1.00, alpha: 1)
    )

    static let phantomAdvancedSoft = adaptiveColor(
        light: UIColor(red: 0.00, green: 0.48, blue: 1.00, alpha: 1),
        dark: UIColor(red: 0.40, green: 0.70, blue: 1.00, alpha: 1)
    )

    static let phantomAdvancedTexture = adaptiveColor(
        light: UIColor(red: 0.58, green: 0.32, blue: 0.94, alpha: 1),
        dark: UIColor(red: 0.75, green: 0.63, blue: 1.00, alpha: 1)
    )

    static let phantomAdvancedStrength = adaptiveColor(
        light: UIColor(red: 1.00, green: 0.58, blue: 0.00, alpha: 1),
        dark: UIColor(red: 1.00, green: 0.72, blue: 0.34, alpha: 1)
    )

    static let phantomBackdropBase = adaptiveColor(
        light: .systemGroupedBackground,
        dark: UIColor(red: 0.100, green: 0.085, blue: 0.170, alpha: 1)
    )

    static let phantomPageBackground = adaptiveColor(
        light: .systemGroupedBackground,
        dark: UIColor(red: 0.105, green: 0.090, blue: 0.175, alpha: 0.50)
    )

    static let phantomCardBackground = adaptiveColor(
        light: .secondarySystemGroupedBackground,
        dark: UIColor(red: 0.170, green: 0.145, blue: 0.255, alpha: 0.84)
    )

    static let phantomElevatedBackground = adaptiveColor(
        light: .tertiarySystemGroupedBackground,
        dark: UIColor(red: 0.230, green: 0.200, blue: 0.330, alpha: 0.90)
    )

    static let phantomInputBackground = adaptiveColor(
        light: UIColor(white: 0.92, alpha: 1),
        dark: UIColor(red: 0.200, green: 0.180, blue: 0.290, alpha: 0.92)
    )

    static let phantomNavigationBackground = adaptiveColor(
        light: .systemBackground,
        dark: UIColor(red: 0.100, green: 0.085, blue: 0.170, alpha: 0.92)
    )

    private static func adaptiveColor(light: UIColor, dark: UIColor) -> Color {
        Color(uiColor: UIColor { traits in
            traits.userInterfaceStyle == .dark ? dark : light
        })
    }
}
