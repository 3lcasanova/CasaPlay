// CasaPlay · Designed by 𝐂𝓪sΔηⓞשα
//
// The compatibility player. VLCKit plays what Apple's player can't: MKV, AVI, WebM, TrueHD,
// DTS, FLAC, image subtitles (PGS) and more. VLC draws only the picture, so this file adds
// the controls, the audio and subtitle menus, resume, and CasaPlay's own subtitle overlay.
//
// Not covered here: Apple's HDR / Dolby Vision display switching, and Atmos passthrough.
// Those stay with the Apple engine, which the router still picks for files it can play.

import SwiftUI
import AVFoundation
import VLCKitSPM
import CasaPlayKit

// MARK: - Model

struct VLCTrackChoice: Identifiable, Hashable {
    /// VLC's track index. -1 means "off".
    let id: Int32
    let name: String
}

/// VLC reports state changes through an Objective-C delegate; this forwards them to the main thread.
private final class VLCEvents: NSObject, VLCMediaPlayerDelegate {
    var onStateChange: (() -> Void)?

    func mediaPlayerStateChanged(_ aNotification: Notification) {
        DispatchQueue.main.async { [weak self] in self?.onStateChange?() }
    }
}

@Observable
final class VLCPlayerModel {
    enum Phase: Equatable {
        case loading, buffering, playing, paused, ended
        case failed(String)
    }

    private(set) var phase: Phase = .loading
    private(set) var seconds: TimeInterval = 0
    private(set) var duration: TimeInterval = 0
    private(set) var audioTracks: [VLCTrackChoice] = []
    private(set) var subtitleTracks: [VLCTrackChoice] = []
    private(set) var audioIndex: Int32 = -1
    private(set) var subtitleIndex: Int32 = -1

    @ObservationIgnored var onProgress: ((TimeInterval) -> Void)?
    @ObservationIgnored var onTime: ((TimeInterval) -> Void)?

    @ObservationIgnored private let events = VLCEvents()
    /// Created on first use. SwiftUI may build a model and throw it away, and that must stay cheap.
    @ObservationIgnored private lazy var player: VLCMediaPlayer = {
        let player = VLCMediaPlayer()
        player.delegate = self.events
        return player
    }()
    @ObservationIgnored private var started = false
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var drawable: UIView?
    @ObservationIgnored private var pendingMedia: VLCMedia?
    @ObservationIgnored private var startAt: TimeInterval = 0
    @ObservationIgnored private var resumeChecked = false
    @ObservationIgnored private var lastReport = Date.distantPast
    @ObservationIgnored private var isTorrent = false
    @ObservationIgnored private var hideEmbeddedSubtitles = false
    @ObservationIgnored private var appliedInitialSubtitle = false

    init() {
        events.onStateChange = { [weak self] in self?.stateChanged() }
    }

    deinit { timer?.invalidate() }

    // MARK: Opening

    /// Opens the stream. Torrent links are served over local HTTP first, because VLC can't read
    /// CasaPlay's own torrent scheme.
    @MainActor
    func open(url: URL, headers: [String: String]?, startAt: TimeInterval, hideEmbeddedSubtitles: Bool) async {
        self.startAt = startAt
        self.hideEmbeddedSubtitles = hideEmbeddedSubtitles
        phase = .loading
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)

        var playable = url
        if url.scheme == TorrentResourceLoader.scheme {
            isTorrent = true
            do {
                playable = try await TorrentHTTPServer.shared.localURL(for: url)
            } catch {
                phase = .failed(error.localizedDescription)
                return
            }
        }
        guard !Task.isCancelled else { return }

        let media = VLCMedia(url: playable)
        // Torrent pieces arrive unevenly, so a torrent gets a longer buffer.
        media.addOption(":network-caching=\(isTorrent ? 4000 : 1500)")
        // VLC can send these two request headers; any other header an add-on asks for is dropped.
        for (name, value) in headers ?? [:] {
            switch name.lowercased() {
            case "referer", "referrer": media.addOption(":http-referrer=\(value)")
            case "user-agent": media.addOption(":http-user-agent=\(value)")
            default: break
            }
        }
        if startAt > 5 { media.addOption(":start-time=\(Int(startAt))") }
        pendingMedia = media
        startIfReady()
    }

    /// The video view is created by SwiftUI; playback starts once both it and the media exist.
    func attach(_ view: UIView) {
        drawable = view
        player.drawable = view
        startIfReady()
    }

    private func startIfReady() {
        guard let media = pendingMedia, drawable != nil else { return }
        pendingMedia = nil
        started = true
        player.media = media
        player.play()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            self?.tick()
        }
    }

    // MARK: Controls

    var isPlaying: Bool { phase == .playing || phase == .buffering }

    func togglePlay() {
        if player.isPlaying { player.pause() } else { player.play() }
    }

    func skip(_ amount: Int32) {
        if amount >= 0 { player.jumpForward(amount) } else { player.jumpBackward(-amount) }
    }

    func seek(toFraction fraction: Double) {
        guard duration > 0 else { return }
        player.position = Float(min(max(fraction, 0), 1))
    }

    func selectAudio(_ index: Int32) {
        player.currentAudioTrackIndex = index
        refreshTracks()
    }

    func selectSubtitle(_ index: Int32) {
        player.currentVideoSubTitleIndex = index
        refreshTracks()
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        if seconds > 0 { onProgress?(seconds) }
        onProgress = nil
        onTime = nil
        guard started else { return }
        player.delegate = nil
        player.stop()
        player.drawable = nil
    }

    // MARK: VLC events

    private func stateChanged() {
        switch player.state {
        case .opening:
            if phase != .playing { phase = .loading }
        case .buffering:
            phase = .buffering
        case .playing:
            phase = .playing
            refreshTracks()
            applyInitialSubtitle()
        case .paused:
            phase = .paused
        case .ended:
            phase = .ended
            if duration > 0 { onProgress?(duration) }
        case .error:
            phase = .failed(failureText)
        case .esAdded:
            refreshTracks()
        default:
            break
        }
    }

    private var failureText: String {
        if isTorrent, let reason = TorrentHTTPServer.shared.lastFailureMessage { return reason }
        return "VLC couldn't open this stream. The link may have expired, or the source may be unreachable."
    }

    private func tick() {
        let now = max(Double(player.time.intValue), 0) / 1000
        let length = Double(player.media?.length.intValue ?? 0) / 1000
        if now != seconds { seconds = now }
        if length > 0, length != duration { duration = length }
        onTime?(now)

        if (phase == .loading || phase == .buffering), player.isPlaying, now > 0 { phase = .playing }
        guard phase == .playing, now > 0 else { return }

        // If the start-time option was ignored, jump to the saved spot once.
        if !resumeChecked {
            resumeChecked = true
            if startAt > 5, now < startAt - 10 { player.time = VLCTime(int: Int32(startAt * 1000)) }
        }
        if Date().timeIntervalSince(lastReport) >= 5 {
            lastReport = Date()
            onProgress?(now)
        }
        if audioTracks.isEmpty || subtitleTracks.isEmpty, Int(now) % 2 == 0 { refreshTracks() }
    }

    private func refreshTracks() {
        audioTracks = Self.choices(indexes: player.audioTrackIndexes, names: player.audioTrackNames)
        subtitleTracks = Self.choices(indexes: player.videoSubTitlesIndexes, names: player.videoSubTitlesNames)
        audioIndex = player.currentAudioTrackIndex
        subtitleIndex = player.currentVideoSubTitleIndex
    }

    /// When CasaPlay is already drawing a subtitle file, VLC's own embedded track would double it.
    private func applyInitialSubtitle() {
        guard !appliedInitialSubtitle, !subtitleTracks.isEmpty else { return }
        appliedInitialSubtitle = true
        if hideEmbeddedSubtitles, player.currentVideoSubTitleIndex != -1 {
            player.currentVideoSubTitleIndex = -1
            refreshTracks()
        }
    }

    private static func choices(indexes: [Any]?, names: [Any]?) -> [VLCTrackChoice] {
        guard let indexes = indexes as? [NSNumber], let names = names as? [String] else { return [] }
        return zip(indexes, names).map { index, name in
            VLCTrackChoice(id: index.int32Value, name: index.int32Value == -1 ? "Off" : name)
        }
    }
}

// MARK: - Video surface

struct VLCVideoSurface: UIViewRepresentable {
    let model: VLCPlayerModel

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .black
        // Not during the view update; attaching can start playback.
        DispatchQueue.main.async { model.attach(view) }
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {}
}

// MARK: - Screen

struct VLCPlayerScreen: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    let item: MediaItem
    let url: URL

    private enum Focus: Hashable { case surface, playPause }

    @State private var model = VLCPlayerModel()
    @State private var overlay = SubtitleOverlayModel()
    @State private var controlsVisible = true
    @State private var hideTask: Task<Void, Never>?
    @State private var scrub: Double?
    @FocusState private var focus: Focus?

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VLCVideoSurface(model: model).ignoresSafeArea()
            SubtitleOverlayView(model: overlay)
            inputLayer
            statusLayer
            if controlsVisible {
                controls.transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.2), value: controlsVisible)
        .task { await begin() }
        .onAppear {
            UIApplication.shared.isIdleTimerDisabled = true  // keep the TV and the phone awake
            syncSubtitles()
            showControls(focusPlayPause: true)
        }
        .onDisappear {
            UIApplication.shared.isIdleTimerDisabled = false
            hideTask?.cancel()
            model.stop()
        }
        .onChange(of: app.activeSubtitle(for: item.id)?.id) { _, _ in syncSubtitles() }
        #if os(tvOS)
        .onPlayPauseCommand { model.togglePlay(); showControls() }
        .onExitCommand {
            // Menu hides the controls first, and leaves the player on the second press.
            if controlsVisible && model.phase == .playing { hideControls() } else { dismiss() }
        }
        #endif
    }

    // MARK: Setup

    private func begin() async {
        let itemID = item.id
        let app = self.app
        let overlay = self.overlay
        model.onProgress = { seconds in app.updateProgress(id: itemID, seconds: seconds) }
        model.onTime = { seconds in overlay.time = seconds }
        await model.open(
            url: url,
            headers: item.streamHeaders,
            startAt: item.canResume ? item.progressSeconds : 0,
            hideEmbeddedSubtitles: app.activeSubtitle(for: item.id) != nil
        )
    }

    private func syncSubtitles() {
        overlay.style = app.subtitleStyle
        overlay.setTrack(app.activeSubtitle(for: item.id))
    }

    // MARK: Input

    /// A full-screen layer under the controls that takes the remote or a tap.
    @ViewBuilder private var inputLayer: some View {
        #if os(tvOS)
        Color.clear
            .contentShape(Rectangle())
            .focusable(!controlsVisible)
            .focused($focus, equals: .surface)
            .onMoveCommand { direction in
                switch direction {
                case .left: model.skip(-10); showControls()
                case .right: model.skip(10); showControls()
                case .up, .down: showControls(focusPlayPause: true)
                @unknown default: break
                }
            }
            .onTapGesture { model.togglePlay(); showControls() }
        #else
        Color.clear
            .contentShape(Rectangle())
            .onTapGesture { controlsVisible ? hideControls() : showControls() }
        #endif
    }

    private func showControls(focusPlayPause: Bool = false) {
        controlsVisible = true
        #if os(tvOS)
        if focusPlayPause { focus = .playPause }
        #endif
        hideTask?.cancel()
        hideTask = Task {
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard !Task.isCancelled, scrub == nil, model.phase == .playing else { return }
            hideControls()
        }
    }

    private func hideControls() {
        controlsVisible = false
        #if os(tvOS)
        focus = .surface
        #endif
    }

    // MARK: Status

    @ViewBuilder private var statusLayer: some View {
        switch model.phase {
        case .loading, .buffering:
            ProgressView()
                .progressViewStyle(.circular)
                .controlSize(.large)
                .tint(Color.white)
        case .failed(let reason):
            failureView(reason)
        default:
            EmptyView()
        }
    }

    private func failureView(_ reason: String) -> some View {
        VStack(spacing: Metrics.s(10)) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: Metrics.s(36)))
                .foregroundStyle(Theme.accent)
            Text("Can't play this")
                .font(.casa(19, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Text(reason)
                .font(.casa(13))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
            #if os(tvOS)
            Text("Press Menu to go back")
                .font(.casa(12))
                .foregroundStyle(Theme.textSecondary)
                .padding(.top, 8)
            #endif
        }
        .padding(Metrics.screenPadding)
    }

    // MARK: Controls

    private var fraction: Double {
        model.duration > 0 ? min(max(model.seconds / model.duration, 0), 1) : 0
    }

    private var controls: some View {
        let shown = scrub.map { $0 * model.duration } ?? model.seconds
        return VStack(spacing: 0) {
            Spacer()
            VStack(spacing: Metrics.s(10)) {
                Text(item.title)
                    .font(.casa(17, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                progressBar
                HStack {
                    Text(Self.clock(shown))
                    Spacer()
                    if model.duration > 0 { Text("-" + Self.clock(max(model.duration - shown, 0))) }
                }
                .font(.casa(12))
                .foregroundStyle(Theme.textSecondary)
                HStack(spacing: Metrics.s(24)) {
                    controlButton("gobackward.10", label: "Back 10 seconds") { model.skip(-10) }
                    controlButton(model.isPlaying ? "pause.fill" : "play.fill",
                                  label: model.isPlaying ? "Pause" : "Play") { model.togglePlay() }
                        .focused($focus, equals: .playPause)
                    controlButton("goforward.10", label: "Forward 10 seconds") { model.skip(10) }
                    Spacer()
                    audioMenu
                    subtitleMenu
                }
            }
            .padding(.horizontal, Metrics.screenPadding)
            .padding(.top, Metrics.s(40))
            .padding(.bottom, Metrics.s(20))
            .background(
                LinearGradient(colors: [Color.clear, Color.black.opacity(0.85)], startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()
            )
        }
    }

    @ViewBuilder private var progressBar: some View {
        #if os(tvOS)
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.25))
                Capsule().fill(Theme.accent).frame(width: proxy.size.width * fraction)
            }
        }
        .frame(height: 8)
        #else
        Slider(value: Binding(get: { scrub ?? fraction }, set: { scrub = $0 }), in: 0...1) { editing in
            if !editing, let target = scrub {
                model.seek(toFraction: target)
                scrub = nil
            }
            showControls()
        }
        .tint(Theme.accent)
        #endif
    }

    private func controlButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button {
            action()
            showControls()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: Metrics.s(22), weight: .semibold))
                .foregroundStyle(Color.white)
                .frame(minWidth: Metrics.s(34), minHeight: Metrics.s(34))
        }
        .accessibilityLabel(label)
        #if !os(tvOS)
        .buttonStyle(.plain)
        #endif
    }

    private func menuIcon(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: Metrics.s(22), weight: .semibold))
            .foregroundStyle(Color.white)
            .frame(minWidth: Metrics.s(34), minHeight: Metrics.s(34))
    }

    private var audioMenu: some View {
        let tracks = model.audioTracks.filter { $0.id >= 0 }
        return Menu {
            ForEach(tracks) { track in
                Button {
                    model.selectAudio(track.id)
                    showControls()
                } label: {
                    if model.audioIndex == track.id {
                        Label(track.name, systemImage: "checkmark")
                    } else {
                        Text(track.name)
                    }
                }
            }
        } label: {
            menuIcon("waveform")
        }
        .disabled(tracks.count < 2)
        .accessibilityLabel("Audio")
    }

    /// One menu for both kinds of subtitles: the ones inside the file (including image subtitles
    /// that only VLC can draw) and the files CasaPlay found or downloaded.
    private var subtitleMenu: some View {
        let embedded = model.subtitleTracks.filter { $0.id >= 0 }
        let files = app.subtitleOptions(for: item.id)
        let activeFile = app.activeSubtitle(for: item.id)
        let isOff = model.subtitleIndex == -1 && activeFile == nil
        return Menu {
            Button {
                model.selectSubtitle(-1)
                app.selectSubtitle(nil, for: item.id)
                showControls()
            } label: {
                if isOff { Label("Off", systemImage: "checkmark") } else { Text("Off") }
            }
            ForEach(files) { option in
                Button {
                    model.selectSubtitle(-1)
                    app.selectSubtitle(option.id, for: item.id)
                    showControls()
                } label: {
                    if activeFile?.id == option.id && model.subtitleIndex == -1 {
                        Label(option.track.displayName, systemImage: "checkmark")
                    } else {
                        Text(option.track.displayName)
                    }
                }
            }
            ForEach(embedded) { track in
                Button {
                    app.selectSubtitle(nil, for: item.id)
                    model.selectSubtitle(track.id)
                    showControls()
                } label: {
                    if model.subtitleIndex == track.id {
                        Label(track.name, systemImage: "checkmark")
                    } else {
                        Text(track.name)
                    }
                }
            }
        } label: {
            menuIcon(isOff ? "captions.bubble" : "captions.bubble.fill")
        }
        .disabled(embedded.isEmpty && files.isEmpty)
        .accessibilityLabel("Subtitles")
    }

    private static func clock(_ seconds: TimeInterval) -> String {
        let total = max(Int(seconds.isFinite ? seconds : 0), 0)
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let secs = total % 60
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, secs)
            : String(format: "%d:%02d", minutes, secs)
    }
}
