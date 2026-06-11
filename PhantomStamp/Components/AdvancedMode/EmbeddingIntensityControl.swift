//
//  EmbeddingIntensityControl.swift
//  PhantomStamp
//
//  Global intensity slider with amplitude histogram (Advanced Mode).
//

import SwiftUI
import UIKit

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
    let varianceCache: MacroblockVarianceCache
    let varianceGainCurve: VarianceGainCurve
    let intensity: Double

    private var attenuatedCount: Int {
        summary.attenuatedBlockCount(variance: varianceCache, curve: varianceGainCurve)
    }

    private var fullStrengthCount: Int {
        summary.fullStrengthBlockCount(variance: varianceCache, curve: varianceGainCurve)
    }

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
                blockStatColumn(title: "Attenuated", value: attenuatedCount, alignment: .leading)
                blockStatColumn(title: "Full", value: fullStrengthCount, alignment: .center)
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
    let baseQCache: MacroblockBaseQuantizationCache?
    let varianceCache: MacroblockVarianceCache?
    let varianceGainCurve: VarianceGainCurve
    var isEnabled: Bool = true
    var onLiveIntensityChange: ((Double) -> Void)?
    var onEditingChanged: ((Bool) -> Void)?

    @State private var liveIntensity: Double = 10.0

    private static let histogramHeight: CGFloat = 56

    private var liveHistogram: AmplitudeHistogramSummary? {
        guard let baseQCache, let varianceCache else { return nil }
        return AmplitudeHistogramSummary.build(
            baseQ: baseQCache,
            variance: varianceCache,
            varianceGainCurve: varianceGainCurve,
            embeddingIntensity: Float(liveIntensity)
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let liveHistogram, let varianceCache {
                AmplitudeHistogramSparkline(summary: liveHistogram, intensity: liveIntensity)
                    .frame(height: Self.histogramHeight)

                SnappingIntensitySlider(
                    liveValue: $liveIntensity,
                    isEnabled: isEnabled,
                    onEditingChanged: { handleEditingChanged($0) }
                )
                .frame(height: 28)

                AmplitudeIntensityStats(
                    summary: liveHistogram,
                    varianceCache: varianceCache,
                    varianceGainCurve: varianceGainCurve,
                    intensity: liveIntensity
                )
            } else {
                SnappingIntensitySlider(
                    liveValue: $liveIntensity,
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

// MARK: - Intensity UISlider (0…10, step 0.5)

private struct SnappingIntensitySlider: UIViewRepresentable {
    @Binding var liveValue: Double
    var isEnabled: Bool
    var onEditingChanged: ((Bool) -> Void)?

    private let step = BlockEmbedAmplitude.intensityStep
    private let range: ClosedRange<Double> = 0...BlockEmbedAmplitude.intensityMax

    func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    func makeUIView(context: Context) -> UISlider {
        let slider = UISlider(frame: .zero)
        slider.minimumValue = Float(range.lowerBound)
        slider.maximumValue = Float(range.upperBound)
        slider.minimumTrackTintColor = UIColor.systemOrange
        slider.maximumTrackTintColor = UIColor.tertiarySystemFill
        slider.addTarget(context.coordinator, action: #selector(Coordinator.valueChanged(_:)), for: .valueChanged)
        slider.addTarget(context.coordinator, action: #selector(Coordinator.touchDown(_:)), for: .touchDown)
        slider.addTarget(
            context.coordinator,
            action: #selector(Coordinator.touchUp(_:)),
            for: [.touchUpInside, .touchUpOutside, .touchCancel]
        )
        return slider
    }

    func updateUIView(_ slider: UISlider, context: Context) {
        context.coordinator.parent = self
        guard !context.coordinator.isDragging else {
            slider.isEnabled = isEnabled
            return
        }
        let snapped = snap(liveValue)
        if abs(Double(slider.value) - snapped) > 0.001 {
            slider.setValue(Float(snapped), animated: false)
        }
        slider.isEnabled = isEnabled
    }

    private func snap(_ raw: Double) -> Double {
        let clamped = min(range.upperBound, max(range.lowerBound, raw))
        return (clamped / step).rounded() * step
    }

    final class Coordinator: NSObject {
        var parent: SnappingIntensitySlider
        var isDragging = false

        init(parent: SnappingIntensitySlider) { self.parent = parent }

        @objc func valueChanged(_ sender: UISlider) {
            parent.liveValue = parent.snap(Double(sender.value))
        }

        @objc func touchDown(_ sender: UISlider) {
            isDragging = true
            parent.onEditingChanged?(true)
        }

        @objc func touchUp(_ sender: UISlider) {
            let snapped = parent.snap(Double(sender.value))
            sender.setValue(Float(snapped), animated: false)
            parent.liveValue = snapped
            isDragging = false
            parent.onEditingChanged?(false)
        }
    }
}
