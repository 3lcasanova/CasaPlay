// CasaPlay · Designed by 𝐂𝓪sΔηⓞשα

import XCTest
@testable import CasaPlayKit

final class SubtitleTests: XCTestCase {
    private let srt = """
    1
    00:00:01,000 --> 00:00:03,500
    We don't have until dawn.

    2
    00:00:04,000 --> 00:00:06,000
    <i>Then we'd better decide</i>
    who's lying.
    """

    private let vtt = """
    WEBVTT - sample

    NOTE this is a comment

    intro
    00:01.000 --> 00:03.500 align:start
    We don't have until dawn.

    00:00:04.000 --> 00:00:06.000
    Then we'd better decide
    who's lying.
    """

    func testSRTParsing() {
        let cues = SRTParser.parse(srt)
        XCTAssertEqual(cues.count, 2)
        XCTAssertEqual(cues[0].start, 1.0, accuracy: 0.001)
        XCTAssertEqual(cues[0].end, 3.5, accuracy: 0.001)
        XCTAssertEqual(cues[0].text, "We don't have until dawn.")
        XCTAssertEqual(cues[1].text, "Then we'd better decide\nwho's lying.")
    }

    func testSRTHandlesWindowsLineEndingsAndBOM() {
        let windows = "\u{FEFF}" + srt.replacingOccurrences(of: "\n", with: "\r\n")
        XCTAssertEqual(SRTParser.parse(windows).count, 2)
    }

    func testWebVTTParsing() {
        let cues = WebVTTParser.parse(vtt)
        XCTAssertEqual(cues.count, 2)
        XCTAssertEqual(cues[0].start, 1.0, accuracy: 0.001)
        XCTAssertEqual(cues[0].end, 3.5, accuracy: 0.001)
        XCTAssertEqual(cues[1].start, 4.0, accuracy: 0.001)
    }

    func testSRTToWebVTTRoundTrip() {
        let original = SRTParser.parse(srt)
        let converted = WebVTTWriter.make(from: original)
        XCTAssertTrue(converted.hasPrefix("WEBVTT"))
        XCTAssertEqual(WebVTTParser.parse(converted), original)
    }

    func testTimelineAppliesDelay() {
        let timeline = SubtitleTimeline(cues: SRTParser.parse(srt))
        XCTAssertEqual(timeline.activeCues(at: 2.0).count, 1)
        XCTAssertEqual(timeline.activeCues(at: 3.8).count, 0)
        // Subtitles shifted 2 seconds later: the first cue now shows from 3.0 to 5.5.
        XCTAssertEqual(timeline.activeCues(at: 3.2, delay: 2.0).first?.text, "We don't have until dawn.")
        XCTAssertEqual(timeline.activeCues(at: 2.0, delay: 2.0).count, 0)
    }

    // MARK: Track selection

    private let tracks: [SubtitleTrack] = [
        SubtitleTrack(id: "en", languageCode: "en", displayName: "English", origin: .embedded, format: .tx3g),
        SubtitleTrack(id: "en-sdh", languageCode: "en", displayName: "English SDH", origin: .sidecar, format: .srt, isSDH: true),
        SubtitleTrack(id: "fr", languageCode: "fr-CA", displayName: "Français", origin: .embedded, format: .tx3g),
        SubtitleTrack(id: "fr-forced", languageCode: "fr", displayName: "Français (forced)", origin: .embedded, format: .tx3g, isForced: true)
    ]

    func testPicksFirstPreferredLanguage() {
        let pick = SubtitleSelector.defaultTrack(from: tracks, preferredLanguages: ["fr", "en"], audioLanguage: "en")
        XCTAssertEqual(pick?.id, "fr")
    }

    func testAudioInPreferredLanguageOnlyShowsForced() {
        let none = SubtitleSelector.defaultTrack(from: tracks, preferredLanguages: ["en"], audioLanguage: "en")
        XCTAssertNil(none)

        let forced = SubtitleSelector.defaultTrack(from: tracks, preferredLanguages: ["fr"], audioLanguage: "fr")
        XCTAssertEqual(forced?.id, "fr-forced")
    }

    func testPreferSDH() {
        let normal = SubtitleSelector.defaultTrack(from: tracks, preferredLanguages: ["en"], audioLanguage: "ja")
        XCTAssertEqual(normal?.id, "en")

        let sdh = SubtitleSelector.defaultTrack(from: tracks, preferredLanguages: ["en"], audioLanguage: "ja", preferSDH: true)
        XCTAssertEqual(sdh?.id, "en-sdh")
    }

    func testStyleDefaults() {
        let style = SubtitleStyle.default
        XCTAssertEqual(style.size, .large)
        XCTAssertEqual(style.delay, 0)
    }
}
