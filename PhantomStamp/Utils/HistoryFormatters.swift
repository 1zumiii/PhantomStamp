// Utils/HistoryFormatters.swift
// PhantomStamp
//
// Pure formatting helpers for the History module.
// All methods are static and stateless — calling them with the same input
// always returns the same output (idempotent). No side effects.

import Foundation

// MARK: - HistoryFormatters

enum HistoryFormatters {

    private static let calendar = Calendar.current

    // MARK: Section header

    /// Returns an uppercase section heading for a grouped list.
    /// Examples: "TODAY", "YESTERDAY", "MAY 5"
    static func sectionHeader(for date: Date) -> String {
        if calendar.isDateInToday(date)     { return "TODAY" }
        if calendar.isDateInYesterday(date) { return "YESTERDAY" }

        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date).uppercased()
    }

    // MARK: Relative time string

    /// Returns a short relative label shown on each history card.
    /// Examples: "Just now", "2m ago", "18m ago", "3h ago", "Yesterday", "May 5"
    static func relativeTimeString(for date: Date) -> String {
        let now     = Date()
        let seconds = Int(now.timeIntervalSince(date))
        let minutes = seconds / 60
        let hours   = minutes / 60

        if seconds < 60  { return "Just now" }
        if minutes < 60  { return "\(minutes)m ago" }
        if hours   < 24  { return "\(hours)h ago" }

        if calendar.isDateInYesterday(date) { return "Yesterday" }

        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }

    // MARK: Detail date string

    /// Returns a formatted date string for the History Detail screen.
    /// Examples: "Today · 2:40 PM", "Yesterday · 9:15 AM", "May 5 · 11:30 AM"
    static func detailDateString(for date: Date) -> String {
        let dayLabel: String

        if calendar.isDateInToday(date) {
            dayLabel = "Today"
        } else if calendar.isDateInYesterday(date) {
            dayLabel = "Yesterday"
        } else {
            let dayFormatter = DateFormatter()
            dayFormatter.dateFormat = "MMM d"
            dayLabel = dayFormatter.string(from: date)
        }

        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "h:mm a"
        let timeLabel = timeFormatter.string(from: date)

        return "\(dayLabel) · \(timeLabel)"
    }

    // MARK: Image size

    /// Returns a formatted image dimension string.
    /// Example: "3024 × 4032"
    static func imageSize(width: Int, height: Int) -> String {
        "\(width) × \(height)"
    }

    // MARK: Processing duration

    /// Returns a human-readable processing time from a millisecond value.
    /// Examples: "430ms", "1.2s", "3.0s"
    static func processingDuration(ms: Double) -> String {
        if ms < 1000 {
            return String(format: "%.0fms", ms)
        }
        return String(format: "%.1fs", ms / 1000)
    }

    // MARK: Embed parameters

    /// Converts stored physical variance (σ²) to UI σ (gray-level standard deviation).
    static func textureSigma(fromVarianceThreshold variance: Double) -> Double? {
        guard variance >= 0 else { return nil }
        return sqrt(variance)
    }

    /// Display label for smooth-block threshold, e.g. `σ: 6.0`.
    static func formatTextureSigma(fromVarianceThreshold variance: Double?) -> String? {
        guard let variance else { return nil }
        if variance < 0 { return "σ: all" }
        guard let sigma = textureSigma(fromVarianceThreshold: variance) else { return nil }
        return String(format: "σ: %.1f", sigma)
    }

    /// Display label for global embed intensity, e.g. `5.5×`.
    static func formatEmbeddingStrength(_ strength: Double?) -> String? {
        guard let strength else { return nil }
        let normalized = AppConstants.normalizedEmbeddingStrength(strength)
        return String(format: "%.1f×", normalized)
    }

    /// Compact embed settings line for history list cards, e.g. `σ: 6.0 · 5.5×`.
    static func embedSettingsSummary(
        varianceThreshold: Double?,
        embeddingStrength: Double?
    ) -> String? {
        var parts: [String] = []
        if let sigma = formatTextureSigma(fromVarianceThreshold: varianceThreshold) {
            parts.append(sigma)
        }
        if let intensity = formatEmbeddingStrength(embeddingStrength) {
            parts.append(intensity)
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    // MARK: Extract parameters

    /// Deskew rotation for display, e.g. `+3.2°`.
    static func formatDeskewAngle(degrees: Double?) -> String? {
        guard let degrees else { return nil }
        return String(format: "%+.2f°", degrees)
    }

    /// Deskew scale for display, e.g. `1.045×`.
    static func formatDeskewScale(_ scale: Double?) -> String? {
        guard let scale else { return nil }
        return String(format: "%.3f×", scale)
    }

    /// Whether detected transform is effectively identity (deskew skipped).
    static func deskewWasApplied(angleDegrees: Double?, scale: Double?) -> Bool {
        guard let angleDegrees, let scale else { return false }
        let angleRad = angleDegrees * .pi / 180.0
        return abs(angleRad) >= 5e-3 || abs(scale - 1.0) >= 5e-4
    }

}
