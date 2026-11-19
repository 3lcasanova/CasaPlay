// CasaPlay · Designed by 𝐂𝓪sΔηⓞשα
//
// Source picker that runs the aggregator and shows verified / advertised quality badges.

import SwiftUI
import CasaPlayKit

struct StreamSourcesView: View {
    let request: ContentRequest
    var libraryItemID: UUID? = nil
    /// True when the viewer pressed Resume: the stream the title was last played from starts by itself, and the
    /// list only shows if that stream can't be found.
    var resumeLastStream = false
    /// The next episode after one ends: once the search finishes, the best stream plays without anyone choosing.
    var autoPlayBest = false
    @State private var didAutoPlay = false
    @Environment(ExtensionCenter.self) private var center
    @Environment(AppState.self) private var app
    @Environment(TorrentCenter.self) private var torrents
    @Environment(ServerCenter.self) private var servers
    @Environment(\.dismiss) private var dismiss

    @State private var results = SourceResults()
    @State private var showQualityPicker = false
    /// Bumped by the refresh button to search again.
    @State private var refreshCount = 0
    /// The source chip that is on: only streams from that add-on are listed. Nil lists every source.
    @State private var sourceFilter: String?
    @State private var isAddingTorrent = false
    @State private var addTorrentError: String?
    /// The torrent whose file list is open, pushed inside this screen's own navigation.
    @State private var openedTorrent: InfoHash?
    /// Looking for the last stream so Resume can play it without the list.
    @State private var resuming = false
    /// The last stream wasn't there this time; the list is shown instead.
    @State private var resumeMissed = false
    @State private var resumeChecked = false

    var body: some View {
        NavigationStack {
            GeometryReader { geometry in
                let wide = geometry.size.width >= 700
                ZStack {
                    backdrop
                    if wide {
                        // Apple TV and iPad: the title on the left, the streams on a glass panel on the right.
                        HStack(spacing: 0) {
                            heroColumn(compact: false)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                            panel
                                .frame(width: geometry.size.width * 0.57)
                                .padding(.trailing, Platform.isTV ? 60 : 24)
                                .padding(.vertical, Platform.isTV ? 70 : 20)
                        }
                    } else {
                        VStack(spacing: 10) {
                            heroColumn(compact: true)
                            panel
                                .padding(.horizontal, 12)
                                .padding(.bottom, 8)
                        }
                    }
                }
            }
            .background(Color.black.ignoresSafeArea())
            .scrollingScreenTitle("Choose Stream")
            .navigationDestination(item: $openedTorrent) { hash in
                TorrentDetailView(hash: hash, libraryItemID: libraryItemID)
            }
            #if !os(tvOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            #endif
        }
        .confirmationDialog("Stream Quality", isPresented: $showQualityPicker) {
            ForEach(QualityMode.menuOrder, id: \.shortLabel) { mode in
                Button(mode.shortLabel) { center.setQualityMode(mode) }
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Couldn't add torrent", isPresented: .constant(addTorrentError != nil), actions: {
            Button("OK") { addTorrentError = nil }
        }, message: { Text(addTorrentError ?? "") })
        .task(id: RunKey(mode: center.qualityMode, refresh: refreshCount)) { [mode = center.qualityMode] in
            await runAggregator(mode: mode)
        }
        // The player is presented from the app's root, which can't happen while this sheet is up.
        .onChange(of: app.playing?.id) { _, playingID in
            if playingID != nil { dismiss() }
        }
        .overlay {
            if isAddingTorrent {
                VStack(spacing: Metrics.s(10)) {
                    ProgressView()
                    Text("Adding torrent…")
                        .font(.casa(13))
                        .foregroundStyle(Theme.textSecondary)
                }
                .padding(Metrics.s(24))
                .background(Theme.surface, in: RoundedRectangle(cornerRadius: 16))
            }
        }
    }

    // MARK: - Hero look

    /// The film or show this is for, when the library knows it: its pictures, genres and logo.
    private var art: MediaItem? {
        if let libraryItemID, let own = app.item(id: libraryItemID), own.kind != .episode { return own }
        let parent = libraryItemID.flatMap { app.item(id: $0) }?.parentIMDbID ?? request.id
        return app.items.first { $0.imdbID == parent }
    }

    private var logoID: Int? { art?.tmdbShowID ?? art?.tmdbMovieID }

    private var heroMeta: String {
        var parts: [String] = []
        if request.kind == .episode, let season = request.season, let episode = request.episode {
            parts.append("Season \(season) · Episode \(episode)")
        }
        parts += (art?.genres ?? []).prefix(3)
        if let year = art?.year ?? request.year { parts.append(String(year)) }
        return parts.joined(separator: " • ")
    }

    /// The artwork, dimmed so the glass panel and the words stay readable.
    private var backdrop: some View {
        ZStack {
            BackdropImage(path: art?.backdropPath ?? art?.posterPath, hue: art?.artHue ?? 30,
                          fullSize: Platform.isTV, alignment: .top)
            Color.black.opacity(0.66)
            LinearGradient(colors: [Color.clear, Color.black.opacity(0.5)], startPoint: .top, endPoint: .bottom)
        }
        .ignoresSafeArea()
    }

    private func heroColumn(compact: Bool) -> some View {
        VStack(spacing: compact ? 6 : 22) {
            TitleLogo(title: request.title, tmdbID: logoID, isShow: art?.tmdbShowID != nil,
                      logoWidth: compact ? 220 : 460, logoHeight: compact ? 64 : 190,
                      alignment: .center, plainSize: compact ? 30 : 64)
            if !heroMeta.isEmpty {
                Text(heroMeta)
                    .font(.system(size: compact ? 13 : 28, weight: .semibold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
            }
        }
        .padding(.horizontal, compact ? 16 : 50)
        .padding(.top, compact ? 4 : 0)
        .frame(maxWidth: .infinity)
    }

    /// The glass panel: source chips on top, then the streams.
    private var panel: some View {
        VStack(spacing: 0) {
            if resuming {
                resumingView
            } else {
                if resumeMissed { resumeMissedNote }
                chipsRow
                // With "Where to watch" entries the scrolling list is used, so a long list of services fits.
                if results.ranked.isEmpty && results.finished && results.whereToWatch.isEmpty && results.infoNotes.isEmpty {
                    emptyView
                } else {
                    streamList
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.ultraThinMaterial,
                    in: RoundedRectangle(cornerRadius: Platform.isTV ? 44 : 26, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Platform.isTV ? 44 : 26, style: .continuous)
                .strokeBorder(Color.white.opacity(0.14), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Platform.isTV ? 44 : 26, style: .continuous))
    }

    /// Shown while the last stream is looked up. Choosing another stream drops back to the list.
    private var resumingView: some View {
        VStack(spacing: Metrics.s(16)) {
            ProgressView().tint(Theme.accent)
            Text("Resuming where you left off")
                .font(.casa(17, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Text("Finding the stream you were watching…")
                .font(.casa(13))
                .foregroundStyle(Theme.textSecondary)
            Button {
                resuming = false
            } label: {
                Text("Choose another stream")
            }
            .buttonStyle(StreamChipStyle(selected: false))
            .padding(.top, Metrics.s(8))
        }
        .multilineTextAlignment(.center)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Metrics.s(24))
    }

    private var resumeMissedNote: some View {
        Text("Your last stream wasn't available this time. Choose another.")
            .font(.casa(12))
            .foregroundStyle(Theme.textSecondary)
            .padding(.horizontal, Platform.isTV ? 40 : 14)
            .padding(.top, Platform.isTV ? 24 : 12)
    }

    /// Refresh, All, one chip per source, and the quality setting.
    private var chipsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Metrics.s(10)) {
                Button {
                    refreshCount += 1
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(StreamChipStyle(selected: false, round: true))
                .accessibilityLabel("Search again")

                Button {
                    sourceFilter = nil
                } label: {
                    Text("All")
                }
                .buttonStyle(StreamChipStyle(selected: activeSource == nil))

                ForEach(results.outcomes) { outcome in
                    Button {
                        sourceFilter = activeSource == outcome.providerID ? nil : outcome.providerID
                    } label: {
                        ProviderChipLabel(outcome: outcome)
                    }
                    .buttonStyle(StreamChipStyle(selected: activeSource == outcome.providerID))
                }

                Button {
                    showQualityPicker = true
                } label: {
                    HStack(spacing: Metrics.s(6)) {
                        Text(center.qualityMode.shortLabel)
                        Image(systemName: "chevron.down")
                            .font(.casa(10, weight: .bold))
                    }
                }
                .buttonStyle(StreamChipStyle(selected: false))
                .accessibilityLabel("Stream quality")
            }
            .padding(.horizontal, Platform.isTV ? 40 : 14)
            .padding(.vertical, Platform.isTV ? 28 : 12)
        }
    }

    // MARK: - Source filter

    /// The chosen source, unless it is no longer among the sources (a new search starts the list over).
    private var activeSource: String? {
        guard let sourceFilter, results.outcomes.contains(where: { $0.providerID == sourceFilter }) else { return nil }
        return sourceFilter
    }

    private var activeSourceName: String? {
        results.outcomes.first { $0.providerID == activeSource }?.name
    }

    private var shownStreams: [StreamCandidate] {
        guard let activeSource else { return results.ranked }
        return results.ranked.filter { $0.providerID == activeSource }
    }

    // MARK: - Stream list

    private var streamList: some View {
        ScrollView {
            LazyVStack(spacing: Metrics.s(10)) {
                if results.ranked.isEmpty, let message = results.emptyMessage {
                    Text(message)
                        .font(.casa(14))
                        .foregroundStyle(Theme.textPrimary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Metrics.s(16))
                        .focusableOnTV()
                }
                ForEach(results.unavailableReasons, id: \.self) { reason in
                    Text(reason)
                        .font(.casa(12))
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                }
                if shownStreams.isEmpty, !results.ranked.isEmpty, let name = activeSourceName {
                    Text("\(name) has no streams in this list. Choose All to see the other sources.")
                        .font(.casa(14))
                        .foregroundStyle(Theme.textPrimary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, Metrics.s(16))
                        .focusableOnTV()
                }
                ForEach(entries) { entry in
                    if let header = entry.header {
                        Text(header)
                            .font(.casa(12, weight: .bold))
                            .foregroundStyle(Color.white.opacity(0.92))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, Metrics.s(6))
                            .padding(.leading, Metrics.s(8))
                    } else if let candidate = entry.candidate {
                        StreamCandidateRow(candidate: candidate, isBest: results.bestChoice?.id == candidate.id) {
                            play(candidate)
                        }
                    }
                }
                if !results.finished {
                    HStack(spacing: Metrics.s(10)) {
                        ProgressView()
                        Text("Searching…")
                            .font(.casa(13))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(Metrics.s(20))
                }
                if results.hiddenStreamCount > 0 {
                    Text("\(results.hiddenStreamCount) streams hidden by quality filter")
                        .font(.casa(12))
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.top, Metrics.s(4))
                        .focusableOnTV()
                }
                whereToWatchSection
                aboutSection
                if !results.rejected.isEmpty {
                    rejectedSection
                }
            }
            .padding(.horizontal, Platform.isTV ? 40 : 14)
            .padding(.bottom, Platform.isTV ? 40 : 14)
        }
    }

    /// The streams in ranked order, with a small heading each time the group (4KHDHub, a service, an add-on)
    /// changes.
    private struct StreamEntry: Identifiable {
        let id: String
        let header: String?
        let candidate: StreamCandidate?
    }

    private var entries: [StreamEntry] {
        var out: [StreamEntry] = []
        var last: String?
        for candidate in shownStreams {
            let group = Self.groupName(candidate)
            if group != last {
                out.append(StreamEntry(id: "group-\(out.count)-\(group)", header: group, candidate: nil))
                last = group
            }
            out.append(StreamEntry(id: candidate.id, header: nil, candidate: candidate))
        }
        return out
    }

    /// "4KHDHub - FSL 2160p" belongs to "4KHDHub"; a label with no such start belongs to its add-on.
    private static func groupName(_ candidate: StreamCandidate) -> String {
        let firstLine = candidate.label.split(separator: "\n", omittingEmptySubsequences: true).first.map(String.init) ?? ""
        if let range = firstLine.range(of: " - ") {
            let prefix = firstLine[..<range.lowerBound].trimmingCharacters(in: .whitespaces)
            if !prefix.isEmpty, prefix.count <= 24 { return prefix }
        }
        return candidate.providerName
    }

    // MARK: - Where to watch

    /// Services the title is on, from add-ons like WatchHub. iPhone and iPad open the link;
    /// Apple TV has no browser, so there the list is information only.
    @ViewBuilder
    private var whereToWatchSection: some View {
        let services = results.whereToWatch.filter { activeSource == nil || $0.providerID == activeSource }
        if !services.isEmpty {
            VStack(alignment: .leading, spacing: Metrics.s(8)) {
                Text("Where to watch")
                    .font(.casa(13, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(Platform.isTV
                     ? "Available on these services. Open the service's own app to watch."
                     : "Available on these services. Tap one to open it.")
                    .font(.casa(12))
                    .foregroundStyle(Theme.textSecondary)
                ForEach(services) { candidate in
                    WhereToWatchRow(candidate: candidate)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, Metrics.s(10))
        }
    }

    // MARK: - About this title

    /// What add-ons say about the title itself (release date, ratings, advisories). Kept apart from the
    /// services, because none of it is somewhere to watch.
    @ViewBuilder
    private var aboutSection: some View {
        let notes = results.infoNotes.filter { activeSource == nil || $0.providerID == activeSource }
        if !notes.isEmpty {
            VStack(alignment: .leading, spacing: Metrics.s(8)) {
                Text("About this title")
                    .font(.casa(13, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                ForEach(notes) { candidate in
                    WhereToWatchRow(candidate: candidate, isNote: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, Metrics.s(10))
        }
    }

    private var emptyView: some View {
        VStack(spacing: Metrics.s(16)) {
            Image(systemName: "magnifyingglass")
                .font(.casa(36))
                .foregroundStyle(Theme.textSecondary)
            Text(results.emptyMessage ?? "No streams found.")
                .font(.casa(14))
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, Metrics.s(40))
            ForEach(results.unavailableReasons, id: \.self) { reason in
                Text(reason)
                    .font(.casa(12))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .focusableOnTV()
    }

    // MARK: - Rejected streams section

    @ViewBuilder
    private var rejectedSection: some View {
        #if os(tvOS)
        // DisclosureGroup is unavailable on tvOS — show a plain collapsed summary row.
        VStack(alignment: .leading, spacing: Metrics.s(4)) {
            Text("\(results.rejected.count) rejected streams")
                .font(.casa(12))
                .foregroundStyle(Theme.textSecondary)
            ForEach(results.rejected.indices, id: \.self) { i in
                let r = results.rejected[i]
                HStack {
                    Text(r.candidate.filename ?? r.candidate.id)
                        .font(.casa(11))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text(r.reason)
                        .font(.casa(11))
                        .foregroundStyle(.red.opacity(0.7))
                        .lineLimit(1)
                }
                .padding(.vertical, 2)
            }
        }
        .padding(.horizontal, Metrics.screenPadding)
        .focusableOnTV()
        #else
        DisclosureGroup {
            ForEach(results.rejected.indices, id: \.self) { i in
                let r = results.rejected[i]
                HStack {
                    Text(r.candidate.filename ?? r.candidate.id)
                        .font(.casa(11))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text(r.reason)
                        .font(.casa(11))
                        .foregroundStyle(.red.opacity(0.7))
                        .lineLimit(1)
                }
                .padding(.vertical, 2)
            }
        } label: {
            Text("\(results.rejected.count) rejected")
                .font(.casa(12))
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(.horizontal, Metrics.screenPadding)
        #endif
    }

    // MARK: - Aggregator

    private func runAggregator(mode: QualityMode) async {
        guard !Task.isCancelled else { return }
        if !resumeChecked {
            resumeChecked = true
            if resumeLastStream, let id = libraryItemID, app.item(id: id)?.canResume == true,
               app.savedStream(for: id) != nil {
                resuming = true
            }
        }
        let pick = resuming ? libraryItemID.flatMap { app.savedStream(for: $0) } : nil
        results = SourceResults()
        let providers = await buildProviders()
        guard !Task.isCancelled else { return }
        // Aether plays what Apple's player can't, so MKV and similar files aren't marked "can't play".
        let probe = PlaylistProbe(fallback: AVFoundationProbe(compatibilityPlays: true), compatibilityPlays: true)
        let agg = SourceAggregator(providers: providers, probe: probe)
        for await snapshot in agg.run(request, mode: mode) {
            guard !Task.isCancelled else { return }
            results = snapshot
            // Resume: the moment the add-ons list the stream it was last played from, play it.
            if resuming, let pick, let match = pick.bestMatch(in: snapshot.ranked + snapshot.hidden) {
                resuming = false
                play(match)
                return
            }
        }
        if resuming {
            resuming = false
            resumeMissed = true
        }
        if autoPlayBest, !didAutoPlay, !Task.isCancelled, let best = results.bestChoice {
            didAutoPlay = true
            play(best)
        }
    }

    private func buildProviders() async -> [any StreamProvider] {
        var providers: [any StreamProvider] = []
        // Enabled Stremio add-ons
        providers += await center.providers(for: request.stremioType, id: request.stremioID)
        // Self-hosted servers (Plex, Jellyfin)
        providers += servers.providers()
        // Torrent sources (backup priority)
        providers.append(TorrentStreamProvider(center: torrents))
        return providers
    }

    /// Adds a torrent, then opens its file list. Nothing is fetched from peers until the
    /// user picks a file there.
    private func addTorrent(_ add: @escaping () async -> InfoHash?) {
        guard !isAddingTorrent else { return }
        isAddingTorrent = true
        addTorrentError = nil
        Task {
            let hash = await add()
            isAddingTorrent = false
            if let hash {
                openedTorrent = hash
            } else {
                addTorrentError = torrents.message ?? "The torrent couldn't be added."
            }
        }
    }

    // MARK: - Playback

    private func play(_ candidate: StreamCandidate) {
        switch candidate.location {
        case .http(let url, let headers):
            // Direct HTTP/HLS stream — hand off to AVFoundation player.
            let streamHeaders = headers.isEmpty ? nil : headers
            let ext = url.pathExtension.lowercased()
            // mp4, m4v, mov and m3u8 go to Apple's player. mkv, avi, webm, ts and anything
            // unrecognised go to Aether, which opens whatever the link turns out to be.
            var container = MediaContainer(fileExtension: ext)
            // Apple's player was already refused on this link, so it would be refused again: go to Aether.
            if case .unreadable(let note) = candidate.verification, note == StreamCandidate.refusedByAppleNote {
                container = .other
            }
            let file = MediaFileInfo(container: container, videoCodec: .hevc)
            if let libraryItemID {
                // Remembered so Resume can play this same stream later without the list.
                app.rememberStream(candidate, for: libraryItemID)
                if app.play(libraryItemID: libraryItemID, streamURL: url, headers: streamHeaders, file: file) {
                    dismiss()
                    return
                }
            }
            let item = MediaItem(
                id: UUID(),
                title: request.title,
                runtimeSeconds: 0,
                file: file,
                imdbID: request.kind == .movie ? request.id : nil,
                streamURL: url,
                streamHeaders: streamHeaders
            )
            app.play(item)
            dismiss()

        case .torrent(let hash, _, let trackers):
            let magnet = candidate.originalMagnet ?? MagnetLink(infoHash: hash, trackers: trackers).uri
            addTorrent { await torrents.add(magnet: magnet) }

        case .torrentFile(let url):
            // Download the .torrent file, add it, then go to its file picker. Nothing is
            // downloaded from peers until a file is chosen there.
            addTorrent { await torrents.add(torrentURL: url) }

        case .external, .unsupported:
            // Never offered as playable streams.
            break
        }
    }
}

// MARK: - Stream row

private struct StreamCandidateRow: View {
    let candidate: StreamCandidate
    let isBest: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(alignment: .center, spacing: Metrics.s(14)) {
                VStack(alignment: .leading, spacing: Metrics.s(4)) {
                    Text(verbatim: candidate.label.isEmpty ? candidate.filename ?? "Stream" : candidate.label)
                        .font(.casa(16, weight: .bold))
                        .foregroundStyle(Color.white)
                        .lineLimit(Platform.isTV ? 3 : nil)
                        .fixedSize(horizontal: false, vertical: true)
                    if let filename = candidate.filename, !candidate.label.isEmpty,
                       !candidate.label.localizedCaseInsensitiveContains(filename) {
                        Text(verbatim: filename)
                            .font(.casa(12, weight: .semibold))
                            .foregroundStyle(Color.white.opacity(0.9))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    HStack(spacing: Metrics.s(6)) {
                        if let size = candidate.advertised.sizeBytes {
                            Text(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
                                .font(.casa(12, weight: .semibold))
                                .foregroundStyle(Color.white.opacity(0.9))
                        }
                        resolutionBadge
                        verifiedBadge
                        if let hdr = (candidate.advertised.dynamicRange ?? candidate.verification.verified?.dynamicRange)?.shortLabel {
                            Text(hdr).badgeStyle(.info)
                        }
                        if let bitrate = candidate.verification.verified?.bitrate {
                            Text(bitrateLabel(bitrate)).badgeStyle(QualityRanking.isLowBitrate(candidate.verification.verified!) ? .warning : .neutral)
                        }
                        if candidate.isProbablyExpired() {
                            Text("may have expired").badgeStyle(.warning)
                        }
                    }
                }

                Spacer(minLength: 0)

                VStack(alignment: .trailing, spacing: Metrics.s(6)) {
                    if isBest {
                        Image(systemName: "star.fill")
                            .font(.casa(13))
                            .foregroundStyle(Theme.accent)
                    }
                    Text(candidate.providerName)
                        .font(.casa(11, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.75))
                        .multilineTextAlignment(.trailing)
                        .frame(maxWidth: Metrics.s(120), alignment: .trailing)
                }
            }
            .padding(Metrics.s(16))
        }
        .buttonStyle(StreamRowStyle(isBest: isBest))
    }

    @ViewBuilder
    private var resolutionBadge: some View {
        let res = candidate.verification.verified?.resolution ?? candidate.advertised.resolution
        let verified = candidate.verification.verified != nil
        Text(res.shortLabel)
            .font(.casa(11, weight: .bold))
            .foregroundStyle(verified && res == .uhd2160 ? Theme.onAccent : Color.white)
            .padding(.horizontal, Metrics.s(6))
            .padding(.vertical, Metrics.s(2))
            .background(verified && res == .uhd2160 ? Theme.accent : Color.white.opacity(0.2), in: Capsule())
    }

    @ViewBuilder
    private var verifiedBadge: some View {
        switch candidate.verification {
        case .verified:
            Text("verified").badgeStyle(.neutral)
        case .checking:
            ProgressView().scaleEffect(0.5).frame(height: 14)
        case .unreadable:
            EmptyView()
        case .unplayable:
            Text("can't play").badgeStyle(.error)
        case .notChecked:
            EmptyView()
        }
    }

    private func bitrateLabel(_ bps: Int) -> String {
        bps >= 1_000_000 ? String(format: "%.0f Mbps", Double(bps) / 1_000_000) : "\(bps / 1000) kbps"
    }
}

/// A stream row on the glass panel: a soft card that gets a white frame while it has focus.
private struct StreamRowStyle: ButtonStyle {
    let isBest: Bool

    func makeBody(configuration: Configuration) -> some View {
        StreamRowBody(configuration: configuration, isBest: isBest)
    }

    private struct StreamRowBody: View {
        let configuration: ButtonStyleConfiguration
        let isBest: Bool
        @Environment(\.isFocused) private var focused

        private var shape: RoundedRectangle {
            RoundedRectangle(cornerRadius: Metrics.s(14), style: .continuous)
        }

        var body: some View {
            configuration.label
                .background(shape.fill(isBest ? Theme.accent.opacity(0.16) : Color.white.opacity(focused ? 0.16 : 0.09)))
                .overlay(
                    shape.strokeBorder(focused ? Color.white : (isBest ? Theme.accent.opacity(0.5) : Color.clear),
                                       lineWidth: focused ? 4 : 1.5)
                )
                .opacity(configuration.isPressed ? 0.85 : 1)
                .animation(.easeOut(duration: 0.12), value: focused)
        }
    }
}

// MARK: - Where to watch row

private struct WhereToWatchRow: View {
    let candidate: StreamCandidate
    /// A note about the title rather than a service: shown with an info symbol.
    var isNote = false
    @Environment(\.openURL) private var openURL
    #if !os(tvOS)
    /// A YouTube link picked from the list, played inside CasaPlay instead of the YouTube app.
    @State private var inAppVideo: Trailer?
    #endif

    var body: some View {
        #if os(tvOS)
        content.focusable()
        #else
        Button {
            guard case .external(let url) = candidate.location else { return }
            if let id = YouTubeLink.videoID(from: url), let video = Trailer(youTubeID: id) {
                inAppVideo = video
            } else {
                openURL(url)
            }
        } label: { content }
        .buttonStyle(.plain)
        .fullScreenCover(item: $inAppVideo) { video in
            TrailerScreen(title: video.name, trailers: [video])
        }
        #endif
    }

    private var content: some View {
        HStack(spacing: Metrics.s(10)) {
            Image(systemName: isNote ? "info.circle" : (Platform.isTV ? "tv" : "arrow.up.right.square"))
                .foregroundStyle(Theme.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(candidate.externalService?.name ?? candidate.providerName)
                    .font(.casa(14, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                if let detail = candidate.externalService?.detail {
                    Text(detail)
                        .font(.casa(12))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(Metrics.s(12))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Metrics.cornerRadius, style: .continuous))
    }
}

// MARK: - Chips

/// A source chip's words: its name, a dot while it's still searching or has failed, and how many streams it gave.
private struct ProviderChipLabel: View {
    let outcome: ProviderOutcome

    var body: some View {
        HStack(spacing: Metrics.s(6)) {
            if case .finished = outcome.status {
                EmptyView()
            } else {
                Circle()
                    .fill(outcome.status.color)
                    .frame(width: Metrics.s(7), height: Metrics.s(7))
            }
            Text(outcome.name)
            if case .finished(let count, _) = outcome.status {
                // "0 of 20" when results were discarded as a different title, so the count
                // is not mistaken for streams that should be listed.
                Text(outcome.rejected > 0 ? "\(max(count - outcome.rejected, 0)) of \(count) matched" : "\(count)")
                    .font(.casa(11))
                    .opacity(0.65)
            }
        }
    }
}

/// A pill on the glass panel: outlined glass, solid white when it is the chosen one or has focus.
private struct StreamChipStyle: ButtonStyle {
    let selected: Bool
    var round = false

    func makeBody(configuration: Configuration) -> some View {
        StreamChipBody(configuration: configuration, selected: selected, round: round)
    }

    private struct StreamChipBody: View {
        let configuration: ButtonStyleConfiguration
        let selected: Bool
        let round: Bool
        @Environment(\.isFocused) private var focused

        var body: some View {
            let lit = selected || focused
            configuration.label
                .font(.casa(13, weight: .semibold))
                .foregroundStyle(lit ? Theme.onLight : Color.white)
                .padding(.horizontal, round ? Metrics.s(12) : Metrics.s(16))
                .padding(.vertical, Metrics.s(8))
                .frame(minHeight: Metrics.s(38))
                .background(Capsule().fill(lit ? Color.white.opacity(selected ? 0.95 : 0.85) : Color.white.opacity(0.14)))
                .overlay(Capsule().strokeBorder(Color.white.opacity(lit ? 0 : 0.35), lineWidth: 1.5))
                .scaleEffect(focused ? 1.06 : (configuration.isPressed ? 0.96 : 1))
                .animation(.easeOut(duration: 0.15), value: focused)
        }
    }
}

/// Reruns the search when the quality setting changes or the refresh button is pressed.
private struct RunKey: Equatable {
    let mode: QualityMode
    let refresh: Int
}

// MARK: - Playing resolution overlay

/// Shows the actual resolution being played vs the source's advertised/verified resolution.
struct PlayingResolutionOverlay: View {
    let playingSize: CGSize        // from AVPlayer.currentItem.presentationSize
    let indicatedBitrate: Double?  // from AVPlayerItem.accessLog().events.last?.indicatedBitrate
    let sourceVerified: VerifiedQuality?

    var body: some View {
        HStack(spacing: Metrics.s(10)) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Playing")
                    .font(.casa(10, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
                Text(playingResLabel)
                    .font(.casa(13, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                if let bps = indicatedBitrate {
                    Text(String(format: "%.1f Mbps", bps / 1_000_000))
                        .font(.casa(11))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            if let v = sourceVerified {
                Divider().frame(height: 32).background(Theme.surfaceStrong)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Source")
                        .font(.casa(10, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                    Text("\(v.width)×\(v.height)")
                        .font(.casa(13, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                    if let bitrate = v.bitrate {
                        Text(String(format: "%.1f Mbps", Double(bitrate) / 1_000_000))
                            .font(.casa(11))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
            }
        }
        .padding(.horizontal, Metrics.s(14))
        .padding(.vertical, Metrics.s(10))
        .background(Color.black.opacity(0.75), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var playingResLabel: String {
        guard playingSize.width > 0 else { return "—" }
        return "\(Int(playingSize.width))×\(Int(playingSize.height))"
    }
}

// MARK: - Extension helpers

private extension ResolutionClass {
    var shortLabel: String {
        switch self {
        case .unknown: "?"
        case .sd: "SD"
        case .hd720: "720p"
        case .fhd1080: "1080p"
        case .uhd2160: "4K"
        }
    }
}

private extension DynamicRange {
    var shortLabel: String {
        switch self {
        case .sdr: return ""
        case .hdr10: return "HDR10"
        case .hdr10Plus: return "HDR10+"
        case .hlg: return "HLG"
        case .dolbyVision: return "DV"
        case .pq: return "HDR (PQ)"
        }
    }
}

private extension ProviderOutcome.Status {
    var color: Color {
        switch self {
        case .waiting: Theme.textSecondary
        case .finished(_, _): .green
        case .failed(_): .red
        case .timedOut: Color.orange
        }
    }
}

private extension QualityMode {
    var shortLabel: String {
        switch self {
        case .preferUHD: return "All resolutions"
        case .uhdOnly: return "4K only"
        case .allowFHDFallback: return "4K and 1080p"
        case .fhdOnly: return "1080p only"
        case .hd720Only: return "720p only"
        case .sdOnly: return "SD only"
        }
    }
}

// MARK: - Identifiable wrapper for InfoHash (for .sheet(item:))

private struct IdentifiableInfoHash: Identifiable {
    let hash: InfoHash
    var id: String { hash.hex }
    init(_ hash: InfoHash) { self.hash = hash }
}
