//
//  SnappingTrackSlider.swift
//  PhantomStamp
//

import SwiftUI

/// A lightweight snapping slider whose thumb follows the drag location directly.
/// Keeping the gesture and rendering in SwiftUI avoids UIKit tracking-value
/// feedback when the value is quantized during a drag.
struct SnappingTrackSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let tint: Color
    var isEnabled: Bool = true
    var onEditingChanged: ((Bool) -> Void)?

    @State private var isDragging = false

    private let thumbDiameter: CGFloat = 28
    private let trackHeight: CGFloat = 4

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let trackWidth = max(1, width - thumbDiameter)
            let fraction = normalizedFraction(for: value)
            let thumbX = thumbDiameter / 2 + fraction * trackWidth

            ZStack(alignment: .leading) {
                Capsule(style: .continuous)
                    .fill(Color(uiColor: .tertiarySystemFill))
                    .frame(height: trackHeight)
                    .padding(.horizontal, thumbDiameter / 2)

                Capsule(style: .continuous)
                    .fill(tint.opacity(isEnabled ? 0.65 : 0.3))
                    .frame(width: max(0, thumbX - thumbDiameter / 2), height: trackHeight)
                    .offset(x: thumbDiameter / 2)

                Circle()
                    .fill(tint)
                    .frame(width: thumbDiameter, height: thumbDiameter)
                    .overlay {
                        Circle()
                            .strokeBorder(Color.white.opacity(0.9), lineWidth: 2)
                    }
                    .shadow(color: tint.opacity(isDragging ? 0.34 : 0.18), radius: isDragging ? 5 : 3, y: 1)
                    .scaleEffect(isDragging ? 1.04 : 1)
                    .position(x: thumbX, y: geometry.size.height / 2)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .local)
                    .onChanged { drag in
                        guard isEnabled else { return }
                        if !isDragging {
                            isDragging = true
                            onEditingChanged?(true)
                        }
                        value = snappedValue(at: drag.location.x, width: width)
                    }
                    .onEnded { drag in
                        guard isEnabled else { return }
                        value = snappedValue(at: drag.location.x, width: width)
                        isDragging = false
                        onEditingChanged?(false)
                    }
            )
        }
        .frame(height: thumbDiameter)
        .opacity(isEnabled ? 1 : 0.55)
        .accessibilityElement()
        .accessibilityValue(Text(value.formatted(.number.precision(.fractionLength(1)))))
        .accessibilityAdjustableAction { direction in
            guard isEnabled else { return }
            onEditingChanged?(true)
            switch direction {
            case .increment:
                value = snap(value + step)
            case .decrement:
                value = snap(value - step)
            @unknown default:
                break
            }
            onEditingChanged?(false)
        }
    }

    private func normalizedFraction(for value: Double) -> CGFloat {
        let span = max(range.upperBound - range.lowerBound, .leastNonzeroMagnitude)
        let clamped = min(range.upperBound, max(range.lowerBound, value))
        return CGFloat((clamped - range.lowerBound) / span)
    }

    private func snappedValue(at x: CGFloat, width: CGFloat) -> Double {
        let usableWidth = max(1, width - thumbDiameter)
        let clampedX = min(max(x - thumbDiameter / 2, 0), usableWidth)
        let fraction = Double(clampedX / usableWidth)
        return snap(range.lowerBound + fraction * (range.upperBound - range.lowerBound))
    }

    private func snap(_ rawValue: Double) -> Double {
        let clamped = min(range.upperBound, max(range.lowerBound, rawValue))
        let steps = ((clamped - range.lowerBound) / step).rounded()
        return min(range.upperBound, max(range.lowerBound, range.lowerBound + steps * step))
    }
}
