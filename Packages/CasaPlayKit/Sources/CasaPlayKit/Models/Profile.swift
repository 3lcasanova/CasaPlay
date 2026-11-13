// CasaPlay · Designed by 𝐂𝓪sΔηⓞשα

import Foundation

public struct Profile: Identifiable, Codable, Hashable, Sendable {
    public let id: UUID
    public var name: String
    /// Placeholder avatar colour (0...360).
    public var hue: Double
    public var isKids: Bool
    /// Subtitle languages in order of preference, as two-letter codes ("en", "fr", "ht").
    public var preferredSubtitleLanguages: [String]

    public init(
        id: UUID = UUID(),
        name: String,
        hue: Double,
        isKids: Bool = false,
        preferredSubtitleLanguages: [String] = ["en"]
    ) {
        self.id = id
        self.name = name
        self.hue = hue
        self.isKids = isKids
        self.preferredSubtitleLanguages = preferredSubtitleLanguages
    }

    public var glyph: String {
        String(name.prefix(1)).uppercased()
    }
}

public struct MediaSource: Identifiable, Codable, Hashable, Sendable {
    public enum Kind: String, Codable, Sendable {
        case mac, nas, plex, jellyfin, network
    }

    public enum Status: String, Codable, Sendable {
        case connected, scanning, notSetUp

        public var label: String {
            switch self {
            case .connected: return "Connected"
            case .scanning: return "Scanning"
            case .notSetUp: return "Set up"
            }
        }
    }

    public let id: UUID
    public var name: String
    public var detail: String
    public var kind: Kind
    public var status: Status

    public init(
        id: UUID = UUID(),
        name: String,
        detail: String,
        kind: Kind,
        status: Status
    ) {
        self.id = id
        self.name = name
        self.detail = detail
        self.kind = kind
        self.status = status
    }
}
