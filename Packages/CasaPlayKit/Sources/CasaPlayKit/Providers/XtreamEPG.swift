// CasaPlay · Designed by 𝐂𝓪sΔηⓞשα
//
// The program guide of an Xtream Codes channel: what is on now and what comes next. The server sends the
// titles and descriptions base64-encoded. Everything is read as plain text and never executed.

import Foundation

public struct EPGProgram: Identifiable, Equatable, Sendable {
    public let id: String
    public let title: String
    public let detail: String
    public let start: Date
    public let end: Date

    public init(id: String, title: String, detail: String, start: Date, end: Date) {
        self.id = id
        self.title = title
        self.detail = detail
        self.start = start
        self.end = end
    }

    public func isOn(at date: Date) -> Bool { start <= date && date < end }

    /// 0 to 1: how far through the program the date is.
    public func progress(at date: Date) -> Double {
        let length = end.timeIntervalSince(start)
        guard length > 0 else { return 0 }
        return min(max(date.timeIntervalSince(start) / length, 0), 1)
    }
}

public struct NowNext: Equatable, Sendable {
    public let now: EPGProgram?
    public let next: EPGProgram?

    public init(now: EPGProgram?, next: EPGProgram?) {
        self.now = now
        self.next = next
    }
}

public enum XtreamEPG {
    /// Reads the answer to `get_short_epg`. Programs without a title or with unreadable times are skipped.
    public static func parse(_ json: Any) -> [EPGProgram] {
        guard let dict = json as? [String: Any], let list = dict["epg_listings"] as? [[String: Any]] else { return [] }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"

        var programs: [EPGProgram] = []
        for item in list {
            guard let title = text(item["title"]), !title.isEmpty,
                  let start = time(item["start_timestamp"], fallback: item["start"], formatter: formatter),
                  let end = time(item["stop_timestamp"], fallback: item["end"], formatter: formatter),
                  end > start else { continue }
            let id = "\(raw(item["id"]) ?? title)@\(Int(start.timeIntervalSince1970))"
            programs.append(EPGProgram(id: id, title: title, detail: text(item["description"]) ?? "",
                                       start: start, end: end))
        }
        return programs.sorted { $0.start < $1.start }
    }

    /// The program on at `date`, and the one after it.
    public static func nowNext(_ programs: [EPGProgram], at date: Date) -> NowNext {
        let sorted = programs.sorted { $0.start < $1.start }
        let now = sorted.first { $0.isOn(at: date) }
        let next = sorted.first { $0.start >= (now?.end ?? date) && $0.start > date }
        return NowNext(now: now, next: next)
    }

    // MARK: Helpers

    private static func raw(_ value: Any?) -> String? {
        if let s = value as? String { return s.isEmpty ? nil : s }
        if let n = value as? NSNumber { return n.stringValue }
        return nil
    }

    /// Titles come base64-encoded; plain text is accepted too.
    static func text(_ value: Any?) -> String? {
        guard let s = raw(value) else { return nil }
        var padded = s.trimmingCharacters(in: .whitespacesAndNewlines)
        while padded.count % 4 != 0 { padded += "=" }
        if let data = Data(base64Encoded: padded), let decoded = String(data: data, encoding: .utf8),
           !decoded.isEmpty, !decoded.contains("\u{FFFD}") {
            return decoded.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return s.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func time(_ stamp: Any?, fallback: Any?, formatter: DateFormatter) -> Date? {
        if let s = raw(stamp), let seconds = TimeInterval(s), seconds > 0 {
            return Date(timeIntervalSince1970: seconds)
        }
        if let s = raw(fallback) { return formatter.date(from: s) }
        return nil
    }
}

extension XtreamProvider {
    /// What is on a live channel now and next. `channelID` is the "xtream:<stream id>" the channel list uses.
    public func nowNext(for channelID: String, at date: Date = Date()) async throws -> NowNext {
        guard channelID.hasPrefix(XtreamLive.sourcePrefix) else { return NowNext(now: nil, next: nil) }
        let streamID = String(channelID.dropFirst(XtreamLive.sourcePrefix.count))
        let json = try await api(action: "get_short_epg", extra: ["stream_id": streamID, "limit": "6"])
        return XtreamEPG.nowNext(XtreamEPG.parse(json), at: date)
    }
}
