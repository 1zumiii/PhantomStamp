# PhantomStamp - iOS Frequency Domain Blind Watermark Tool

* **Github Repository:** [1zumiii/PhantomStamp](https://github.com/1zumiii/PhantomStamp)
* **Video Presentation (earlier version):** [Watch on Google Drive](https://drive.google.com/file/d/1rBPoBV3JAGi38SdUDUDxOj4K1WqetIcT/view?usp=sharing)
* **Prototype:** [Figma Interactive Demo](https://www.figma.com/proto/GKE5AVKHtmakByYIsy8D9o/PhantomStamp?node-id=0-1&t=nQGHNjCcTTFPQSyT-1)

## 1. Project Overview

**PhantomStamp** is an iOS application designed for digital artists, photographers, and content creators. It utilizes the Discrete Cosine Transform (DCT) to embed invisible copyright information into the frequency domain of an image. Unlike traditional watermarks, PhantomStamp's blind watermarking solution provides highly robust copyright protection without compromising the aesthetic value of the original artwork.

## 2. Problem Statement

During digital content distribution, creators face several core pain points:

* **Visual Interference:** Traditional visible watermarks (e.g., text, logos) obscure image details and degrade the artistic value of the work.
* **Vulnerability to Removal:** Visible watermarks can be easily cropped out, covered, or erased using modern AI removal tools (like Content-Aware Fill).
* **Difficulty in Copyright Assertion:** When creators discover stolen work, it is often difficult to prove ownership without presenting the original file for comparison.
* **Social Media Compression Loss:** Standard spatial-domain watermarks often become blurred or completely destroyed after undergoing lossy compression on social media platforms (e.g., Instagram, Twitter).

## 3. Technical Principles

PhantomStamp's core competency lies in its dual-domain **Hybrid Architecture**, which seamlessly integrates high-capacity local data hiding with robust global geometric resilience:

### 3.1 Discrete Cosine Transform (DCT) & Local Data Hiding

The app leverages Apple's official **Accelerate (vDSP)** framework to slice the host image's Y-channel into 8x8 macroblocks and transforms them into the frequency domain. The copyright payload is embedded into the **(1,2) and (2,1) mid-low frequency boundary coefficients** by modifying their relative magnitude relationships.

To balance robustness and visual fidelity, an **Adaptive Quantization Step** is employed. The algorithm calculates the mean absolute AC magnitude of each 8×8 block to assess texture complexity dynamically. Smooth areas receive a lighter embedding to preserve pristine visual quality, while highly textured areas receive a stronger embedding to maximize robustness against compression.

### 3.2 Global Geometric Synchronization (DFT & Inverse Mapping)

To counter severe geometric attacks (rotation, scaling) that typically destroy block-based DCT watermarks, PhantomStamp embeds a pre-computed **Continuous Spatial Cosine Wave** across the entire image.

* **Embedding:** By exploiting the Fourier Linearity Theorem, the spatial wave is overlaid onto the image matrix using simple addition, entirely avoiding convolution artifacts. This creates 4 distinct, highly energetic peaks at specific coordinates in the global magnitude spectrum.
* **Spectrum Estimation:** Before any DCT data retrieval, the algorithm extracts a 512x512 zero-mean crop, applies a **2D Separable Hann Window** to eliminate rectangular boundary leakage, and performs a **2D Fast Fourier Transform (FFT)**. By calculating the spectrum ratio of the peaks via a **Grandke Interpolator**, the system eliminates discrete bin bias and derives the precise rotation angle and scaling factor.
* **Deskewing Pipeline:** Using a forward transformation matrix for inverse mapping combined with **Bilinear Interpolation**, the corrupted image is realigned. The intermediate values bypass any integer truncation and flow into a high-fidelity **FloatMatrix**, preserving sub-pixel phase fluctuations required for downstream DCT extraction.

### 3.3 Data Link Layer Security (FEC & Interleaving)

To combat localized burst errors caused by image damage or heavy compression artifacts, the copyright payload is rigorously protected before embedding:

* **Extended Hamming(8,4) Code:** Provides SECDED (Single Error Correction, Double Error Detection) capabilities.
* **Bit-level Block Interleaving:** Scatters adjacent bits of the codeword across different spatial areas, ensuring that localized pixel damage won't wipe out an entire Hamming codeword.

### 3.4 Blind Extraction & Sync-Gated Soft Voting

The extraction algorithm operates entirely blindly (requires no original image):

* **64-Offset Sliding Window Scan:** Re-aligns the grid origin perfectly even if the image suffers from severe translation or cropping attacks.
* **Sync-Gated Local Evaluation:** Each $17 \times 17$ tile undergoes a "local health check" via its embedded 32-bit synchronization markers. Only tiles maintaining a $\ge 75\%$ match gate are permitted to vote, blocking out-of-phase noise from edge-cropped zones.
* **Soft-Decision Energy Summation:** Instead of binary hard-decisions, the system accumulates raw floating-point coefficient differences ($\Delta = |C_{(1,2)}| - |C_{(2,1)}|$) across all surviving repetitions. This matched-filter approach allows high-confidence blocks to mask zero-sum noise, pushing JPEG compression resilience down to an unprecedented **q = 0.24**.

## 4. Technical Highlights

* **Unbiased Grandke DSP Alignment:** Eradicated textbook spectrum estimation bias. By integrating a 2D Hann window with a **Grandke Ratio Interpolator** $\delta = (2\alpha - 1) / (\alpha + 1)$, the static grid alignment error is compressed to under 0.05% ($\le 0.002^\circ$ angle drift, $<0.0005$ scale residual). This reduces global grid accumulation drift from 15px down to <1px, unlocking geometric survival bounds up to 1.50x+ scaling.
* **FloatMatrix & Active Poisoning Pipeline:** Reengineered the graphics processing pipeline to protect fragile AC signal deltas. Recompressed frames straight into a full-precision `FloatMatrix` pipeline to bypass `UInt8` integer rounding truncation. Simultaneously, out-of-bounds canvas regions are explicitly injected with an invalid float token (`-1000.0`), allowing downstream decoders to immediately short-circuit black-border corruption and halt malicious voting injection.
* **Heuristic 4-fold Ambiguity Resolution:** Elegantly bypassed the $\pm45^\circ$ theoretical rotation singularity inherent to 4-peak symmetric templates. By integrating an orthogonal hypothesis-testing loop directly into the FEC decoding pipeline, the system reliably resolves phase ambiguity without compromising the strict real-number constraint of the spatial IFFT wave.
* **High-Performance Concurrency & OOM Prevention:** Utilizes Swift Concurrency (`async/await`) and `TaskGroup` to slice and process large images (e.g., 4K resolutions) concurrently. Dedicated `autoreleasepool` scopes within strip processing enforce strict memory recycling, preventing Out-Of-Memory (OOM) silent crashes during heavy matrix operations.
* **Zero-Parsing Binary Asset Pipeline:** The 512x512 spatial synchronization template is generated offline via Python and shipped as a highly optimized, raw 32-bit floating-point binary (`.bin`). At runtime, Swift utilizes Unsafe Pointer Binding to map the 1MB file directly into memory, achieving instant loading with 0ms CPU parsing overhead.
* **Event-Driven MVVM & State Machine:** Completely decouples complex mathematical transformations from the View layer. The UI is driven by a robust enumeration-based state machine and `CheckedContinuation`, achieving a true zero-polling event-driven pump that consumes negligible CPU overhead when idle.
* **Adaptive Backpressure via Min-Heap:** Developed a highly resilient SwiftUI progress overlay to handle the massive influx of out-of-order progress events from the concurrent backend. It utilizes a custom **Min-Heap priority queue** to reduce sorting overhead from `O(n log n)` to amortized `O(log n)`. Combined with dynamic pacing, it automatically fast-forwards animations under heavy event backlogs, ensuring smooth 60fps rendering without freezing the main thread.

## 5. Performance & Limit Testing

PhantomStamp employs a rigorous, automated **Smart Step Boundary Scan** to evaluate the hybrid architecture's absolute physical limits under severe geometric attacks. By differentiating between algorithmic failures and theoretical DSP boundaries, the system is calibrated to the Pareto-Optimal point.

<p align="center">
  <img src="PhantomStamp/Testing/phantomstamp_boundary_scan_v3.png" alt="Hybrid Architecture Boundary Scan" width="70%">
  <br>
  <em>Figure 1: Boundary scan results revealing the 1/f² compensation and the Bilinear Death Valley.</em>
</p>

### 5.1 Geometric Resilience (Intensity = 4.0 - 5.0)

* **Static Precision:** Utilizing a Sub-pixel Parabolic Fitting combined with a Matched Gaussian Prior Filter, the extraction drift is practically eliminated (Angle Error $\le 0.002^\circ$, Scale Relative Error $\le 0.0003$).
* **Rotation Resilience:** Operates flawlessly within $(-45^\circ, 45^\circ)$. To break the theoretical 4-fold symmetry ambiguity inherent to cross-shaped FFT spectra, an elegant heuristic retry mechanism is integrated into the FEC layer, testing orthogonal hypotheses to achieve full $360^\circ$ immunity.
* **Scaling Resilience:** Demonstrates highly asymmetric robustness tailored for real-world screenshot attacks. It survives severe image upscaling up to **1.50x**, while gracefully degrading below **0.85x** as the downsampled frequency peaks are pushed out of the Gaussian prior's safety envelope and masked by natural image noise.

### 5.2 Conquering the DSP "Death Valley"

Through high-granularity fuzzing, we identified and mitigated two critical DSP phenomena:

1. **Bilinear Death Valley:** Minimal deformations (e.g., $\pm 2^\circ$ or $0.98x$) force nearly 100% of the image pixels into non-integer coordinates, triggering global low-pass filtering via bilinear interpolation.
2. **Phase Cancellation (Non-contiguous Failure Distribution):** Specific fractional scaling ratios (e.g., $1.07x$) occasionally cause destructive interference between the resampling grid and the host's natural textures.

**Solution:** By exposing the `Intensity` parameter (defaulting to the 4.0 - 5.0 tier for the "Balanced/Paranoid" modes), PhantomStamp injects just enough energetic armor into the mid-frequency spectrum to bridge these interpolation valleys, maintaining seamless extraction without triggering the Human Visual System (HVS) threshold.

### 5.3 Robustness Against Heavy JPEG Compression (Paranoid Mode: Multiplier = 10.0, Threshold = -1.0)

To map the absolute breakdown boundaries under extreme lossy channel conditions, an automated 19-case non-uniform quality sweep was executed on a high-resolution **4032x3024** pixel asset. Under full-block saturation (`textureVarianceThreshold = -1.0`), the architecture establishes a highly robust survival profile against aggressive quantization.

<p align="center">
  <img src="PhantomStamp/Testing/compression_sweep_respaced.png" alt="Compression Sweep Respaced Results" width="75%">
  <br>
  <em>Figure 2: Non-uniform quality sweep revealing the compression asymptote and step aliasing inversion.</em>
</p>

* **Extreme Quantization Survival:** The pipeline achieves an absolute survival boundary down to **q = 0.24** (`lowestPass = 0.24`), successfully extracting the exact plaintext signature from highly degraded image artifacts.
* **The "Compression Floor" Phenomenon:** A distinct asymptotic behavior is captured between **q = 0.30** and **q = 0.20**. While file size drops linearly from 4.15MB (**q = 0.95**) down to 1.39MB (**q = 0.40**) as natural spatial details are stripped, it locks firmly near the **1.0MB floor** below **q = 0.30**. This quantitatively verifies that the remaining file allocation is strictly bound to the invariant macroblock DC coefficients and the heavily armored (1,2)/(2,1) watermark wave.
* **Quantization Step Aliasing Validation:** The boundary scan successfully isolated a non-monotonic inversion point at **q = 0.25 (FAIL)** followed by an immediate revival at **q = 0.24 (PASS)**. This provides empirical validation of discrete rounding effects: the slight shift in the JPEG quantization matrix step at **q = 0.24** repositions the truncation boundaries, pushing localized double-bit errors back within the error-correction capability of the FEC layer.

### 5.4 Robustness Against Severe Edge Cropping (Single Variable: Right-Side Crop)

To evaluate the grid-tracking resilience and redundant block spatial alignment under extreme surface destruction, a 59-case segmented boundary sweep was executed by progressively shaving pixels from the right margin of a **4032x3024** image asset (`identity = PASS`).

<p align="center">
  <img src="PhantomStamp/Testing/crop_sweep_sampled.png" alt="Crop Sweep Sampled Results" width="75%">
  <br>
  <em>Figure 3: Segmented crop sweep illustrating the 136px physical payload period boundary and abrupt decoding collapse.</em>
</p>

* **96% Surface Destruction Survival:** The pipeline maintains a flawless reconstruction rate up to an extreme **96.0% crop ratio** (`maxPass = 96.0%`), preserving absolute extraction capability from a heavily mutilated, pillar-like canvas slice of only **162x3024** pixels.
* **The 136px Spatial Period Boundary:** A steep failure cliff is captured precisely at **97.0% crop** (canvas width dropping to **121px**). In PhantomStamp's core layout, a single complete 2D payload tile comprises $17 \times 17$ macroblocks of 8x8 DCT grids, setting a hard physical period limit of $17 \times 8 = 136\text{ px}$. At 96% crop (162px), the remaining width safely covers at least one horizontal period, allowing the **64-Offset Sliding Window Scan** to accurately resolve the spatial phase. At 97% crop (121px), the horizontal continuity of the information source is physically broken ($121\text{ px} < 136\text{ px}$), causing an immediate decoding collapse.
* **One-Dimensional Vertical Energy Accumulation:** Despite the severe horizontal compression, the vertical axis remains 100% intact at 3024px ($3024 / 8 = 378$ rows of DCT blocks). This yields roughly $378 / 17 \approx 22.2$ full vertical repetitions. The **Soft-Decision Voting** engine aggregates these 22 matching spatial lines to accumulate massive positive confidence scores, completely overriding localized truncation noise.
* **DFT Fail-Safe Short-Circuit Protection:** Because the test isolates a pure crop attack without compound rotation or scaling, the FFT spectrum radar notes a lack of multi-dimensional deformation. The system's **Fail-Safe mechanism** instantly short-circuits the resampling layer, bypassing bilinear interpolation entirely and passing the unadulterated `FloatMatrix` directly to the DCT decoder, shielding the fragile remaining block energy from low-pass filtering degradation.

## 6. Tech Stack

* **Language:** Swift 6.3+
* **UI Framework:** SwiftUI
* **Image Processing:** Accelerate (vDSP / vImage), Core Image
* **Data Persistence:** SwiftData
* **Concurrency:** Swift Concurrency (Async/Await)