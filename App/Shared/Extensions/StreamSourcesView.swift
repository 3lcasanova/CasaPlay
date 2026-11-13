// CasaPlay · Designed by 𝐂𝓪sΔηⓞשα
//
// Source picker that runs the aggregator and shows verified / advertised quality badges.

import SwiftUI
import CasaPlayKit

struct StreamSourcesView: View {
    let request: ContentRequest
    var libraryItemID: UUID? = nil
    @Environment(ExtensionCenter.self) private var center
    @Environment(AppState.self) private var app
    @Environment(TorrentCenter.self) private var torrents
    @Environment(ServerCenter.self) private var servers
    @Environment(\.dismiss) private var dismiss

    @State private var results = SourceResults()
    @State private var showQualityPicker = false
    @State private var isAddingTorrent = false
    @State private var addTorrentError: String?
    /// The torrent whose file list is open, pushed inside this screen's own navigation.
    @State private var openedTorrent: InfoHash?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Quality mode selector
                HStack(spacing: Metrics.s(10)) {
                    Text("Quality:")
                        .font(.casa(13))
                        .foregroundStyle(Theme.textSecondary)
                    Button {
                        showQualityPicker = true
                    } label: {
                        HStack(spacing: 4) {
                            Text(center.qualityMode.shortLabel)
                                .font(.casa(13, weight: .semibold))
                                .foregroundStyle(Theme.accent)
                            Image(systemName: "chevron.down")
                                .font(.casa(10, weight: .bold))
                                .foregroundStyle(Theme.accent)
                        }
                    }
                    .buttonStyle(.plain)

                    Spacer(minLength: 0)

                    // Per-provider status chips
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: Metrics.s(6)) {
                            ForEach(results.outcomes) { outcome in
                                ProviderStatusChip(outcome: outcome)
                            }
                        }
                    }
                }
                .padding(.horizontal, Metrics.screenPadding)
                .padding(.vertical, Metrics.s(10))

                Divider().background(Theme.surfaceStrong)

                // Stream list
                // With "Where to watch" entries the scrolling list is used, so a long list of services fits.
                if results.ranked.isEmpty && results.finished && results.whereToWatch.isEmpty {
                    emptyView
                } else {
                    streamList
                }
            }
            .screenBackground()
            .scrollingScreenTitle("Choose Stream")
            .navigationDestination(item: $openedTorrent) { hash in
                TorrentDetailView(hash: hash, libraryItemID: libraryItemID)
            }
            #if !os(tvOS)
            .navigationBarTitleDisplayMode(.inline)
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
        .task(id: center.qualityMode) { [mode = center.qualityMode] in
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
                ForEach(results.ranked) { candidate in
                    StreamCandidateRow(candidate: candidate, isBest: results.bestChoice?.id == candidate.id) {
                        play(candidate)
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
                if !results.rejected.isEmpty {
                    rejectedSection
                }
            }
            .padding(Metrics.screenPadding)
        }
    }

    // MARK: - Where to watch

    /// Services the title is on, from add-ons like WatchHub. iPhone and iPad open the link;
    /// Apple TV has no browser, so there the list is information only.
    @ViewBuilder
    private var whereToWatchSection: some View {
        let services = results.whereToWatch
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
        results = SourceResults()
        let providers = await buildProviders()
        guard !Task.isCancelled else { return }
        let probe = PlaylistProbe(fallback: AVFoundationProbe())
        let agg = SourceAggregator(providers: providers, probe: probe)
        for await snapshot in agg.run(request, mode: mode) {
            guard !Task.isCancelled else { return }
            results = snapshot
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
            let container: MediaContainer = ext == "m3u8" ? .hls : (ext == "mp4" ? .mp4 : .other)
            let file = MediaFileInfo(container: container, videoCodec: .hevc)
            if let libraryItemID,
               app.play(libraryItemID: libraryItemID, streamURL: url, headers: streamHeaders, file: file) {
                dismiss()
                return
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
            HStack(spacing: Metrics.s(14)) {
                // Quality badge column
                VStack(spacing: 4) {
                    resolutionBadge
                    verifiedBadge
                }
                .frame(width: Metrics.s(60))

                // Info
                VStack(alignment: .leading, spacing: 3) {
                    Text(verbatim: candidate.label.isEmpty ? candidate.filename ?? "Stream" : candidate.label)
                        .font(.casa(14, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(Platform.isTV ? 3 : nil)
                        .fixedSize(horizontal: false, vertical: true)
                    if let filename = candidate.filename, !candidate.label.isEmpty,
                       !candidate.label.localizedCaseInsensitiveContains(filename) {
                        Text(verbatim: filename)
                            .font(.casa(11))
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    HStack(spacing: Metrics.s(6)) {
                        Text(candidate.providerName)
                            .font(.casa(11))
                            .foregroundStyle(Theme.textSecondary)
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
                    if let size = candidate.advertised.sizeBytes {
                        Text(ByteCountFormatter.string(fromByteCount: size, countStyle: .file))
                            .font(.casa(11))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }

                Spacer(minLength: 0)

                if isBest {
                    Image(systemName: "star.fill")
                        .font(.casa(14))
                        .foregroundStyle(Theme.accent)
                }

                Image(systemName: "play.fill")
                    .font(.casa(14))
                    .foregroundStyle(Theme.textSecondary)
            }
            .padding(Metrics.s(14))
            .background(isBest ? Theme.accent.opacity(0.1) : Theme.surface,
                        in: RoundedRectangle(cornerRadius: Metrics.cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Metrics.cornerRadius, style: .continuous)
                    .strokeBorder(isBest ? Theme.accent.opacity(0.4) : Color.clear, lineWidth: 1)
            )
        }
        .cardRowButtonStyle()
    }

    @ViewBuilder
    private var resolutionBadge: some View {
        let res = candidate.verification.verified?.resolution ?? candidate.advertised.resolution
        let verified = candidate.verification.verified != nil
        Text(res.shortLabel)
            .font(.casa(11, weight: .bold))
            .foregroundStyle(verified ? Theme.onAccent : Theme.textPrimary)
            .padding(.horizontal, Metrics.s(6))
            .padding(.vertical, Metrics.s(2))
            .background(verified ? (res == .uhd2160 ? Theme.accent : Theme.surfaceStrong) : Theme.surfaceStrong,
                        in: Capsule())
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

// MARK: - Where to watch row

private struct WhereToWatchRow: View {
    let candidate: StreamCandidate
    @Environment(\.openURL) private var openURL

    var body: some View {
        #if os(tvOS)
        content.focusable()
        #else
        Button {
            if case .external(let url) = candidate.location { openURL(url) }
        } label: { content }
        .buttonStyle(.plain)
        #endif
    }

    private var content: some View {
        HStack(spacing: Metrics.s(10)) {
            Image(systemName: Platform.isTV ? "tv" : "arrow.up.right.square")
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

// MARK: - Per-provider status chip

private struct ProviderStatusChip: View {
    let outcome: ProviderOutcome
    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(outcome.status.color)
                .frame(width: 6, height: 6)
            Text(outcome.name)
                .font(.casa(10, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
            if case .finished(let count, _) = outcome.status {
                // "0 of 20" when results were discarded as a different title, so the count
                // is not mistaken for streams that should be listed.
                Text(outcome.rejected > 0 ? "\(max(count - outcome.rejected, 0)) of \(count) matched" : "\(count)")
                    .font(.casa(10)).foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(.horizontal, Metrics.s(7))
        .padding(.vertical, Metrics.s(3))
        .background(Theme.surface, in: Capsule())
    }
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
