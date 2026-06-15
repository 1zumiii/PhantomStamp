//
//  DataProcessingTests.swift
//  PhantomStamp
//
//  Lightweight validation helpers for DataProcessing (FEC / sync marker / 2D tile).
//  (This is not XCTest; it is intended for manual/DEBUG smoke checks.)
//

import Foundation

/// Manual / DEBUG-entry validation for:
/// - `encodeFEC(text:)`
/// - `decodeFEC(bits:)`
/// - `getSyncMarkerBits()`
/// - `build2DTile(from:)`
enum DataProcessingTests {

    struct Report: Sendable {
        var encodeRejectsOverLimitPassed: Bool
        var roundTripAsciiPassed: Bool
        var roundTripUtf8Passed: Bool
        var singleBitCorrectionPassed: Bool
        var doubleBitDetectionPassed: Bool
        var syncMarkerShapePassed: Bool
        var build2DTileDimsPassed: Bool
        var build2DTilePaddingPassed: Bool
        var variableLengthRoundTripsPassed: Bool
        var variableTilePeriodsPassed: Bool
        var asciiInputRulesPassed: Bool

        var encodedBitCount: Int
        var correctedSampleDecoded: String?
        var doubleErrorSampleDecoded: String?
        var tileSide: Int
        var tileBitCount: Int
    }

    /// Runs all validations and returns a metrics report.
    static func runAll() -> Report {
        // 1) Length cap: 16 bytes max (backend safety net).
        let overLimit = String(repeating: "A", count: 17)
        let overEncoded = encodeFEC(text: overLimit)
        let encodeRejectsOverLimitPassed = overEncoded.isEmpty

        // 2) Round-trip (ASCII).
        let msgAscii = "HELLO-123"
        let encAscii = encodeFEC(text: msgAscii)
        let decAscii = decodeFEC(bits: encAscii)
        let roundTripAsciiPassed = (decAscii == msgAscii)
            && decodeFEC(bits: encAscii, expectedMessageLengthBytes: msgAscii.utf8.count) == msgAscii
            && decodeFEC(bits: encAscii, expectedMessageLengthBytes: msgAscii.utf8.count + 1) == nil

        // 3) Round-trip (actual multibyte UTF-8). Four CJK characters = 12 UTF-8 bytes.
        let msgUtf8 = "水印测试"
        let encUtf8 = encodeFEC(text: msgUtf8)
        let decUtf8 = decodeFEC(bits: encUtf8)
        let roundTripUtf8Passed = (decUtf8 == msgUtf8)

        // 4) FEC single-bit correction (flip one bit and expect correct decode).
        // We flip a bit well after the header to avoid accidentally breaking the length field.
        var noisy = encAscii
        if noisy.count > 64 { noisy[64] ^= 1 }
        let corrected = decodeFEC(bits: noisy)
        let singleBitCorrectionPassed = (corrected == msgAscii)

        // 5) FEC double-bit detection (flip two bits in the same 8-bit codeword).
        // The interleaver uses a transpose mapping with `columns = 8`:
        //   out[c * rows + r] = in[r * columns + c]
        // To ensure two flips land in the same original codeword (same row `r`), we must flip
        // two indices with the same `r` and different `c` values in the interleaved stream.
        var doubleNoisy = encAscii
        if doubleNoisy.count >= 16 {
            let columns = 8
            let rows = doubleNoisy.count / columns
            // Avoid r=0 (first codeword likely includes length header bits). Use r=1 if possible.
            let r = min(1, max(0, rows - 1))
            let i0 = 0 * rows + r
            let i1 = 1 * rows + r
            if i1 < doubleNoisy.count {
                doubleNoisy[i0] ^= 1
                doubleNoisy[i1] ^= 1
            }
        }
        let doubleDecoded = decodeFEC(bits: doubleNoisy)
        let doubleBitDetectionPassed = (doubleDecoded == nil)

        // 6) Sync marker should be exactly 32 bits and binary.
        let sync = getSyncMarkerBits()
        let syncMarkerShapePassed = sync.count == 32 && sync.allSatisfy { $0 == 0 || $0 == 1 }

        // 7) build2DTile must set dimensions and pad to a square.
        let tileBits = Array(repeating: 1, count: 10)
        let tile = build2DTile(from: tileBits)
        let build2DTileDimsPassed = tile.bitsWide > 0 && tile.bitsHigh > 0 && tile.bitsWide == tile.bitsHigh
        let expectedSide = Int(ceil(sqrt(Double(tileBits.count))))
        let build2DTilePaddingPassed = tile.bits.count == expectedSide * expectedSide

        // 8) Payloads remain variable-length. The length header lets extraction recover each
        // exact message without padding every payload to 16 bytes.
        let variableCases: [(text: String, expectedTileSide: Int)] = [
            ("12345678", 14),
            ("Successful", 15),
            ("DesignedByOrion", 17),
            ("1234567890123456", 18)
        ]
        let variableLengthRoundTripsPassed = variableCases.allSatisfy { testCase in
            let encoded = encodeFEC(text: testCase.text)
            return decodeFEC(bits: encoded) == testCase.text
                && decodeFEC(
                    bits: encoded,
                    expectedMessageLengthBytes: testCase.text.utf8.count
                ) == testCase.text
        }
        let variableTilePeriodsPassed = variableCases.allSatisfy { testCase in
            let encoded = encodeFEC(text: testCase.text)
            let payloadTile = build2DTile(from: getSyncMarkerBits() + encoded)
            return payloadTile.bitsWide == testCase.expectedTileSide
                && payloadTile.bitsHigh == testCase.expectedTileSide
        }

        // 9) The low-level codec remains UTF-8 capable, while product entry points expose a
        // deterministic ASCII identifier alphabet.
        let exactBudget = "Abcd1234._-@WXYZ"
        let sanitized = WatermarkPayloadLimits.sanitizingUserInput(
            "水印 Abcd1234._-@WXYZ!"
        )
        let asciiInputRulesPassed =
            WatermarkPayloadLimits.utf8ByteCount(of: msgUtf8) == 12
            && WatermarkPayloadLimits.isValidUserPayload(exactBudget)
            && !WatermarkPayloadLimits.isValidUserPayload(msgUtf8)
            && !WatermarkPayloadLimits.isValidUserPayload("Contains Space")
            && sanitized == exactBudget
            && sanitized.count == WatermarkPayloadLimits.maximumCharacterCount

        return Report(
            encodeRejectsOverLimitPassed: encodeRejectsOverLimitPassed,
            roundTripAsciiPassed: roundTripAsciiPassed,
            roundTripUtf8Passed: roundTripUtf8Passed,
            singleBitCorrectionPassed: singleBitCorrectionPassed,
            doubleBitDetectionPassed: doubleBitDetectionPassed,
            syncMarkerShapePassed: syncMarkerShapePassed,
            build2DTileDimsPassed: build2DTileDimsPassed,
            build2DTilePaddingPassed: build2DTilePaddingPassed,
            variableLengthRoundTripsPassed: variableLengthRoundTripsPassed,
            variableTilePeriodsPassed: variableTilePeriodsPassed,
            asciiInputRulesPassed: asciiInputRulesPassed,
            encodedBitCount: encAscii.count,
            correctedSampleDecoded: corrected,
            doubleErrorSampleDecoded: doubleDecoded,
            tileSide: tile.bitsWide,
            tileBitCount: tile.bits.count
        )
    }

    /// Runs all validations and prints a single summary line (DEBUG only).
    static func runAllAndPrint() {
        #if DEBUG
        let r = runAll()
        let passed =
            r.encodeRejectsOverLimitPassed
            && r.roundTripAsciiPassed
            && r.roundTripUtf8Passed
            && r.singleBitCorrectionPassed
            && r.doubleBitDetectionPassed
            && r.syncMarkerShapePassed
            && r.build2DTileDimsPassed
            && r.build2DTilePaddingPassed
            && r.variableLengthRoundTripsPassed
            && r.variableTilePeriodsPassed
            && r.asciiInputRulesPassed

        let status = passed ? "PASS" : "FAIL"
        print("[DataProcessingTests] \(status) Data / FEC / Tile")
        print("  - overLimit (17B rejected): \(r.encodeRejectsOverLimitPassed ? "PASS" : "FAIL")")
        print("  - roundTrip ASCII:          \(r.roundTripAsciiPassed ? "PASS" : "FAIL")")
        print("  - roundTrip UTF-8:          \(r.roundTripUtf8Passed ? "PASS" : "FAIL")")
        print("  - FEC single-bit correct:   \(r.singleBitCorrectionPassed ? "PASS" : "FAIL")")
        print("  - FEC double-bit detect:    \(r.doubleBitDetectionPassed ? "PASS" : "FAIL")")
        print("  - sync marker shape (32b):  \(r.syncMarkerShapePassed ? "PASS" : "FAIL")")
        print("  - build2DTile dims square:  \(r.build2DTileDimsPassed ? "PASS" : "FAIL")")
        print("  - build2DTile padding:      \(r.build2DTilePaddingPassed ? "PASS" : "FAIL")")
        print("  - variable-length decode:   \(r.variableLengthRoundTripsPassed ? "PASS" : "FAIL")")
        print("  - variable tile periods:    \(r.variableTilePeriodsPassed ? "PASS" : "FAIL")")
        print("  - ASCII input rules:        \(r.asciiInputRulesPassed ? "PASS" : "FAIL")")
        print("  - metrics: encBits=\(r.encodedBitCount) tile=\(r.tileSide)x\(r.tileSide) tileBits=\(r.tileBitCount)")
        #endif
    }
}
