// CasaPlay · Designed by 𝐂𝓪sΔηⓞשα

import SwiftUI
import CasaPlayKit

struct TorrentSettingsView: View {
    @Environment(TorrentCenter.self) private var center
    @State private var feedName = ""
    @State private var feedURL = ""
    @State private var confirmingClear = false

    private static let uploadOptions: [Int] = [0, 50 * 1024, 100 * 1024, 500 * 1024, 1024 * 1024, 5 * 1024 * 1024]
    private static let storageOptions: [Int64] = [2, 5, 10, 20, 50, 100].map { Int64($0) * 1024 * 1024 * 1024 }

    var body: some View {
        @Bindable var bindable = center

        ScrollView {
            VStack(alignment: .leading, spacing: Metrics.sectionSpacing / 2) {
                SettingsGroup(title: "Privacy") {
                    Text("""
                    • Trackers and every peer you connect to see your device's public IP address and which torrent you are on. Use torrents you are allowed to share.
                    • CasaPlay connects out to peers. It doesn't open a port, so peers can't connect to you first.
                    • Web seeds (HTTPS servers listed in a torrent, such as archive.org) see your IP address like any website.
                    """)
                    .font(.casa(12))
                    .foregroundStyle(Theme.textSecondary)
                    .focusableOnTV()
                }

                SettingsGroup(title: "Uploading") {
                    Toggle("Upload while downloading", isOn: $bindable.settings.uploadWhileDownloading)
                    Text("Peers usually send more to devices that also upload. Turn off to only download.")
                        .font(.casa(12)).foregroundStyle(Theme.textSecondary)
                    Toggle("Keep seeding after a file finishes", isOn: $bindable.settings.seedAfterDownload)
                    Text("Off: CasaPlay disconnects from peers once your file is complete. Seeding only happens while CasaPlay is open.")
                        .font(.casa(12)).foregroundStyle(Theme.textSecondary)
                    OptionRow(
                        title: "Upload limit",
                        options: Self.uploadOptions,
                        label: { $0 == 0 ? "No upload" : "\(TorrentFormat.bytes(Int64($0)))/s" },
                        selection: $bindable.settings.uploadLimit
                    )
                }

                SettingsGroup(title: "Storage") {
                    OptionRow(
                        title: "Torrent cache limit",
                        options: Self.storageOptions,
                        label: { TorrentFormat.bytes($0) },
                        selection: $bindable.settings.storageLimit
                    )
                    Text("Using \(TorrentFormat.bytes(center.usedBytes)). Downloads pause when the limit or the device's free space runs low.")
                        .font(.casa(12)).foregroundStyle(Theme.textSecondary)
                    #if os(tvOS)
                    Text("Apple TV keeps torrent data in a cache that tvOS may empty when space is low and CasaPlay isn't running. CasaPlay checks every piece again and downloads anything missing.")
                        .font(.casa(12)).foregroundStyle(Theme.textSecondary)
                        .focusableOnTV()
                    #endif
                    HStack(spacing: Metrics.s(10)) {
                        Button("Remove oldest to fit") { Task { await center.trimCache() } }
                            .buttonStyle(.bordered)
                        Button("Clear torrent cache", role: .destructive) { confirmingClear = true }
                            .buttonStyle(.bordered)
                    }
                }

                SettingsGroup(title: "RSS feeds") {
                    Text("Add HTTPS feeds you are allowed to use, for example a project's release feed. Items need a .torrent enclosure or a magnet link.")
                        .font(.casa(12)).foregroundStyle(Theme.textSecondary)
                    ForEach(center.feeds) { feed in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(feed.name).font(.casa(14, weight: .semibold)).foregroundStyle(Theme.textPrimary)
                                Text(feed.url).font(.casa(11)).foregroundStyle(Theme.textSecondary).lineLimit(1)
                            }
                            Spacer()
                            Button(role: .destructive) { center.removeFeed(feed) } label: { Image(systemName: "trash") }
                                .buttonStyle(.bordered)
                        }
                    }
                    TextField("Name", text: $feedName)
                        #if !os(tvOS)
                        .textFieldStyle(.roundedBorder)
                        #endif
                    TextField("https://…", text: $feedURL)
                        #if !os(tvOS)
                        .textFieldStyle(.roundedBorder)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        #endif
                        .autocorrectionDisabled()
                    Button("Add feed") {
                        if center.addFeed(name: feedName, url: feedURL) { feedName = ""; feedURL = "" }
                    }
                    .buttonStyle(.bordered)
                    .disabled(feedURL.isEmpty)
                    if let message = center.message {
                        Text(message).font(.casa(12)).foregroundStyle(Color.orange)
                    }
                }

                SettingsGroup(title: "When CasaPlay is in the background") {
                    Text("iPhone, iPad and Apple TV pause apps that aren't on screen, so transfers stop when you leave CasaPlay and continue when you come back. Progress is saved.")
                        .font(.casa(12)).foregroundStyle(Theme.textSecondary)
                        .focusableOnTV()
                }
            }
            .padding(Metrics.screenPadding)
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Torrent settings")
        .onChange(of: center.settings) { _, _ in center.saveSettings() }
        .confirmationDialog("Delete all torrents and their data?", isPresented: $confirmingClear) {
            Button("Delete everything", role: .destructive) { Task { await center.clearCache() } }
            Button("Cancel", role: .cancel) {}
        }
    }
}

private struct SettingsGroup<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.s(10)) {
            Text(title)
                .font(.casa(17, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            content()
        }
        .padding(Metrics.s(16))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Metrics.cornerRadius, style: .continuous))
    }
}
