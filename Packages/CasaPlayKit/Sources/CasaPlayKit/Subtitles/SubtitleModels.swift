// CasaPlay · Designed by 𝐂𝓪sΔηⓞשα

import Foundation

public struct SubtitleCue: Equatable, Hashable, Sendable {
    public var start: TimeInterval
    public var end: TimeInterval
    public var text: String

    public init(start: TimeInterval, end: TimeInterval, text: String) {
        self.start = start
        self.end = end
        self.text = text
    }
}

public struct SubtitleTrack: Identifiable, Hashable, Sendable {
    public enum Origin: String, Sendable {
        case embedded, sidecar, online
    }

    public let id: String
    /// Language code such as "en", "fr-CA" or "ht".
    public var languageCode: String
    public var displayName: String
    public var origin: Origin
    public var format: SubtitleFormat
    public var isSDH: Bool
    public var isForced: Bool

    public init(
        id: String,
        languageCode: String,
        displayName: String,
        origin: Origin,
        format: SubtitleFormat,
        isSDH: Bool = false,
        isForced: Bool = false
    ) {
        self.id = id
        self.languageCode = languageCode
        self.displayName = displayName
        self.origin = origin
        self.format = format
        self.isSDH = isSDH
        self.isForced = isForced
    }

    /// "Embedded", "File · .srt" or "Online", as shown in the track list.
    public var originLabel: String {
        switch origin {
        case .embedded: return "Embedded"
        case .sidecar: return "File · .\(format.rawValue)"
        case .online: return "Online"
        }
    }
}

public struct SubtitleStyle: Codable, Hashable, Sendable {
    public enum Size: String, Codable, CaseIterable, Sendable {
        case small, medium, large, extraLarge

        public var scale: Double {
            switch self {
            case .small: return 0.8
            case .medium: return 1.0
            case .large: return 1.25
            case .extraLarge: return 1.5
            }
        }

        public var label: String {
            switch self {
            case .small: return "Small"
            case .medium: return "Medium"
            case .large: return "Large"
            case .extraLarge: return "Extra Large"
            }
        }
    }

    public enum TextColor: String, Codable, CaseIterable, Sendable {
        case white, yellow, cyan

        public var label: String {
            switch self {
            case .white: return "White"
            case .yellow: return "Yellow"
            case .cyan: return "Cyan"
            }
        }
    }

    public enum Background: String, Codable, CaseIterable, Sendable {
        case none, softShadow, box

        public var label: String {
            switch self {
            case .none: return "None"
            case .softShadow: return "Soft shadow"
            case .box: return "Box"
            }
        }
    }

    public enum Position: String, Codable, CaseIterable, Sendable {
        case bottom, top

        public var label: String {
            switch self {
            case .bottom: return "Bottom"
            case .top: return "Top"
            }
        }
    }

    public var size: Size
    public var textColor: TextColor
    public var background: Background
    public var position: Position
    /// Seconds. Positive values show subtitles later, negative earlier.
    public var delay: TimeInterval

    public init(
        size: Size = .large,
        textColor: TextColor = .white,
        background: Background = .softShadow,
        position: Position = .bottom,
        delay: TimeInterval = 0
    ) {
        self.size = size
        self.textColor = textColor
        self.background = background
        self.position = position
        self.delay = delay
    }

    public static let `default` = SubtitleStyle()
}

/// Finds which cues are on screen at a given playback time.
/// Used by the custom overlay renderer (ASS styling and delay) planned for Phase 3.
public struct SubtitleTimeline: Sendable {
    public let cues: [SubtitleCue]

    public init(cues: [SubtitleCue]) {
        self.cues = cues.sorted { $0.start < $1.start }
    }

    public func activeCues(at time: TimeInterval, delay: TimeInterval = 0) -> [SubtitleCue] {
        let adjusted = time - delay
        return cues.filter { $0.start <= adjusted && adjusted < $0.end }
    }
}
