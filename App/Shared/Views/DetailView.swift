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
                Text(item.metaLine)
                    .font(.casa(13))
                    .foregroundStyle(Theme.textSecondary)
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
        }
        .padding(.horizontal, Metrics.screenPadding)
    }

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
