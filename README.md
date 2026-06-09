# PhantomStamp - iOS Frequency Domain Blind Watermark Tool



- Github Repository: [https://github.com/1zumiii/PhantomStamp](https://github.com/1zumiii/PhantomStamp)
- Video Presentation: [https://drive.google.com/file/d/1rBPoBV3JAGi38SdUDUDxOj4K1WqetIcT/view?usp=sharing](https://drive.google.com/file/d/1rBPoBV3JAGi38SdUDUDxOj4K1WqetIcT/view?usp=sharing)
- Prototype: [https://www.figma.com/proto/GKE5AVKHtmakByYIsy8D9o/PhantomStamp?node-id=0-1&t=nQGHNjCcTTFPQSyT-1](https://www.figma.com/proto/GKE5AVKHtmakByYIsy8D9o/PhantomStamp?node-id=0-1&t=nQGHNjCcTTFPQSyT-1)




## 1. Project Overview

**PhantomStamp** is an iOS application designed for digital artists, photographers, and content creators. It utilizes the Discrete Cosine Transform (DCT) to embed invisible copyright information into the frequency domain of an image. Unlike traditional watermarks, PhantomStamp's blind watermarking solution provides highly robust copyright protection without compromising the aesthetic value of the original artwork.

## 2. Problem Statement

During digital content distribution, creators face several core pain points:

- **Visual Interference:** Traditional visible watermarks (e.g., text, logos) obscure image details and degrade the artistic value of the work.
- **Vulnerability to Removal:** Visible watermarks can be easily cropped out, covered, or erased using modern AI removal tools (like Content-Aware Fill).
- **Difficulty in Copyright Assertion:** When creators discover stolen work, it is often difficult to prove ownership without presenting the original file for comparison.
- **Social Media Compression Loss:** Standard spatial-domain watermarks often become blurred or completely destroyed after undergoing lossy compression on social media platforms (e.g., Instagram, Twitter).

## 3. Technical Principles

PhantomStamp's core competency lies in its dual-domain **Hybrid Architecture**, which seamlessly integrates high-capacity local data hiding with robust global geometric resilience:

### 3.1 Discrete Cosine Transform (DCT) & Local Data Hiding
The app leverages Apple's official **Accelerate (vDSP)** framework to slice the host image's Y-channel into 8x8 macroblocks and transforms them into the frequency domain. The copyright payload is embedded into the **mid-frequency coefficients** by modifying their relative magnitude relationships.

To balance robustness and visual fidelity, an **Adaptive Quantization Step** is employed. The algorithm calculates the mean absolute AC magnitude of each 8×8 block to assess texture complexity dynamically. Smooth areas receive a lighter embedding to preserve pristine visual quality, while highly textured areas receive a stronger embedding to maximize robustness against compression.

### 3.2 Global Geometric Synchronization (DFT & Inverse Mapping)
To counter severe geometric attacks (rotation, scaling) that typically destroy block-based DCT watermarks, PhantomStamp embeds a pre-computed **Continuous Spatial Cosine Wave** across the entire image.
- **Embedding:** By exploiting the Fourier Linearity Theorem, the spatial wave is overlaid onto the image matrix using simple addition, entirely avoiding convolution artifacts. This creates 4 distinct, highly energetic peaks at specific coordinates in the global magnitude spectrum.
- **Extraction:** Before any DCT data retrieval, the algorithm extracts a 512x512 zero-mean crop and performs a **2D Fast Fourier Transform (FFT)**. By calculating the polar coordinates (radius and angle) of the 4 recovered peaks, the system derives the precise rotation angle and scaling factor applied by the attacker.
- **Deskewing:** Using an inverse affine transformation matrix and **Bilinear Interpolation**, the corrupted image is perfectly realigned and resampled to its original grid, restoring the continuous phase required for downstream DCT extraction.

### 3.3 Data Link Layer Security (FEC & Interleaving)
To combat localized burst errors caused by image damage or heavy compression artifacts, the copyright payload is rigorously protected before embedding:
- **Extended Hamming(8,4) Code:** Provides SECDED (Single Error Correction, Double Error Detection) capabilities.
- **Bit-level Block Interleaving:** Scatters adjacent bits of the codeword across different spatial areas, ensuring that localized pixel damage won't wipe out an entire Hamming codeword.

### 3.4 Blind Extraction & Global Majority Voting
The extraction algorithm operates entirely blindly (requires no original image):
- **64-Offset Sliding Window Scan:** Re-aligns the grid origin perfectly even if the image suffers from severe translation or cropping attacks.
- **Global Majority Voting:** The 2D watermark tile is redundantly paved across the entire image. The algorithm aggregates surviving data from all valid fragments (including edge-cropped macroblocks) to recover the most likely true payload. This approach survives severe JPEG compression at quality levels as low as ~51%.

---

## 4. Technical Highlights

- **Pareto-Optimal DSP Trade-offs:** Achieved an idealized equilibrium in the frequency domain. By introducing a **Gaussian Prior Probability Weighting** during the sub-pixel peak fitting phase (Matched Filtering), the system perfectly neutralizes the $1/f^2$ spectral leakage ("DC pull") inherent in natural images. This yields a static alignment error of practically zero ($\approx 0.001^\circ$ angle, $<0.0001$ scale) while sustaining robust detection under isotropic scaling up to 1.50x+.
- **Heuristic 4-fold Ambiguity Resolution:** Elegantly bypassed the $\pm45^\circ$ theoretical rotation singularity inherent to 4-peak symmetric templates. By integrating an orthogonal hypothesis-testing loop directly into the FEC decoding pipeline, the system reliably resolves phase ambiguity without compromising the strict real-number constraint of the spatial IFFT wave.
- **High-Performance Concurrency & OOM Prevention:** Utilizes Swift Concurrency (`async/await`) and `TaskGroup` to slice and process large images (e.g., 4K resolutions) concurrently. Dedicated `autoreleasepool` scopes within strip processing enforce strict memory recycling, preventing Out-Of-Memory (OOM) silent crashes during heavy matrix operations.
- **Zero-Parsing Binary Asset Pipeline:** The 512x512 spatial synchronization template is generated offline via Python and shipped as a highly optimized, raw 32-bit floating-point binary (`.bin`). At runtime, Swift utilizes Unsafe Pointer Binding to map the 1MB file directly into memory, achieving instant loading with 0ms CPU parsing overhead.
- **Event-Driven MVVM & State Machine:** Completely decouples complex mathematical transformations from the View layer. The UI is driven by a robust enumeration-based state machine and `CheckedContinuation`, achieving a true zero-polling event-driven pump that consumes negligible CPU overhead when idle.
- **Adaptive Backpressure via Min-Heap:** Developed a highly resilient SwiftUI progress overlay to handle the massive influx of out-of-order progress events from the concurrent backend. It utilizes a custom **Min-Heap priority queue** to reduce sorting overhead from `O(n log n)` to amortized `O(log n)`. Combined with dynamic pacing, it automatically fast-forwards animations under heavy event backlogs, ensuring smooth 60fps rendering without freezing the main thread.

## 5. Tech Stack

- **Language:** Swift 6.3+
- **UI Framework:** SwiftUI
- **Image Processing:** Accelerate (vDSP / vImage), Core Image
- **Data Persistence:** SwiftData
- **Concurrency:** Swift Concurrency (Async/Await)

