// CasaPlay · Designed by 𝐂𝓪sΔηⓞשα
//
// IPTV: live channels from the Stremio add-ons you installed. Nothing is built in. An add-on
// that offers channel lists (catalogs of type "tv") shows up here with its channels, and
// tapping a channel asks the add-on for the live link and plays it.

import SwiftUI
import CasaPlayKit

/// One channel list: a catalog of one installed add-on.
struct LiveSource: Identifiable, Equatable {
    let addonID: String
    let addonName: String
    let manifest: StremioManifest
    let catalog: StremioManifest.Catalog

    var id: String { "\(addonID)|\(catalog.type)|\(catalog.id)" }
}

struct LiveAddon: Identifiable, Equatable {
    let id: String
    let name: String
}

@MainActor
@Observable
final class LiveTVModel {
    private(set) var sources: [LiveSource] = []
    private(set) var selectedID: String?
    private(set) var genre: String?
    private(set) var channels: [StremioMetaPreview] = []
    private(set) var hasLoadedSources = false
    private(set) var isLoading = false
    private(set) var isLoadingMore = false
    private(set) var canLoadMore = false
    private(set) var error: String?
    private(set) var showAllCatalogs: Bool
    var searchText = ""

    @ObservationIgnored private var clients: [String: StremioClient] = [:]
    @ObservationIgnored private var installed: [InstalledExtension] = []
    @ObservationIgnored private var center: ExtensionCenter?
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var appliedSearch = ""

    private static let showAllKey = "iptv.showAllCatalogs"

    init() {
        showAllCatalogs = UserDefaults.standard.bool(forKey: Self.showAllKey)
    }

    // MARK: What is on screen

    var selected: LiveSource? { sources.first { $0.id == selectedID } }

    var addons: [LiveAddon] {
        var seen = Set<String>()
        var list: [LiveAddon] = []
        for source in sources where seen.insert(source.addonID).inserted {
            list.append(LiveAddon(id: source.addonID, name: source.addonName))
        }
        return list
    }

    var catalogsOfSelectedAddon: [LiveSource] {
        guard let addonID = selected?.addonID else { return [] }
        return sources.filter { $0.addonID == addonID }
    }

    var genreChoices: [String] { selected?.catalog.genreOptions ?? [] }
    var genreIsRequired: Bool { selected?.catalog.genreRequired ?? false }
    var canSearchOnServer: Bool { selected?.catalog.supportsSearch ?? false }

    private var trimmedSearch: String { searchText.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// The channels to draw. A catalog without server-side search is filtered here.
    var visibleChannels: [StremioMetaPreview] {
        canSearchOnServer ? channels : LiveTV.filter(channels, matching: searchText)
    }

    // MARK: Finding the channel lists

    func loadSources(center: ExtensionCenter) async {
        self.center = center
        installed = center.state.installed
        let addons = installed.filter { $0.isEnabled && $0.compatibility.isUsable && $0.manifest.hasCatalogResource }

        var found: [String: StremioClient] = [:]
        for addon in addons {
            if let client = await center.client(for: addon) { found[addon.id] = client }
        }
        clients.merge(found) { _, new in new }

        // The saved manifest is a trimmed copy. Ask each add-on for its full one, so genres and
        // required filters are known. If an add-on doesn't answer, its saved copy is used.
        var fresh: [String: StremioManifest] = [:]
        await withTaskGroup(of: (String, StremioManifest?).self) { group in
            for (id, client) in found {
                group.addTask { (id, try? await client.manifest(timeout: 10)) }
            }
            for await (id, manifest) in group {
                if let manifest { fresh[id] = manifest }
            }
        }
        guard !Task.isCancelled else { return }

        var list: [LiveSource] = []
        for addon in addons {
            let manifest = fresh[addon.id] ?? addon.manifest
            let catalogs = showAllCatalogs ? manifest.browsableCatalogs : manifest.liveCatalogs
            for catalog in catalogs {
                list.append(LiveSource(addonID: addon.id, addonName: addon.name, manifest: manifest, catalog: catalog))
            }
        }
        let previous = selectedID
        sources = list
        hasLoadedSources = true
        if let previous, list.contains(where: { $0.id == previous }) {
            if channels.isEmpty && !isLoading && error == nil { reload() }
            return
        }
        select(list.first?.id)
    }

    func setShowAllCatalogs(_ on: Bool) {
        showAllCatalogs = on
        UserDefaults.standard.set(on, forKey: Self.showAllKey)
        selectedID = nil
        channels = []
        if let center {
            Task { await loadSources(center: center) }
        }
    }

    func select(_ id: String?) {
        selectedID = id
        genre = nil
        if let catalog = selected?.catalog, catalog.genreRequired { genre = catalog.genreOptions.first }
        reload()
    }

    func selectAddon(_ id: String) {
        guard let first = sources.first(where: { $0.addonID == id }) else { return }
        select(first.id)
    }

    func selectGenre(_ value: String?) {
        guard genre != value else { return }
        genre = value
        reload()
    }

    // MARK: Channels

    private func fetch(skip: Int) async throws -> [StremioMetaPreview] {
        guard let source = selected, let client = clients[source.addonID] else { return [] }
        let term = canSearchOnServer ? trimmedSearch : ""
        return try await client.catalog(
            type: source.catalog.type, id: source.catalog.id,
            search: term.isEmpty ? nil : term, genre: genre, skip: skip, timeout: 20
        )
    }

    func reload() {
        loadTask?.cancel()
        generation += 1
        let token = generation
        channels = []
        error = nil
        canLoadMore = false
        isLoadingMore = false
        guard let source = selected else {
            isLoading = false
            return
        }
        isLoading = true
        appliedSearch = canSearchOnServer ? trimmedSearch : ""
        loadTask = Task { [weak self] in
            guard let self else { return }
            do {
                let page = try await self.fetch(skip: 0)
                guard token == self.generation else { return }
                self.channels = LiveTV.merge([], with: page).channels
                self.canLoadMore = source.catalog.supportsSkip && !page.isEmpty
            } catch {
                guard token == self.generation, !Task.isCancelled else { return }
                self.error = "Couldn't load channels. \(error.localizedDescription)"
            }
            self.isLoading = false
        }
    }

    func loadMore() async {
        guard canLoadMore, !isLoadingMore, !isLoading, let source = selected else { return }
        let token = generation
        isLoadingMore = true
        defer { if token == generation { isLoadingMore = false } }
        do {
            let page = try await fetch(skip: channels.count)
            guard token == generation else { return }
            let merged = LiveTV.merge(channels, with: page)
            channels = merged.channels
            // A page with nothing new means the add-on ignores skip or has run out.
            canLoadMore = source.catalog.supportsSkip && merged.added > 0
        } catch {
            guard token == generation, !Task.isCancelled else { return }
            canLoadMore = false
        }
    }

    /// Called after the search box settles. Server-side search asks the add-on again; otherwise
    /// the pages are fetched so the local filter can see every channel.
    func searchChanged() async {
        if canSearchOnServer {
            guard trimmedSearch != appliedSearch else { return }
            reload()
        } else if !trimmedSearch.isEmpty {
            var pages = 0
            while canLoadMore, pages < 20, !Task.isCancelled {
                await loadMore()
                pages += 1
            }
        }
    }

    // MARK: Playing

    struct Resolution {
        var options: [LiveStreamOption]
        var onlyUnplayable: Bool
    }

    /// Asks the add-on that listed the channel, then any other add-on that answers for it,
    /// for playable links.
    func resolve(_ channel: StremioMetaPreview) async throws -> Resolution {
        guard let source = selected else { return Resolution(options: [], onlyUnplayable: false) }
        let type = channel.type.isEmpty ? source.catalog.type : channel.type

        var order: [String] = []
        if source.manifest.resources.contains(where: { $0.name == "stream" }) { order.append(source.addonID) }
        for addon in installed
        where addon.id != source.addonID && addon.isEnabled && addon.compatibility.isUsable
            && addon.handles(.stream, type: type, id: channel.id) {
            order.append(addon.id)
        }

        var onlyUnplayable = false
        var lastError: Error?
        for id in order {
            guard let client = await client(for: id) else { continue }
            do {
                let streams = try await client.streams(type: type, id: channel.id, timeout: 20)
                let options = LiveTV.options(from: streams)
                if !options.isEmpty { return Resolution(options: options, onlyUnplayable: false) }
                if LiveTV.hasOnlyUnplayableLinks(streams) { onlyUnplayable = true }
            } catch {
                lastError = error
            }
        }
        if let lastError, !onlyUnplayable { throw lastError }
        return Resolution(options: [], onlyUnplayable: onlyUnplayable)
    }

    private func client(for addonID: String) async -> StremioClient? {
        if let known = clients[addonID] { return known }
        guard let addon = installed.first(where: { $0.id == addonID }), let center else { return nil }
        guard let made = await center.client(for: addon) else { return nil }
        clients[addonID] = made
        return made
    }
}

// MARK: - Screen

struct LiveTVView: View {
    @Environment(AppState.self) private var app
    @Environment(ExtensionCenter.self) private var center
    @State private var model = LiveTVModel()
    @State private var choices: [LiveStreamOption] = []
    @State private var choosing: StremioMetaPreview?
    @State private var showChoices = false
    @State private var openingID: String?
    @State private var notice: String?

    /// Wide channel tiles: five across on Apple TV, filling the width; as many as fit on iPhone and iPad.
    private var columns: [GridItem] {
        if Platform.isTV {
            return Array(repeating: GridItem(.flexible(), spacing: 28, alignment: .top), count: 5)
        }
        return [GridItem(.adaptive(minimum: 150, maximum: 260), spacing: 12, alignment: .top)]
    }

    /// Changes when an add-on is installed, removed, switched on or off.
    private var installedSignature: String {
        center.state.installed.map { "\($0.id):\($0.isEnabled)" }.joined(separator: ",")
    }

    var body: some View {
        @Bindable var searchModel = model

        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Metrics.s(14)) {
                    content
                }
                .padding(.bottom, Metrics.sectionSpacing)
            }
            .tvFullWidth()
            .screenBackground()
            .scrollingScreenTitle("IPTV")
            .searchable(text: $searchModel.searchText)
            .task(id: model.searchText) {
                do { try await Task.sleep(nanoseconds: 450_000_000) } catch { return }
                await model.searchChanged()
            }
        }
        .task(id: installedSignature) {
            await model.loadSources(center: center)
        }
        .confirmationDialog("Choose a stream", isPresented: $showChoices, titleVisibility: .visible) {
            ForEach(choices) { option in
                Button(option.title) {
                    if let channel = choosing { play(option, channel: channel) }
                }
            }
        }
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        if !model.hasLoadedSources {
            ProgressView()
                .frame(maxWidth: .infinity)
                .padding(.top, Metrics.sectionSpacing)
        } else if model.sources.isEmpty {
            emptyState
        } else {
            pickers

            if let notice {
                Text(notice)
                    .font(.casa(13))
                    .foregroundStyle(.red)
                    .padding(.horizontal, PremiumGrid.edge)
                    .focusableOnTV()
            }

            channelArea
            footer
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Live TV yet", systemImage: "antenna.radiowaves.left.and.right")
        } description: {
            Text(model.showAllCatalogs
                 ? "None of your add-ons has a catalog that can be listed."
                 : "None of your installed add-ons lists live channels. Install an IPTV add-on in Extensions. If yours files its channels under another type, show every catalog.")
        } actions: {
            Button("Open Extensions") { app.selectedSection = .extensions }
            if !model.showAllCatalogs {
                Button("Show every catalog") { model.setShowAllCatalogs(true) }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, Metrics.sectionSpacing)
    }

    /// Add-ons, then the add-on's lists, then genres, each as a row of colourful tiles.
    @ViewBuilder
    private var pickers: some View {
        if model.addons.count > 1 {
            CategoryRail {
                ForEach(Array(model.addons.enumerated()), id: \.element.id) { index, addon in
                    tile(title: addon.name, symbol: "antenna.radiowaves.left.and.right",
                         palette: Self.palette(index), isSelected: addon.id == model.selected?.addonID) {
                        model.selectAddon(addon.id)
                    }
                }
            }
        }
        if model.catalogsOfSelectedAddon.count > 1 {
            CategoryRail {
                ForEach(Array(model.catalogsOfSelectedAddon.enumerated()), id: \.element.id) { index, source in
                    tile(title: source.catalog.displayName, symbol: "tv.fill",
                         palette: Self.palette(index + 3), isSelected: source.id == model.selectedID) {
                        model.select(source.id)
                    }
                }
            }
        }
        if !model.genreChoices.isEmpty {
            CategoryRail {
                if !model.genreIsRequired {
                    tile(title: "All", symbol: "square.grid.2x2.fill", palette: .graphite,
                         isSelected: model.genre == nil) { model.selectGenre(nil) }
                }
                ForEach(Array(model.genreChoices.enumerated()), id: \.element) { index, name in
                    tile(title: name, symbol: "play.rectangle.fill", palette: Self.palette(index + 1),
                         isSelected: model.genre == name) { model.selectGenre(name) }
                }
            }
        }
    }

    private static func palette(_ index: Int) -> TilePalette {
        let all = TilePalette.allCases
        return all[((index % all.count) + all.count) % all.count]
    }

    private func tile(title: String, symbol: String, palette: TilePalette, isSelected: Bool,
                      action: @escaping () -> Void) -> some View {
        Button(action: action) {
            CategoryTile(title: title, symbol: symbol, palette: palette, isSelected: isSelected)
        }
        .premiumCardStyle(focusScale: 1.06)
    }

    private func chipRow<Chips: View>(@ViewBuilder _ chips: () -> Chips) -> some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: Metrics.s(8)) { chips() }
                .padding(.horizontal, PremiumGrid.edge)
                .padding(.vertical, Platform.isTV ? 14 : 0)
        }
    }

    @ViewBuilder
    private var channelArea: some View {
        let channels = model.visibleChannels
        if model.isLoading {
            ProgressView()
                .tint(Theme.accent)
                .frame(maxWidth: .infinity)
                .padding(.top, Metrics.sectionSpacing)
        } else if channels.isEmpty, let error = model.error {
            ContentUnavailableView {
                Label("Couldn't load channels", systemImage: "wifi.exclamationmark")
            } description: {
                Text(error)
            } actions: {
                Button("Try again") { model.reload() }
            }
            .frame(maxWidth: .infinity)
            .padding(.top, Metrics.sectionSpacing)
        } else if channels.isEmpty {
            ContentUnavailableView(
                "No channels found",
                systemImage: "tv",
                description: Text(model.searchText.isEmpty ? "This list is empty right now." : "Try a different search or filter.")
            )
            .frame(maxWidth: .infinity)
            .padding(.top, Metrics.sectionSpacing)
        } else {
            LazyVGrid(columns: columns, alignment: .leading, spacing: PremiumGrid.rowSpacing) {
                ForEach(channels) { channel in
                    Button { open(channel) } label: {
                        ChannelCard(channel: channel, isOpening: openingID == channel.id)
                    }
                    .premiumCardStyle()
                    .disabled(openingID != nil)
                    .onAppear {
                        if channel.id == channels.last?.id { Task { await model.loadMore() } }
                    }
                }
            }
            .padding(.horizontal, PremiumGrid.edge)

            if model.isLoadingMore {
                ProgressView()
                    .tint(Theme.accent)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var footer: some View {
        chipRow {
            ChipButton(title: "Reload", isSelected: false) { model.reload() }
            ChipButton(
                title: model.showAllCatalogs ? "Show only Live TV" : "Show every catalog",
                isSelected: false
            ) { model.setShowAllCatalogs(!model.showAllCatalogs) }
        }
        .padding(.top, Metrics.s(8))
    }

    // MARK: Playing

    private func open(_ channel: StremioMetaPreview) {
        guard openingID == nil else { return }
        openingID = channel.id
        notice = nil
        Task {
            do {
                let result = try await model.resolve(channel)
                openingID = nil
                if result.options.count == 1, let only = result.options.first {
                    play(only, channel: channel)
                } else if !result.options.isEmpty {
                    choices = result.options
                    choosing = channel
                    showChoices = true
                } else if result.onlyUnplayable {
                    notice = "\(channel.name) only offers links CasaPlay can't open here: a web page, YouTube or a torrent."
                } else {
                    notice = "\(channel.name) has no stream right now. Try again in a moment."
                }
            } catch {
                openingID = nil
                notice = "Couldn't open \(channel.name). \(error.localizedDescription)"
            }
        }
    }

    private func play(_ option: LiveStreamOption, channel: StremioMetaPreview) {
        // Live links rarely say what they hold; H.264 is what channels almost always carry.
        // An .m3u8 goes to Apple's player. Anything else goes to the compatibility player.
        let item = MediaItem(
            id: UUID(),
            title: channel.name,
            runtimeSeconds: 0,
            file: MediaFileInfo(container: option.container, videoCodec: .h264),
            sourceName: model.selected?.addonName ?? "Live TV",
            streamURL: option.url,
            streamHeaders: option.headers.isEmpty ? nil : option.headers
        )
        app.play(item)
    }
}

/// A channel: its logo on a dark card with a soft glow, the name underneath. On Apple TV the focused
/// card gets a white ring, as the posters do.
private struct ChannelCard: View {
    let channel: StremioMetaPreview
    let isOpening: Bool
    @Environment(\.cardFocused) private var focused

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Metrics.cornerRadius, style: .continuous)
    }

    var body: some View {
        VStack(spacing: Metrics.s(8)) {
            ZStack {
                LinearGradient(colors: [Color.white.opacity(0.14), Color.white.opacity(0.05)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
                if let url = LiveTV.artworkURL(for: channel) {
                    AsyncImage(url: url) { phase in
                        if let image = phase.image {
                            image.resizable().scaledToFit().padding(Metrics.s(12))
                        } else {
                            placeholder
                        }
                    }
                } else {
                    placeholder
                }
                if isOpening {
                    Color.black.opacity(0.45)
                    ProgressView().tint(.white)
                }
            }
            .aspectRatio(1.6, contentMode: .fit)
            .overlay(alignment: .topLeading) {
                Text("LIVE")
                    .font(.casa(10.5, weight: .heavy))
                    .tracking(0.6)
                    .foregroundStyle(.white)
                    .padding(.horizontal, Metrics.s(7))
                    .padding(.vertical, Metrics.s(3))
                    .background(Color(red: 0.88, green: 0.11, blue: 0.16),
                                in: RoundedRectangle(cornerRadius: Metrics.s(5), style: .continuous))
                    .padding(Metrics.s(6))
            }
            .clipShape(shape)
            .overlay { shape.strokeBorder(Color.white, lineWidth: focused ? Metrics.s(2.6) : 0) }

            Text(channel.name)
                .font(.casa(14, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
        }
    }

    private var placeholder: some View {
        Image(systemName: "tv")
            .font(.casa(26))
            .foregroundStyle(Theme.textSecondary)
    }
}
