//
//  AdvancedCanvasVisualization.swift
//  PhantomStamp
//

import Foundation

enum AdvancedCanvasVisualization: Equatable {
    case smoothBlock(varianceThreshold: Float)
    case embedIntensity(varianceThreshold: Float, embeddingIntensity: Float)
}
