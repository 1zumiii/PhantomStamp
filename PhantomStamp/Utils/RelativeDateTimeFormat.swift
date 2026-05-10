//
//  RelativeDateTimeFormat.swift
//  PhantomStamp
//

import Foundation

enum RelativeDateTimeFormat {
    /// Examples (en):
    /// - Today • 17:22
    /// - Yesterday • 17:22
    /// - May 15 • 17:22
    static func humanReadable(_ date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        let time = timeFormatter.string(from: date)
        if calendar.isDate(date, inSameDayAs: now) {
            return "Today • \(time)"
        }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(date, inSameDayAs: yesterday)
        {
            return "Yesterday • \(time)"
        }
        return "\(monthDayFormatter.string(from: date)) • \(time)"
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.dateFormat = "HH:mm"
        return f
    }()

    private static let monthDayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.calendar = Calendar(identifier: .gregorian)
        f.dateFormat = "MMM d"
        return f
    }()
}

