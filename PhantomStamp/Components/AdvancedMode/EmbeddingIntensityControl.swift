//
//  EmbeddingIntensityControl.swift
//  PhantomStamp
//
//  Global intensity slider with amplitude histogram (Advanced Mode).
//

import SwiftUI

/// Amplitude histogram sparkline for the intensity sub-panel.
struct AmplitudeHistogramSparkline: View {
    let summary: AmplitudeHistogramSummary
    let intensity: Double

    var body: some View {
        ZStack {
            AmplitudeHistogramBars(summary: summary)
            AmplitudeHistogramIntensityOverlay(intensity: intensity, amplitudeMax: summary.amplitudeMax)
        }
    }
}

private struct AmplitudeHistogramBars: View, Equatable {
    let summary: AmplitudeHistogramSummary

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.summary.totalBlocks == rhs.summary.totalBlocks
            && lhs.summary.amplitudeMax == rhs.summary.amplitudeMax
            && lhs.summary.maxBinCount == rhs.summary.maxBinCount
    }

    var body: some View {
        Canvas { context, canvasSize in
            guard summary.maxBinCount > 0 else { return }

            let inset = SigmaTrackGeometry.thumbInset
            let trackWidth = SigmaTrackGeometry.trackWidth(in: canvasSize.width)
            let barSlot = trackWidth / CGFloat(AmplitudeHistogramSummary.binCount)
            let maxCount = CGFloat(summary.maxBinCount)
            let drawableHeight = canvasSize.height - 4

            for (index, count) in summary.binCounts.enumerated() {
                guard count > 0 else { continue }
                let normalized = sqrt(CGFloat(count) / maxCount)
                let barHeight = max(4, normalized * drawableHeight * 0.96)
                let rect = CGRect(
                    x: inset + CGFloat(index) * barSlot + barSlot * 0.06,
                    y: canvasSize.height - barHeight - 2,
                    width: max(1.2, barSlot * 0.88),
                    height: barHeight
                )
                context.fill(
                    Path(roundedRect: rect, cornerRadius: 1.5),
                    with: .color(Color.orange.opacity(0.22))
                )
            }
        }
        .allowsHitTesting(false)
    }
}

private struct AmplitudeHistogramIntensityOverlay: View {
    let intensity: Double
    let amplitudeMax: Double

    var body: some View {
        Canvas { context, canvasSize in
            let inset = SigmaTrackGeometry.thumbInset
            let thresholdX = SigmaTrackGeometry.xPosition(
                forSigma: intensity,
                in: canvasSize.width,
                domainMax: BlockEmbedAmplitude.intensityMax
            )

            var shaded = Path()
            shaded.addRect(CGRect(x: inset, y: 0, width: max(0, thresholdX - inset), height: canvasSize.height))
            context.fill(shaded, with: .color(Color.orange.opacity(0.08)))

            var cutLine = Path()
            cutLine.move(to: CGPoint(x: thresholdX, y: 2))
            cutLine.addLine(to: CGPoint(x: thresholdX, y: canvasSize.height - 2))
            context.stroke(
                cutLine,
                with: .color(Color.orange.opacity(0.65)),
                style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])
            )
        }
        .allowsHitTesting(false)
    }
}

struct AmplitudeIntensityStats: View {
    let summary: AmplitudeHistogramSummary
    let intensity: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Label {
                    Text("Median amp: \(summary.medianAmplitude(), specifier: "%.1f")")
                        .monospacedDigit()
                } icon: {
                    Image(systemName: "waveform.path")
                        .font(.caption2)
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.orange.opacity(0.9))

                Spacer()

                Text("\(intensity, specifier: "%.1f")×")
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 0) {
                blockStatColumn(title: "Attenuated", value: summary.attenuatedBlockCount, alignment: .leading)
                blockStatColumn(title: "Full", value: summary.fullStrengthBlockCount, alignment: .center)
                blockStatColumn(title: "Total", value: summary.totalBlocks, alignment: .trailing)
            }

            Text("Heatmap shows per-block target DCT delta (adaptive Q × intensity × gain curve).")
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

/// Intensity slider with amplitude histogram (reuses snapping UISlider infrastructure).
struct EmbeddingIntensityControl: View {
    @Binding var intensity: Double
    let histogram: AmplitudeHistogramSummary?
    var isEnabled: Bool = true
    var onLiveIntensityChange: ((Double) -> Void)?
    var onEditingChanged: ((Bool) -> Void)?

    @State private var liveIntensity: Double = 10.0

    private static let histogramHeight: CGFloat = 56

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let histogram {
                AmplitudeHistogramSparkline(summary: histogram, intensity: liveIntensity)
                    .frame(height: Self.histogramHeight)

                SnappingTrackSlider(
                    value: $liveIntensity,
                    range: 0...BlockEmbedAmplitude.intensityMax,
                    step: BlockEmbedAmplitude.intensityStep,
                    tint: .orange,
                    isEnabled: isEnabled,
                    onEditingChanged: { handleEditingChanged($0) }
                )
                .frame(height: 28)

                AmplitudeIntensityStats(
                    summary: histogram,
                    intensity: liveIntensity
                )
            } else {
                SnappingTrackSlider(
                    value: $liveIntensity,
                    range: 0...BlockEmbedAmplitude.intensityMax,
                    step: BlockEmbedAmplitude.intensityStep,
                    tint: .orange,
                    isEnabled: isEnabled,
                    onEditingChanged: { handleEditingChanged($0) }
                )
                .frame(height: 28)

                Text("Load a photo to see the embed-amplitude distribution for this image.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onAppear { liveIntensity = intensity }
        .onChange(of: intensity) { _, newValue in
            if abs(liveIntensity - newValue) > 0.001 { liveIntensity = newValue }
        }
        .onChange(of: liveIntensity) { _, newValue in
            onLiveIntensityChange?(newValue)
        }
    }

    private func handleEditingChanged(_ editing: Bool) {
        if !editing { intensity = liveIntensity }
        onEditingChanged?(editing)
    }
}
