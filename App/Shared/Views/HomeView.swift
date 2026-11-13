// CasaPlay · Designed by 𝐂𝓪sΔηⓞשα

import SwiftUI
import CasaPlayKit

struct HomeView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Metrics.sectionSpacing) {
                    if let featured = app.featured {
                        HeroView(item: featured)
                    }

                    if !app.continueWatching.isEmpty {
                        Shelf(title: "Continue Watching") {
                            ForEach(app.continueWatching) { item in
                                NavigationLink(value: item.id) {
                                    LandscapeCard(item: item)
                                }
                                .posterButtonStyle()
                            }
                        }
                    }

                    Shelf(title: "Recently Added") {
                        ForEach(app.recentlyAdded) { item in
                            NavigationLink(value: item.id) {
                                PosterCard(item: item)
                            }
                            .posterButtonStyle()
                        }
                    }

                    if !app.favorites.isEmpty {
                        Shelf(title: "Favorites") {
                            ForEach(app.favorites) { item in
                                NavigationLink(value: item.id) {
                                    PosterCard(item: item)
                                }
                                .posterButtonStyle()
                            }
                        }
                    }
                }
                .padding(.bottom, Metrics.sectionSpacing)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationDestination(for: UUID.self) { id in
                DetailView(itemID: id)
            }
        }
    }
}

struct HeroView: View {
    @Environment(AppState.self) private var app
    let item: MediaItem

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            ArtView(hue: item.artHue, cornerRadius: 0)
            LinearGradient(
                colors: [Color.clear, Theme.background],
                startPoint: .center,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: Metrics.s(8)) {
                Text(item.canResume ? "CONTINUE WATCHING" : "FEATURED")
                    .font(.casa(11, weight: .bold))
                    .tracking(Platform.isTV ? 3 : 1.5)
                    .foregroundStyle(Theme.accent)

                Text(item.title)
                    .font(.casa(34, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)

                Text(item.metaLine)
                    .font(.casa(13))
                    .foregroundStyle(Theme.textSecondary)

                HStack(spacing: Metrics.s(6)) {
                    ForEach(item.file.badges, id: \.self) { badge in
                        Pill(text: badge)
                    }
                }

                HStack(spacing: Metrics.s(10)) {
                    Button {
                        app.play(item)
                    } label: {
                        Label(item.canResume ? "Resume" : "Play", systemImage: "play.fill")
                            .foregroundStyle(Theme.onAccent)
                    }
                    .buttonStyle(.borderedProminent)

                    NavigationLink(value: item.id) {
                        Label("Details", systemImage: "info.circle")
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.top, Metrics.s(4))
            }
            .padding(Metrics.screenPadding)
        }
        .frame(height: Metrics.heroHeight)
        .clipped()
    }
}
