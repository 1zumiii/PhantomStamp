//
//  SyncTemplateExtraction.swift
//  PhantomStamp
//
//  Created by Orion on 8/6/2026.
//
//  Companion to `SyncTemplateEmbedding.swift`.
//
//  The embed pipeline tiles a deterministic 512×512 spatial wave on top of the host Y-channel.
//  By construction (see Python generator inside `Assets/DSP_Assets/sync_template_512.bin`), the DFT of
//  that wave has exactly 4 sharp peaks sitting at radius=100, angles ±π/4 around DC. Those peaks
//  are the geometric "lighthouses" the extractor uses to undo any rotation / scale attack the
//  attacker may have performed before saving the image back to disk.
//
//  Extraction pipeline (high level):
//      Matrix(Y) → 512×512 zero-mean center crop → 2D FFT → 4 amplitude peaks
//                → (angle, scale) → inverse warp → corrected Matrix(Y)
//
//  Notation:
//   - All coordinates use the image convention (origin top-left, +y points DOWN).
//   - Angles are reported in radians using `atan2(y, x)`, so a positive angle = clockwise
//     visual rotation (because flipping y flips the sign of the math-convention angle).
//

import Foundation
import Accelerate

extension WatermarkService {

    // ==========================================
    // MARK: - Sync Template Geometric Constants
    // ==========================================

    /// Frequency-space radius (in FFT cells, centered around DC) of every peak baked into
    /// `sync_template_512.bin`.
    ///
    /// IMPORTANT — this is NOT `100.0` even though the Python generator's `radius` variable is.
    /// The generator does `dx = int(radius * cos(π/4))` ⇒ `int(70.71)` ⇒ `70`, then the peak is
    /// placed at integer cell `(±70, ±70)`. The TRUE post-truncation radius is therefore
    /// `sqrt(70² + 70²) = 98.99494937…`, not 100. Using 100 here would inject a systematic
    /// `100 / 98.995 ≈ 1.0102` multiplicative bias into every `scale` recovery.
    static let syncTemplateOriginalRadius: Float = {
        // Compute from integer cell positions used by the generator, so any future tweak to dx/dy
        // ripples through automatically rather than diverging silently.
        let dx: Double = 70
        let dy: Double = 70
        return Float((dx * dx + dy * dy).squareRoot())
    }()

    /// Reference angle of one template peak in `atan2(y, x)` convention.
    /// The full peak set sits at `originalAngle + k·π/2 (k = 0..3)`; 4-fold disambiguation in
    /// `calculateAffineParams` resolves the ambiguity into the smallest-magnitude rotation.
    static let syncTemplateOriginalAngleRadians: Float = .pi / 4

    /// FFT side length used for global geometric analysis. The bundled spatial template is also
    /// exactly this size, so one full period of the template fits inside the analysis crop.
    static let syncTemplateAnalysisFFTSize: Int = 512

// ==========================================
    // MARK: - Core Function 2: Detect Geometric Transforms
    // ==========================================

    /// Detects rotation + isotropic scaling by analyzing the DFT amplitude spectrum of a 512×512
    /// center crop of the host Y-channel.
    ///
    /// On a clean (un-attacked) image the 4 template peaks land at `(±100·cos(π/4), ±100·sin(π/4))`.
    /// After a rotation `θ` and uniform scale `s` by the attacker the peaks rotate by `θ` and
    /// shrink by `1/s` (spatial scaling by `s` ⇔ frequency scaling by `1/s`). We invert that
    /// relationship by reading the polar coordinates of the strongest off-DC peak.
    ///
    /// Returns `(angle: 0, scale: 1)` (identity) whenever the spectrum analysis fails — leaving
    /// the rest of the extraction pipeline as-if the hybrid feature were disabled.
    func detectGeometricTransforms(in yChannel: Matrix) -> (angle: Float, scale: Float) {
        let N = WatermarkService.syncTemplateAnalysisFFTSize
        var complexMatrix = extractAndRemoveDC(from: yChannel, targetSize: N)
        performForwardFFT(matrix: &complexMatrix)
        let peaks = findSyncPeaks(in: complexMatrix)
        
        guard !peaks.isEmpty else {
            return (angle: 0.0, scale: 1.0)
        }
        
        let params = calculateAffineParams(
            from: peaks,
            originalRadius: WatermarkService.syncTemplateOriginalRadius,
            originalAngle: WatermarkService.syncTemplateOriginalAngleRadians
        )
        
        return params
    }

    // ==========================================
    // MARK: - Core Function 3: Deskewing (Inverse Mapping)
    // ==========================================

    /// Reconstructs a corrected Y-channel by reversing the detected rotation and scaling around
    /// the image center, using bilinear interpolation for sub-pixel sampling.
    ///
    /// The output canvas size is identical to the input — pixels that would map outside the
    /// source frame receive the POISON sentinel `-1000.0` (via `bilinearInterpolate`), so the
    /// downstream grid scan / bit extraction can identify and exclude the dead frame. This keeps
    /// the 8×8 macroblock grid period intact while rotated corners / upscale borders abstain.
    ///
    /// PRECISION: returns a ``FloatMatrix`` carrying the RAW bilinear samples. Rounding back to
    /// `UInt8` here would quantize away the sub-intensity AC variations (< 1.0 gray level) that
    /// encode the payload bits, zeroing the mid-frequency DCT coefficients downstream. The whole
    /// extraction path (`extractSpatialBlock` → `performDCT`) consumes this Float plane directly.
    ///
    /// Short-circuits when the detected transform is effectively the identity to avoid the
    /// faint resampling blur a no-op bilinear pass would otherwise introduce.
    func deskewImage(_ yChannel: Matrix, angle: Float, scale: Float) -> FloatMatrix {
        let w = yChannel.width
        let h = yChannel.height

        // Identity short-circuit thresholds: ~5e-3 rad ≈ 0.3°, scale within 0.05%.
        // Below these levels the bilinear pass would lose more SNR than the residual transform
        // would cost, so we keep the source pixels untouched (lossless UInt8 → Float promotion).
        if abs(angle) < 5e-3 && abs(scale - 1.0) < 5e-4 {
            return FloatMatrix(promoting: yChannel)
        }

        let cx = Float(w) / 2.0
        let cy = Float(h) / 2.0

        var outData = [Float](repeating: 0, count: w * h)
        outData.withUnsafeMutableBufferPointer { outPtr in
            for y in 0..<h {
                let rowBase = y * w
                for x in 0..<w {
                    // Map destination pixel → source coordinate the attacker pulled it from.
                    let inv = calculateInverseCoordinate(
                        targetX: x, targetY: y,
                        centerX: cx, centerY: cy,
                        angle: angle, scale: scale
                    )
                    // Store the raw interpolated value — no clamp/round/UInt8 quantization.
                    outPtr[rowBase + x] = bilinearInterpolate(matrix: yChannel, x: inv.x, y: inv.y)
                }
            }
        }

        return FloatMatrix(width: w, height: h, data: outData)
    }

    // ==========================================
    // MARK: - Helper Functions
    // ==========================================

    /// Crops a 512×512 center block from the UInt8 image, converts to Float, removes DC, and
    /// packs it directly into the ComplexMatrix that the FFT will operate on in place.
    ///
    /// IMPLEMENTATION NOTES:
    ///  1. `startX/startY` may be negative when the source image is smaller than `targetSize`,
    ///     in which case the explicit bounds-check below treats out-of-bounds samples as 0.0.
    ///  2. The mean used for DC removal is computed over **only the in-bounds** samples so the
    ///     zero-padded border doesn't bias it toward 0 (which would leave a residual DC bump in
    ///     the FFT, surrounded by a sinc-shaped boundary artifact).
    ///  3. The `imag` array is already zeroed by `FFTComplexMatrix.init` — we only need to fill
    ///     the real part, the input signal is purely real.
    func extractAndRemoveDC(
        from yChannel: Matrix,
        targetSize: Int = 512,
        originX: Int? = nil,
        originY: Int? = nil
    ) -> FFTComplexMatrix {
        let w = yChannel.width
        let h = yChannel.height
        let N = targetSize
        precondition(N > 0 && (N & (N - 1)) == 0, "targetSize must be a power of two")
        precondition(yChannel.data.count == w * h, "Y channel data size does not match width * height")

        // Center the N×N analysis window. Negative origin = zero-padding to the top/left.
        let startX = originX ?? ((w - N) / 2)
        let startY = originY ?? ((h - N) / 2)

        // PASS 1: accumulate the mean over actual in-bounds pixels only.
        var sum: Float = 0
        var count: Int = 0
        yChannel.data.withUnsafeBufferPointer { src in
            for j in 0..<N {
                let sy = startY + j
                if sy < 0 || sy >= h { continue }
                let srcRowBase = sy * w
                for i in 0..<N {
                    let sx = startX + i
                    if sx < 0 || sx >= w { continue }
                    sum += Float(src[srcRowBase + sx])
                    count += 1
                }
            }
        }
        let mean: Float = count > 0 ? sum / Float(count) : 0

        // 2D Hann window (separable, periodic/DFT-even form).
        //
        // WHY: with a rectangular window, a peak at a non-integer bin leaks an asymmetric |sinc|
        // pattern into its neighbors, and sub-bin interpolation gets pulled toward the integer
        // bin by up to ~0.3 cells. At r≈90 that is a systematic ~0.3% scale error — which
        // accumulates to >10px of macroblock-grid drift across a 4K image and de-correlates the
        // tile repetitions during voting. Hann shapes the main lobe so the Grandke ratio
        // interpolation in `refinePeakSubPixel` becomes (nearly) bias-free.
        var hann = [Float](repeating: 0, count: N)
        for i in 0..<N {
            hann[i] = 0.5 * (1.0 - cos(2.0 * Float.pi * Float(i) / Float(N)))
        }

        // PASS 2: write (pixel - mean) · hann[j] · hann[i] into the real part; OOB stays 0.
        var matrix = FFTComplexMatrix(width: N, height: N)
        matrix.real.withUnsafeMutableBufferPointer { real in
            yChannel.data.withUnsafeBufferPointer { src in
                for j in 0..<N {
                    let sy = startY + j
                    if sy < 0 || sy >= h { continue }
                    let dstRowBase = j * N
                    let srcRowBase = sy * w
                    let wy = hann[j]
                    for i in 0..<N {
                        let sx = startX + i
                        if sx < 0 || sx >= w { continue }
                        real[dstRowBase + i] = (Float(src[srcRowBase + sx]) - mean) * wy * hann[i]
                    }
                }
            }
        }
        return matrix
    }

    /// Executes a 2D forward FFT in place using Apple's Accelerate / vDSP framework.
    ///
    /// WHY `vDSP_fft2d_zip` AND NOT `vDSP_fft2d_zrip`:
    ///  - `FFTComplexMatrix` stores full-size `real` and `imag` arrays (N×N each).
    ///  - `_zrip` is the real-to-complex variant that packs results into Nyquist-packed format
    ///    (DC and Nyquist real parts crammed into one slot, etc.) — convenient for memory but
    ///    painful to traverse for a magnitude-spectrum peak search.
    ///  - `_zip` (complex-to-complex with `imag = 0`) uses ~2× the memory of `_zrip` but lets us
    ///    treat the output as a plain N×N grid where `magnitudeAt(row, col)` Just Works.
    ///
    /// WARNINGS:
    ///  - vDSP scales the forward FFT result by N (total samples). Absolute magnitudes are
    ///    inflated, but RELATIVE rankings (which the peak search uses) are unaffected.
    ///  - `vDSP_create_fftsetup` allocates twiddle factors; we always destroy it via `defer` so
    ///    repeated calls don't leak.
    func performForwardFFT(matrix: inout FFTComplexMatrix) {
        let N = matrix.width
        precondition(matrix.width == matrix.height, "Only square matrices supported by this helper")
        precondition(N > 0 && (N & (N - 1)) == 0, "FFT size must be a power of two")

        let log2N: vDSP_Length = vDSP_Length(log2(Float(N)).rounded())
        guard let setup = vDSP_create_fftsetup(log2N, FFTRadix(kFFTRadix2)) else {
            #if DEBUG
            print("[SyncTemplateExtraction] vDSP_create_fftsetup returned nil — spectrum left unchanged")
            #endif
            return
        }
        defer { vDSP_destroy_fftsetup(setup) }

        matrix.withDSPSplitComplex { split in
            // IC0=1 → stride-1 within rows; IC1=0 → defaults to 2^log2N (= row length) between rows.
            // Square FFT so both `__Log2N0` and `__Log2N1` are equal. Direction = -1 (forward).
            vDSP_fft2d_zip(setup, &split, 1, 0, log2N, log2N, FFTDirection(FFT_FORWARD))
        }
    }

    /// Scans the magnitude spectrum and returns the strongest off-DC peak in each of the four
    /// "centered" quadrants, sorted by SCORE descending.
    ///
    /// Returned coordinates use the image convention: `(x = col - centerCol, y = row - centerRow)`,
    /// so positive `y` points DOWN, matching `bilinearInterpolate` and `calculateInverseCoordinate`.
    ///
    /// PEAK SCORING: `score = magnitude · exp(-((r - 100) / sigma)²)`
    ///   The Gaussian half-life around the template's nominal radius (100) suppresses image-content
    ///   peaks that would otherwise dominate the raw magnitude race. Empirically natural photos
    ///   often have strong frequency clusters at r≈30..50 (e.g. ocean waves, sky gradients) that
    ///   are 5×–80× stronger than the template peaks; the Gaussian prior crushes those to a
    ///   negligible weight (`exp(-((37-100)/30)²) ≈ 0.012`) while keeping template peaks at full
    ///   weight even under scale attacks in roughly `[0.7×, 1.4×]` (`exp(-((±30)/30)²) ≈ 0.37`).
    ///   Beyond that range the Gaussian falls off fast enough that the template peak loses to noise.
    ///
    /// Sub-pixel position is refined via a 1-D parabolic fit (separable in row and col) on the
    /// 3×3 magnitude neighborhood. The fit is clamped to ±0.5 to keep noisy peaks from running
    /// away from the integer maximum.
    func findSyncPeaks(in freqMatrix: FFTComplexMatrix) -> [(x: Float, y: Float)] {
        let N = freqMatrix.width
        precondition(freqMatrix.width == freqMatrix.height, "Expected square FFT matrix")
        let halfN = N / 2

        // Hard search-ring kept ONLY to avoid wasting magnitude calculations on cells whose
        // Gaussian weight is essentially zero. Inner cap also dodges DC contamination from
        // residual low-frequency leakage the mean subtraction can't fully kill.
        let dcKeepOutRadius: Int = 25
        let maxSearchRadius: Int = 200
        let dcKeepOutSq = dcKeepOutRadius * dcKeepOutRadius
        let maxSearchSq = maxSearchRadius * maxSearchRadius

        // Radius prior centered on the known template radius. Sigma=30 corresponds to roughly
        // ±30% scale tolerance at half-weight; tweak in lock-step with the test sweep range.
        let expectedRadius: Float = WatermarkService.syncTemplateOriginalRadius
        let sigma: Float = 30
        let invSigmaSq: Float = 1.0 / (sigma * sigma)

        // Track the highest-SCORED peak (not highest magnitude) per centered quadrant.
        // q index: 0=(x>=0, y>=0), 1=(x>=0, y<0), 2=(x<0, y>=0), 3=(x<0, y<0).
        var bestScore: [Float] = [Float](repeating: -1, count: 4)
        var bestMag: [Float] = [Float](repeating: 0, count: 4)
        var bestRow: [Int] = [Int](repeating: -1, count: 4)
        var bestCol: [Int] = [Int](repeating: -1, count: 4)

        for row in 0..<N {
            let dy = row < halfN ? row : (row - N)        // centered: y > 0 → row > halfN flipped
            for col in 0..<N {
                let dx = col < halfN ? col : (col - N)    // centered: x > 0 → right of DC

                let rSq = dx * dx + dy * dy
                if rSq < dcKeepOutSq || rSq > maxSearchSq { continue }

                let m = freqMatrix.magnitudeAt(row: row, col: col)
                let r = sqrt(Float(rSq))
                let radiusErr = r - expectedRadius
                // Gaussian: peaks far from the expected template radius are dramatically penalized.
                let weight = exp(-radiusErr * radiusErr * invSigmaSq)
                let score = m * weight

                let q: Int
                if dx >= 0 && dy >= 0 { q = 0 }
                else if dx >= 0 && dy <  0 { q = 1 }
                else if dx <  0 && dy >= 0 { q = 2 }
                else { q = 3 }

                if score > bestScore[q] {
                    bestScore[q] = score
                    bestMag[q] = m
                    bestRow[q] = row
                    bestCol[q] = col
                }
            }
        }

        // Refine each integer-pixel peak to sub-pixel precision and convert to centered coords.
        // Note: sub-pixel refinement still uses RAW magnitude (not weighted score) — the
        // weighting affects which integer cell we choose as the peak, but the local parabolic
        // shape we fit on top of it should reflect the actual energy distribution.
        var peaks: [(score: Float, x: Float, y: Float)] = []
        for q in 0..<4 {
            guard bestRow[q] >= 0 else { continue }
            let row = bestRow[q]
            let col = bestCol[q]
            let refined = refinePeakSubPixel(in: freqMatrix, row: row, col: col)

            // Recenter using the fractional refined row/col. The "side" of DC is determined by
            // the integer row/col, which is stable as long as the integer peak is off-DC (we
            // already enforced that with the keep-out mask).
            let dy: Float = (row < halfN) ? refined.row : (refined.row - Float(N))
            let dx: Float = (col < halfN) ? refined.col : (refined.col - Float(N))
            peaks.append((score: bestScore[q], x: dx, y: dy))
            _ = bestMag[q]  // kept for potential future diagnostic logging
        }

        peaks.sort { $0.score > $1.score }
        return peaks.map { (x: $0.x, y: $0.y) }
    }

    /// 1-D Grandke ratio interpolation along rows and columns separately, with FFT wrap-around
    /// indexing so peaks near the spectrum borders still get a clean neighborhood.
    ///
    /// MATCHED TO THE HANN WINDOW applied in `extractAndRemoveDC`: for a Hann-windowed sinusoid
    /// the estimator `α = |X(k₀±1)| / |X(k₀)| (toward the larger neighbor), δ = (2α − 1)/(α + 1)`
    /// is exact — unlike parabolic-on-magnitude over a rectangular window, whose |sinc| leakage
    /// biased the radius by up to ~0.3 cells (≈0.3% scale error ⇒ >10px grid drift on 4K images).
    private func refinePeakSubPixel(in freqMatrix: FFTComplexMatrix, row: Int, col: Int) -> (row: Float, col: Float) {
        let N = freqMatrix.width
        let rm1 = (row - 1 + N) % N
        let rp1 = (row + 1) % N
        let cm1 = (col - 1 + N) % N
        let cp1 = (col + 1) % N

        let mC = freqMatrix.magnitudeAt(row: row, col: col)
        let mU = freqMatrix.magnitudeAt(row: rm1, col: col)
        let mD = freqMatrix.magnitudeAt(row: rp1, col: col)
        let mL = freqMatrix.magnitudeAt(row: row, col: cm1)
        let mR = freqMatrix.magnitudeAt(row: row, col: cp1)

        // Clamped to ±0.5 cells — noise can push α outside the model's valid range, and it's
        // safer to under-correct than to run away from the integer maximum.
        func grandkeOffset(center: Float, minus: Float, plus: Float) -> Float {
            guard center > 1e-12 else { return 0 }
            let delta: Float
            if plus >= minus {
                let alpha = plus / center
                delta = (2 * alpha - 1) / (alpha + 1)
            } else {
                let alpha = minus / center
                delta = -((2 * alpha - 1) / (alpha + 1))
            }
            return min(max(delta, -0.5), 0.5)
        }

        return (
            row: Float(row) + grandkeOffset(center: mC, minus: mU, plus: mD),
            col: Float(col) + grandkeOffset(center: mC, minus: mL, plus: mR)
        )
    }

    /// Recovers `(rotation, scale)` from the peak coordinates returned by `findSyncPeaks`.
    ///
    /// MATH:
    ///  - Spatial up-scaling by `s` ⇒ frequency shrink by `1/s`, so
    ///    `scale = originalRadius / detectedRadius`.
    ///  - Rotation maps directly between domains, so `rotation = detectedAngle - originalAngle`.
    ///
    /// 4-FOLD AMBIGUITY: The template has 4 peaks at `originalAngle + k·π/2 (k = 0..3)`. We try
    /// every `k`, wrap the candidate rotation to `(-π, π]`, and pick the one with the smallest
    /// magnitude — equivalent to assuming the true attack rotation lives in `(-π/4, +π/4]`.
    /// Larger rotations would also flip the macroblock layout in ways the existing grid scan
    /// can't recover from anyway.
    func calculateAffineParams(from peaks: [(x: Float, y: Float)], originalRadius: Float, originalAngle: Float) -> (angle: Float, scale: Float) {
        // Per-peak estimate with 4-fold disambiguation: try every k ∈ {0, 1, 2, 3} and keep the
        // rotation closest to 0 (wrap to (-π, π] via atan2(sin, cos) — cheap and branch-free).
        func solve(_ peak: (x: Float, y: Float)) -> (angle: Float, scale: Float) {
            let r = sqrt(peak.x * peak.x + peak.y * peak.y)
            let detectedAngle = atan2(peak.y, peak.x)
            // Guard against zero radius (would only happen if the DC mask failed).
            let scale = originalRadius / max(r, 1e-3)

            var bestRotation: Float = .infinity
            for k in 0..<4 {
                let candidate = detectedAngle - (originalAngle + Float(k) * (.pi / 2))
                let wrapped = atan2(sin(candidate), cos(candidate))
                if abs(wrapped) < abs(bestRotation) {
                    bestRotation = wrapped
                }
            }
            return (angle: bestRotation, scale: scale)
        }

        guard let strongest = peaks.first else { return (0.0, 1.0) }
        let reference = solve(strongest)

        // PRECISION: averaging the (up to) 4 template peaks roughly halves the estimator noise
        // vs using the strongest peak alone. This matters downstream: a residual scale error of
        // just 3e-4 (or ~0.1° of rotation) accumulates to >1px of macroblock-grid drift across a
        // 4000+ px image, which is what de-correlates distant tile repetitions during voting.
        //
        // Consistency gate vs the strongest peak (±1°, ±2% scale) rejects the occasional
        // image-content peak that survived the radius prior in a weak quadrant.
        var angleSum: Float = 0
        var scaleSum: Float = 0
        var count = 0
        for peak in peaks.prefix(4) {
            let est = solve(peak)
            let angleDelta = atan2(sin(est.angle - reference.angle), cos(est.angle - reference.angle))
            guard abs(angleDelta) <= (1.0 * .pi / 180.0), abs(est.scale / reference.scale - 1.0) <= 0.02 else {
                continue
            }
            angleSum += est.angle
            scaleSum += est.scale
            count += 1
        }

        guard count > 0 else { return reference }
        return (angle: angleSum / Float(count), scale: scaleSum / Float(count))
    }

    /// Maps a destination pixel `(targetX, targetY)` back to its source pixel in the attacked
    /// image.
    ///
    /// CRITICAL FIX: In inverse mapping (Destination -> Source), because Source = Attacked and
    /// Destination = Original, the mapping function MUST be the attacker's FORWARD transform.
    func calculateInverseCoordinate(targetX: Int, targetY: Int, centerX: Float, centerY: Float, angle: Float, scale: Float) -> (x: Float, y: Float) {
        let tx = Float(targetX) - centerX
        let ty = Float(targetY) - centerY

        // FORWARD rotation by +angle:
        // The attacker rotated the image by +angle. To find where a pixel in the original
        // image ended up in the attacked image, we must apply that same +angle rotation.
        let cosA = cos(angle)
        let sinA = sin(angle)
        let xRot = tx * cosA - ty * sinA
        let yRot = tx * sinA + ty * cosA

        // FORWARD scaling:
        // The attacker scaled the image by `scale`. A coordinate in the original image
        // is stretched by `scale` in the attacked image.
        let xInv = xRot * scale
        let yInv = yRot * scale

        return (x: xInv + centerX, y: yInv + centerY)
    }

    /// Bilinear sample from a UInt8 matrix. Out-of-frame coordinates return the POISON sentinel
    /// `-1000.0` (not 0): downstream block extraction uses `isBlockPolluted` to make dead-frame
    /// blocks abstain from voting instead of decoding as fabricated bits.
    ///
    /// NOTE: We use a strict OOB check `> Float(w - 1)` rather than `>= Float(w)` so the sample
    /// at the very last valid row/column still works (its `x1`/`y1` neighbor would otherwise be
    /// out of bounds; we clamp it back to the last valid index to keep the 4-tap formula sane).
    func bilinearInterpolate(matrix: Matrix, x: Float, y: Float) -> Float {
        let w = matrix.width
        let h = matrix.height
        guard w > 0, h > 0 else { return 0 }

        // True out-of-bounds → zero (visual black corner after a rotation).
        if x < 0 || y < 0 || x > Float(w - 1) || y > Float(h - 1) {
            return -1000.0
        }

        let x0 = Int(floor(x))
        let y0 = Int(floor(y))
        let x1 = min(x0 + 1, w - 1)
        let y1 = min(y0 + 1, h - 1)

        let fx = x - Float(x0)
        let fy = y - Float(y0)

        return matrix.data.withUnsafeBufferPointer { src -> Float in
            let p00 = Float(src[y0 * w + x0])
            let p01 = Float(src[y0 * w + x1])
            let p10 = Float(src[y1 * w + x0])
            let p11 = Float(src[y1 * w + x1])

            // Mix columns first, then rows (separable bilinear).
            let top = p00 * (1 - fx) + p01 * fx
            let bot = p10 * (1 - fx) + p11 * fx
            return top * (1 - fy) + bot * fy
        }
    }
}
