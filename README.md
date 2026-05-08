# PhantomStamp - iOS Frequency Domain Blind Watermark Tool

## 1. Project Overview

**PhantomStamp** is an iOS application designed for digital artists, photographers, and content creators. It utilizes the Discrete Cosine Transform (DCT) to embed invisible copyright information into the frequency domain of an image. Unlike traditional watermarks, PhantomStamp's blind watermarking solution provides highly robust copyright protection without compromising the aesthetic value of the original artwork.

## 2. Problem Statement

During digital content distribution, creators face several core pain points:

- **Visual Interference:** Traditional visible watermarks (e.g., text, logos) obscure image details and degrade the artistic value of the work.
- **Vulnerability to Removal:** Visible watermarks can be easily cropped out, covered, or erased using modern AI removal tools (like Content-Aware Fill).
- **Difficulty in Copyright Assertion:** When creators discover stolen work, it is often difficult to prove ownership without presenting the original file for comparison.
- **Social Media Compression Loss:** Standard spatial-domain watermarks often become blurred or completely destroyed after undergoing lossy compression on social media platforms (e.g., Instagram, Twitter).

## 3. Technical Principles

PhantomStamp's core competency lies in how its underlying algorithm processes image signals and guarantees data integrity:

### 3.1 Discrete Cosine Transform (DCT)

The app leverages Apple's official **Accelerate (vDSP)** framework to transform the image from the spatial domain (pixel matrix) to the frequency domain. In the frequency domain, the image is decomposed into different frequency components.

### 3.2 Adaptive Visual Masking (Mid-Frequency Embedding)

Based on the characteristics of the Human Visual System (HVS), the algorithm embeds the watermark into the **mid-frequency coefficients** (e.g., utilizing symmetry points).
Crucially, it employs an **Adaptive Quantization Step**: The algorithm calculates the mean absolute AC magnitude of each $8 \times 8$ block to dynamically assess texture complexity. Smooth areas receive a lighter embedding to preserve pristine visual quality. Highly textured areas receive a stronger embedding to maximize robustness against compression.

### 3.3 Data Link Layer Security (FEC & Interleaving)

To combat localized burst errors caused by image damage or heavy compression artifacts, the copyright payload is rigorously protected before embedding:
- **Extended Hamming(8,4) Code:** Provides SECDED (Single Error Correction, Double Error Detection) capabilities.
- **Bit-level Block Interleaving:** Scatters adjacent bits of the codeword across different spatial areas, ensuring that localized pixel damage won't wipe out an entire Hamming codeword.

### 3.4 Blind Extraction & Global Majority Voting

The extraction algorithm operates entirely blindly (requires no original image):
- **64-Offset Sliding Window Scan:** Re-aligns the grid origin perfectly even if the image suffers from severe translation or cropping attacks.
- **Global Majority Voting:** Because the 2D watermark tile is redundantly paved across the entire image, the algorithm aggregates surviving data from all valid fragments (including edge-cropped macroblocks) to recover the most likely true payload, demonstrating extreme resistance—capable of surviving JPEG compression qualities down to ~51%.

## 4. Technical Highlights

- **High-Performance Concurrency & OOM Prevention:** Utilizes Swift Concurrency (`async/await`) and `TaskGroup` to slice and process large images (e.g., 4K resolutions) concurrently. Dedicated `autoreleasepool` scopes within strip processing enforce strict memory recycling, preventing Out-Of-Memory (OOM) silent crashes during heavy matrix operations.
- **Low Overhead Optimization:** Calls the SIMD instruction sets of the Accelerate framework for matrix operations, significantly reducing computational overhead and battery consumption on mobile devices.
- **Loosely Coupled Architecture:** Adopts the MVVM design pattern to completely decouple complex mathematical transformation logic from the View layer, ensuring code extensibility, testability, and isolated collaboration via GitHub.
- **Adaptive UI Throttling & Backpressure:** Developed a highly resilient SwiftUI progress overlay to handle high-frequency, out-of-order progress notifications from the concurrent backend. It features dynamic queuing and adaptive animation pacing—automatically fast-forwarding when the event backlog grows—ensuring smooth 60fps rendering without freezing the main UI thread.
- **Strict Producer-Consumer Synchronization:** Implemented a robust "Drain ACK" handshake mechanism between the headless data-processing layer and the UI layer. This guarantees perfect synchronization during multi-file batch processing, forcing the backend to pace its workload until the UI gracefully completes its progress animations, entirely eliminating race conditions and event loss.

## 5. Tech Stack

- **Language:** Swift 5.9+
- **UI Framework:** SwiftUI
- **Image Processing:** Accelerate (vDSP / vImage), Core Image
- **Data Persistence:** SwiftData
- **Concurrency:** Swift Concurrency (Async/Await)
