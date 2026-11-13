// CasaPlay · Designed by 𝐂𝓪sΔηⓞשα

import SwiftUI
import UniformTypeIdentifiers
import CasaPlayKit

// MARK: - List

struct TorrentsView: View {
    @Environment(TorrentCenter.self) private var center

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Metrics.s(14)) {
                    HStack(spacing: Metrics.s(10)) {
                        NavigationLink {
                            AddTorrentView()
                        } label: {
                            Label("Add", systemImage: "plus")
                        }
                        .buttonStyle(.borderedProminent)

                        NavigationLink {
                            TorrentSourcesView()
                        } label: {
                            Label("Browse", systemImage: "books.vertical")
                        }
                        .buttonStyle(.bordered)

                        NavigationLink {
                            TorrentSettingsView()
                        } label: {
                            Label("Settings & privacy", systemImage: "hand.raised")
                        }
                        .buttonStyle(.bordered)
                    }

                    if center.summaries.isEmpty {
                        Text("Add a magnet link or .torrent file, or browse free films from the Internet Archive. Only use torrents you are allowed to download and share.")
                            .font(.casa(13))
                            .foregroundStyle(Theme.textSecondary)
                            .padding(.top, Metrics.s(10))
                            .focusableOnTV()
                    }

                    ForEach(center.summaries) { summary in
                        NavigationLink(value: summary.infoHash) {
                            TorrentRow(summary: summary)
                        }
                        .posterButtonStyle()
                    }

                    Text("Cache: \(ByteCountFormatter.string(fromByteCount: center.usedBytes, countStyle: .file)) of \(ByteCountFormatter.string(fromByteCount: center.settings.storageLimit, countStyle: .file))")
                        .font(.casa(12))
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.top, Metrics.s(6))
                        .focusableOnTV()
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(Metrics.screenPadding)
            }
            .screenBackground()
            .scrollingScreenTitle("Torrents")
            .navigationDestination(for: InfoHash.self) { hash in
                TorrentDetailView(hash: hash)
            }
        }
    }
}

private struct TorrentRow: View {
    let summary: TorrentSummary

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.s(6)) {
            HStack {
                Text(summary.stats.name)
                    .font(.casa(15, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Spacer(minLength: Metrics.s(8))
                Text(summary.stats.state.label)
                    .font(.casa(11, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                    .padding(.horizontal, Metrics.s(8))
                    .padding(.vertical, Metrics.s(2))
                    .background(Theme.surfaceStrong, in: Capsule())
            }
            ProgressBar(fraction: summary.stats.progress)
                .clipShape(Capsule())
            Text(TorrentFormat.line(summary.stats))
                .font(.casa(12))
                .foregroundStyle(Theme.textSecondary)
                .lineLimit(1)
        }
        .padding(Metrics.s(14))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Metrics.cornerRadius, style: .continuous))
    }
}

enum TorrentFormat {
    static func bytes(_ value: Int64) -> String { ByteCountFormatter.string(fromByteCount: value, countStyle: .file) }
    static func rate(_ value: Double) -> String { "\(bytes(Int64(value)))/s" }

    static func line(_ s: TorrentStats) -> String {
        var parts = ["\(Int(s.progress * 100))%", "↓ \(rate(s.downloadRate))", "↑ \(rate(s.uploadRate))"]
        parts.append("\(s.connectedPeers) peer\(s.connectedPeers == 1 ? "" : "s")")
        if s.activeWebSeeds > 0 { parts.append("web seed") }
        return parts.joined(separator: " · ")
    }
}

// MARK: - Add

/// Apple TV: type with the on-screen keyboard, or use the keyboard notification that
/// appears on a nearby iPhone to paste a magnet link. iPhone and iPad can also paste
/// or open a .torrent file.
struct AddTorrentView: View {
    @Environment(TorrentCenter.self) private var center
    @State private var magnet = ""
    @State private var isWorking = false
    @State private var added: InfoHash?
    @State private var showingImporter = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Metrics.s(14)) {
                Text("Magnet link")
                    .font(.casa(17, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)

                TextField("magnet:?xt=urn:btih:…", text: $magnet)
                    #if !os(tvOS)
                    .textFieldStyle(.roundedBorder)
                    .textInputAutocapitalization(.never)
                    #endif
                    .autocorrectionDisabled()
                    .onSubmit { Task { await addMagnet() } }

                HStack(spacing: Metrics.s(10)) {
                    Button {
                        Task { await addMagnet() }
                    } label: {
                        Label("Add magnet", systemImage: "arrow.down.circle")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(magnet.isEmpty || isWorking)

                    #if !os(tvOS)
                    Button {
                        if let text = UIPasteboard.general.string { magnet = text }
                    } label: {
                        Label("Paste", systemImage: "doc.on.clipboard")
                    }
                    .buttonStyle(.bordered)

                    Button {
                        showingImporter = true
                    } label: {
                        Label(".torrent file", systemImage: "doc")
                    }
                    .buttonStyle(.bordered)
                    #endif

                    if isWorking { ProgressView() }
                }

                #if os(tvOS)
                Text("Tip: select the field, then use the keyboard notification on your iPhone or the Apple TV Remote app to paste a long magnet link. Or browse sources instead of typing.")
                    .font(.casa(12))
                    .foregroundStyle(Theme.textSecondary)
                    .focusableOnTV()
                #endif

                NavigationLink {
                    TorrentSourcesView()
                } label: {
                    Label("Browse sources", systemImage: "books.vertical")
                }
                .buttonStyle(.bordered)

                if let message = center.message {
                    ErrorNote(text: message)
                }

                TorrentPrivacyNote()
            }
            .padding(Metrics.screenPadding)
        }
        .screenBackground()
        .scrollingScreenTitle("Add torrent")
        .navigationDestination(item: $added) { hash in
            TorrentDetailView(hash: hash)
        }
        #if !os(tvOS)
        .fileImporter(
            isPresented: $showingImporter,
            allowedContentTypes: [UTType(filenameExtension: "torrent") ?? .data]
        ) { result in
            guard case .success(let url) = result else { return }
            Task { await importTorrent(url) }
        }
        #endif
        .onAppear { center.message = nil }
    }

    private func addMagnet() async {
        isWorking = true
        defer { isWorking = false }
        if let hash = await center.add(magnet: magnet) {
            magnet = ""
            added = hash
        }
    }

    private func importTorrent(_ url: URL) async {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size <= 16 * 1024 * 1024,
              let data = try? Data(contentsOf: url) else {
            center.message = "That file couldn't be read or is too large to be a .torrent file."
            return
        }
        isWorking = true
        defer { isWorking = false }
        if let hash = await center.add(torrentFile: data) { added = hash }
    }
}

// MARK: - Sources

struct TorrentSourcesView: View {
    @Environment(TorrentCenter.self) private var center

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Metrics.s(12)) {
                Text("Sources only find torrents. CasaPlay checks each file against the torrent before using it. Use sources you are allowed to download from.")
                    .font(.casa(12))
                    .foregroundStyle(Theme.textSecondary)
                    .focusableOnTV()
                ForEach(Array(center.providers.enumerated()), id: \.offset) { _, provider in
                    NavigationLink {
                        TorrentBrowseView(provider: provider)
                    } label: {
                        SourceCard(title: provider.name, detail: provider.summary)
                    }
                    .posterButtonStyle()
                }
                NavigationLink {
                    TorrentSettingsView()
                } label: {
                    Label("Add an RSS feed", systemImage: "plus")
                }
                .buttonStyle(.bordered)
            }
            .padding(Metrics.screenPadding)
        }
        .screenBackground()
        .scrollingScreenTitle("Sources")
    }
}

private struct SourceCard: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.casa(15, weight: .semibold)).foregroundStyle(Theme.textPrimary)
            Text(detail).font(.casa(12)).foregroundStyle(Theme.textSecondary)
        }
        .padding(Metrics.s(14))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Metrics.cornerRadius, style: .continuous))
    }
}

struct TorrentBrowseView: View {
    @Environment(TorrentCenter.self) private var center
    let provider: any TorrentSourceProvider
    @State private var query = ""
    @State private var results: [TorrentCandidate] = []
    @State private var isLoading = false
    @State private var error: String?
    @State private var addingID: String?
    @State private var added: InfoHash?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Metrics.s(12)) {
                HStack(spacing: Metrics.s(10)) {
                    TextField("Search \(provider.name)", text: $query)
                        #if !os(tvOS)
                        .textFieldStyle(.roundedBorder)
                        #endif
                        .onSubmit { Task { await search() } }
                    Button("Search") { Task { await search() } }
                        .buttonStyle(.bordered)
                }
                if isLoading { ProgressView().frame(maxWidth: .infinity) }
                if let error { ErrorNote(text: error) }
                if let message = center.message { ErrorNote(text: message) }
                ForEach(results) { candidate in
                    Button {
                        Task { await add(candidate) }
                    } label: {
                        CandidateRow(candidate: candidate, isAdding: addingID == candidate.id)
                    }
                    .posterButtonStyle()
                    .disabled(addingID != nil)
                }
            }
            .padding(Metrics.screenPadding)
        }
        .screenBackground()
        .scrollingScreenTitle(provider.name)
        .navigationDestination(item: $added) { hash in
            TorrentDetailView(hash: hash)
        }
        .task { if results.isEmpty { await search() } }
    }

    private func search() async {
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            results = try await provider.search(query)
            if results.isEmpty { error = "Nothing found." }
        } catch {
            self.error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func add(_ candidate: TorrentCandidate) async {
        addingID = candidate.id
        defer { addingID = nil }
        if let hash = await center.add(candidate) { added = hash }
    }
}

private struct CandidateRow: View {
    let candidate: TorrentCandidate
    let isAdding: Bool

    var body: some View {
        HStack(spacing: Metrics.s(12)) {
            VStack(alignment: .leading, spacing: 2) {
                Text(candidate.title)
                    .font(.casa(14, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(2)
                Text([candidate.license, candidate.detail].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.casa(12))
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer(minLength: Metrics.s(8))
            if isAdding { ProgressView() } else {
                Image(systemName: "plus.circle").foregroundStyle(Theme.accent)
            }
        }
        .padding(Metrics.s(12))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Metrics.cornerRadius, style: .continuous))
    }
}

// MARK: - Detail and file selection

struct TorrentDetailView: View {
    @Environment(TorrentCenter.self) private var center
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    let hash: InfoHash
    var libraryItemID: UUID? = nil
    @State private var files: [TorrentFile] = []
    @State private var showAllFiles = false
    @State private var confirmingRemove = false

    private var stats: TorrentStats { center.summary(hash)?.stats ?? TorrentStats() }

    private var visibleFiles: [TorrentFile] {
        showAllFiles ? files : files.filter(\.isVideo)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Metrics.s(16)) {
                Text(stats.name)
                    .font(.casa(24, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)

                statsPanel

                if files.isEmpty {
                    HStack(spacing: Metrics.s(10)) {
                        ProgressView()
                        Text("Getting the torrent's file list from peers or sources…")
                            .font(.casa(13))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .focusableOnTV()
                } else {
                    Text("Choose a file")
                        .font(.casa(17, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    ForEach(visibleFiles) { file in
                        FileRow(file: file, isSelected: stats.selectedFileIndex == file.index) {
                            Task { await play(file) }
                        }
                    }
                    if files.contains(where: { !$0.isVideo }) {
                        Button(showAllFiles ? "Show video files only" : "Show all \(files.count) files") {
                            showAllFiles.toggle()
                        }
                        .buttonStyle(.bordered)
                    }
                    Text("CasaPlay only plays video. Other files are listed but never opened.")
                        .font(.casa(12))
                        .foregroundStyle(Theme.textSecondary)
                        .focusableOnTV()
                }

                controls

                if let message = center.message { ErrorNote(text: message) }
                TorrentPrivacyNote()
            }
            .padding(Metrics.screenPadding)
        }
        .screenBackground()
        .scrollingScreenTitle("Torrent")
        .task(id: hash) {
            // Wait for the file list (magnet links need peers or sources first).
            while files.isEmpty, !Task.isCancelled {
                files = await center.files(hash)
                if files.isEmpty { try? await Task.sleep(nanoseconds: 1_000_000_000) }
            }
        }
        .confirmationDialog("Remove this torrent and delete its downloaded data?", isPresented: $confirmingRemove) {
            Button("Remove and delete", role: .destructive) {
                Task {
                    await center.remove(hash)
                    dismiss()
                }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var statsPanel: some View {
        VStack(alignment: .leading, spacing: Metrics.s(8)) {
            HStack {
                Text(stats.state.label)
                    .font(.casa(14, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Text("\(Int(stats.progress * 100))%")
                    .font(.casa(14, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
            }
            ProgressBar(fraction: stats.progress).clipShape(Capsule())
            StatLine(label: "Download", value: TorrentFormat.rate(stats.downloadRate) + " · " + TorrentFormat.bytes(stats.downloadedBytes))
            StatLine(label: "Upload", value: TorrentFormat.rate(stats.uploadRate) + " · " + TorrentFormat.bytes(stats.uploadedBytes))
            StatLine(label: "Peers", value: "\(stats.connectedPeers) connected · \(stats.knownPeers) known")
            if stats.activeWebSeeds > 0 { StatLine(label: "Web seeds", value: "\(stats.activeWebSeeds) connections") }
            if stats.selectedFileIndex != nil {
                StatLine(label: "Buffered ahead", value: TorrentFormat.bytes(stats.bufferedAhead))
            }
            if let error = stats.lastError {
                Text(error)
                    .font(.casa(12))
                    .foregroundStyle(Color.orange)
            }
        }
        .padding(Metrics.s(14))
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Metrics.cornerRadius, style: .continuous))
        .focusableOnTV()
    }

    private var controls: some View {
        HStack(spacing: Metrics.s(10)) {
            if case .paused = stats.state {
                Button {
                    Task { await center.resume(hash) }
                } label: { Label("Resume", systemImage: "play.fill") }
                .buttonStyle(.bordered)
            } else {
                Button {
                    Task { await center.pause(hash) }
                } label: { Label("Pause", systemImage: "pause.fill") }
                .buttonStyle(.bordered)
            }
            Button(role: .destructive) {
                confirmingRemove = true
            } label: { Label("Remove", systemImage: "trash") }
            .buttonStyle(.bordered)
        }
    }

    private func play(_ file: TorrentFile) async {
        guard file.isVideo else { return }
        guard await center.select(hash, file: file.index) else { return }
        guard let item = center.mediaItem(hash: hash, file: file) else { return }
        if let libraryItemID, let url = item.streamURL,
           app.play(libraryItemID: libraryItemID, streamURL: url, headers: nil, file: item.file) {
            return
        }
        app.play(item)
    }
}

private struct FileRow: View {
    let file: TorrentFile
    let isSelected: Bool
    let play: () -> Void

    var body: some View {
        Button(action: play) {
            HStack(spacing: Metrics.s(12)) {
                Image(systemName: file.isVideo ? (isSelected ? "play.circle.fill" : "play.circle") : "doc")
                    .font(.casa(20))
                    .foregroundStyle(file.isVideo ? Theme.accent : Theme.textSecondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(file.path)
                        .font(.casa(14, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(2)
                    Text(detail)
                        .font(.casa(12))
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer(minLength: 0)
            }
            .padding(Metrics.s(12))
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.surface, in: RoundedRectangle(cornerRadius: Metrics.cornerRadius, style: .continuous))
        }
        .posterButtonStyle()
        .disabled(!file.isVideo)
    }

    private var detail: String {
        var parts = [TorrentFormat.bytes(file.length)]
        if file.isVideo {
            parts.append(file.playsInCasaPlay ? "Plays while downloading" : "Format needs another player")
        }
        return parts.joined(separator: " · ")
    }
}

private struct StatLine: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label).font(.casa(12)).foregroundStyle(Theme.textSecondary)
            Spacer()
            Text(value).font(.casa(12, weight: .medium)).foregroundStyle(Theme.textPrimary)
        }
    }
}

private struct ErrorNote: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.casa(13))
            .foregroundStyle(Theme.textPrimary)
            .padding(Metrics.s(12))
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.orange.opacity(0.18), in: RoundedRectangle(cornerRadius: Metrics.cornerRadius))
            .focusableOnTV()
    }
}

struct TorrentPrivacyNote: View {
    var body: some View {
        Text("BitTorrent is not private: trackers and every peer you connect to can see this device's public IP address and which torrent it is sharing. While uploading is on, peers also receive pieces from you. Change this in Torrents › Settings & privacy.")
            .font(.casa(12))
            .foregroundStyle(Theme.textSecondary)
            .focusableOnTV()
    }
}

// MARK: - Player overlay

/// Small status badge over the player while a torrent stream waits for data.
struct TorrentPlaybackStatus: View {
    @Environment(TorrentCenter.self) private var center
    let hash: InfoHash

    var body: some View {
        let stats = center.summary(hash)?.stats
        VStack {
            if let stats, stats.isBuffering || stats.lastError != nil {
                HStack(spacing: 8) {
                    if stats.isBuffering { ProgressView() }
                    Text(stats.isBuffering
                         ? "Buffering · \(stats.connectedPeers) peers · \(TorrentFormat.rate(stats.downloadRate))"
                         : (stats.lastError ?? ""))
                        .font(.casa(12, weight: .semibold))
                        .foregroundStyle(Color.white)
                        .lineLimit(2)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color.black.opacity(0.65), in: Capsule())
                .padding(.top, Platform.isTV ? 60 : 70)
            }
            Spacer()
        }
        .allowsHitTesting(false)
    }
}
