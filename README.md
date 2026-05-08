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

PhantomStamp's core competency lies in how its underlying algorithm processes image signals:

### 3.1 Discrete Cosine Transform (DCT)

The app leverages Apple's official **Accelerate (vDSP)** framework to transform the image from the spatial domain (pixel matrix) to the frequency domain. In the frequency domain, the image is decomposed into different frequency components.

### 3.2 Mid-Frequency Embedding Strategy

Based on the characteristics of the Human Visual System (HVS), the algorithm embeds the watermark bitstream into the **mid-frequency coefficients**:

- **Avoiding Low Frequencies:** Ensures no visible alterations or artifacts are introduced to the overall tone and lighting of the image.
- **Avoiding High Frequencies:** Ensures the watermark data survives high-frequency filtering operations like JPEG compression, guaranteeing robustness.

### 3.3 Blind Extraction Technology

The extraction algorithm does not require the original image. By analyzing the magnitude relationships between specific frequency coefficients within 8 \times 8 pixel blocks, the app can reversely recover the hidden binary sequence from a seemingly untouched image.

### 3.4 Sync Markers & Redundancy

- **Sync Markers:** Specific bit sequences are embedded within the data stream to help the extraction algorithm realign the grid origin if the image suffers from translation attacks (e.g., cropping).
- **2D Tiling:** The watermark payload is redundantly tiled across the entire image. Even if the image is heavily cropped, the complete copyright information can still be extracted from the remaining valid fragments.

## 4. Technical Highlights

- **High-Performance Concurrency:** Utilizes Swift Concurrency (`async/await`) and `TaskGroup` to slice and process large images concurrently. This maximizes multi-core CPU performance and guarantees a responsive UI without blocking the main thread.
- **Low Overhead Optimization:** Calls the SIMD instruction sets of the Accelerate framework for matrix operations, significantly reducing computational overhead on mobile devices.
- **Loosely Coupled Architecture:** Adopts the MVVM design pattern to completely decouple complex mathematical transformation logic from the View layer, ensuring code extensibility, testability, and isolated collaboration via GitHub.
- **Adaptive UI Throttling & Backpressure:** Developed a highly resilient SwiftUI progress overlay to handle high-frequency, out-of-order progress notifications from the concurrent backend. It features dynamic queuing and adaptive animation pacing—automatically fast-forwarding when the event backlog grows—ensuring smooth 60fps rendering without freezing the main UI thread.
- **Strict Producer-Consumer Synchronization:** Implemented a robust "Drain ACK" handshake mechanism between the headless data-processing layer and the UI layer. This guarantees perfect synchronization during multi-file batch processing, forcing the backend to pace its workload until the UI gracefully completes its progress animations, entirely eliminating race conditions and event loss.

## 5. Tech Stack

- **Language:** Swift 5.9+
- **UI Framework:** SwiftUI
- **Image Processing:** Accelerate (vDSP / vImage), Core Image
- **Data Persistence:** SwiftData
- **Concurrency:** Swift Concurrency (Async/Await)
