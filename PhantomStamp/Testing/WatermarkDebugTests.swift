//
//  WatermarkDebugTests.swift
//  PhantomStamp
//
//  Single entry-point for all manual / DEBUG smoke tests.
//

import Foundation

enum WatermarkDebugTests {
    static func runAllAndPrint() {
        #if DEBUG
        do {
            let t0 = CFAbsoluteTimeGetCurrent()
            ImagePipelineTests.runAllBundledAndPrint()
            let dtMs = (CFAbsoluteTimeGetCurrent() - t0) * 1000
            print("[Timing] ImagePipelineTests.runAllBundledAndPrint took \(String(format: "%.2f", dtMs)) ms")
        }

        do {
            let t0 = CFAbsoluteTimeGetCurrent()
            DSPTransformsTests.runAllAndPrint()
            let dtMs = (CFAbsoluteTimeGetCurrent() - t0) * 1000
            print("[Timing] DSPTransformsTests.runAllAndPrint took \(String(format: "%.2f", dtMs)) ms")
        }

        do {
            let t0 = CFAbsoluteTimeGetCurrent()
            StripsTests.runAllAndPrint()
            let dtMs = (CFAbsoluteTimeGetCurrent() - t0) * 1000
            print("[Timing] StripsTests.runAllAndPrint took \(String(format: "%.2f", dtMs)) ms")
        }

        do {
            let t0 = CFAbsoluteTimeGetCurrent()
            GridAlignmentTests.runAllAndPrint()
            let dtMs = (CFAbsoluteTimeGetCurrent() - t0) * 1000
            print("[Timing] GridAlignmentTests.runAllAndPrint took \(String(format: "%.2f", dtMs)) ms")
        }

        do {
            let t0 = CFAbsoluteTimeGetCurrent()
            ExtractionAndVotingTests.runAllAndPrint()
            let dtMs = (CFAbsoluteTimeGetCurrent() - t0) * 1000
            print("[Timing] ExtractionAndVotingTests.runAllAndPrint took \(String(format: "%.2f", dtMs)) ms")
        }

        do {
            let t0 = CFAbsoluteTimeGetCurrent()
            DataProcessingTests.runAllAndPrint()
            let dtMs = (CFAbsoluteTimeGetCurrent() - t0) * 1000
            print("[Timing] DataProcessingTests.runAllAndPrint took \(String(format: "%.2f", dtMs)) ms")
        }
        #endif
    }
}

