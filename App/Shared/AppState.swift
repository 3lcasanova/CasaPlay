// CasaPlay · Designed by 𝐂𝓪sΔηⓞשα

import SwiftUI
import CasaPlayKit

enum AppSection: String, CaseIterable, Identifiable {
    case home, movies, favorites, sources, profile

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: return "Home"
        case .movies: return "Movies"
        case .favorites: return "Favorites"
        case .sources: return "Sources"
        case .profile: return "Profile"
        }
    }

    var systemImage: String {
        switch self {
        case .home: return "house"
        case .movies: return "film"
        case .favorites: return "heart"
        case .sources: return "externaldrive"
        case .profile: return "person.crop.circle"
        }
    }
}

/// One shared, in-memory store for the whole app.
/// Phase 2 replaces `items` with a SwiftData library fed by real sources.
/// Watch progress is shared between profiles until Phase 5 splits it per profile.
@Observable
final class AppState {
    var items: [MediaItem] = SampleData.movies
    var profiles: [Profile] = SampleData.profiles
    var sources: [MediaSource] = SampleData.sources
    var activeProfileID: UUID = SampleData.profiles[0].id
    var subtitleStyle = SubtitleStyle.default
    var selectedSection: AppSection = .home
    var playing: MediaItem?
    var router = PlaybackRouter()

    var activeProfile: Profile {
        profiles.first { $0.id == activeProfileID } ?? profiles[0]
    }

    /// What the active profile is allowed to see. The Kids profile only shows G and PG.
    var library: [MediaItem] {
        guard activeProfile.isKids else { return items }
        return items.filter { ["G", "PG"].contains($0.rating ?? "") }
    }

    var continueWatching: [MediaItem] {
        library
            .filter { $0.canResume }
            .sorted { ($0.lastPlayedAt ?? .distantPast) > ($1.lastPlayedAt ?? .distantPast) }
    }

    var recentlyAdded: [MediaItem] {
        library.sorted { $0.addedAt > $1.addedAt }
    }

    var favorites: [MediaItem] {
        library.filter { $0.isFavorite }
    }

    var featured: MediaItem? {
        continueWatching.first ?? library.first
    }

    func item(id: MediaItem.ID) -> MediaItem? {
        items.first { $0.id == id }
    }

    func play(_ item: MediaItem) {
        playing = items.first { $0.id == item.id } ?? item
    }

    func startOver(_ id: MediaItem.ID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].progressSeconds = 0
        items[index].isWatched = false
        playing = items[index]
    }

    func toggleFavorite(_ id: MediaItem.ID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].isFavorite.toggle()
    }

    func toggleWatched(_ id: MediaItem.ID) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].isWatched.toggle()
        if items[index].isWatched {
            items[index].progressSeconds = 0
        }
    }

    func updateProgress(id: MediaItem.ID, seconds: TimeInterval) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].progressSeconds = seconds
        items[index].lastPlayedAt = Date()
        if items[index].progressFraction >= 0.95 {
            items[index].isWatched = true
        }
    }
}
