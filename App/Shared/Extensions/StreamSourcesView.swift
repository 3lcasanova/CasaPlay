// CasaPlay · Designed by 𝐂𝓪sΔηⓞשα
//
// Source picker that runs the aggregator and shows verified / advertised quality badges.

import SwiftUI
import CasaPlayKit

struct StreamSourcesView: View {
    let request: ContentRequest
    @Environment(ExtensionCenter.self) private var center
    @Environment(AppState.self) private var app
    @Environment(TorrentCenter.self) private var torrents
    @Environment(ServerCenter.self) private var servers
    @Environment(\.dismiss) private var dismiss

    @State private var results = SourceResults()
    @State private var aggregatorTask: Task<Void, Never>?
    @State private var showQualityPicker = false
    @State private var isAddingTorrent = false

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
                if results.ranked.isEmpty && results.finished {
                    emptyView
                } else {
                    streamList
                }
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Choose Stream")
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
            ForEach([QualityMode.preferUHD, .uhdOnly, .allowFHDFallback], id: \.shortLabel) { mode in
                Button(mode.shortLabel) { center.setQualityMode(mode) }
            }
            Button("Cancel", role: .cancel) {}
        }
        .task { await runAggregator() }
        .onDisappear { aggregatorTask?.cancel() }
        .sheet(item: Binding(
            get: { app.pendingTorrentHash.map(IdentifiableInfoHash.init) },
            set: { app.pendingTorrentHash = $0?.hash }
        )) { wrapper in
            TorrentDetailView(hash: wrapper.hash)
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
                if !results.hidden.isEmpty {
                    Text("\(results.hidden.count) streams hidden by quality filter")
                        .font(.casa(12))
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.top, Metrics.s(4))
                        .focusableOnTV()
                }
                if !results.rejected.isEmpty {
                    rejectedSection
                }
            }
            .padding(Metrics.screenPadding)
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

    private func runAggregator() async {
        let providers = await buildProviders()
        let probe = PlaylistProbe(fallback: AVFoundationProbe())
        let agg = SourceAggregator(providers: providers, probe: probe)
        aggregatorTask = Task {
            for await snapshot in agg.run(request, mode: center.qualityMode) {
                results = snapshot
                if Task.isCancelled { break }
            }
        }
        await aggregatorTask?.value
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

    // MARK: - Playback

    private func play(_ candidate: StreamCandidate) {
        switch candidate.location {
        case .http(let url, let headers):
            // Direct HTTP/HLS stream — hand off to AVFoundation player.
            let ext = url.pathExtension.lowercased()
            let container: MediaContainer = ext == "m3u8" ? .hls : (ext == "mp4" ? .mp4 : .other)
            let item = MediaItem(
                id: UUID(),
                title: request.title,
                runtimeSeconds: 0,
                file: MediaFileInfo(container: container, videoCodec: .hevc),
                imdbID: request.kind == .movie ? request.id : nil,
                streamURL: url,
                streamHeaders: headers.isEmpty ? nil : headers
            )
            app.play(item)
            dismiss()

        case .torrent(let hash, _, _):
            // Torrent already has an InfoHash — navigate straight to the file picker.
            app.pendingTorrentHash = hash
            dismiss()

        case .unsupported(let reason) where reason.hasPrefix("Torrent file"):
            // .torrent URL candidate — look up by ID and add via TorrentCenter.
            if let tc = findTorrentCandidate(id: candidate.id) {
                isAddingTorrent = true
                Task {
                    if let hash = await torrents.add(tc) {
                        await MainActor.run {
                            app.pendingTorrentHash = hash
                            dismiss()
                        }
                    }
                    await MainActor.run { isAddingTorrent = false }
                }
            }

        default:
            break
        }
    }

    /// Look up the original TorrentCandidate by StreamCandidate ID.
    private func findTorrentCandidate(id: String) -> TorrentCandidate? {
        // The ID is "torrent:{tc.id}"; reverse-map isn't stored, so we
        // keep a secondary list produced by TorrentStreamProvider.
        // For now, return nil — .torrent file candidates shown as info only.
        return nil
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
                    Text(candidate.label.isEmpty ? candidate.filename ?? "Stream" : candidate.label)
                        .font(.casa(14, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(2)
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
        .buttonStyle(.plain)
        .focusableOnTV()
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
                Text("\(count)").font(.casa(10)).foregroundStyle(Theme.textSecondary)
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
        case .preferUHD: return "Prefer 4K"
        case .uhdOnly: return "4K only"
        case .allowFHDFallback: return "Allow 1080p"
        }
    }
}

// MARK: - Identifiable wrapper for InfoHash (for .sheet(item:))

private struct IdentifiableInfoHash: Identifiable {
    let hash: InfoHash
    var id: String { hash.hex }
    init(_ hash: InfoHash) { self.hash = hash }
}
