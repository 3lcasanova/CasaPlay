// CasaPlay · Designed by 𝐂𝓪sΔηⓞשα

import SwiftUI
import CasaPlayKit

struct ProfileView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Metrics.sectionSpacing) {
                    Shelf(title: "Who's watching?") {
                        ForEach(app.profiles) { profile in
                            Button {
                                app.activeProfileID = profile.id
                            } label: {
                                ProfileTile(profile: profile, isSelected: profile.id == app.activeProfileID)
                            }
                            .posterButtonStyle()
                        }
                    }

                    VStack(alignment: .leading, spacing: Metrics.s(12)) {
                        NavigationLink {
                            SettingsView()
                        } label: {
                            SettingsLinkRow(
                                title: "Subtitles & playback",
                                detail: "Size, colour, background, position and delay",
                                symbol: "captions.bubble"
                            )
                        }
                        .posterButtonStyle()

                        NavigationLink {
                            OnlineServicesView()
                        } label: {
                            SettingsLinkRow(
                                title: "Online services",
                                detail: "IMDb ratings and OpenSubtitles",
                                symbol: "globe"
                            )
                        }
                        .posterButtonStyle()

                        if app.activeProfile.isKids {
                            Text("Kids profile: only G and PG titles are shown.")
                                .font(.casa(12))
                                .foregroundStyle(Theme.textSecondary)
                                .focusableOnTV()
                        }
                    }
                    .padding(.horizontal, Metrics.screenPadding)

                    VStack(alignment: .leading, spacing: Metrics.s(4)) {
                        Text("CasaPlay")
                            .font(.casa(13, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                        Text("Designed by 𝐂𝓪sΔηⓞשα")
                            .font(.casa(12))
                            .foregroundStyle(Theme.textSecondary)
                        Text("Early build · sample library")
                            .font(.casa(12))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .padding(.horizontal, Metrics.screenPadding)
                    .focusableOnTV()
                }
                .padding(.vertical, Metrics.s(16))
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Profile")
        }
    }
}

private struct ProfileTile: View {
    let profile: Profile
    let isSelected: Bool

    var body: some View {
        VStack(spacing: Metrics.s(8)) {
            AvatarView(text: profile.glyph, hue: profile.hue, size: Metrics.s(72))
                .overlay(
                    Circle()
                        .stroke(isSelected ? Theme.accent : Color.clear, lineWidth: Metrics.s(3))
                        .padding(-Metrics.s(5))
                )
                .padding(Metrics.s(6))

            Text(profile.name)
                .font(.casa(13, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)

            if profile.isKids {
                Pill(text: "KIDS")
            }
        }
        .frame(width: Metrics.s(100))
    }
}

private struct SettingsLinkRow: View {
    let title: String
    let detail: String
    let symbol: String

    var body: some View {
        HStack(spacing: Metrics.s(14)) {
            Image(systemName: symbol)
                .font(.casa(20))
                .foregroundStyle(Theme.accent)
                .frame(width: Metrics.s(36))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.casa(15, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(detail)
                    .font(.casa(12))
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer(minLength: Metrics.s(8))
            Image(systemName: "chevron.right")
                .font(.casa(13, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(Metrics.s(14))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Metrics.cornerRadius, style: .continuous))
    }
}
