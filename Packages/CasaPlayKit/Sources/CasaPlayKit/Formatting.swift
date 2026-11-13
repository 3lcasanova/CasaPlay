// CasaPlay · Designed by 𝐂𝓪sΔηⓞשα

import Foundation

public enum TimeFormat {
    /// 4328 -> "1:12:08", 65 -> "1:05"
    public static func clock(_ seconds: TimeInterval) -> String {
        let total = max(Int(seconds.rounded(.down)), 0)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        }
        return String(format: "%d:%02d", minutes, secs)
    }

    /// 7440 -> "2h 04m", 2700 -> "45m"
    public static func runtime(_ seconds: TimeInterval) -> String {
        let totalMinutes = max(Int((seconds / 60).rounded()), 0)
        let hours = totalMinutes / 60
        let minutes = totalMinutes % 60
        if hours > 0 {
            return String(format: "%dh %02dm", hours, minutes)
        }
        return "\(minutes)m"
    }

    /// 3112 -> "52 min left", 3900 -> "1h 05m left"
    public static func timeLeft(_ seconds: TimeInterval) -> String {
        let totalMinutes = max(Int((seconds / 60).rounded(.up)), 0)
        if totalMinutes >= 60 {
            return String(format: "%dh %02dm left", totalMinutes / 60, totalMinutes % 60)
        }
        return "\(totalMinutes) min left"
    }

    /// 3723.5 -> "01:02:03.500" (WebVTT timestamp)
    public static func vtt(_ seconds: TimeInterval) -> String {
        let totalMillis = max(Int((seconds * 1000).rounded()), 0)
        let hours = totalMillis / 3_600_000
        let minutes = (totalMillis % 3_600_000) / 60_000
        let secs = (totalMillis % 60_000) / 1000
        let millis = totalMillis % 1000
        return String(format: "%02d:%02d:%02d.%03d", hours, minutes, secs, millis)
    }
}
