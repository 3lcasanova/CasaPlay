// CasaPlay · Designed by 𝐂𝓪sΔηⓞשα

import SwiftUI
import CasaPlayKit

struct DetailView: View {
    @Environment(AppState.self) private var app
    let itemID: UUID

    var body: some View {
        if let item = app.item(id: itemID) {
            DetailContent(item: item)
        } else {
            ContentUnavailableView("Title not found", systemImage: "film")
        }
    }
}

private struct DetailContent: View {
    @Environment(AppState.self) private var app
    let item: MediaItem
    @State private var showingSubtitleSearch = false
    @State private var showingEpisodes = false

    var body: some View {
        let decision = app.router.decide(for: item.file)

        ScrollView {
            VStack(alignment: .leading, spacing: Metrics.sectionSpacing) {
                header
                actions(decision)

                if !item.overview.isEmpty {
                    Text(item.overview)
                        .font(.casa(15))
                        .foregroundStyle(Theme.textPrimary.opacity(0.9))
                        .padding(.horizontal, Metrics.screenPadding)
                        .focusableOnTV()
                }

                playbackPanel(decision)

                subtitlesPanel

                if !item.cast.isEmpty {
                    castRow
                }
            }
            .padding(.bottom, Metrics.sectionSpacing)
        }
        .background(Theme.background.ignoresSafeArea())
        #if !os(tvOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .sheet(isPresented: $showingSubtitleSearch) {
            SubtitleSearchView(item: item)
        }
        .sheet(isPresented: $showingEpisodes) {
            if item.tmdbShowID != nil {
                EpisodesView(show: item,
                             totalSeasons: episodeSeasonCount)
                    .environment(app)
            }
        }
        .task(id: item.id) {
            await app.refreshIMDb(for: item.id)
        }
    }

    // MARK: Header

    private var header: some View {
        ZStack(alignment: .bottomLeading) {
            ArtView(hue: item.artHue, cornerRadius: 0)
            LinearGradient(
                colors: [Color.clear, Theme.background],
                startPoint: .center,
                endPoint: .bottom
            )
            VStack(alignment: .leading, spacing: Metrics.s(8)) {
                Text(item.title)
                    .font(.casa(32, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                HStack(spacing: Metrics.s(12)) {
                    Text(item.metaLine)
                        .font(.casa(13))
                        .foregroundStyle(Theme.textSecondary)
                    if let rating = item.imdbRating {
                        IMDbBadge(rating: rating, votes: item.imdbVotes)
                    }
                }
                if !item.genres.isEmpty {
                    Text(item.genres.joined(separator: " · "))
                        .font(.casa(13))
                        .foregroundStyle(Theme.textSecondary)
                }
                HStack(spacing: Metrics.s(6)) {
                    ForEach(item.file.badges, id: \.self) { badge in
                        Pill(text: badge)
                    }
                }
            }
            .padding(Metrics.screenPadding)
        }
        .frame(height: Metrics.heroHeight)
        .clipped()
    }

    // MARK: Actions

    private func actions(_ decision: PlaybackDecision) -> some View {
        HStack(spacing: Metrics.s(10)) {
            Button {
                app.play(item)
            } label: {
                Label(
                    item.canResume ? "Resume · \(TimeFormat.clock(item.progressSeconds))" : "Play",
                    systemImage: "play.fill"
                )
                .foregroundStyle(Theme.onAccent)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!decision.isPlayable)

            if item.canResume {
                Button {
                    app.startOver(item.id)
                } label: {
                    Image(systemName: "arrow.counterclockwise")
                }
                .buttonStyle(.bordered)
                .disabled(!decision.isPlayable)
                .accessibilityLabel("Start over")
            }

            Button {
                app.toggleFavorite(item.id)
            } label: {
                Image(systemName: item.isFavorite ? "heart.fill" : "heart")
            }
            .buttonStyle(.bordered)
            .accessibilityLabel(item.isFavorite ? "Remove from favorites" : "Add to favorites")

            Button {
                app.toggleWatched(item.id)
            } label: {
                Image(systemName: item.isWatched ? "checkmark.circle.fill" : "checkmark.circle")
            }
            .buttonStyle(.bordered)
            .accessibilityLabel(item.isWatched ? "Mark as unwatched" : "Mark as watched")

            if item.tmdbShowID != nil {
                Button {
                    showingEpisodes = true
                } label: {
                    Label("Episodes", systemImage: "list.bullet")
                }
                .buttonStyle(.bordered)
            }

            #if !os(tvOS)
            if let url = item.imdbURL {
                Link(destination: url) {
                    Text("IMDb")
                        .font(.casa(13, weight: .heavy))
                }
                .buttonStyle(.bordered)
                .accessibilityLabel("Open on IMDb")
            }
            #endif
        }
        .padding(.horizontal, Metrics.screenPadding)
    }

    private var episodeSeasonCount: Int { item.numberOfSeasons ?? 1 }

    // MARK: How it plays

    private func playbackPanel(_ decision: PlaybackDecision) -> some View {
        VStack(alignment: .leading, spacing: Metrics.s(10)) {
            Text("How it plays")
                .font(.casa(19, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)

            HStack(spacing: Metrics.s(8)) {
                Image(systemName: decision.isPlayable ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    .foregroundStyle(decision.isPlayable ? Theme.accent : Color.orange)
                Text(decision.badgeText)
                    .font(.casa(14, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
            }

            ForEach(decision.reasons, id: \.self) { reason in
                Text("Apple's player can't open: \(reason)")
                    .font(.casa(12))
                    .foregroundStyle(Theme.textSecondary)
            }
            ForEach(decision.notes, id: \.self) { note in
                Text(note)
                    .font(.casa(12))
                    .foregroundStyle(Theme.textSecondary)
            }

            Divider().overlay(Theme.surfaceStrong)

            FactRow(label: "Container", value: item.file.container.displayName)
            FactRow(
                label: "Video",
                value: "\(item.file.videoCodec.displayName) · \(item.file.width)×\(item.file.height)"
            )
            FactRow(
                label: "Audio",
                value: item.file.audioCodecs.isEmpty
                    ? "None"
                    : item.file.audioCodecs.map { $0.displayName }.joined(separator: ", ")
            )
            FactRow(
                label: "Subtitles",
                value: item.file.subtitleFormats.isEmpty
                    ? "None"
                    : item.file.subtitleFormats.map { $0.rawValue.uppercased() }.joined(separator: ", ")
            )
            if let size = item.file.sizeBytes {
                FactRow(
                    label: "Size",
                    value: ByteCountFormatter.string(fromByteCount: size, countStyle: .file)
                )
            }
            if !item.sourceName.isEmpty {
                FactRow(label: "Source", value: item.sourceName)
            }
        }
        .padding(Metrics.s(16))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Metrics.cornerRadius, style: .continuous))
        .padding(.horizontal, Metrics.screenPadding)
        .focusableOnTV()
    }

    // MARK: Subtitles

    private var subtitlesPanel: some View {
        let options = app.subtitleOptions(for: item.id)
        let active = app.activeSubtitle(for: item.id)

        return VStack(alignment: .leading, spacing: Metrics.s(10)) {
            Text("Subtitles")
                .font(.casa(19, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Metrics.s(8)) {
                    ChipButton(title: "Off", isSelected: active == nil) {
                        app.selectSubtitle(nil, for: item.id)
                    }
                    ForEach(options) { option in
                        ChipButton(title: option.track.displayName, isSelected: active?.id == option.id) {
                            app.selectSubtitle(option.id, for: item.id)
                        }
                    }
                }
                .padding(.vertical, Platform.isTV ? 14 : 0)
            }

            Button {
                showingSubtitleSearch = true
            } label: {
                Label("Find subtitles online", systemImage: "magnifyingglass")
            }
            .buttonStyle(.bordered)

            Text(active.map { "\($0.track.displayName) · \($0.track.originLabel) · \($0.cues.count) lines. Style them in Profile › Subtitles & playback." }
                 ?? "Subtitles from files and OpenSubtitles appear here. Subtitles inside the video are in the player's own menu.")
                .font(.casa(12))
                .foregroundStyle(Theme.textSecondary)
                .focusableOnTV()
        }
        .padding(.horizontal, Metrics.screenPadding)
    }

    // MARK: Cast

    private var castRow: some View {
        Shelf(title: "Cast") {
            ForEach(Array(item.cast.enumerated()), id: \.element.id) { index, member in
                VStack(spacing: Metrics.s(6)) {
                    AvatarView(
                        text: member.initials,
                        hue: (item.artHue + Double(index) * 37).truncatingRemainder(dividingBy: 360),
                        size: Metrics.s(56)
                    )
                    Text(member.name)
                        .font(.casa(12, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                    Text(member.role)
                        .font(.casa(11))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }
                .frame(width: Metrics.s(84))
                .focusableOnTV()
            }
        }
    }
}

private struct FactRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label)
                .font(.casa(13))
                .foregroundStyle(Theme.textSecondary)
            Spacer(minLength: Metrics.s(12))
            Text(value)
                .font(.casa(13, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.trailing)
        }
    }
}
