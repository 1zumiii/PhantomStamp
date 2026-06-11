//
//  VarianceThresholdControl.swift
//  PhantomStamp
//
//  σ threshold slider with histogram track and protected-area readout.
//

import SwiftUI
import UIKit

/// UISlider wrapper — avoids SwiftUI `Slider` release glitches inside `ScrollView`.
private struct SnappingSigmaSlider: UIViewRepresentable {
    @Binding var value: Double
    var isEnabled: Bool
    var onEditingChanged: ((Bool) -> Void)?

    private let step = 0.1
    private let range: ClosedRange<Double> = 0...VarianceHistogramSummary.sigmaMax

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
        // While dragging, UISlider owns thumb position — don't fight it from stale binding.
        guard !context.coordinator.isDragging else {
            slider.isEnabled = isEnabled
            return
        }
        let snapped = snap(value)
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

        private var lastEmitTime: CFAbsoluteTime = 0
        private var pendingEmit: DispatchWorkItem?
        private let throttleInterval: TimeInterval = 0.1

        init(parent: SnappingSigmaSlider) {
            self.parent = parent
        }

        @objc func valueChanged(_ sender: UISlider) {
            let snapped = parent.snap(Double(sender.value))
            let now = CFAbsoluteTimeGetCurrent()

            if now - lastEmitTime >= throttleInterval {
                emit(snapped)
                lastEmitTime = now
                pendingEmit?.cancel()
                pendingEmit = nil
            } else {
                pendingEmit?.cancel()
                let work = DispatchWorkItem { [weak self] in
                    guard let self else { return }
                    self.emit(snapped)
                    self.lastEmitTime = CFAbsoluteTimeGetCurrent()
                    self.pendingEmit = nil
                }
                pendingEmit = work
                DispatchQueue.main.asyncAfter(
                    deadline: .now() + throttleInterval,
                    execute: work
                )
            }
        }

        @objc func touchDown(_ sender: UISlider) {
            isDragging = true
            parent.onEditingChanged?(true)
        }

        @objc func touchUp(_ sender: UISlider) {
            pendingEmit?.cancel()
            pendingEmit = nil
            let snapped = parent.snap(Double(sender.value))
            sender.setValue(Float(snapped), animated: false)
            emit(snapped)
            lastEmitTime = CFAbsoluteTimeGetCurrent()
            isDragging = false
            parent.onEditingChanged?(false)
        }

        private func emit(_ snapped: Double) {
            parent.value = snapped
        }
    }
}

/// Sparkline histogram aligned above the σ slider.
struct VarianceHistogramSparkline: View {
    let summary: VarianceHistogramSummary
    let sigma: Double

    var body: some View {
        GeometryReader { geo in
            Canvas { context, canvasSize in
                guard summary.maxBinCount > 0 else { return }

                let barSlot = canvasSize.width / CGFloat(VarianceHistogramSummary.binCount)
                let maxCount = CGFloat(summary.maxBinCount)
                let drawableHeight = canvasSize.height - 4

                for (index, count) in summary.binCounts.enumerated() {
                    guard count > 0 else { continue }
                    // Sqrt scale so low-count bins stay visible against a dominant peak.
                    let normalized = sqrt(CGFloat(count) / maxCount)
                    let barHeight = max(4, normalized * drawableHeight * 0.96)
                    let rect = CGRect(
                        x: CGFloat(index) * barSlot + barSlot * 0.06,
                        y: canvasSize.height - barHeight - 2,
                        width: max(1.2, barSlot * 0.88),
                        height: barHeight
                    )
                    context.fill(
                        Path(roundedRect: rect, cornerRadius: 1.5),
                        with: .color(Color.primary.opacity(0.18))
                    )
                }

                let thresholdX = CGFloat(sigma / VarianceHistogramSummary.sigmaMax) * canvasSize.width
                var cutLine = Path()
                cutLine.move(to: CGPoint(x: thresholdX, y: 2))
                cutLine.addLine(to: CGPoint(x: thresholdX, y: canvasSize.height - 2))
                context.stroke(
                    cutLine,
                    with: .color(Color.orange.opacity(0.6)),
                    style: StrokeStyle(lineWidth: 1.5, dash: [4, 3])
                )

                var shaded = Path()
                shaded.addRect(CGRect(x: 0, y: 0, width: thresholdX, height: canvasSize.height))
                context.fill(shaded, with: .color(Color.blue.opacity(0.07)))
            }
        }
        .allowsHitTesting(false)
    }
}

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

/// σ slider with histogram track and stats below the control.
struct VarianceThresholdControl: View {
    @Binding var sigma: Double
    let histogram: VarianceHistogramSummary?
    var isEnabled: Bool = true
    var onEditingChanged: ((Bool) -> Void)?

    private static let histogramHeight: CGFloat = 56

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let histogram {
                VarianceHistogramSparkline(summary: histogram, sigma: sigma)
                    .frame(height: Self.histogramHeight)
                    .padding(.horizontal, 2)
            }

            SnappingSigmaSlider(
                value: $sigma,
                isEnabled: isEnabled,
                onEditingChanged: onEditingChanged
            )
            .frame(height: 28)

            if let histogram {
                VarianceThresholdStats(summary: histogram, sigma: sigma)
            } else {
                Text("Load a photo to see the variance distribution for this image.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
