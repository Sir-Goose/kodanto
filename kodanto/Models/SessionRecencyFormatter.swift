import Foundation

enum SessionRecencyFormatter {
    private static let minute: TimeInterval = 60
    private static let hour: TimeInterval = 60 * minute
    private static let day: TimeInterval = 24 * hour
    private static let week: TimeInterval = 7 * day
    private static let year: TimeInterval = 52 * week
    private static let millisecondsThreshold = 10_000_000_000.0
    private static let futureTolerance: TimeInterval = 24 * hour
    private static let maxDisplayYears = 99

    static let maxLayoutToken = "\(maxDisplayYears)y+"

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

        if elapsed < year {
            return "\(Int(elapsed / week))w"
        }

        let years = Int(elapsed / year)
        if years > maxDisplayYears {
            return maxLayoutToken
        }

        return "\(max(1, years))y"
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
