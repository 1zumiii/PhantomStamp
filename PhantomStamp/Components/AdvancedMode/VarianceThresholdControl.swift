//
//  VarianceThresholdControl.swift
//  PhantomStamp
//
//  σ threshold slider with histogram track and protected-area readout.
//

import SwiftUI
import UIKit

// MARK: - Track geometry (histogram line ↔ UISlider thumb)

/// Maps σ to horizontal position using the same inset UISlider reserves for its thumb.
enum SigmaTrackGeometry {
    static let thumbInset: CGFloat = 15.5
    static let sigmaMax = VarianceHistogramSummary.sigmaMax

    static func trackWidth(in totalWidth: CGFloat) -> CGFloat {
        max(1, totalWidth - thumbInset * 2)
    }

    static func xPosition(forSigma sigma: Double, in totalWidth: CGFloat) -> CGFloat {
        let t = CGFloat(min(sigmaMax, max(0, sigma)) / sigmaMax)
        return thumbInset + t * trackWidth(in: totalWidth)
    }
}

// MARK: - UISlider

/// UISlider wrapper — avoids SwiftUI `Slider` release glitches inside `ScrollView`.
private struct SnappingSigmaSlider: UIViewRepresentable {
    @Binding var liveSigma: Double
    var isEnabled: Bool
    var onEditingChanged: ((Bool) -> Void)?

    private let step = 0.1
    private let range: ClosedRange<Double> = 0...SigmaTrackGeometry.sigmaMax

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    func makeUIView(context: Context) -> UISlider {
        let slider = UISlider(frame: .zero)
        slider.minimumValue = Float(range.lowerBound)
        slider.maximumValue = Float(range.upperBound)
        slider.minimumTrackTintColor = UIColor.systemOrange
        slider.maximumTrackTintColor = UIColor.tertiarySystemFill
        slider.addTarget(
            context.coordinator,
            action: #selector(Coordinator.valueChanged(_:)),
            for: .valueChanged
        )
        slider.addTarget(
            context.coordinator,
            action: #selector(Coordinator.touchDown(_:)),
            for: .touchDown
        )
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
        let snapped = snap(liveSigma)
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
        var parent: SnappingSigmaSlider
        var isDragging = false

        init(parent: SnappingSigmaSlider) {
            self.parent = parent
        }

        @objc func valueChanged(_ sender: UISlider) {
            parent.liveSigma = parent.snap(Double(sender.value))
        }

        @objc func touchDown(_ sender: UISlider) {
            isDragging = true
            parent.onEditingChanged?(true)
        }

        @objc func touchUp(_ sender: UISlider) {
            let snapped = parent.snap(Double(sender.value))
            sender.setValue(Float(snapped), animated: false)
            parent.liveSigma = snapped
            isDragging = false
            parent.onEditingChanged?(false)
        }
    }
}

// MARK: - Histogram

/// Static σ-bin bars — does not depend on the current threshold.
private struct VarianceHistogramBars: View, Equatable {
    let summary: VarianceHistogramSummary

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.summary.totalBlocks == rhs.summary.totalBlocks
            && lhs.summary.maxBinCount == rhs.summary.maxBinCount
    }

    var body: some View {
        Canvas { context, canvasSize in
            guard summary.maxBinCount > 0 else { return }

            let inset = SigmaTrackGeometry.thumbInset
            let trackWidth = SigmaTrackGeometry.trackWidth(in: canvasSize.width)
            let barSlot = trackWidth / CGFloat(VarianceHistogramSummary.binCount)
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
                    with: .color(Color.primary.opacity(0.18))
                )
            }
        }
        .allowsHitTesting(false)
    }
}

/// Threshold overlay — shaded region + dashed cut line, tracks live σ.
private struct VarianceHistogramThresholdOverlay: View {
    let sigma: Double

    var body: some View {
        Canvas { context, canvasSize in
            let inset = SigmaTrackGeometry.thumbInset
            let thresholdX = SigmaTrackGeometry.xPosition(forSigma: sigma, in: canvasSize.width)

            var shaded = Path()
            shaded.addRect(CGRect(x: inset, y: 0, width: max(0, thresholdX - inset), height: canvasSize.height))
            context.fill(shaded, with: .color(Color.blue.opacity(0.07)))

            var cutLine = Path()
            cutLine.move(to: CGPoint(x: thresholdX, y: 2))
            cutLine.addLine(to: CGPoint(x: thresholdX, y: canvasSize.height - 2))
            context.stroke(
                cutLine,
                with: .color(Color.orange.opacity(0.6)),
                style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])
            )
        }
        .allowsHitTesting(false)
    }
}

/// Sparkline histogram aligned above the σ slider.
struct VarianceHistogramSparkline: View {
    let summary: VarianceHistogramSummary
    let sigma: Double

    var body: some View {
        ZStack {
            VarianceHistogramBars(summary: summary)
            VarianceHistogramThresholdOverlay(sigma: sigma)
        }
    }
}

// MARK: - Stats

/// Stats row shown beneath the σ slider.
struct VarianceThresholdStats: View {
    let summary: VarianceHistogramSummary
    let sigma: Double

    private var protectedCount: Int { summary.protectedBlockCount(atSigma: sigma) }
    private var protectedPercent: Double { summary.protectedFraction(atSigma: sigma) * 100 }
    private var textureCount: Int { summary.textureBlockCount(atSigma: sigma) }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Label {
                    Text("Protected: \(protectedPercent, specifier: "%.1f")%")
                        .monospacedDigit()
                } icon: {
                    Image(systemName: "shield.lefthalf.filled")
                        .font(.caption2)
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(Color.blue.opacity(0.85))

                Spacer()

                Text("σ \(sigma, specifier: "%.1f")")
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 0) {
                blockStatColumn(title: "Smooth", value: protectedCount, alignment: .leading)
                blockStatColumn(title: "Texture", value: textureCount, alignment: .center)
                blockStatColumn(title: "Total", value: summary.totalBlocks, alignment: .trailing)
            }

            Text("Based on the visible canvas preview · blocks below σ² embed at reduced energy.")
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

// MARK: - Control

/// σ slider with histogram track and stats below the control.
struct VarianceThresholdControl: View {
    @Binding var sigma: Double
    let histogram: VarianceHistogramSummary?
    var isEnabled: Bool = true
    /// Fired on every σ change while dragging (for debounced Loupe preview only).
    var onLiveSigmaChange: ((Double) -> Void)?
    var onEditingChanged: ((Bool) -> Void)?

    @State private var liveSigma: Double = 2.0

    private static let histogramHeight: CGFloat = 56

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let histogram {
                VarianceHistogramSparkline(summary: histogram, sigma: liveSigma)
                    .frame(height: Self.histogramHeight)

                SnappingSigmaSlider(
                    liveSigma: $liveSigma,
                    isEnabled: isEnabled,
                    onEditingChanged: { handleEditingChanged($0) }
                )
                .frame(height: 28)

                VarianceThresholdStats(summary: histogram, sigma: liveSigma)
            } else {
                SnappingSigmaSlider(
                    liveSigma: $liveSigma,
                    isEnabled: isEnabled,
                    onEditingChanged: { handleEditingChanged($0) }
                )
                .frame(height: 28)

                Text("Load a photo to see the variance distribution for this image.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onAppear {
            liveSigma = sigma
        }
        .onChange(of: sigma) { _, newValue in
            // External writes (e.g. reset) — don't fight an active drag.
            if abs(liveSigma - newValue) > 0.001 {
                liveSigma = newValue
            }
        }
        .onChange(of: liveSigma) { _, newValue in
            onLiveSigmaChange?(newValue)
        }
    }

    private func handleEditingChanged(_ editing: Bool) {
        if !editing {
            sigma = liveSigma
        }
        onEditingChanged?(editing)
    }
}
