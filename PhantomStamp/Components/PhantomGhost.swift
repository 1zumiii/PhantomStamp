//
//  PhantomGhost.swift
//  PhantomStamp
//

import SwiftUI

private struct PhantomGhostBody: Shape {
    func path(in rect: CGRect) -> Path {
        let w = rect.width
        let h = rect.height
        let bodyBottom = h * 0.82

        return Path { path in
            path.move(to: CGPoint(x: w * 0.12, y: bodyBottom))
            path.addLine(to: CGPoint(x: w * 0.12, y: h * 0.38))
            path.addCurve(
                to: CGPoint(x: w * 0.88, y: h * 0.38),
                control1: CGPoint(x: w * 0.12, y: h * 0.06),
                control2: CGPoint(x: w * 0.88, y: h * 0.06)
            )
            path.addLine(to: CGPoint(x: w * 0.88, y: bodyBottom))
            path.addLine(to: CGPoint(x: w * 0.76, y: h * 0.70))
            path.addLine(to: CGPoint(x: w * 0.64, y: bodyBottom))
            path.addLine(to: CGPoint(x: w * 0.52, y: h * 0.70))
            path.addLine(to: CGPoint(x: w * 0.40, y: bodyBottom))
            path.addLine(to: CGPoint(x: w * 0.28, y: h * 0.70))
            path.closeSubpath()
        }
    }
}

private struct PhantomSmile: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addQuadCurve(
                to: CGPoint(x: rect.maxX, y: rect.minY),
                control: CGPoint(x: rect.midX, y: rect.maxY)
            )
        }
    }
}

struct PhantomGhost: View {
    var bodyColor: Color = Color(red: 0.91, green: 0.93, blue: 1.0)
    var inkColor: Color = Color(red: 0.11, green: 0.10, blue: 0.31)

    var body: some View {
        GeometryReader { geometry in
            let size = geometry.size

            ZStack {
                PhantomGhostBody()
                    .fill(bodyColor)

                eye(at: CGPoint(x: size.width * 0.38, y: size.height * 0.39), in: size)
                eye(at: CGPoint(x: size.width * 0.62, y: size.height * 0.39), in: size)

                PhantomSmile()
                    .trim(from: 0.04, to: 0.96)
                    .stroke(
                        Color(red: 0.48, green: 0.53, blue: 0.96),
                        style: StrokeStyle(lineWidth: max(1.5, size.width * 0.035), lineCap: .round)
                    )
                    .frame(width: size.width * 0.22, height: size.height * 0.10)
                    .position(x: size.width * 0.50, y: size.height * 0.55)

            }
        }
        .aspectRatio(0.88, contentMode: .fit)
        .accessibilityHidden(true)
    }

    private func eye(at point: CGPoint, in size: CGSize) -> some View {
        let eyeWidth = size.width * 0.15
        let eyeHeight = size.height * 0.18

        return Ellipse()
            .fill(inkColor)
            .frame(width: eyeWidth, height: eyeHeight)
            .overlay(alignment: .topLeading) {
                Circle()
                    .fill(Color.white.opacity(0.66))
                    .frame(width: eyeWidth * 0.34)
                    .padding(eyeWidth * 0.16)
            }
            .position(point)
    }

}

#Preview {
    ZStack {
        Color(uiColor: .systemGroupedBackground)
        PhantomGhost()
            .frame(width: 110)
    }
}
