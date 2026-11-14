// CasaPlay · Designed by 𝐂𝓪sΔηⓞשα

import SwiftUI
import CasaPlayKit

/// A poster with the title, year and rating underneath. Used for TMDB titles on Home, Movies and Series.
struct TitlePosterCard: View {
    let title: String
    let year: Int?
    let posterPath: String?
    let rating: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.s(6)) {
            posterImage
                .frame(width: Metrics.posterWidth, height: Metrics.posterWidth * 1.5)
                .clipShape(RoundedRectangle(cornerRadius: Metrics.cornerRadius, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.casa(13, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .lineLimit(1)
                Text(subtitleLine)
                    .font(.casa(12))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }
            .frame(width: Metrics.posterWidth, alignment: .leading)
        }
    }

    @ViewBuilder
    private var posterImage: some View {
        if let path = posterPath, let url = TMDBClient.posterURL(path) {
            AsyncImage(url: url) { phase in
                switch phase {
                case .success(let image):
                    image.resizable().aspectRatio(contentMode: .fill)
                case .failure, .empty:
                    fallbackArt
                @unknown default:
                    fallbackArt
                }
            }
        } else {
            fallbackArt
        }
    }

    private var fallbackArt: some View {
        ZStack {
            Rectangle().fill(Theme.surface)
            Text(title.prefix(2).uppercased())
                .font(.casa(28, weight: .bold))
                .foregroundStyle(Theme.textSecondary)
        }
    }

    private var subtitleLine: String {
        [year.map(String.init), rating].compactMap { $0 }.joined(separator: " · ")
    }
}
