//
//  ReticleAxisSlider.swift
//  PhantomStamp
//
//  Custom discrete axis slider with a pointed cursor thumb facing the image canvas.
//

import SwiftUI

enum ReticleSliderAxis {
    case horizontal
    case vertical
}

/// Pointed cursor thumb: rectangular body with a triangular tip toward the image.
private struct ReticleCursorThumb: View {
    let axis: ReticleSliderAxis
    let accentColor: Color

    private static let bodyAlongTrack: CGFloat = 14
    private static let bodyAcrossTrack: CGFloat = 8
    private static let pointLength: CGFloat = 6

    var body: some View {
        Canvas { context, size in
            let path = Self.cursorPath(axis: axis, in: CGRect(origin: .zero, size: size))
            context.fill(path, with: .color(accentColor))
            context.stroke(path, with: .color(.white.opacity(0.6)), lineWidth: 0.6)
        }
        .frame(width: thumbSize.width, height: thumbSize.height)
        .shadow(color: .black.opacity(0.18), radius: 1.5, x: 0, y: 1)
    }

    var thumbSize: CGSize {
        switch axis {
        case .horizontal:
            return CGSize(width: Self.bodyAlongTrack, height: Self.bodyAcrossTrack + Self.pointLength)
        case .vertical:
            return CGSize(width: Self.bodyAcrossTrack + Self.pointLength, height: Self.bodyAlongTrack)
        }
    }

    private static func cursorPath(axis: ReticleSliderAxis, in rect: CGRect) -> Path {
        var path = Path()
        switch axis {
        case .horizontal:
            let tipY = rect.minY
            let bodyTop = rect.minY + pointLength
            let bodyBottom = rect.maxY
            let insetX: CGFloat = 1.5
            path.move(to: CGPoint(x: rect.midX, y: tipY))
            path.addLine(to: CGPoint(x: rect.maxX - insetX, y: bodyTop))
            path.addLine(to: CGPoint(x: rect.maxX - insetX, y: bodyBottom))
            path.addLine(to: CGPoint(x: rect.minX + insetX, y: bodyBottom))
            path.addLine(to: CGPoint(x: rect.minX + insetX, y: bodyTop))
            path.closeSubpath()
        case .vertical:
            let tipX = rect.minX
            let bodyLeft = rect.minX + pointLength
            let bodyRight = rect.maxX
            let insetY: CGFloat = 1.5
            path.move(to: CGPoint(x: tipX, y: rect.midY))
            path.addLine(to: CGPoint(x: bodyLeft, y: rect.minY + insetY))
            path.addLine(to: CGPoint(x: bodyRight, y: rect.minY + insetY))
            path.addLine(to: CGPoint(x: bodyRight, y: rect.maxY - insetY))
            path.addLine(to: CGPoint(x: bodyLeft, y: rect.maxY - insetY))
            path.closeSubpath()
        }
        return path
    }
}

/// Discrete block-index slider; horizontal sits below the canvas, vertical sits to the right.
struct ReticleAxisSlider: View {
    @Binding var value: Double
    let range: ClosedRange<Double>
    let blockCount: Int
    let axis: ReticleSliderAxis
    var accentColor: Color = .phantomAccent
    var isEnabled: Bool = true

    var body: some View {
        GeometryReader { geo in
            let trackLength = axis == .horizontal ? geo.size.width : geo.size.height
            let thumb = ReticleCursorThumb(axis: axis, accentColor: isEnabled ? accentColor : .gray)
            let thumbCenter = thumbCenterPosition(
                for: value,
                trackLength: trackLength,
                thumb: thumb
            )

            ZStack(alignment: .topLeading) {
                trackLine(in: geo.size, thumb: thumb)
                thumb
                    .position(thumbCenter)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        guard isEnabled else { return }
                        value = snappedValue(from: gesture.location, trackLength: trackLength)
                    }
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(axis == .horizontal ? "Block X" : "Block Y")
            .accessibilityValue("\(Int(value))")
            .accessibilityAdjustableAction { direction in
                guard isEnabled else { return }
                switch direction {
                case .increment:
                    value = min(range.upperBound, value + 1)
                case .decrement:
                    value = max(range.lowerBound, value - 1)
                @unknown default:
                    break
                }
            }
        }
    }

    @ViewBuilder
    private func trackLine(in size: CGSize, thumb: ReticleCursorThumb) -> some View {
        let color = isEnabled ? accentColor.opacity(0.4) : Color.secondary.opacity(0.25)
        switch axis {
        case .horizontal:
            Capsule()
                .fill(color)
                .frame(height: 2)
                .frame(maxWidth: .infinity)
                .padding(.top, thumb.thumbSize.height - 2)
        case .vertical:
            Capsule()
                .fill(color)
                .frame(width: 2)
                .frame(maxHeight: .infinity)
                .padding(.leading, thumb.thumbSize.width - 2)
        }
    }

    /// Positions the thumb center so its tip aligns with the crosshair block-center line.
    private func thumbCenterPosition(
        for value: Double,
        trackLength: CGFloat,
        thumb: ReticleCursorThumb
    ) -> CGPoint {
        let index = Int(value.rounded())
        let blockCenter = ReticleBlockGeometry.blockCenterPosition(
            index: index,
            blockCount: blockCount,
            trackLength: trackLength
        )
        switch axis {
        case .horizontal:
            return CGPoint(x: blockCenter, y: thumb.thumbSize.height * 0.5)
        case .vertical:
            return CGPoint(x: thumb.thumbSize.width * 0.5, y: blockCenter)
        }
    }

    private func snappedValue(from location: CGPoint, trackLength: CGFloat) -> Double {
        let position = axis == .horizontal ? location.x : location.y
        let index = ReticleBlockGeometry.blockIndex(
            at: position,
            blockCount: blockCount,
            trackLength: trackLength
        )
        return min(range.upperBound, max(range.lowerBound, Double(index)))
    }
}
