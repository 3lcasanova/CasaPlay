// CasaPlay · Designed by 𝐂𝓪sΔηⓞשα
//
// Two engines. Files Apple's player can open use AVPlayerViewController, so Apple TV gets the
// native transport bar, subtitle and audio menus, HDR and Dolby Vision switching for free.
// Everything else (MKV, AVI, WebM, DTS, TrueHD, PGS subtitles...) goes to AetherPlayerScreen, which decodes
// on the Apple hardware and also switches the TV into HDR10 or Dolby Vision.

import SwiftUI
import AVKit
import CasaPlayKit

struct PlayerScreen: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    let item: MediaItem

    var body: some View {
        let decision = app.router.decide(for: item.file)
        // Files Apple's player can't open, which the Aether player draws with its own controls.
        let ownPlayer = decision.engine == .compatibility

        ZStack {
            Color.black.ignoresSafeArea()

            if decision.engine == .apple || decision.engine == .appleViaServerStream {
                if let url = item.streamURL {
                    AVPlayerControllerView(
                        url: url,
                        title: item.title,
                        startAt: item.canResume ? item.progressSeconds : 0,
                        subtitle: app.activeSubtitle(for: item.id),
                        subtitleOptions: app.subtitleOptions(for: item.id),
                        subtitleStyle: app.subtitleStyle,
                        onSelectSubtitle: { trackID in
                            app.selectSubtitle(trackID, for: item.id)
                        },
                        onProgress: { seconds in
                            app.updateProgress(id: item.id, seconds: seconds)
                        },
                        streamHeaders: item.streamHeaders,
                        onEnded: { app.playNextEpisode(after: item) }
                    )
                    .ignoresSafeArea()
                } else {
                    message(
                        title: "No source yet",
                        detail: "This title has no playable address. Connect a source to play it."
                    )
                }
            } else if ownPlayer {
                if let url = item.streamURL {
                    AetherPlayerScreen(item: item, url: url)
                        .ignoresSafeArea()
                } else {
                    message(
                        title: "No source yet",
                        detail: "This title has no playable address. Connect a source to play it."
                    )
                }
            } else {
                message(
                    title: "Can't play this file yet",
                    detail: decision.reasons.joined(separator: " · ")
                )
            }

            overlayLayout(ownPlayer: ownPlayer)

            if let target = app.upNext {
                UpNextCard(target: target,
                           onPlay: { app.startUpNext() },
                           onCancel: { app.cancelUpNext() })
                    .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.2), value: app.upNext?.id)
    }

    // MARK: Overlay

    /// Close button at the top. At the bottom, one row: what is happening (buffering, subtitle making) on the
    /// left and the subtitle button on the right, sitting just above where the player's own controls appear.
    private func overlayLayout(ownPlayer: Bool) -> some View {
        VStack(spacing: 0) {
            #if !os(tvOS)
            HStack {
                Button {
                    dismiss()
                } label: {
                    PlayerGlassIcon(systemName: "xmark", size: 42)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close player")
                Spacer()
            }
            .padding()
            #endif

            Spacer()

            HStack(alignment: .bottom, spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    if let url = item.streamURL, let parsed = TorrentResourceLoader.parse(url) {
                        TorrentPlaybackStatus(hash: parsed.0)
                    }
                    #if !os(tvOS)
                    NihonSubStatusPill(itemID: item.id)
                    #endif
                }
                Spacer(minLength: 12)
                #if !os(tvOS)
                // The Aether player has its own subtitle menu.
                if !ownPlayer { subtitleMenu }
                #endif
            }
            .padding(.horizontal, Platform.isTV ? 80 : 20)
            .padding(.bottom, bottomInset(ownPlayer: ownPlayer))
        }
    }

    /// How far above the bottom edge the row sits, so it clears the player's controls.
    private func bottomInset(ownPlayer: Bool) -> CGFloat {
        #if os(tvOS)
        return ownPlayer ? 300 : 240
        #else
        return ownPlayer ? 190 : 84
        #endif
    }

    #if !os(tvOS)
    /// iPhone and iPad: CasaPlay's subtitle tracks. Subtitles inside the video stay in the player's own menu.
    @ViewBuilder private var subtitleMenu: some View {
        let options = app.subtitleOptions(for: item.id)
        // Hidden until there is something to pick, unless NihonSub can make subtitles.
        if !options.isEmpty || app.nihonSubClient != nil {
            subtitleMenuButton(options: options)
        }
    }

    private func subtitleMenuButton(options: [LoadedSubtitle]) -> some View {
        let active = app.activeSubtitle(for: item.id)
        return Menu {
            Button {
                app.selectSubtitle(nil, for: item.id)
            } label: {
                if active == nil { Label("Off", systemImage: "checkmark") } else { Text("Off") }
            }
            ForEach(options) { option in
                Button {
                    app.selectSubtitle(option.id, for: item.id)
                } label: {
                    if active?.id == option.id {
                        Label(option.track.displayName, systemImage: "checkmark")
                    } else {
                        Text(option.track.displayName)
                    }
                }
            }
            nihonSubMenuItems(app: app, item: item)
        } label: {
            PlayerGlassIcon(systemName: active == nil ? "captions.bubble" : "captions.bubble.fill",
                            tint: active == nil ? Color.white : Theme.accent,
                            size: 46)
        }
        .accessibilityLabel("Subtitles")
    }
    #endif

    private func message(title: String, detail: String) -> some View {
        VStack(spacing: Metrics.s(10)) {
            Image(systemName: "film")
                .font(.system(size: Metrics.s(36)))
                .foregroundStyle(Theme.accent)
            Text(title)
                .font(.casa(19, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Text(detail)
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
}

/// Wraps AVPlayerViewController. Reports the playback position every 5 seconds
/// and once more when the player goes away, so "Continue Watching" stays accurate.
/// CasaPlay's own subtitles are drawn in the player's content overlay, under the controls.
struct AVPlayerControllerView: UIViewControllerRepresentable {
    let url: URL
    let title: String
    let startAt: TimeInterval
    let subtitle: LoadedSubtitle?
    let subtitleOptions: [LoadedSubtitle]
    let subtitleStyle: SubtitleStyle
    let onSelectSubtitle: (String?) -> Void
    let onProgress: (TimeInterval) -> Void
    var streamHeaders: [String: String]? = nil
    /// The video played to its end.
    var onEnded: (() -> Void)? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator(onProgress: onProgress)
    }

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)

        let playerItem: AVPlayerItem
        if url.scheme == TorrentResourceLoader.scheme {
            // Torrent: AVPlayer reads byte ranges through CasaPlay's resource loader.
            let asset = AVURLAsset(url: url)
            let loader = TorrentResourceLoader()
            asset.resourceLoader.setDelegate(loader, queue: loader.queue)
            context.coordinator.torrentLoader = loader  // the asset only keeps a weak reference
            playerItem = AVPlayerItem(asset: asset)
        } else if let headers = streamHeaders, !headers.isEmpty {
            // Stremio proxyHeaders: inject via AVURLAsset HTTP options (undocumented key).
            var options: [String: Any] = [:]
            options["AVURLAssetHTTPHeaderFieldsKey"] = headers
            let asset = AVURLAsset(url: url, options: options)
            playerItem = AVPlayerItem(asset: asset)
        } else {
            playerItem = AVPlayerItem(url: url)
        }

        let titleMetadata = AVMutableMetadataItem()
        titleMetadata.identifier = .commonIdentifierTitle
        titleMetadata.value = title as NSString
        titleMetadata.extendedLanguageTag = "und"
        playerItem.externalMetadata = [titleMetadata]

        let player = AVPlayer(playerItem: playerItem)
        let controller = AVPlayerViewController()
        controller.player = player
        #if os(tvOS)
        controller.appliesPreferredDisplayCriteriaAutomatically = true
        #endif

        // Subtitle overlay.
        let coordinator = context.coordinator
        let overlay = UIHostingController(rootView: SubtitleOverlayView(model: coordinator.overlay))
        overlay.view.backgroundColor = .clear
        overlay.view.isUserInteractionEnabled = false
        if let host = controller.contentOverlayView {
            controller.addChild(overlay)
            overlay.view.frame = host.bounds
            overlay.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            host.addSubview(overlay.view)
            overlay.didMove(toParent: controller)
        }
        apply(to: controller, coordinator: coordinator)

        if startAt > 1 {
            player.seek(
                to: CMTime(seconds: startAt, preferredTimescale: 600),
                toleranceBefore: .zero,
                toleranceAfter: .zero
            )
        }

        let progressToken = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 5, preferredTimescale: 1),
            queue: .main
        ) { time in
            coordinator.report(time)
        }
        let subtitleToken = player.addPeriodicTimeObserver(
            forInterval: CMTime(value: 1, timescale: 10),
            queue: .main
        ) { time in
            coordinator.tick(time)
        }
        coordinator.onEnded = onEnded
        coordinator.watchForEnd(of: playerItem)
        coordinator.attach(player: player, tokens: [progressToken, subtitleToken])
        coordinator.watchForFailure(of: playerItem, in: controller, isTorrent: url.scheme == TorrentResourceLoader.scheme)

        player.play()
        return controller
    }

    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
        context.coordinator.onProgress = onProgress
        context.coordinator.onEnded = onEnded
        apply(to: uiViewController, coordinator: context.coordinator)
    }

    private func apply(to controller: AVPlayerViewController, coordinator: Coordinator) {
        coordinator.overlay.style = subtitleStyle
        coordinator.overlay.setTrack(subtitle)

        #if os(tvOS)
        // tvOS: a Subtitles menu in the transport bar, next to Apple's own audio and subtitle menus.
        guard !subtitleOptions.isEmpty else {
            controller.transportBarCustomMenuItems = []
            return
        }
        let select = onSelectSubtitle
        let activeID = subtitle?.id
        var actions: [UIMenuElement] = [
            UIAction(title: "Off", state: activeID == nil ? .on : .off) { _ in select(nil) }
        ]
        for option in subtitleOptions {
            actions.append(UIAction(title: option.track.displayName, state: activeID == option.id ? .on : .off) { _ in
                select(option.id)
            })
        }
        controller.transportBarCustomMenuItems = [
            UIMenu(
                title: "CasaPlay Subtitles",
                image: UIImage(systemName: "captions.bubble"),
                options: [.singleSelection],
                children: actions
            )
        ]
        #endif
    }

    static func dismantleUIViewController(_ uiViewController: AVPlayerViewController, coordinator: Coordinator) {
        coordinator.stop()
    }

    final class Coordinator {
        var onProgress: (TimeInterval) -> Void
        var onEnded: (() -> Void)?
        private var endObserver: NSObjectProtocol?
        let overlay = SubtitleOverlayModel()
        var torrentLoader: TorrentResourceLoader?
        private var player: AVPlayer?
        private var tokens: [Any] = []

        init(onProgress: @escaping (TimeInterval) -> Void) {
            self.onProgress = onProgress
        }

        func attach(player: AVPlayer, tokens: [Any]) {
            self.player = player
            self.tokens = tokens
        }

        private var statusObservation: NSKeyValueObservation?
        private var failureObserver: NSObjectProtocol?
        private var didReportFailure = false

        /// Says why playback stopped. Without this a stream that can't be opened, or a torrent
        /// that stops sending data, just left a black screen.
        func watchForFailure(of item: AVPlayerItem, in controller: AVPlayerViewController, isTorrent: Bool) {
            let report: (Error?) -> Void = { [weak self, weak controller] error in
                DispatchQueue.main.async {
                    guard let self, let controller, !self.didReportFailure else { return }
                    self.didReportFailure = true
                    // For a torrent the engine knows the real reason; AVPlayer only reports
                    // "The operation could not be completed".
                    let engineReason = self.torrentLoader?.lastFailureMessage
                    let reason = engineReason ?? (error as NSError?)?.localizedDescription ?? "The stream could not be opened."
                    let hint = engineReason != nil ? ""
                        : isTorrent
                        ? "\n\nThe torrent may have no reachable peers or sources right now, or the file may be in a format Apple's player can't read."
                        : "\n\nThe link may have expired, or the file may be in a format Apple's player can't read."
                    let alert = UIAlertController(title: "Can't play this", message: reason + hint, preferredStyle: .alert)
                    alert.addAction(UIAlertAction(title: "OK", style: .default))
                    controller.present(alert, animated: true)
                }
            }
            statusObservation = item.observe(\.status, options: [.new]) { item, _ in
                if item.status == .failed { report(item.error) }
            }
            failureObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemFailedToPlayToEndTime, object: item, queue: .main
            ) { note in
                report(note.userInfo?[AVPlayerItemFailedToPlayToEndTimeErrorKey] as? Error)
            }
        }

        func watchForEnd(of item: AVPlayerItem) {
            endObserver = NotificationCenter.default.addObserver(
                forName: .AVPlayerItemDidPlayToEndTime, object: item, queue: .main
            ) { [weak self] _ in self?.onEnded?() }
        }

        func report(_ time: CMTime) {
            let seconds = time.seconds
            guard seconds.isFinite, seconds > 0 else { return }
            onProgress(seconds)
        }

        func tick(_ time: CMTime) {
            let seconds = time.seconds
            guard seconds.isFinite else { return }
            overlay.time = seconds
        }

        func stop() {
            guard let player else { return }
            report(player.currentTime())
            for token in tokens {
                player.removeTimeObserver(token)
            }
            player.pause()
            torrentLoader?.cancelAll()
            torrentLoader = nil
            statusObservation?.invalidate()
            statusObservation = nil
            if let failureObserver { NotificationCenter.default.removeObserver(failureObserver) }
            failureObserver = nil
            if let endObserver { NotificationCenter.default.removeObserver(endObserver) }
            endObserver = nil
            self.player = nil
            self.tokens = []
        }
    }
}


// MARK: - Next episode

/// Shown when an episode ends: the next one starts after a short countdown unless the viewer cancels.
private struct UpNextCard: View {
    let target: NextEpisodeTarget
    let onPlay: () -> Void
    let onCancel: () -> Void

    @State private var seconds = 8
    @FocusState private var focused: Bool

    var body: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                VStack(alignment: .leading, spacing: 12) {
                    Text("Up next")
                        .font(.casa(13, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.8))
                    Text(verbatim: "S\(target.season) · E\(target.number)" + (target.name.isEmpty ? "" : " · \(target.name)"))
                        .font(.casa(18, weight: .bold))
                        .foregroundStyle(Color.white)
                        .lineLimit(2)
                    Text("Playing in \(seconds)")
                        .font(.casa(14))
                        .foregroundStyle(Color.white.opacity(0.9))
                    HStack(spacing: 12) {
                        Button(action: onPlay) { Text("Next Episode").frame(minWidth: 140) }
                            .focused($focused)
                        Button(action: onCancel) { Text("Cancel") }
                    }
                }
                .padding(24)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                .tvFocusSection()
            }
            .padding(.horizontal, Platform.isTV ? 80 : 20)
            .padding(.bottom, Platform.isTV ? 120 : 60)
        }
        .onAppear { focused = true }
        .task(id: target.id) {
            seconds = 8
            while seconds > 0 {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if Task.isCancelled { return }
                seconds -= 1
            }
            onPlay()
        }
        #if os(tvOS)
        .onExitCommand(perform: onCancel)
        #endif
    }
}
