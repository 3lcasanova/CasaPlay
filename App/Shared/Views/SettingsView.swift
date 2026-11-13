// CasaPlay · Designed by 𝐂𝓪sΔηⓞשα

import SwiftUI
import CasaPlayKit

/// Subtitle appearance. The player's subtitle overlay draws file and online
/// subtitles in this style.
struct SettingsView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        @Bindable var state = app

        ScrollView {
            VStack(alignment: .leading, spacing: Metrics.sectionSpacing / 2) {
                ScreenTitle("Subtitles & playback")
                SubtitlePreview(style: app.subtitleStyle)

                OptionRow(
                    title: "Size",
                    options: SubtitleStyle.Size.allCases,
                    label: { $0.label },
                    selection: $state.subtitleStyle.size
                )
                OptionRow(
                    title: "Text colour",
                    options: SubtitleStyle.TextColor.allCases,
                    label: { $0.label },
                    selection: $state.subtitleStyle.textColor
                )
                OptionRow(
                    title: "Background",
                    options: SubtitleStyle.Background.allCases,
                    label: { $0.label },
                    selection: $state.subtitleStyle.background
                )
                OptionRow(
                    title: "Position",
                    options: SubtitleStyle.Position.allCases,
                    label: { $0.label },
                    selection: $state.subtitleStyle.position
                )

                VStack(alignment: .leading, spacing: Metrics.s(8)) {
                    Text("Delay")
                        .font(.casa(13, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                    HStack(spacing: Metrics.s(8)) {
                        ChipButton(title: "−0.5 s", isSelected: false) {
                            app.subtitleStyle.delay -= 0.5
                        }
                        Text(String(format: "%+.1f s", app.subtitleStyle.delay))
                            .font(.casa(15, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                            .frame(minWidth: Metrics.s(70))
                        ChipButton(title: "+0.5 s", isSelected: false) {
                            app.subtitleStyle.delay += 0.5
                        }
                        ChipButton(title: "Reset", isSelected: false) {
                            app.subtitleStyle.delay = 0
                        }
                    }
                }
            }
            .padding(Metrics.screenPadding)
        }
        .screenBackground()
        .scrollingScreenTitle("Subtitles & playback")
    }
}

private struct SubtitlePreview: View {
    let style: SubtitleStyle

    var body: some View {
        ZStack(alignment: style.position == .bottom ? .bottom : .top) {
            ArtView(hue: 215)

            SubtitleText(text: "The last ferry leaves at midnight.", style: style, baseSize: Metrics.s(16))
                .padding(Metrics.s(14))
        }
        .frame(height: Metrics.s(150))
        .focusableOnTV()
    }
}
