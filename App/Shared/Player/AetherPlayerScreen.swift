// CasaPlay · Designed by 𝐂𝓪sΔηⓞשα
//
// The Aether player. It plays what Apple's player can't open (MKV, WebM, AVI, DTS, TrueHD, PGS subtitles) and,
// unlike VLC, switches the TV into HDR10 or Dolby Vision. The engine draws only the picture, so this file adds the
// controls, the audio and subtitle menus, resume, and CasaPlay's own subtitle overlay. If Aether can't open a file,
// the VLC player takes it (unless the setting says Aether only).

import SwiftUI
import AVFoundation
import CasaPlayKit

// MARK: - Subtitles inside the file

/// The subtitles that are part of the video file: words in CasaPlay's subtitle style, or the picture for
/// image subtitles (PGS, DVD).
private struct AetherSubtitleLayer: View {
    let cues: [AetherCue]
    let style: SubtitleStyle

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                ForEach(cues.filter { $0.image != nil }) { cue in
                    imageView(cue, in: proxy.size)
                }
                let lines = cues.compactMap(\.text)
                if !lines.isEmpty {
                    VStack {
                        if style.position == .bottom { Spacer() }
                        SubtitleText(text: lines.joined(separator: "\n"), style: style,
                                     baseSize: max(proxy.size.height * 0.045, 14))
                            .frame(maxWidth: proxy.size.width * 0.86)
                        if style.position == .top { Spacer() }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, proxy.size.height * 0.08)
                }
            }
        }
        .allowsHitTesting(false)
    }

    /// An image subtitle is laid out on the video's own canvas, so it is scaled to the picture like the video is.
    @ViewBuilder
    private func imageView(_ cue: AetherCue, in size: CGSize) -> some View {
        if let image = cue.image {
            let canvas = cue.canvas.width > 0 && cue.canvas.height > 0 ? cue.canvas : CGSize(width: 1920, height: 1080)
            let scale = min(size.width / canvas.width, size.height / canvas.height)
            let originX = (size.width - canvas.width * scale) / 2
            let originY = (size.height - canvas.height * scale) / 2
            Image(decorative: image, scale: 1)
                .resizable()
                .frame(width: cue.rect.width * scale, height: cue.rect.height * scale)
                .position(x: originX + (cue.rect.minX + cue.rect.width / 2) * scale,
                          y: originY + (cue.rect.minY + cue.rect.height / 2) * scale)
        }
    }
}

// MARK: - Screen

struct AetherPlayerScreen: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    let item: MediaItem
    let url: URL
    /// True when VLC should take over by itself if Aether can't open the file.
    let fallsBackToVLC: Bool
    /// Hands this file to the VLC player instead.
    let onUseVLC: () -> Void

    private enum Focus: Hashable { case surface, playPause, row(String) }

    #if os(tvOS)
    /// The audio and subtitle pickers on Apple TV. The system Menu froze open on screen here, so
    /// the player draws its own panel and controls exactly when it opens and closes.
    private enum TrackPanel { case audio, subtitles }
    #endif

    @State private var model = AetherPlayerModel()
    @State private var overlay = SubtitleOverlayModel()
    @State private var controlsVisible = true
    @State private var hideTask: Task<Void, Never>?
    @State private var scrub: Double?
    @FocusState private var focus: Focus?
    #if os(tvOS)
    @State private var trackPanel: TrackPanel?
    #endif

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            AetherVideoSurface(model: model).ignoresSafeArea()
            AetherSubtitleLayer(cues: model.cues, style: app.subtitleStyle)
            SubtitleOverlayView(model: overlay)
            inputLayer
            statusLayer
            if controlsVisible {
                controls.transition(.opacity)
            }
            #if os(tvOS)
            if let panel = trackPanel {
                trackPanelView(panel).transition(.opacity)
            }
            #endif
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
        .onChange(of: app.activeSubtitle(for: item.id)?.id) { _, newValue in
            syncSubtitles()
            // A downloaded file that starts showing must not double up with a track inside the video.
            if newValue != nil, model.subtitleIndex != -1 { model.selectSubtitle(-1) }
        }
        #if os(tvOS)
        .onPlayPauseCommand { model.togglePlay(); showControls() }
        .onExitCommand {
            // Menu closes an open picker first, then hides the controls, then leaves the player.
            if trackPanel != nil { closeTrackPanel(); return }
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
        // When Aether can't open the file, VLC plays it instead.
        let fallBack = fallsBackToVLC
        let useVLC = onUseVLC
        model.onFailure = { _ in
            if fallBack { useVLC() }
        }
        await model.open(
            url: url,
            headers: item.streamHeaders,
            startAt: item.canResume ? item.progressSeconds : 0
        )
    }

    private func syncSubtitles() {
        overlay.style = app.subtitleStyle
        overlay.setTrack(app.activeSubtitle(for: item.id))
        model.subtitleDelay = app.subtitleStyle.delay
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
            #if os(tvOS)
            guard trackPanel == nil else { return }
            #endif
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
                #if !os(tvOS)
                .controlSize(.large)
                #endif
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
                HStack(spacing: Metrics.s(10)) {
                    Text(item.title)
                        .font(.casa(17, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    if let format = model.formatLabel {
                        Text(format.uppercased())
                            .font(.casa(11, weight: .bold))
                            .foregroundStyle(Theme.textPrimary)
                            .padding(.horizontal, Metrics.s(8))
                            .padding(.vertical, Metrics.s(3))
                            .background(Color.white.opacity(0.2), in: Capsule())
                    }
                    Spacer(minLength: 0)
                }
                progressBar
                HStack {
                    Text(Self.clock(shown))
                    Spacer()
                    if model.duration > 0 { Text("-" + Self.clock(max(model.duration - shown, 0))) }
                }
                .font(.casa(12))
                .foregroundStyle(Theme.textSecondary)
                #if os(tvOS)
                if trackPanel == nil { buttonRow }
                #else
                buttonRow
                #endif
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

    private var buttonRow: some View {
        HStack(spacing: Metrics.s(24)) {
            controlButton("gobackward.10", label: "Back 10 seconds") { model.skip(-10) }
            controlButton(model.isPlaying ? "pause.fill" : "play.fill",
                          label: model.isPlaying ? "Pause" : "Play") { model.togglePlay() }
                .focused($focus, equals: .playPause)
            controlButton("goforward.10", label: "Forward 10 seconds") { model.skip(10) }
            Spacer()
            controlButton("arrow.triangle.2.circlepath", label: "Play with VLC instead") { onUseVLC() }
            #if os(tvOS)
            trackButton("waveform", label: "Audio", panel: .audio,
                        enabled: model.audioTracks.filter { $0.id >= 0 }.count > 1)
            trackButton(subtitlesAreOn ? "captions.bubble.fill" : "captions.bubble", label: "Subtitles", panel: .subtitles,
                        enabled: !model.subtitleTracks.filter { $0.id >= 0 }.isEmpty
                            || !app.subtitleOptions(for: item.id).isEmpty)
            #else
            audioMenu
            subtitleMenu
            #endif
        }
    }

    #if os(tvOS)
    private var subtitlesAreOn: Bool {
        model.subtitleIndex != -1 || app.activeSubtitle(for: item.id) != nil
    }

    private struct TrackRow: Identifiable {
        let id: String
        let title: String
        let selected: Bool
        let action: () -> Void
    }

    private func trackButton(_ symbol: String, label: String, panel: TrackPanel, enabled: Bool) -> some View {
        Button {
            hideTask?.cancel()
            trackPanel = panel
        } label: {
            menuIcon(symbol)
        }
        .disabled(!enabled)
        .accessibilityLabel(label)
    }

    private var audioRows: [TrackRow] {
        model.audioTracks.filter { $0.id >= 0 }.map { track in
            TrackRow(id: "audio-\(track.id)", title: track.name, selected: model.audioIndex == track.id) {
                model.selectAudio(track.id)
            }
        }
    }

    private var subtitleRows: [TrackRow] {
        let activeFile = app.activeSubtitle(for: item.id)
        let isOff = model.subtitleIndex == -1 && activeFile == nil
        var rows = [TrackRow(id: "sub-off", title: "Off", selected: isOff) {
            model.selectSubtitle(-1)
            app.selectSubtitle(nil, for: item.id)
        }]
        for option in app.subtitleOptions(for: item.id) {
            rows.append(TrackRow(
                id: "sub-file-\(option.id)",
                title: option.track.displayName,
                selected: activeFile?.id == option.id && model.subtitleIndex == -1
            ) {
                model.selectSubtitle(-1)
                app.selectSubtitle(option.id, for: item.id)
            })
        }
        for track in model.subtitleTracks where track.id >= 0 {
            rows.append(TrackRow(id: "sub-in-\(track.id)", title: track.name, selected: model.subtitleIndex == track.id) {
                app.selectSubtitle(nil, for: item.id)
                model.selectSubtitle(track.id)
            })
        }
        return rows
    }

    private func trackPanelView(_ panel: TrackPanel) -> some View {
        let rows = panel == .audio ? audioRows : subtitleRows
        return VStack(alignment: .leading, spacing: Metrics.s(12)) {
            Text(panel == .audio ? "Audio" : "Subtitles")
                .font(.casa(15, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
                .padding(.horizontal, Metrics.s(16))
            ScrollView {
                VStack(spacing: Metrics.s(6)) {
                    ForEach(rows) { row in
                        Button {
                            row.action()
                            closeTrackPanel()
                        } label: {
                            HStack(spacing: Metrics.s(12)) {
                                Image(systemName: "checkmark")
                                    .font(.system(size: Metrics.s(15), weight: .bold))
                                    .opacity(row.selected ? 1 : 0)
                                Text(row.title)
                                    .font(.casa(16, weight: .medium))
                                    .lineLimit(2)
                                    .multilineTextAlignment(.leading)
                                Spacer(minLength: 0)
                            }
                        }
                        .buttonStyle(AetherTrackRowStyle())
                        .focused($focus, equals: .row(row.id))
                    }
                }
                .padding(Metrics.s(6))
            }
        }
        .padding(Metrics.s(18))
        .frame(width: Metrics.s(520))
        .frame(maxHeight: Metrics.s(430))
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: Metrics.s(26), style: .continuous))
        .focusSection()
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        .padding(.trailing, Metrics.screenPadding)
        .padding(.bottom, Metrics.s(110))
        .onAppear {
            focus = .row(rows.first { $0.selected }?.id ?? rows.first?.id ?? "")
        }
    }

    private func closeTrackPanel() {
        trackPanel = nil
        Task { showControls(focusPlayPause: true) }
    }
    #endif

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

    /// One menu for both kinds of subtitles: the ones inside the file (including image subtitles)
    /// and the files CasaPlay found or downloaded.
    private var subtitleMenu: some View {
        let embedded = model.subtitleTracks.filter { $0.id >= 0 }
        let files = app.subtitleOptions(for: item.id)
        let activeFile = app.activeSubtitle(for: item.id)
        let isOff = model.subtitleIndex == -1 && activeFile == nil
        #if os(tvOS)
        let canMakeSubtitles = false
        #else
        let canMakeSubtitles = app.nihonSubClient != nil
        #endif
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
            #if !os(tvOS)
            nihonSubMenuItems(app: app, item: item)
            #endif
        } label: {
            menuIcon(isOff ? "captions.bubble" : "captions.bubble.fill")
        }
        .disabled(embedded.isEmpty && files.isEmpty && !canMakeSubtitles)
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

#if os(tvOS)
/// A row in the Apple TV audio and subtitle picker: light pill while focused.
private struct AetherTrackRowStyle: ButtonStyle {
    func makeBody(configuration: ButtonStyleConfiguration) -> some View {
        AetherTrackRowLabel(configuration: configuration)
    }
}

private struct AetherTrackRowLabel: View {
    let configuration: ButtonStyleConfiguration
    @Environment(\.isFocused) private var focused

    var body: some View {
        configuration.label
            .padding(.horizontal, 18)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(focused ? Color.black : Color.white)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(focused ? Color.white.opacity(0.92) : Color.clear)
            )
            .scaleEffect(focused ? 1.03 : 1)
            .animation(.easeOut(duration: 0.15), value: focused)
    }
}
#endif
