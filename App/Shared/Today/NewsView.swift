// CasaPlay · Designed by 𝐂𝓪sΔηⓞשα
//
// News, grouped by story: the same story from several outlets shows once, with every outlet's coverage under it.

import SwiftUI
import CasaPlayKit

struct NewsView: View {
    @Environment(NewsCenter.self) private var center
    @State private var selected: NewsStory?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Metrics.s(14)) {
                    ScreenTitle("News")

                    Text(summaryLine)
                        .font(.casa(13))
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.horizontal, Metrics.screenPadding)
                        .focusableOnTV()

                    if center.stories.isEmpty {
                        emptyState
                    } else {
                        LazyVStack(spacing: Metrics.s(10)) {
                            ForEach(center.stories) { story in
                                Button { selected = story } label: {
                                    NewsStoryRow(story: story)
                                }
                                .cardRowButtonStyle()
                            }
                        }
                        .padding(.horizontal, Metrics.screenPadding)
                        .tvFocusSection()
                    }
                }
                .padding(.vertical, Metrics.s(16))
            }
            .tvFullWidth()
            .screenBackground()
            #if !os(tvOS)
            .refreshable { await center.refresh(force: true) }
            #endif
            .scrollingScreenTitle("News")
            .task { await center.refresh() }
            .adaptiveSheet(item: $selected) { story in
                NewsStoryDetail(story: story)
            }
        }
    }

    private var summaryLine: String {
        if center.stories.isEmpty { return "Headlines from BBC News, NPR, The Guardian and Al Jazeera." }
        let multi = center.stories.filter { $0.sources.count > 1 }.count
        return "\(center.stories.count) stories. \(multi) covered by more than one outlet."
    }

    @ViewBuilder
    private var emptyState: some View {
        if center.isLoading {
            ProgressView()
                .tint(Theme.accent)
                .frame(maxWidth: .infinity)
                .padding(.top, Metrics.sectionSpacing)
        } else if center.failed {
            VStack(spacing: Metrics.s(12)) {
                Text("Couldn't load the news. Check your connection.")
                    .font(.casa(14))
                    .foregroundStyle(Theme.textSecondary)
                Button("Try again") { Task { await center.refresh(force: true) } }
                    .cardRowButtonStyle()
            }
            .frame(maxWidth: .infinity)
            .padding(.top, Metrics.sectionSpacing)
        }
    }
}

// MARK: - Rows

struct NewsStoryRow: View {
    let story: NewsStory

    var body: some View {
        HStack(alignment: .top, spacing: Metrics.s(14)) {
            NewsThumbnail(url: story.imageURL)
                .frame(width: Metrics.s(110), height: Metrics.s(70))
                .clipShape(RoundedRectangle(cornerRadius: Metrics.cornerRadius, style: .continuous))

            VStack(alignment: .leading, spacing: Metrics.s(5)) {
                Text(story.headline)
                    .font(.casa(15, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(3)
                if !story.summary.isEmpty {
                    Text(story.summary)
                        .font(.casa(12))
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(2)
                }
                HStack(spacing: Metrics.s(8)) {
                    Text(NewsFormat.outlets(story.sources))
                        .font(.casa(11, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                    if let latest = story.latest {
                        Text(NewsFormat.age(latest))
                            .font(.casa(11))
                            .foregroundStyle(Theme.textSecondary)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(Metrics.s(12))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Metrics.cornerRadius, style: .continuous))
    }
}

struct NewsThumbnail: View {
    let url: URL?

    var body: some View {
        // Only https pictures are loaded; feeds are outside sources.
        if let url, url.scheme?.lowercased() == "https" {
            AsyncImage(url: url) { phase in
                if let image = phase.image {
                    image.resizable().aspectRatio(contentMode: .fill)
                } else {
                    placeholder
                }
            }
        } else {
            placeholder
        }
    }

    private var placeholder: some View {
        ZStack {
            Rectangle().fill(Theme.surfaceStrong)
            Image(systemName: "newspaper")
                .foregroundStyle(Theme.textSecondary)
        }
    }
}

// MARK: - Detail

struct NewsStoryDetail: View {
    let story: NewsStory
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Metrics.s(16)) {
                    Text(story.headline)
                        .font(.casa(22, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                        .focusableOnTV()

                    if !story.summary.isEmpty {
                        Text(story.summary)
                            .font(.casa(14))
                            .foregroundStyle(Theme.textPrimary.opacity(0.9))
                            .focusableOnTV()
                    }

                    Text("Coverage (\(story.articles.count))")
                        .font(.casa(16, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)

                    ForEach(story.articles) { article in
                        CoverageRow(article: article)
                    }

                    if Platform.isTV {
                        Text("Open CasaPlay on your iPhone or iPad to read the full articles.")
                            .font(.casa(12))
                            .foregroundStyle(Theme.textSecondary)
                            .focusableOnTV()
                    }
                }
                .padding(Metrics.screenPadding)
            }
            .screenBackground()
            #if !os(tvOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            #endif
        }
    }
}

private struct CoverageRow: View {
    let article: NewsArticle

    var body: some View {
        let content = VStack(alignment: .leading, spacing: Metrics.s(4)) {
            HStack(spacing: Metrics.s(8)) {
                Text(article.source)
                    .font(.casa(12, weight: .semibold))
                    .foregroundStyle(Theme.accent)
                if let date = article.published {
                    Text(NewsFormat.age(date))
                        .font(.casa(11))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            Text(article.title)
                .font(.casa(14, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .multilineTextAlignment(.leading)
            if !article.summary.isEmpty {
                Text(article.summary)
                    .font(.casa(12))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(4)
            }
        }
        .padding(Metrics.s(12))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Metrics.cornerRadius, style: .continuous))

        #if os(tvOS)
        content.focusable()
        #else
        if let link = article.link, link.scheme?.lowercased() == "https" {
            Link(destination: link) { content }
                .buttonStyle(.plain)
        } else {
            content
        }
        #endif
    }
}

// MARK: - Text

enum NewsFormat {
    /// "BBC News", "BBC News · NPR", "BBC News · NPR · +2"
    static func outlets(_ sources: [String]) -> String {
        switch sources.count {
        case 0: return ""
        case 1, 2: return sources.joined(separator: " · ")
        default: return sources.prefix(2).joined(separator: " · ") + " · +\(sources.count - 2)"
        }
    }

    static func age(_ date: Date) -> String {
        date.formatted(.relative(presentation: .numeric, unitsStyle: .abbreviated))
    }
}
