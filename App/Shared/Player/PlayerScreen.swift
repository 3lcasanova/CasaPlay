// CasaPlay · Designed by 𝐂𝓪sΔηⓞשα
//
// Phase 1 player: Apple's own AVPlayerViewController, so Apple TV gets the native
// transport bar, subtitle and audio menus, HDR and Dolby Vision switching for free.

import SwiftUI
import AVKit
import CasaPlayKit

struct PlayerScreen: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    let item: MediaItem

    private var playbackURL: URL? {
        if let url = item.streamURL { return url }
        #if DEBUG
        // Lets the player be tried before a real source exists. Not shipped in release builds.
        return DevStreams.appleBipBop
        #else
        return nil
        #endif
    }

    var body: some View {
        let decision = app.router.decide(for: item.file)

        ZStack {
            Color.black.ignoresSafeArea()

            if decision.engine == .apple || decision.engine == .appleViaServerStream {
                if let url = playbackURL {
                    AVPlayerControllerView(
                        url: url,
                        title: item.title,
                        startAt: item.canResume ? item.progressSeconds : 0,
                        onProgress: { seconds in
                            app.updateProgress(id: item.id, seconds: seconds)
                        }
                    )
                    .ignoresSafeArea()
                } else {
                    message(
                        title: "No source yet",
                        detail: "This title has no playable address. Connect a source to play it."
                    )
                }
            } else if decision.engine == .compatibility {
                message(
                    title: "Needs the compatibility engine",
                    detail: "This file needs the compatibility player, which is planned for a later phase."
                )
            } else {
                message(
                    title: "Can't play this file yet",
                    detail: decision.reasons.joined(separator: " · ")
                )
            }

            #if !os(tvOS)
            VStack {
                HStack {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 30))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(Color.white, Color.black.opacity(0.55))
                    }
                    .accessibilityLabel("Close player")
                    Spacer()
                }
                .padding()
                Spacer()
            }
            #endif
        }
    }

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
struct AVPlayerControllerView: UIViewControllerRepresentable {
    let url: URL
    let title: String
    let startAt: TimeInterval
    let onProgress: (TimeInterval) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onProgress: onProgress)
    }

    func makeUIViewController(context: Context) -> AVPlayerViewController {
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)

        let playerItem = AVPlayerItem(url: url)

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

        if startAt > 1 {
            player.seek(
                to: CMTime(seconds: startAt, preferredTimescale: 600),
                toleranceBefore: .zero,
                toleranceAfter: .zero
            )
        }

        let coordinator = context.coordinator
        let token = player.addPeriodicTimeObserver(
            forInterval: CMTime(seconds: 5, preferredTimescale: 1),
            queue: .main
        ) { time in
            coordinator.report(time)
        }
        coordinator.attach(player: player, token: token)

        player.play()
        return controller
    }

    func updateUIViewController(_ uiViewController: AVPlayerViewController, context: Context) {
        context.coordinator.onProgress = onProgress
    }

    static func dismantleUIViewController(_ uiViewController: AVPlayerViewController, coordinator: Coordinator) {
        coordinator.stop()
    }

    final class Coordinator {
        var onProgress: (TimeInterval) -> Void
        private var player: AVPlayer?
        private var token: Any?

        init(onProgress: @escaping (TimeInterval) -> Void) {
            self.onProgress = onProgress
        }

        func attach(player: AVPlayer, token: Any) {
            self.player = player
            self.token = token
        }

        func report(_ time: CMTime) {
            let seconds = time.seconds
            guard seconds.isFinite, seconds > 0 else { return }
            onProgress(seconds)
        }

        func stop() {
            guard let player else { return }
            report(player.currentTime())
            if let token {
                player.removeTimeObserver(token)
            }
            player.pause()
            self.player = nil
            self.token = nil
        }
    }
}
