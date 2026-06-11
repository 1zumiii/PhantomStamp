//
//  AdvancedCanvasVisualization.swift
//  PhantomStamp
//

import Foundation

enum AdvancedCanvasVisualization: Equatable {
    case smoothBlock(varianceThreshold: Float)
    case varianceGain(curve: VarianceGainCurve)
    case embedIntensity(curve: VarianceGainCurve, embeddingIntensity: Float)
}
