// CasaPlay · Designed by 𝐂𝓪sΔηⓞשα
//
// Plays a trailer inside CasaPlay on iPhone and iPad, instead of sending the viewer to the YouTube app.
// Trailers live on YouTube, and the way YouTube allows an app to show one is its own embedded player, so
// this screen is that player in a web view, full screen with a close button. It tries each trailer in turn
// (some can't be embedded) and closes by itself when the trailer ends.
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

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            TrailerWebView(videoIDs: trailers.map(\.youTubeID)) { event in
                switch event {
                case .ready: phase = .playing
                case .failed: phase = .failed
                case .ended: dismiss()
                }
            }
            .aspectRatio(16.0 / 9.0, contentMode: .fit)
            .opacity(phase == .playing ? 1 : 0)

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
        .task {
            // A page that never answers (no internet) would otherwise sit on the spinner.
            try? await Task.sleep(nanoseconds: 15_000_000_000)
            if phase == .loading { phase = .failed }
        }
        .preferredColorScheme(.dark)
        .accessibilityLabel("\(title) trailer")
    }
}

private enum TrailerPhase {
    case loading, playing, failed
}

enum TrailerEvent {
    case ready, failed, ended
}

private struct TrailerWebView: UIViewRepresentable {
    let videoIDs: [String]
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

    /// The page: YouTube's own player, told to play the first trailer and to move to the next if one fails.
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
          function onYouTubeIframeAPIReady() {
            if (ids.length === 0) { tell('failed'); return; }
            player = new YT.Player('player', {
              width: '100%',
              height: '100%',
              videoId: ids[0],
              playerVars: { autoplay: 1, playsinline: 1, rel: 0, origin: '\(origin)' },
              events: {
                onReady: function (event) { event.target.playVideo(); tell('ready'); },
                onError: function () {
                  at += 1;
                  if (at < ids.length) { player.loadVideoById(ids[at]); } else { tell('failed'); }
                },
                onStateChange: function (event) { if (event.data === 0) { tell('ended'); } }
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
            switch message.body as? String {
            case "ready": onEvent(.ready)
            case "failed": onEvent(.failed)
            case "ended": onEvent(.ended)
            default: break
            }
        }
    }
}
#endif
