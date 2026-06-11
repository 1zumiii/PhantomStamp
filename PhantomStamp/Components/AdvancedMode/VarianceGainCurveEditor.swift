//
//  VarianceGainCurveEditor.swift
//  PhantomStamp
//
//  Interactive variance → gain spline editor for Advanced Mode.
//

import SwiftUI

// MARK: - Stats

struct VarianceGainCurveStats: View {
  let summary: VarianceGainCurveSummary?
  let curve: VarianceGainCurve

  private var attenuatedCount: Int { summary?.attenuatedBlockCount() ?? 0 }
  private var fullCount: Int { summary?.fullStrengthBlockCount() ?? 0 }
  private var attenuatedPercent: Double { (summary?.attenuatedFraction() ?? 0) * 100 }

  var body: some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack(alignment: .firstTextBaseline) {
        Label {
          Text("Attenuated: \(attenuatedPercent, specifier: "%.1f")%")
            .monospacedDigit()
        } icon: {
          Image(systemName: "waveform.path")
            .font(.caption2)
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(Color.orange.opacity(0.9))

        Spacer()

        Text("max σ² \(Int(curve.maxVariance))")
          .font(.caption.monospacedDigit().weight(.semibold))
          .foregroundStyle(.secondary)
      }

      HStack(spacing: 0) {
        blockStatColumn(title: "Reduced", value: attenuatedCount, alignment: .leading)
        blockStatColumn(title: "Full", value: fullCount, alignment: .center)
        blockStatColumn(title: "Total", value: summary?.totalBlocks ?? 0, alignment: .trailing)
      }

      Text("Drag anchors vertically · gain maps to heatmap opacity in the loupe viewport.")
        .font(.caption2)
        .foregroundStyle(.tertiary)
        .fixedSize(horizontal: false, vertical: true)
    }
    .padding(.horizontal, 2)
  }

  private func blockStatColumn(title: String, value: Int, alignment: HorizontalAlignment) -> some View {
    VStack(alignment: alignment, spacing: 2) {
      Text(title)
        .font(.caption2)
        .foregroundStyle(.tertiary)
      Text(value, format: .number.grouping(.automatic))
        .font(.caption.monospacedDigit().weight(.medium))
        .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, alignment: Alignment(horizontal: alignment, vertical: .center))
  }
}

// MARK: - Editor

struct VarianceGainCurveEditor: View {
  @Binding var curve: VarianceGainCurve
  let varianceSummary: VarianceGainCurveSummary?
  var isEnabled: Bool = true

  private let plotHeight: CGFloat = 148
  private let axisInset = EdgeInsets(top: 10, leading: 36, bottom: 22, trailing: 12)

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      curvePlot
        .frame(height: plotHeight)
        .background {
          RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(Color(uiColor: .tertiarySystemGroupedBackground))
        }

      presetRow

      VarianceGainCurveStats(summary: varianceSummary, curve: curve)
    }
    .opacity(isEnabled ? 1 : 0.55)
  }

  private var presetRow: some View {
    HStack(spacing: 8) {
      presetButton("S-curve", points: VarianceGainCurve.presetS.points)
      presetButton("Log", points: VarianceGainCurve.presetLog.points)
      presetButton("Linear", points: VarianceGainCurve.presetLinear.points)
    }
  }

  private func presetButton(_ title: String, points: [VarianceGainControlPoint]) -> some View {
    Button {
      curve.points = points
    } label: {
      Text(title)
        .font(.caption.weight(.semibold))
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background {
          Capsule(style: .continuous)
            .fill(Color.accentColor.opacity(0.12))
        }
    }
    .buttonStyle(.plain)
    .disabled(!isEnabled)
  }

  private var curvePlot: some View {
    GeometryReader { geo in
      let plotRect = plotArea(in: geo.size)
      ZStack {
        axisLabels(plotRect: plotRect, size: geo.size)
        curvePath(in: plotRect)
          .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
        ForEach(draggableAnchors, id: \.index) { anchor in
          anchorHandle(anchor: anchor, plotRect: plotRect)
        }
      }
    }
  }

  private struct DraggableAnchor {
    let index: Int
    let normalizedX: Double
    let gain: Double
  }

  private var draggableAnchors: [DraggableAnchor] {
    let sorted = curve.sortedPoints
    guard sorted.count >= 2 else { return [] }
    return sorted.enumerated().compactMap { index, pt in
      guard index < sorted.count - 1 else { return nil }
      return DraggableAnchor(index: index, normalizedX: pt.normalizedX, gain: pt.gain)
    }
  }

  private func plotArea(in size: CGSize) -> CGRect {
    CGRect(
      x: axisInset.leading,
      y: axisInset.top,
      width: max(1, size.width - axisInset.leading - axisInset.trailing),
      height: max(1, size.height - axisInset.top - axisInset.bottom)
    )
  }

  private func pointInPlot(normalizedX: Double, gain: Double, plotRect: CGRect) -> CGPoint {
    CGPoint(
      x: plotRect.minX + CGFloat(normalizedX) * plotRect.width,
      y: plotRect.maxY - CGFloat(gain) * plotRect.height
    )
  }

  private func curvePath(in plotRect: CGRect) -> Path {
    var path = Path()
    let steps = 64
    for step in 0...steps {
      let t = Double(step) / Double(steps)
      let gain = curve.sortedPoints.isEmpty
        ? 1.0
        : sampleCurve(normalizedX: t)
      let pt = pointInPlot(normalizedX: t, gain: gain, plotRect: plotRect)
      if step == 0 {
        path.move(to: pt)
      } else {
        path.addLine(to: pt)
      }
    }
    return path
  }

  private func sampleCurve(normalizedX t: Double) -> Double {
    Double(curve.gain(atVariance: Float(t * curve.maxVariance)))
  }

  @ViewBuilder
  private func axisLabels(plotRect: CGRect, size: CGSize) -> some View {
    Path { path in
      path.move(to: CGPoint(x: plotRect.minX, y: plotRect.maxY))
      path.addLine(to: CGPoint(x: plotRect.maxX, y: plotRect.maxY))
      path.move(to: CGPoint(x: plotRect.minX, y: plotRect.minY))
      path.addLine(to: CGPoint(x: plotRect.minX, y: plotRect.maxY))
    }
    .stroke(Color.primary.opacity(0.15), lineWidth: 1)

    Text("0%")
      .font(.caption2)
      .foregroundStyle(.tertiary)
      .position(x: plotRect.minX - 14, y: plotRect.maxY)
    Text("100%")
      .font(.caption2)
      .foregroundStyle(.tertiary)
      .position(x: plotRect.minX - 14, y: plotRect.minY)
    Text("variance →")
      .font(.caption2)
      .foregroundStyle(.tertiary)
      .position(x: plotRect.midX, y: size.height - 8)
  }

  @ViewBuilder
  private func anchorHandle(anchor: DraggableAnchor, plotRect: CGRect) -> some View {
    let center = pointInPlot(normalizedX: anchor.normalizedX, gain: anchor.gain, plotRect: plotRect)
    Circle()
      .fill(Color.accentColor)
      .frame(width: 18, height: 18)
      .overlay {
        Circle().strokeBorder(Color.white, lineWidth: 2)
      }
      .shadow(color: .black.opacity(0.18), radius: 3, y: 1)
      .position(center)
      .gesture(
        DragGesture(minimumDistance: 0)
          .onChanged { value in
            guard isEnabled else { return }
            let y = min(max(value.location.y, plotRect.minY), plotRect.maxY)
            let gain = 1.0 - Double((y - plotRect.minY) / plotRect.height)
            curve.setGain(atSortedIndex: anchor.index, gain: gain)
          }
      )
      .accessibilityLabel("Gain anchor \(anchor.index + 1)")
  }
}
