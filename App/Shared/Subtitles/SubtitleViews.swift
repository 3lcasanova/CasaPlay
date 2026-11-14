// CasaPlay · Designed by 𝐂𝓪sΔηⓞשα
//
// Subtitles drawn by CasaPlay itself, so the viewer's size, colour, background,
// position and delay apply to any SRT or WebVTT file.

import SwiftUI
import CasaPlayKit

extension SubtitleStyle.TextColor {
    var color: Color {
        switch self {
        case .white: return .white
        case .yellow: return .yellow
        case .cyan: return .cyan
        }
    }
}

/// One subtitle block in the viewer's style. Used by the player and the Settings preview.
struct SubtitleText: View {
    let text: String
    let style: SubtitleStyle
    /// Font size before the style's size scale is applied.
    let baseSize: CGFloat

    var body: some View {
        Text(text)
            .font(.system(size: baseSize * style.size.scale, weight: .semibold))
            .foregroundStyle(style.textColor.color)
            .multilineTextAlignment(.center)
            .padding(.horizontal, baseSize * 0.5)
            .padding(.vertical, baseSize * 0.2)
            .background(
                style.background == .box ? Color.black.opacity(0.7) : Color.clear,
                in: RoundedRectangle(cornerRadius: baseSize * 0.25, style: .continuous)
            )
            .shadow(
                color: style.background == .softShadow ? Color.black.opacity(0.9) : Color.clear,
                radius: baseSize * 0.2
            )
            .shadow(
                color: style.background == .softShadow ? Color.black.opacity(0.6) : Color.clear,
                radius: 1
            )
    }
}

/// Playback time and cues for the overlay. The player updates `time` about ten times a second.
@Observable
final class SubtitleOverlayModel {
    var time: TimeInterval = 0
    var style: SubtitleStyle = .default
    private(set) var timeline = SubtitleTimeline(cues: [])
    private(set) var trackID: String?

    func setTrack(_ subtitle: LoadedSubtitle?) {
        guard subtitle?.id != trackID else { return }
        trackID = subtitle?.id
        timeline = SubtitleTimeline(cues: subtitle?.cues ?? [])
    }

    var currentText: String? {
        let cues = timeline.activeCues(at: time, delay: style.delay)
        guard !cues.isEmpty else { return nil }
        return cues.map(\.text).joined(separator: "\n")
    }
}

struct SubtitleOverlayView: View {
    let model: SubtitleOverlayModel

    var body: some View {
        GeometryReader { proxy in
            VStack {
                if model.style.position == .bottom { Spacer() }
                if let text = model.currentText {
                    SubtitleText(text: text, style: model.style, baseSize: max(proxy.size.height * 0.045, 14))
                        .frame(maxWidth: proxy.size.width * 0.86)
                        .transition(.opacity)
                }
                if model.style.position == .top { Spacer() }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, proxy.size.height * 0.08)
            .animation(.easeOut(duration: 0.12), value: model.currentText)
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Online search

/// Searches OpenSubtitles for a title and loads the chosen file into the player.
struct SubtitleSearchView: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    let item: MediaItem

    @State private var language: String = "en"
    @State private var results: [OnlineSubtitle] = []
    @State private var isSearching = false
    @State private var downloadingID: Int?
    @State private var message: String?
    @State private var nihonLanguage: NihonSubClient.Language = .english

    /// Streams started this session that belong to this title: the title itself, or one of its episodes.
    private var streamLinks: [StreamLink] {
        app.streamLinks.values
            .filter { link in
                guard let linked = app.item(id: link.itemID) else { return false }
                return linked.id == item.id || (linked.kind == .episode && linked.title.hasPrefix(item.title + " S"))
            }
            .sorted { $0.playedAt > $1.playedAt }
    }

    private var languages: [String] {
        var list = app.activeProfile.preferredSubtitleLanguages
        for extra in ["en", "fr", "es", "ht", "pt", "de", "it"] where !list.contains(extra) {
            list.append(extra)
        }
        return list
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Metrics.s(14)) {
                    OptionRow(
                        title: "Language",
                        options: languages,
                        label: { LanguageNames.displayName($0) },
                        selection: $language
                    )

                    Text(item.imdbID != nil
                         ? "Searching by IMDb ID \(item.imdbID ?? "")."
                         : "Searching by title and year. An IMDb ID gives more exact matches.")
                        .font(.casa(12))
                        .foregroundStyle(Theme.textSecondary)

                    if let message {
                        Text(message)
                            .font(.casa(13))
                            .foregroundStyle(Theme.textPrimary)
                            .padding(Metrics.s(12))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Metrics.cornerRadius))
                            .focusableOnTV()
                    }

                    if isSearching {
                        ProgressView().frame(maxWidth: .infinity).padding(.top, Metrics.s(20))
                    }

                    ForEach(results) { result in
                        Button {
                            Task { await download(result) }
                        } label: {
                            ResultRow(result: result, isDownloading: downloadingID == result.fileID)
                        }
                        .posterButtonStyle()
                        .disabled(downloadingID != nil)
                    }

                    nihonSubSection
                }
                .padding(Metrics.screenPadding)
            }
            .screenBackground()
            .scrollingScreenTitle("Find subtitles")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .task(id: language) { await search() }
        .onAppear {
            language = app.activeProfile.preferredSubtitleLanguages.first ?? "en"
        }
    }

    // MARK: NihonSub

    @ViewBuilder
    private var nihonSubSection: some View {
        VStack(alignment: .leading, spacing: Metrics.s(10)) {
            Text("Make subtitles with NihonSub")
                .font(.casa(15, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Text("When nobody has published subtitles, your Mac can listen to the video and write them. It takes a few minutes. You can close this screen; the subtitles switch on when they are ready.")
                .font(.casa(12))
                .foregroundStyle(Theme.textSecondary)

            if app.nihonSubClient == nil {
                note("Add your Mac's address and token in Profile › Online services › NihonSub.")
            } else if streamLinks.isEmpty {
                note("Start the stream first, then come back here. NihonSub needs the stream's link, and CasaPlay only keeps it until you quit the app.")
            } else {
                OptionRow(
                    title: "Subtitle language",
                    options: NihonSubClient.Language.allCases,
                    label: { $0.displayName },
                    selection: $nihonLanguage
                )
                ForEach(streamLinks) { link in
                    let status = app.nihonSubStatus[link.itemID]
                    Button {
                        app.generateSubtitles(link: link, language: nihonLanguage)
                    } label: {
                        NihonSubRow(
                            title: app.item(id: link.itemID)?.title ?? item.title,
                            canSend: link.canSendToMac,
                            isRunning: status?.isRunning == true,
                            progress: status?.progress
                        )
                    }
                    .posterButtonStyle()
                    .disabled(!link.canSendToMac || status?.isRunning == true)
                    if let failure = status?.failure { note(failure) }
                }
                if streamLinks.contains(where: { app.nihonSubStatus[$0.itemID]?.isRunning == true }) {
                    Button("Stop", role: .destructive) {
                        for link in streamLinks { app.cancelNihonSub(for: link.itemID) }
                    }
                    .buttonStyle(.bordered)
                }
            }
        }
        .padding(.top, Metrics.s(10))
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.casa(13))
            .foregroundStyle(Theme.textPrimary)
            .padding(Metrics.s(12))
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Metrics.cornerRadius))
            .focusableOnTV()
    }

    private func search() async {
        guard let client = app.openSubtitlesClient else {
            message = "Add your OpenSubtitles API key in Profile › Online services to search for subtitles."
            return
        }
        isSearching = true
        message = nil
        defer { isSearching = false }
        let query: OpenSubtitlesClient.Query = item.imdbID.map { .imdb($0) } ?? .title(item.title, year: item.year)
        do {
            results = try await client.search(query, languages: [language])
            if results.isEmpty { message = "No \(LanguageNames.displayName(language)) subtitles found." }
        } catch {
            results = []
            message = error.localizedDescription
        }
    }

    private func download(_ result: OnlineSubtitle) async {
        guard let client = app.openSubtitlesClient else { return }
        downloadingID = result.fileID
        defer { downloadingID = nil }
        do {
            let cues = try await client.download(result)
            app.addSubtitle(LoadedSubtitle(track: result.track, cues: cues), for: item.id)
            dismiss()
        } catch {
            message = error.localizedDescription
        }
    }
}

private struct NihonSubRow: View {
    let title: String
    let canSend: Bool
    let isRunning: Bool
    let progress: String?

    var body: some View {
        HStack(spacing: Metrics.s(12)) {
            Image(systemName: "waveform.badge.magnifyingglass")
                .font(.casa(18))
                .foregroundStyle(Theme.accent)
                .frame(width: Metrics.s(30))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.casa(14, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(2)
                Text(detail)
                    .font(.casa(12))
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer(minLength: Metrics.s(8))
            if isRunning {
                ProgressView()
            } else if canSend {
                Image(systemName: "sparkles")
                    .font(.casa(18))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(Metrics.s(12))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Metrics.cornerRadius, style: .continuous))
    }

    private var detail: String {
        if isRunning { return progress ?? "Working" }
        if !canSend { return "On-device torrent stream. Your Mac can't reach it. Pick a stream with a web link." }
        return "Generate subtitles on your Mac"
    }
}

private struct ResultRow: View {
    let result: OnlineSubtitle
    let isDownloading: Bool

    var body: some View {
        HStack(spacing: Metrics.s(12)) {
            Image(systemName: "captions.bubble")
                .font(.casa(18))
                .foregroundStyle(Theme.accent)
                .frame(width: Metrics.s(30))
            VStack(alignment: .leading, spacing: 2) {
                Text(result.release.isEmpty ? result.fileName : result.release)
                    .font(.casa(14, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(2)
                Text(details)
                    .font(.casa(12))
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer(minLength: Metrics.s(8))
            if isDownloading {
                ProgressView()
            } else {
                Image(systemName: "arrow.down.circle")
                    .font(.casa(18))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(Metrics.s(12))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Metrics.cornerRadius, style: .continuous))
    }

    private var details: String {
        var parts = [result.track.displayName, "\(result.downloadCount) downloads"]
        if result.isMachineTranslated { parts.append("machine translated") }
        if result.fromTrusted { parts.append("trusted") }
        return parts.joined(separator: " · ")
    }
}

#if !os(tvOS)
/// Subtitle-menu entries that start, follow or stop NihonSub for the title being played.
@ViewBuilder
func nihonSubMenuItems(app: AppState, item: MediaItem) -> some View {
    if app.nihonSubClient != nil {
        Divider()
        if let status = app.nihonSubStatus[item.id], status.isRunning {
            Button(role: .destructive) {
                app.cancelNihonSub(for: item.id)
            } label: {
                Label("Stop NihonSub · \(status.progress)", systemImage: "stop.circle")
            }
        } else if let link = app.streamLinks[item.id], link.canSendToMac {
            Section("Make subtitles with NihonSub") {
                ForEach(NihonSubClient.Language.allCases, id: \.self) { language in
                    Button {
                        app.generateSubtitles(link: link, language: language)
                    } label: {
                        Label(language.displayName, systemImage: "sparkles")
                    }
                }
            }
        } else {
            Button {} label: {
                Label("NihonSub needs a web link", systemImage: "waveform.badge.magnifyingglass")
            }
            .disabled(true)
        }
    }
}

/// A small badge in the player showing what NihonSub is doing for this title.
struct NihonSubStatusPill: View {
    @Environment(AppState.self) private var app
    let itemID: MediaItem.ID

    var body: some View {
        if let status = app.nihonSubStatus[itemID] {
            HStack(spacing: 6) {
                if status.isRunning {
                    ProgressView().controlSize(.mini).tint(.white)
                } else {
                    Image(systemName: status.failure == nil ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                }
                Text(status.failure ?? status.progress)
                    .lineLimit(2)
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(Color.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: 260, alignment: .leading)
            .playerPill()
            .onTapGesture {
                if !status.isRunning { app.clearNihonSubStatus(for: itemID) }
            }
            .task(id: status) {
                // A finished job's badge goes away on its own; a failure stays until tapped.
                guard !status.isRunning, status.failure == nil else { return }
                try? await Task.sleep(nanoseconds: 4_000_000_000)
                app.clearNihonSubStatus(for: itemID)
            }
        }
    }
}
#endif
