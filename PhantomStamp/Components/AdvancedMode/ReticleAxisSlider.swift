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

    private static let bodyAlongTrack: CGFloat = 20
    private static let bodyAcrossTrack: CGFloat = 12
    private static let pointLength: CGFloat = 9

    var body: some View {
        Canvas { context, size in
            let path = Self.cursorPath(axis: axis, in: CGRect(origin: .zero, size: size))
            context.fill(path, with: .color(accentColor))
            context.stroke(path, with: .color(.white.opacity(0.55)), lineWidth: 0.75)
        }
        .frame(width: thumbSize.width, height: thumbSize.height)
        .shadow(color: .black.opacity(0.22), radius: 2, x: 0, y: 1)
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
            let insetX: CGFloat = 2
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
            let insetY: CGFloat = 2
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
    let axis: ReticleSliderAxis
    var accentColor: Color = .orange
    var isEnabled: Bool = true

    var body: some View {
        GeometryReader { geo in
            let trackLength = axis == .horizontal ? geo.size.width : geo.size.height
            let thumb = ReticleCursorThumb(axis: axis, accentColor: isEnabled ? accentColor : .gray)
            let center = thumbCenter(for: value, trackLength: trackLength, thumb: thumb, in: geo.size)

            ZStack {
                trackLine(in: geo.size)
                thumb.position(center)
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
    private func trackLine(in size: CGSize) -> some View {
        let color = isEnabled ? accentColor.opacity(0.35) : Color.secondary.opacity(0.25)
        switch axis {
        case .horizontal:
            Capsule()
                .fill(color)
                .frame(height: 3)
                .frame(maxHeight: .infinity, alignment: .top)
                .padding(.top, ReticleCursorThumb(axis: .horizontal, accentColor: accentColor).thumbSize.height - 4)
        case .vertical:
            Capsule()
                .fill(color)
                .frame(width: 3)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, ReticleCursorThumb(axis: .vertical, accentColor: accentColor).thumbSize.width - 4)
        }
    }

    private func thumbCenter(
        for value: Double,
        trackLength: CGFloat,
        thumb: ReticleCursorThumb,
        in size: CGSize
    ) -> CGPoint {
        let fraction = normalizedFraction(for: value)
        switch axis {
        case .horizontal:
            let x = thumbTravelOrigin(trackLength: trackLength, thumb: thumb) + fraction * thumbTravelLength(trackLength: trackLength, thumb: thumb)
            let y = thumb.thumbSize.height * 0.5
            return CGPoint(x: x, y: y)
        case .vertical:
            let x = size.width - thumb.thumbSize.width * 0.5
            let y = thumbTravelOrigin(trackLength: trackLength, thumb: thumb) + fraction * thumbTravelLength(trackLength: trackLength, thumb: thumb)
            return CGPoint(x: x, y: y)
        }
    }

    private func thumbTravelOrigin(trackLength: CGFloat, thumb: ReticleCursorThumb) -> CGFloat {
        let travel = thumbTravelLength(trackLength: trackLength, thumb: thumb)
        let along = axis == .horizontal ? thumb.thumbSize.width : thumb.thumbSize.height
        return along * 0.5
    }

    private func thumbTravelLength(trackLength: CGFloat, thumb: ReticleCursorThumb) -> CGFloat {
        let along = axis == .horizontal ? thumb.thumbSize.width : thumb.thumbSize.height
        return max(0, trackLength - along)
    }

    private func normalizedFraction(for value: Double) -> CGFloat {
        guard range.upperBound > range.lowerBound else { return 0.5 }
        let t = (value - range.lowerBound) / (range.upperBound - range.lowerBound)
        return CGFloat(min(max(t, 0), 1))
    }

    private func snappedValue(from location: CGPoint, trackLength: CGFloat) -> Double {
        let thumb = ReticleCursorThumb(axis: axis, accentColor: accentColor)
        let travel = thumbTravelLength(trackLength: trackLength, thumb: thumb)
        let origin = thumbTravelOrigin(trackLength: trackLength, thumb: thumb)
        let raw: CGFloat
        switch axis {
        case .horizontal:
            raw = travel > 0 ? (location.x - origin) / travel : 0
        case .vertical:
            raw = travel > 0 ? (location.y - origin) / travel : 0
        }
        let clamped = min(max(raw, 0), 1)
        let continuous = range.lowerBound + Double(clamped) * (range.upperBound - range.lowerBound)
        return min(range.upperBound, max(range.lowerBound, continuous.rounded()))
    }
}
