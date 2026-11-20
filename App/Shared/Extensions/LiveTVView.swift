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

    /// What is on now and next, by channel id. Filled in as channel cards come on screen.
    private(set) var guide: [String: NowNext] = [:]
    private(set) var favorites: [FavoriteChannel] = []
    private(set) var showFavorites = false
    @ObservationIgnored private var guideAsked: [String: Date] = [:]
    @ObservationIgnored private var guideActive = 0

    @ObservationIgnored private var clients: [String: StremioClient] = [:]
    /// Xtream Codes servers shown as channel lists, keyed by their source addonID.
    @ObservationIgnored private var xtream: [String: XtreamProvider] = [:]
    @ObservationIgnored private var installed: [InstalledExtension] = []
    @ObservationIgnored private var center: ExtensionCenter?
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var appliedSearch = ""

    private static let showAllKey = "iptv.showAllCatalogs"
    private static let favoritesKey = "iptv.favoriteChannels"
    static let showsAddonChannels = false

    init() {
        showAllCatalogs = UserDefaults.standard.bool(forKey: Self.showAllKey)
        if let data = UserDefaults.standard.data(forKey: Self.favoritesKey),
           let saved = try? JSONDecoder().decode([FavoriteChannel].self, from: data) {
            favorites = saved
        }
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

    /// True for a channel list. "Show every catalog" also lists films and shows, which are posters, not channels.
    var selectedIsLive: Bool { selected.map { LiveTV.isLive($0.catalog) } ?? true }

    var genreChoices: [String] { selected?.catalog.genreOptions ?? [] }
    var genreIsRequired: Bool { selected?.catalog.genreRequired ?? false }
    var canSearchOnServer: Bool { selected?.catalog.supportsSearch ?? false }

    private var trimmedSearch: String { searchText.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// The channels to draw. A catalog without server-side search is filtered here.
    var visibleChannels: [StremioMetaPreview] {
        if showFavorites { return LiveTV.filter(favorites.compactMap(\.preview), matching: searchText) }
        return canSearchOnServer ? channels : LiveTV.filter(channels, matching: searchText)
    }

    // MARK: Favorites and the guide

    func setShowFavorites(_ on: Bool) { showFavorites = on }

    func isFavorite(_ channel: StremioMetaPreview) -> Bool {
        favorites.contains { $0.id == channel.id }
    }

    /// Adds or removes a channel. Only channels from an Xtream server can be saved.
    func toggleFavorite(_ channel: StremioMetaPreview) {
        if let index = favorites.firstIndex(where: { $0.id == channel.id }) {
            favorites.remove(at: index)
        } else if let addonID = selected?.addonID, xtream[addonID] != nil {
            let logo = (channel.logo ?? channel.poster)
            favorites.append(FavoriteChannel(id: channel.id, name: channel.name, logo: logo, addonID: addonID))
        }
        if let data = try? JSONEncoder().encode(favorites) {
            UserDefaults.standard.set(data, forKey: Self.favoritesKey)
        }
    }

    /// The Xtream server a channel belongs to: the saved one for a favorite, else the list on screen.
    private func serverID(for channel: StremioMetaPreview) -> String? {
        favorites.first { $0.id == channel.id }?.addonID ?? selected?.addonID
    }

    /// Looks up what is on a channel now and next. At most four lookups run at once, and a channel is
    /// asked again no sooner than five minutes later.
    func loadGuide(for channel: StremioMetaPreview) async {
        guard let addonID = serverID(for: channel), let provider = xtream[addonID] else { return }
        if let asked = guideAsked[channel.id], Date().timeIntervalSince(asked) < 300 { return }
        while guideActive >= 4 {
            do { try await Task.sleep(nanoseconds: 150_000_000) } catch { return }
        }
        guard guideAsked[channel.id].map({ Date().timeIntervalSince($0) >= 300 }) ?? true else { return }
        guideAsked[channel.id] = Date()
        guideActive += 1
        defer { guideActive -= 1 }
        do {
            guide[channel.id] = try await provider.nowNext(for: channel.id)
        } catch {
            guideAsked[channel.id] = nil
        }
    }

    // MARK: Finding the channel lists

    func loadSources(center: ExtensionCenter) async {
        self.center = center
        installed = center.state.installed
        // Only Xtream Codes channels for now. Set showsAddonChannels to true to list add-on channels again.
        let addons = Self.showsAddonChannels
            ? installed.filter { $0.isEnabled && $0.compatibility.isUsable && $0.manifest.hasCatalogResource }
            : []

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
        // Live channels from Xtream Codes logins (Servers tab), one list per server.
        var xtreamFound: [String: XtreamProvider] = [:]
        for server in ServerCenter.shared.xtreamServers() {
            let categories = (try? await server.provider.liveCategoryNames()) ?? []
            guard !Task.isCancelled,
                  let manifest = XtreamLive.manifest(serverID: server.config.id, name: server.config.name, categories: categories),
                  let catalog = manifest.catalogs.first else { continue }
            xtreamFound[manifest.id] = server.provider
            list.insert(LiveSource(addonID: manifest.id, addonName: server.config.name, manifest: manifest, catalog: catalog), at: 0)
        }
        xtream = xtreamFound

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
        if let source = selected, let provider = xtream[source.addonID] {
            return skip == 0 ? try await provider.liveChannels(category: genre) : []
        }
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
        if let addonID = serverID(for: channel), let provider = xtream[addonID] {
            let options = provider.liveOption(for: channel.id, title: channel.name).map { [$0] } ?? []
            return Resolution(options: options, onlyUnplayable: false)
        }
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
        // Films and shows (shown with every catalog) are posters: more across, and narrower.
        if !model.selectedIsLive {
            if Platform.isTV {
                return Array(repeating: GridItem(.flexible(), spacing: 28, alignment: .top), count: 7)
            }
            return [GridItem(.adaptive(minimum: 104, maximum: 170), spacing: 12, alignment: .top)]
        }
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
            .scrollingScreenTitle("TV & IPTV")
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
            modeRow
                .tvFocusSection()
            if !model.showFavorites {
                pickers
            }

            if let notice {
                Text(notice)
                    .font(.casa(13))
                    .foregroundStyle(.red)
                    .padding(.horizontal, PremiumGrid.edge)
                    .focusableOnTV()
            }

            // Each block is one focus region, so Down/Up reaches the nearest item in the next block.
            VStack(alignment: .leading, spacing: Metrics.s(14)) {
                channelArea
            }
            .tvFocusSection()
            footer
                .tvFocusSection()
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Live TV yet", systemImage: "antenna.radiowaves.left.and.right")
        } description: {
            Text("Add your Xtream Codes login in the Servers tab to see your live channels here.")
        } actions: {
            Button("Open Servers") { app.selectedSection = .servers }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, Metrics.sectionSpacing)
    }

    /// All channels, or just the ones you starred. Press and hold a channel to star it.
    private var modeRow: some View {
        chipRow {
            ChipButton(title: "All Channels", isSelected: !model.showFavorites) { model.setShowFavorites(false) }
            ChipButton(title: "Favorites (\(model.favorites.count))", isSelected: model.showFavorites) {
                model.setShowFavorites(true)
            }
        }
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
            .tvFocusSection()
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
            .tvFocusSection()
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
            .tvFocusSection()
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
                description: Text(model.showFavorites
                                  ? "Press and hold a channel, then choose Add to Favorites."
                                  : (model.searchText.isEmpty ? Self.emptyListNote(model.selected?.addonName) : "Try a different search or filter."))
            )
            .frame(maxWidth: .infinity)
            .padding(.top, Metrics.sectionSpacing)
        } else {
            LazyVGrid(columns: columns, alignment: .leading, spacing: PremiumGrid.rowSpacing) {
                ForEach(channels) { channel in
                    Button { open(channel) } label: {
                        ChannelCard(channel: channel, isOpening: openingID == channel.id, isLive: model.selectedIsLive,
                                    nowNext: model.guide[channel.id], isFavorite: model.isFavorite(channel))
                    }
                    .premiumCardStyle()
                    .disabled(openingID != nil)
                    .contextMenu {
                        Button(model.isFavorite(channel) ? "Remove from Favorites" : "Add to Favorites",
                               systemImage: model.isFavorite(channel) ? "star.slash" : "star") {
                            model.toggleFavorite(channel)
                        }
                    }
                    .task { await model.loadGuide(for: channel) }
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
            if LiveTVModel.showsAddonChannels {
                ChipButton(
                    title: model.showAllCatalogs ? "Show only Live TV" : "Show every catalog",
                    isSelected: false
                ) { model.setShowAllCatalogs(!model.showAllCatalogs) }
            }
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
                } else if Self.isSetupPlaceholder(channel.name) {
                    // Some add-ons answer with one fake entry until their owner has configured them.
                    notice = "\(Self.trimmedSetupTitle(channel.name)). This add-on has to be set up on its own website first: open its configure page, enter your key, then install the link it gives you."
                } else {
                    notice = "\(channel.name) has no stream right now. Try again in a moment."
                }
            } catch {
                openingID = nil
                notice = "Couldn't open \(channel.name). \(error.localizedDescription)"
            }
        }
    }

    /// What to tell someone when an add-on's list comes back with nothing in it.
    private static func emptyListNote(_ addon: String?) -> String {
        let name = addon.map { "\($0) " } ?? "The add-on "
        return "\(name)answered, but this list has nothing in it. If it needs an IPTV login, check that login in the add-on's link on its configure page, install the new link, then tap Reload."
    }

    /// True for the stand-in entry an unconfigured add-on shows ("Setup required: add your … key").
    private static func isSetupPlaceholder(_ name: String) -> Bool {
        let lower = name.lowercased()
        return ["setup required", "configuration required", "configure required", "not configured", "needs configuration"]
            .contains { lower.hasPrefix($0) }
    }

    /// The placeholder's own wording without a trailing full stop, so the sentence after it reads cleanly.
    private static func trimmedSetupTitle(_ name: String) -> String {
        name.trimmingCharacters(in: CharacterSet(charactersIn: " .!"))
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
    /// A channel gets a wide card and the LIVE tag. A film or show (from another catalog) gets a poster, no tag.
    var isLive = true
    var nowNext: NowNext?
    var isFavorite = false
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
                    CachedAsyncImage(url: url) { phase in
                        if let image = phase.image {
                            if isLive {
                                image.resizable().scaledToFit().padding(Metrics.s(12))
                            } else {
                                image.resizable().scaledToFill()
                            }
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
            .aspectRatio(isLive ? 1.6 : 2.0 / 3.0, contentMode: .fit)
            .clipped()
            .overlay(alignment: .topLeading) {
                if isLive { liveTag }
            }
            .overlay(alignment: .topTrailing) {
                if isFavorite {
                    Image(systemName: "star.fill")
                        .font(.casa(12))
                        .foregroundStyle(Theme.accent)
                        .padding(Metrics.s(7))
                }
            }
            .clipShape(shape)
            .overlay { shape.strokeBorder(Color.white, lineWidth: focused ? Metrics.s(2.6) : 0) }

            Text(channel.name)
                .font(.casa(14, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)

            if let now = nowNext?.now {
                VStack(spacing: Metrics.s(3)) {
                    Text(now.title)
                        .font(.casa(11, weight: .medium))
                        .foregroundStyle(Theme.accent)
                        .lineLimit(1)
                    GuideProgress(value: now.progress(at: Date()))
                        .frame(height: Metrics.s(3))
                    if let next = nowNext?.next {
                        Text("Next: " + next.title + " · " + next.start.formatted(date: .omitted, time: .shortened))
                            .font(.casa(10))
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
    }

    private var liveTag: some View {
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

    private var placeholder: some View {
        Image(systemName: "tv")
            .font(.casa(26))
            .foregroundStyle(Theme.textSecondary)
    }
}

/// A thin bar showing how far through the program you are.
private struct GuideProgress: View {
    let value: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.18))
                Capsule().fill(Theme.accent).frame(width: proxy.size.width * min(max(value, 0), 1))
            }
        }
    }
}

/// A channel you starred. Saved on this device.
struct FavoriteChannel: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let logo: String?
    let addonID: String

    /// The channel as the list draws it.
    var preview: StremioMetaPreview? {
        var json: [String: Any] = ["id": id, "type": "tv", "name": name]
        if let logo { json["logo"] = logo }
        guard let data = try? JSONSerialization.data(withJSONObject: json) else { return nil }
        return try? JSONDecoder().decode(StremioMetaPreview.self, from: data)
    }
}
