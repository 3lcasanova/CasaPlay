// CasaPlay · Designed by 𝐂𝓪sΔηⓞשα
//
// Plays a trailer inside CasaPlay on iPhone and iPad, instead of sending the viewer to the YouTube app.
// Trailers live on YouTube, and the way YouTube allows an app to show one is its own embedded player, so
// this screen is that player in a web view, full screen. YouTube's own buttons are switched off (its
// "controls" setting) and the picture takes no touches, so none of YouTube's boxes pop up over the trailer.
// CasaPlay draws the controls instead: close, back 10, play or pause, forward 10, and the time.
// It tries each trailer in turn (some can't be embedded) and closes by itself when the trailer ends.
//
// Apple TV has no web view, so this file is not built for tvOS.

#if !os(tvOS)
import SwiftUI
import WebKit
import CasaPlayKit

struct TrailerScreen: View {
    let title: String
    let trailers: [Trailer]

    @Environment(\.dismiss) private var dismiss
    @State private var phase: TrailerPhase = .loading
    @State private var remote = TrailerRemote()
    @State private var isPlaying = true
    @State private var current: Double = 0
    @State private var duration: Double = 0
    @State private var showsControls = true
    /// Changes each time the viewer touches the screen, which restarts the count before the controls hide.
    @State private var touches = 0

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            TrailerWebView(videoIDs: trailers.map(\.youTubeID), remote: remote) { event in
                switch event {
                case .ready:
                    phase = .playing
                case .failed:
                    phase = .failed
                case .ended:
                    dismiss()
                case .progress(let time, let length, let playing):
                    current = time
                    duration = length
                    isPlaying = playing
                }
            }
            .aspectRatio(16.0 / 9.0, contentMode: .fit)
            .opacity(phase == .playing ? 1 : 0)
            // The picture takes no touches: a tap on YouTube's player brings up YouTube's own boxes.
            .allowsHitTesting(false)

            // A tap anywhere shows or hides CasaPlay's controls.
            Color.clear
                .contentShape(Rectangle())
                .ignoresSafeArea()
                .onTapGesture {
                    showsControls.toggle()
                    touches += 1
                }

            switch phase {
            case .loading:
                ProgressView().tint(.white)
            case .failed:
                VStack(spacing: 10) {
                    Image(systemName: "play.slash")
                        .font(.system(size: 34))
                    Text("This trailer can't be played here")
                        .font(.headline)
                    Text("Check the internet connection and try again.")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.7))
                }
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .padding()
            case .playing:
                EmptyView()
            }
        }
        .overlay(alignment: .topLeading) {
            if showsControls || phase != .playing {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 44, height: 44)
                        .background(.white.opacity(0.16), in: Circle())
                }
                .padding(16)
                .accessibilityLabel("Close trailer")
            }
        }
        .overlay(alignment: .bottom) {
            if showsControls && phase == .playing { controls }
        }
        .animation(.easeInOut(duration: 0.2), value: showsControls)
        .task {
            // A page that never answers (no internet) would otherwise sit on the spinner.
            try? await Task.sleep(nanoseconds: 15_000_000_000)
            if phase == .loading { phase = .failed }
        }
        .task(id: ControlsTimer(touches: touches, isPlaying: isPlaying, phase: phase)) {
            // The controls step aside after a few quiet seconds of playing.
            guard phase == .playing, isPlaying, showsControls else { return }
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            if !Task.isCancelled { showsControls = false }
        }
        .preferredColorScheme(.dark)
        .statusBarHidden()
    }

    private var controls: some View {
        VStack(spacing: 14) {
            VStack(spacing: 6) {
                ProgressView(value: min(current, max(duration, 1)), total: max(duration, 1))
                    .tint(.white)
                HStack {
                    Text(TimeFormat.clock(current))
                    Spacer()
                    Text(TimeFormat.clock(duration))
                }
                .font(.caption.monospacedDigit())
                .foregroundStyle(.white.opacity(0.8))
            }

            HStack(spacing: 44) {
                controlButton("gobackward.10", label: "Back 10 seconds") { remote.skip(-10) }
                controlButton(isPlaying ? "pause.fill" : "play.fill", label: isPlaying ? "Pause" : "Play", size: 30) {
                    isPlaying.toggle()
                    remote.setPlaying(isPlaying)
                }
                controlButton("goforward.10", label: "Forward 10 seconds") { remote.skip(10) }
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 28)
        .frame(maxWidth: 560)
        .transition(.opacity)
    }

    private func controlButton(_ symbol: String, label: String, size: CGFloat = 24,
                               action: @escaping () -> Void) -> some View {
        Button {
            touches += 1
            action()
        } label: {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .contentShape(Rectangle())
        }
        .accessibilityLabel(label)
    }
}

private enum TrailerPhase {
    case loading, playing, failed
}

private struct ControlsTimer: Equatable {
    let touches: Int
    let isPlaying: Bool
    let phase: TrailerPhase
}

enum TrailerEvent {
    case ready, failed, ended
    case progress(time: Double, duration: Double, isPlaying: Bool)
}

/// CasaPlay's buttons talk to YouTube's player through this.
@MainActor
final class TrailerRemote {
    fileprivate weak var webView: WKWebView?

    func setPlaying(_ playing: Bool) {
        run(playing ? "casaPlay()" : "casaPause()")
    }

    func skip(_ seconds: Int) {
        run("casaSkip(\(seconds))")
    }

    private func run(_ script: String) {
        webView?.evaluateJavaScript(script, completionHandler: nil)
    }
}

private struct TrailerWebView: UIViewRepresentable {
    let videoIDs: [String]
    let remote: TrailerRemote
    let onEvent: (TrailerEvent) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onEvent: onEvent) }

    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.allowsInlineMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.userContentController.add(context.coordinator, name: "casa")

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.isOpaque = false
        webView.backgroundColor = .black
        webView.scrollView.backgroundColor = .black
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        remote.webView = webView

        // YouTube's player refuses to start unless the page says which app it belongs to, so the page gets
        // an address made from the app's own identifier.
        let identifier = (Bundle.main.bundleIdentifier ?? "com.casanova.CasaPlay").lowercased()
        let origin = "https://\(identifier)"
        webView.loadHTMLString(Self.page(videoIDs: videoIDs, origin: origin), baseURL: URL(string: origin))
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        context.coordinator.onEvent = onEvent
    }

    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        uiView.stopLoading()
        uiView.configuration.userContentController.removeScriptMessageHandler(forName: "casa")
        uiView.loadHTMLString("", baseURL: nil)
    }

    /// The page: YouTube's own player with its buttons off, told to play the first trailer and to move to the
    /// next if one fails. It reports the time twice a second so CasaPlay can draw the progress bar.
    /// The IDs were checked by `Trailer` (letters, digits, "-" and "_" only) before they reach this text.
    private static func page(videoIDs: [String], origin: String) -> String {
        let ids = videoIDs.filter(YouTubeLink.isValidID).map { "\"\($0)\"" }.joined(separator: ",")
        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=1">
        <meta name="referrer" content="strict-origin-when-cross-origin">
        <style>
          html, body { margin: 0; height: 100%; background: #000; overflow: hidden; }
          #player { position: absolute; top: 0; left: 0; width: 100%; height: 100%; }
        </style>
        </head>
        <body>
        <div id="player"></div>
        <script>
          var ids = [\(ids)];
          var at = 0;
          var player;
          function tell(word) {
            try { window.webkit.messageHandlers.casa.postMessage(word); } catch (e) {}
          }
          function casaPlay() { if (player && player.playVideo) { player.playVideo(); } }
          function casaPause() { if (player && player.pauseVideo) { player.pauseVideo(); } }
          function casaSkip(seconds) {
            if (!player || !player.getCurrentTime) { return; }
            var length = player.getDuration() || 0;
            var target = Math.max(0, player.getCurrentTime() + seconds);
            if (length > 0) { target = Math.min(target, Math.max(0, length - 1)); }
            player.seekTo(target, true);
          }
          function report() {
            if (!player || !player.getCurrentTime) { return; }
            var state = player.getPlayerState();
            var playing = (state === 1 || state === 3) ? 1 : 0;
            tell('time|' + (player.getCurrentTime() || 0) + '|' + (player.getDuration() || 0) + '|' + playing);
          }
          function onYouTubeIframeAPIReady() {
            if (ids.length === 0) { tell('failed'); return; }
            player = new YT.Player('player', {
              width: '100%',
              height: '100%',
              videoId: ids[0],
              playerVars: {
                autoplay: 1, playsinline: 1, rel: 0, controls: 0, fs: 0, disablekb: 1,
                iv_load_policy: 3, cc_load_policy: 0, origin: '\(origin)'
              },
              events: {
                onReady: function (event) {
                  event.target.playVideo();
                  tell('ready');
                  setInterval(report, 500);
                },
                onError: function () {
                  at += 1;
                  if (at < ids.length) { player.loadVideoById(ids[at]); } else { tell('failed'); }
                },
                onStateChange: function (event) {
                  if (event.data === 0) { tell('ended'); } else { report(); }
                }
              }
            });
          }
        </script>
        <script src="https://www.youtube.com/iframe_api" onerror="tell('failed')"></script>
        </body>
        </html>
        """
    }

    @MainActor
    final class Coordinator: NSObject, WKScriptMessageHandler {
        var onEvent: (TrailerEvent) -> Void

        init(onEvent: @escaping (TrailerEvent) -> Void) {
            self.onEvent = onEvent
        }

        func userContentController(_ userContentController: WKUserContentController,
                                   didReceive message: WKScriptMessage) {
            guard let text = message.body as? String else { return }
            switch text {
            case "ready": onEvent(.ready)
            case "failed": onEvent(.failed)
            case "ended": onEvent(.ended)
            default:
                let parts = text.split(separator: "|")
                guard parts.count == 4, parts[0] == "time",
                      let time = Double(parts[1]), let length = Double(parts[2]),
                      time.isFinite, length.isFinite else { return }
                onEvent(.progress(time: time, duration: length, isPlaying: parts[3] == "1"))
            }
        }
    }
}
#endif
