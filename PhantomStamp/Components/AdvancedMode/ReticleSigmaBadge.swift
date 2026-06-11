//
//  ReticleSigmaBadge.swift
//  PhantomStamp
//
//  HUD readout for the active 8×8 block population σ under the reticle.
//

import SwiftUI

/// Semi-transparent badge showing σ for the yellow-framed macroblock.
struct ReticleSigmaBadge: View, Equatable {
    let label: String

    var body: some View {
        Text(label)
            .font(.caption2.monospacedDigit().weight(.semibold))
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.black.opacity(0.58))
            }
            .allowsHitTesting(false)
            .accessibilityLabel("Block sigma \(label)")
    }
}
