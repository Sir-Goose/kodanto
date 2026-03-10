import Foundation

enum SessionRecencyFormatter {
    private static let minute: TimeInterval = 60
    private static let hour: TimeInterval = 60 * minute
    private static let day: TimeInterval = 24 * hour
    private static let week: TimeInterval = 7 * day
    private static let millisecondsThreshold = 10_000_000_000.0
    private static let futureTolerance: TimeInterval = 24 * hour

    static func string(since timestamp: Double, now: Date = .now) -> String {
        let elapsed = max(0, now.timeIntervalSince(normalizedDate(from: timestamp, now: now)))

        if elapsed < hour {
            return "\(Int(elapsed / minute))m"
        }

        if elapsed < day {
            return "\(Int(elapsed / hour))h"
        }

        if elapsed < week {
            return "\(Int(elapsed / day))d"
        }

        return "\(Int(elapsed / week))w"
    }

    private static func normalizedDate(from timestamp: Double, now: Date) -> Date {
        let seconds: Double
        if timestamp > millisecondsThreshold {
            seconds = timestamp / 1000
        } else {
            let secondsDate = Date(timeIntervalSince1970: timestamp)
            seconds = secondsDate <= now.addingTimeInterval(futureTolerance) ? timestamp : timestamp / 1000
        }

        return Date(timeIntervalSince1970: seconds)
    }
}
