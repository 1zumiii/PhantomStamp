//
//  GeometricCandidateDetection.swift
//  PhantomStamp
//
//  Robust front-end for the global geometric detector.
//
//  A local image edit must not be allowed to invent one FFT peak and force a destructive
//  full-frame resample. Multiple spatially separated windows therefore propose transforms,
//  compatible proposals form consensus clusters, and identity always remains a candidate.
//

import Foundation

struct GeometricTransformCandidate: Sendable {
    var angle: Float
    var scale: Float
    var confidence: Float
    var supportingWindowCount: Int
    var isIdentity: Bool
}

private struct GeometricWindowEstimate: Sendable {
    var angle: Float
    var scale: Float
    var confidence: Float
    var originX: Int
    var originY: Int
}

extension WatermarkService {
    /// Returns a small, ordered hypothesis set for downstream Sync/FEC validation.
    ///
    /// The first pass uses the center and four spatial corners. Four edge-midpoint windows are
    /// added only when the first pass cannot form a strong consensus. At most two non-identity
    /// clusters survive, and identity is always present.
    func detectGeometricTransformCandidates(in yChannel: Matrix) -> [GeometricTransformCandidate] {
        let primaryOrigins = geometricWindowOrigins(
            imageWidth: yChannel.width,
            imageHeight: yChannel.height,
            fractions: [
                (0.5, 0.5),
                (0.0, 0.0), (1.0, 0.0),
                (0.0, 1.0), (1.0, 1.0)
            ]
        )

        var estimates = analyzeGeometricWindows(in: yChannel, origins: primaryOrigins)
        var clusters = clusterGeometricEstimates(estimates)

        let hasStrongPrimaryConsensus = clusters.first.map {
            $0.supportingWindowCount >= min(3, primaryOrigins.count)
                && $0.confidence >= 0.50
        } ?? false

        if !hasStrongPrimaryConsensus {
            let secondaryOrigins = geometricWindowOrigins(
                imageWidth: yChannel.width,
                imageHeight: yChannel.height,
                fractions: [
                    (0.5, 0.0), (0.0, 0.5),
                    (1.0, 0.5), (0.5, 1.0)
                ]
            ).filter { candidate in
                !primaryOrigins.contains {
                    $0.x == candidate.x && $0.y == candidate.y
                }
            }
            estimates.append(contentsOf: analyzeGeometricWindows(in: yChannel, origins: secondaryOrigins))
            clusters = clusterGeometricEstimates(estimates)
        }

        // Transforms below the deskew threshold are equivalent to identity and should not trigger
        // a second bilinear pass.
        clusters.removeAll {
            abs($0.angle) < 5e-3 && abs($0.scale - 1.0) < 5e-4
        }

        let identity = GeometricTransformCandidate(
            angle: 0,
            scale: 1,
            confidence: 1,
            supportingWindowCount: 0,
            isIdentity: true
        )

        let transforms = Array(clusters.prefix(2))
        let trustBestTransform = transforms.first.map {
            $0.supportingWindowCount >= 3 && $0.confidence >= 0.50
        } ?? false

        let candidates = trustBestTransform
            ? transforms + [identity]
            : [identity] + transforms

        #if DEBUG
        let summary = candidates.map {
            let degrees = $0.angle * 180 / .pi
            return String(
                format: "%@ angle=%+.4fdeg scale=%.6f confidence=%.3f support=%d",
                $0.isIdentity ? "identity" : "consensus",
                degrees,
                $0.scale,
                $0.confidence,
                $0.supportingWindowCount
            )
        }.joined(separator: " | ")
        print("[WatermarkService] geometric candidates: \(summary)")
        #endif

        return candidates
    }

    private func geometricWindowOrigins(
        imageWidth: Int,
        imageHeight: Int,
        fractions: [(Float, Float)]
    ) -> [(x: Int, y: Int)] {
        let side = WatermarkService.syncTemplateAnalysisFFTSize
        let centeredX = (imageWidth - side) / 2
        let centeredY = (imageHeight - side) / 2
        let maxX = imageWidth - side
        let maxY = imageHeight - side

        var seen = Set<String>()
        var origins: [(x: Int, y: Int)] = []
        for (fx, fy) in fractions {
            let x = maxX >= 0 ? Int((Float(maxX) * fx).rounded()) : centeredX
            let y = maxY >= 0 ? Int((Float(maxY) * fy).rounded()) : centeredY
            let key = "\(x):\(y)"
            if seen.insert(key).inserted {
                origins.append((x, y))
            }
        }
        return origins
    }

    private func analyzeGeometricWindows(
        in yChannel: Matrix,
        origins: [(x: Int, y: Int)]
    ) -> [GeometricWindowEstimate] {
        guard !origins.isEmpty else { return [] }
        var results = [GeometricWindowEstimate?](repeating: nil, count: origins.count)

        results.withUnsafeMutableBufferPointer { resultPtr in
            DispatchQueue.concurrentPerform(iterations: origins.count) { index in
                let origin = origins[index]
                resultPtr[index] = self.analyzeGeometricWindow(
                    in: yChannel,
                    originX: origin.x,
                    originY: origin.y
                )
            }
        }
        return results.compactMap { $0 }
    }

    private func analyzeGeometricWindow(
        in yChannel: Matrix,
        originX: Int,
        originY: Int
    ) -> GeometricWindowEstimate? {
        let side = WatermarkService.syncTemplateAnalysisFFTSize
        var spectrum = extractAndRemoveDC(
            from: yChannel,
            targetSize: side,
            originX: originX,
            originY: originY
        )
        performForwardFFT(matrix: &spectrum)
        let peaks = findSyncPeaks(in: spectrum)
        guard peaks.count == 4 else { return nil }

        let params = calculateAffineParams(
            from: peaks,
            originalRadius: WatermarkService.syncTemplateOriginalRadius,
            originalAngle: WatermarkService.syncTemplateOriginalAngleRadians
        )
        guard params.scale.isFinite, (0.4...3.0).contains(params.scale) else { return nil }

        let radii = peaks.map { sqrt($0.x * $0.x + $0.y * $0.y) }
        let meanRadius = radii.reduce(0, +) / Float(radii.count)
        let radiusVariance = radii.reduce(0) {
            $0 + ($1 - meanRadius) * ($1 - meanRadius)
        } / Float(radii.count)
        let radiusCV = sqrt(radiusVariance) / max(meanRadius, 1e-6)
        let radiusScore = clamp01(1 - radiusCV / 0.015)

        let angles = peaks.map {
            normalizedPositiveAngle(atan2($0.y, $0.x))
        }.sorted()
        var gapError: Float = 0
        for index in angles.indices {
            let next = index + 1 < angles.count ? angles[index + 1] : angles[0] + 2 * .pi
            gapError += abs((next - angles[index]) - (.pi / 2))
        }
        let meanGapError = gapError / Float(angles.count)
        let spacingScore = clamp01(1 - meanGapError / (3 * .pi / 180))

        let perPeak = peaks.map {
            calculateAffineParams(
                from: [$0],
                originalRadius: WatermarkService.syncTemplateOriginalRadius,
                originalAngle: WatermarkService.syncTemplateOriginalAngleRadians
            )
        }
        let consistentCount = perPeak.reduce(into: 0) { count, estimate in
            let angleDelta = wrappedAngleDelta(estimate.angle, params.angle)
            let scaleDelta = abs(estimate.scale / params.scale - 1)
            if abs(angleDelta) <= (1 * .pi / 180), scaleDelta <= 0.02 {
                count += 1
            }
        }
        let consistencyScore = Float(consistentCount) / Float(peaks.count)
        let prominenceScore = syncPeakProminenceScore(peaks: peaks, spectrum: spectrum)

        let confidence =
            0.30 * radiusScore
            + 0.30 * spacingScore
            + 0.25 * consistencyScore
            + 0.15 * prominenceScore

        guard confidence >= 0.20 else { return nil }
        return GeometricWindowEstimate(
            angle: params.angle,
            scale: params.scale,
            confidence: confidence,
            originX: originX,
            originY: originY
        )
    }

    private func syncPeakProminenceScore(
        peaks: [(x: Float, y: Float)],
        spectrum: FFTComplexMatrix
    ) -> Float {
        let side = spectrum.width
        let half = side / 2
        let meanRadius = peaks.reduce(Float(0)) {
            $0 + sqrt($1.x * $1.x + $1.y * $1.y)
        } / Float(peaks.count)

        var background: [Float] = []
        background.reserveCapacity(side * 4)
        for row in stride(from: 0, to: side, by: 2) {
            let dy = row < half ? row : row - side
            for col in stride(from: 0, to: side, by: 2) {
                let dx = col < half ? col : col - side
                let radius = sqrt(Float(dx * dx + dy * dy))
                guard abs(radius - meanRadius) <= 5 else { continue }
                let nearPeak = peaks.contains {
                    abs(Float(dx) - $0.x) <= 4 && abs(Float(dy) - $0.y) <= 4
                }
                if !nearPeak {
                    background.append(spectrum.magnitudeAt(row: row, col: col))
                }
            }
        }
        guard !background.isEmpty else { return 0 }
        background.sort()
        let median = background[background.count / 2]
        let weakestPeak = peaks.map { peak -> Float in
            let col = (Int(peak.x.rounded()) % side + side) % side
            let row = (Int(peak.y.rounded()) % side + side) % side
            return spectrum.magnitudeAt(row: row, col: col)
        }.min() ?? 0

        let ratio = weakestPeak / max(median, 1e-6)
        return clamp01(log2(max(ratio, 1)) / 6)
    }

    private func clusterGeometricEstimates(
        _ estimates: [GeometricWindowEstimate]
    ) -> [GeometricTransformCandidate] {
        guard !estimates.isEmpty else { return [] }
        let angleTolerance: Float = 0.75 * .pi / 180
        let logScaleTolerance: Float = log(1.01)
        var seenMemberships = Set<String>()
        var candidates: [GeometricTransformCandidate] = []

        for seedIndex in estimates.indices {
            let seed = estimates[seedIndex]
            let members = estimates.indices.filter { index in
                let item = estimates[index]
                return abs(wrappedAngleDelta(item.angle, seed.angle)) <= angleTolerance
                    && abs(log(item.scale) - log(seed.scale)) <= logScaleTolerance
            }
            let membershipKey = members.map(String.init).joined(separator: ",")
            guard seenMemberships.insert(membershipKey).inserted else { continue }

            let totalWeight = members.reduce(Float(0)) {
                $0 + max(estimates[$1].confidence, 0.05)
            }
            var sinSum: Float = 0
            var cosSum: Float = 0
            var logScaleSum: Float = 0
            var confidenceSum: Float = 0
            for index in members {
                let estimate = estimates[index]
                let weight = max(estimate.confidence, 0.05)
                sinSum += sin(estimate.angle) * weight
                cosSum += cos(estimate.angle) * weight
                logScaleSum += log(estimate.scale) * weight
                confidenceSum += estimate.confidence
            }

            let support = members.count
            let meanConfidence = confidenceSum / Float(support)
            guard support >= 2 || meanConfidence >= 0.92 else { continue }
            let supportScore = min(1, Float(support) / 3)
            candidates.append(
                GeometricTransformCandidate(
                    angle: atan2(sinSum, cosSum),
                    scale: exp(logScaleSum / max(totalWeight, 1e-6)),
                    confidence: meanConfidence * supportScore,
                    supportingWindowCount: support,
                    isIdentity: false
                )
            )
        }

        candidates.sort {
            if $0.supportingWindowCount != $1.supportingWindowCount {
                return $0.supportingWindowCount > $1.supportingWindowCount
            }
            return $0.confidence > $1.confidence
        }

        var deduplicated: [GeometricTransformCandidate] = []
        for candidate in candidates {
            let duplicate = deduplicated.contains {
                abs(wrappedAngleDelta($0.angle, candidate.angle)) <= (0.25 * .pi / 180)
                    && abs(log($0.scale) - log(candidate.scale)) <= log(1.003)
            }
            if !duplicate {
                deduplicated.append(candidate)
            }
        }
        return deduplicated
    }

    private func wrappedAngleDelta(_ lhs: Float, _ rhs: Float) -> Float {
        atan2(sin(lhs - rhs), cos(lhs - rhs))
    }

    private func normalizedPositiveAngle(_ angle: Float) -> Float {
        angle >= 0 ? angle : angle + 2 * .pi
    }

    private func clamp01(_ value: Float) -> Float {
        min(max(value, 0), 1)
    }
}
