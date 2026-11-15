// CasaPlay · Designed by 𝐂𝓪sΔηⓞשα
//
// The link to the Aether engine (FFmpeg opens the file, VideoToolbox decodes, AVPlayer shows the picture and
// switches the TV into HDR10 or Dolby Vision). This is the only file that imports AetherEngine. The engine and
// CasaPlayKit both define types called SubtitleCue and TrackInfo, so keeping them in separate files keeps the
// names from clashing. Everything that leaves this file is a plain type.

import SwiftUI
import AVFoundation
import Combine
import AetherEngine

// MARK: - Plain types

struct AetherTrack: Identifiable, Hashable {
    /// The engine's track number. Subtitles use -1 for "off".
    let id: Int
    let name: String
}

/// One subtitle on screen right now: words, or a picture (image subtitles such as PGS).
struct AetherCue: Identifiable {
    let id: Int
    let text: String?
    let image: CGImage?
    /// Where the picture sits on its canvas, and the size of that canvas.
    let rect: CGRect
    let canvas: CGSize
}

// MARK: - Model

@MainActor
@Observable
final class AetherPlayerModel {
    enum Phase: Equatable {
        case loading, buffering, playing, paused, ended
        case failed(String)
    }

    private(set) var phase: Phase = .loading
    private(set) var seconds: TimeInterval = 0
    private(set) var duration: TimeInterval = 0
    private(set) var audioTracks: [AetherTrack] = []
    private(set) var subtitleTracks: [AetherTrack] = []
    private(set) var audioIndex = -1
    private(set) var subtitleIndex = -1
    private(set) var cues: [AetherCue] = []
    /// "Dolby Vision", "HDR10" and so on, once the picture is up. Nil for ordinary SDR.
    private(set) var formatLabel: String?
    private(set) var engine: AetherEngine?

    @ObservationIgnored var onProgress: ((TimeInterval) -> Void)?
    @ObservationIgnored var onTime: ((TimeInterval) -> Void)?
    /// Called once when the engine can't open or keep playing the file.
    @ObservationIgnored var onFailure: ((String) -> Void)?
    /// How far to shift embedded subtitles, in seconds (positive shows them later).
    @ObservationIgnored var subtitleDelay: TimeInterval = 0

    @ObservationIgnored private var bag = Set<AnyCancellable>()
    @ObservationIgnored private var allCues: [SubtitleCue] = []
    @ObservationIgnored private var sourceTime: TimeInterval = 0
    @ObservationIgnored private var lastReport = Date.distantPast
    @ObservationIgnored private var failedOnce = false
    @ObservationIgnored private var startGuard: Task<Void, Never>?
    @ObservationIgnored private var isTorrent = false

    /// A web stream that hasn't started by now is reported instead of spinning for ever. Torrents are left alone:
    /// finding peers can take a while, and the torrent engine reports its own failures.
    private static let startLimit: TimeInterval = 60

    // MARK: Opening

    /// Opens the stream. Torrent links are served over local HTTP first, because the engine reads web addresses.
    func open(url: URL, headers: [String: String]?, startAt: TimeInterval) async {
        phase = .loading
        try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .moviePlayback)

        var playable = url
        if url.scheme == TorrentResourceLoader.scheme {
            isTorrent = true
            do {
                playable = try await TorrentHTTPServer.shared.localURL(for: url)
            } catch {
                fail(error.localizedDescription)
                return
            }
        }
        guard !Task.isCancelled else { return }

        let player: AetherEngine
        do {
            player = try AetherEngine()
        } catch {
            fail("The Aether engine couldn't start: \(error.localizedDescription)")
            return
        }
        engine = player
        bind(player)

        // Let the picture view mount before the file loads.
        try? await Task.sleep(nanoseconds: 150_000_000)
        guard !Task.isCancelled else { return }

        if !isTorrent {
            startGuard = Task { [weak self] in
                try? await Task.sleep(nanoseconds: UInt64(Self.startLimit * 1_000_000_000))
                guard !Task.isCancelled, let self, self.phase == .loading else { return }
                self.fail("The stream didn't start in \(Int(Self.startLimit)) seconds.")
            }
        }

        var options = LoadOptions()
        if let headers, !headers.isEmpty { options.httpHeaders = headers }
        do {
            _ = try await player.load(url: playable, startPosition: startAt > 5 ? startAt : nil, options: options)
        } catch is CancellationError {
            return
        } catch {
            fail(error.localizedDescription)
        }
    }

    // MARK: Controls

    var isPlaying: Bool { phase == .playing || phase == .buffering }

    func togglePlay() { engine?.togglePlayPause() }

    func skip(_ amount: Double) {
        let target = min(max(seconds + amount, 0), duration > 0 ? max(duration - 1, 0) : seconds + amount)
        seek(to: target)
    }

    func seek(toFraction fraction: Double) {
        guard duration > 0 else { return }
        seek(to: min(max(fraction, 0), 1) * duration)
    }

    private func seek(to target: TimeInterval) {
        guard let engine else { return }
        Task { await engine.seek(to: target) }
    }

    func selectAudio(_ id: Int) {
        engine?.selectAudioTrack(index: id)
    }

    func selectSubtitle(_ id: Int) {
        guard let engine else { return }
        if id < 0 { engine.clearSubtitle() } else { engine.selectSubtitleTrack(index: id) }
    }

    func stop() {
        startGuard?.cancel()
        startGuard = nil
        if seconds > 0 { onProgress?(seconds) }
        onProgress = nil
        onTime = nil
        onFailure = nil
        bag.removeAll()
        engine?.stop()
        engine = nil
    }

    // MARK: Engine events

    private func bind(_ player: AetherEngine) {
        bag.removeAll()

        player.$playbackPhase
            .sink { [weak self] value in self?.phaseChanged(value) }
            .store(in: &bag)

        player.clock.$currentTime
            .sink { [weak self] value in self?.timeChanged(value) }
            .store(in: &bag)

        player.clock.$sourceTime
            .sink { [weak self] value in
                self?.sourceTime = value
                self?.refreshCues()
            }
            .store(in: &bag)

        player.$duration
            .sink { [weak self] value in
                if value.isFinite, value > 0 { self?.duration = value }
            }
            .store(in: &bag)

        player.$audioTracks
            .sink { [weak self] tracks in
                self?.audioTracks = tracks.map { AetherTrack(id: $0.id, name: Self.audioName($0)) }
            }
            .store(in: &bag)

        player.$activeAudioTrackIndex
            .sink { [weak self] value in self?.audioIndex = value ?? -1 }
            .store(in: &bag)

        player.$subtitleTracks
            .sink { [weak self] tracks in
                self?.subtitleTracks = tracks.map { AetherTrack(id: $0.id, name: Self.subtitleName($0)) }
            }
            .store(in: &bag)

        player.$activeSubtitleTrackIndex
            .combineLatest(player.$isSubtitleActive)
            .sink { [weak self] index, active in self?.subtitleIndex = active ? (index ?? -1) : -1 }
            .store(in: &bag)

        player.$subtitleCues
            .sink { [weak self] value in
                self?.allCues = value
                self?.refreshCues()
            }
            .store(in: &bag)

        player.$videoFormat
            .sink { [weak self] format in self?.formatLabel = Self.label(for: format) }
            .store(in: &bag)
    }

    private func phaseChanged(_ value: PlaybackPhase) {
        if case .failed = phase { return }
        switch value {
        case .idle, .loading:
            if phase != .playing { phase = .loading }
        case .playing:
            startGuard?.cancel()
            phase = .playing
        case .paused:
            startGuard?.cancel()
            phase = .paused
        case .seeking, .rebuffering, .stalled:
            phase = .buffering
        case .ended:
            phase = .ended
            if duration > 0 { onProgress?(duration) }
        case .error(let message):
            fail(message)
        }
    }

    private func timeChanged(_ value: TimeInterval) {
        guard value.isFinite else { return }
        seconds = max(value, 0)
        onTime?(seconds)
        if phase == .playing, seconds > 0, Date().timeIntervalSince(lastReport) >= 5 {
            lastReport = Date()
            onProgress?(seconds)
        }
    }

    private func refreshCues() {
        let now = sourceTime - subtitleDelay
        let active = allCues.filter { $0.startTime <= now && now < $0.endTime }
        // Only touch the screen when the set of subtitles actually changes.
        guard active.map(\.id) != cues.map(\.id) else { return }
        cues = active.map(Self.convert)
    }

    private func fail(_ message: String) {
        startGuard?.cancel()
        guard !failedOnce else { return }
        failedOnce = true
        phase = .failed(message)
        onFailure?(message)
    }

    // MARK: Names

    private static func convert(_ cue: SubtitleCue) -> AetherCue {
        if case .image(let image) = cue.body {
            return AetherCue(id: cue.id, text: nil, image: image.cgImage, rect: image.position, canvas: image.canvasSize)
        }
        return AetherCue(id: cue.id, text: cue.text, image: nil, rect: .zero, canvas: .zero)
    }

    private static func language(_ track: TrackInfo) -> String {
        if let code = track.language, !code.isEmpty,
           let name = Locale.current.localizedString(forLanguageCode: code), !name.isEmpty {
            return name.prefix(1).uppercased() + name.dropFirst()
        }
        return track.language ?? ""
    }

    private static func audioName(_ track: TrackInfo) -> String {
        var parts: [String] = []
        let base = track.name.isEmpty ? language(track) : track.name
        parts.append(base.isEmpty ? "Track \(track.id)" : base)
        if track.isAtmos {
            parts.append("Atmos")
        } else {
            switch track.channels {
            case 1: parts.append("Mono")
            case 2: parts.append("Stereo")
            case 6: parts.append("5.1")
            case 8: parts.append("7.1")
            default: break
            }
        }
        if !track.codec.isEmpty { parts.append(track.codec.uppercased()) }
        if track.isCommentary { parts.append("Commentary") }
        return parts.joined(separator: " · ")
    }

    private static func subtitleName(_ track: TrackInfo) -> String {
        var parts: [String] = []
        let base = track.name.isEmpty ? language(track) : track.name
        parts.append(base.isEmpty ? "Subtitle \(track.id)" : base)
        if track.isForced { parts.append("Forced") }
        if track.isHearingImpaired { parts.append("SDH") }
        return parts.joined(separator: " · ")
    }

    private static func label(for format: VideoFormat) -> String? {
        switch format {
        case .dolbyVision: return "Dolby Vision"
        case .hdr10Plus: return "HDR10+"
        case .hdr10: return "HDR10"
        case .hlg: return "HLG"
        default: return nil
        }
    }
}

// MARK: - Picture

/// The engine's own video layer. It switches the TV into HDR10 or Dolby Vision when the file needs it.
struct AetherVideoSurface: View {
    let model: AetherPlayerModel

    var body: some View {
        if let engine = model.engine {
            AetherPlayerSurface(engine: engine)
        } else {
            Color.black
        }
    }
}
