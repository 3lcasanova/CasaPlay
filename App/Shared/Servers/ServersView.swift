// CasaPlay · Designed by 𝐂𝓪sΔηⓞשα
//
// Manage Plex and Jellyfin server connections.

import SwiftUI
import CasaPlayKit

struct ServersView: View {
    @Environment(ServerCenter.self) private var center
    @State private var showAdd = false

    var body: some View {
        NavigationStack {
            Group {
                if center.servers.isEmpty {
                    emptyState
                } else {
                    serverList
                }
            }
            .screenBackground()
            .scrollingScreenTitle("Servers")
            #if !os(tvOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showAdd = true } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            #endif
        }
        .sheet(isPresented: $showAdd) {
            AddServerSheet()
        }
    }

    // MARK: - Server list

    private var serverList: some View {
        ScrollView {
            LazyVStack(spacing: Metrics.s(10)) {
                #if os(tvOS)
                Button { showAdd = true } label: {
                    Label("Add Server", systemImage: "plus")
                        .font(.casa(14, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                        .frame(maxWidth: .infinity)
                        .padding(Metrics.s(14))
                        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Metrics.cornerRadius))
                }
                .cardRowButtonStyle()
                #endif

                ForEach(center.servers) { server in
                    ServerRow(server: server)
                }
            }
            .padding(Metrics.screenPadding)
        }
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: Metrics.s(20)) {
            Image(systemName: "server.rack")
                .font(.casa(48))
                .foregroundStyle(Theme.textSecondary)

            VStack(spacing: Metrics.s(8)) {
                Text("No Servers")
                    .font(.casa(18, weight: .bold))
                    .foregroundStyle(Theme.textPrimary)
                Text("Connect Plex, Jellyfin or a direct M3U playlist\nto stream from your own sources.")
                    .font(.casa(14))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
            }

            Button {
                showAdd = true
            } label: {
                Label("Add Server", systemImage: "plus.circle.fill")
                    .font(.casa(14, weight: .semibold))
                    .foregroundStyle(Theme.onAccent)
                    .padding(.horizontal, Metrics.s(20))
                    .padding(.vertical, Metrics.s(10))
                    .background(Theme.accent, in: Capsule())
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(Metrics.screenPadding)
    }
}

// MARK: - Server row

private struct ServerRow: View {
    let server: ServerConfig
    @Environment(ServerCenter.self) private var center
    @State private var showConfirmDelete = false
    @State private var summary: String?

    var body: some View {
        HStack(spacing: Metrics.s(14)) {
            // Kind icon
            Image(systemName: iconName)
                .font(.casa(20))
                .foregroundStyle(server.isEnabled ? Theme.accent : Theme.textSecondary)
                .frame(width: Metrics.s(36), height: Metrics.s(36))
                .background(Theme.surfaceStrong, in: RoundedRectangle(cornerRadius: 8))

            VStack(alignment: .leading, spacing: 3) {
                Text(server.name)
                    .font(.casa(14, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                HStack(spacing: Metrics.s(6)) {
                    Text(server.kind.label)
                        .font(.casa(11))
                        .foregroundStyle(Theme.textSecondary)
                    Text("·").foregroundStyle(Theme.textSecondary).font(.casa(11))
                    Text(server.displaySource)
                        .font(.casa(11))
                        .foregroundStyle(Theme.textSecondary)
                        .lineLimit(1)
                }
                if server.kind == .xtream {
                    Text(summary ?? "Checking…")
                        .font(.casa(11, weight: .medium))
                        .foregroundStyle((summary ?? "").hasPrefix("Connected") ? Theme.accent : Theme.textSecondary)
                        .lineLimit(2)
                }
            }
            .task(id: server.id) {
                if server.kind == .xtream { summary = await center.xtreamSummary(for: server) }
            }

            Spacer(minLength: 0)

            // Enable toggle
            #if !os(tvOS)
            Toggle("", isOn: Binding(
                get: { server.isEnabled },
                set: { center.setEnabled(server.id, $0) }
            ))
            .labelsHidden()
            .tint(Theme.accent)
            #endif

            // Remove button
            Button(role: .destructive) {
                showConfirmDelete = true
            } label: {
                Image(systemName: "trash")
                    .font(.casa(14))
                    .foregroundStyle(.red.opacity(0.7))
            }
            .buttonStyle(.plain)
        }
        .padding(Metrics.s(14))
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Metrics.cornerRadius, style: .continuous))
        .confirmationDialog("Remove \"\(server.name)\"?",
                            isPresented: $showConfirmDelete,
                            titleVisibility: .visible) {
            Button("Remove", role: .destructive) { center.remove(server.id) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Your library access will be removed from this device.")
        }
    }

    private var iconName: String {
        switch server.kind {
        case .plex: return "play.rectangle.fill"
        case .jellyfin: return "film.stack"
        case .nativePlaylist: return "list.bullet.rectangle"
        case .xtream: return "antenna.radiowaves.left.and.right"
        }
    }
}

// MARK: - Add server sheet

private struct AddServerSheet: View {
    @Environment(ServerCenter.self) private var center
    @Environment(\.dismiss) private var dismiss

    /// Server types offered when adding. Only Xtream Codes for now; add .plex, .jellyfin, .nativePlaylist to bring them back.
    private let offeredKinds: [ServerKind] = [.xtream]
    @State private var kind: ServerKind = .xtream
    @State private var name: String = ""
    @State private var urlString: String = ""
    @State private var token: String = ""
    @State private var username: String = ""
    @State private var isAdding = false
    @State private var error: String?

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty && !urlString.isEmpty && (kind == .nativePlaylist || !token.isEmpty) && (kind != .xtream || !username.trimmingCharacters(in: .whitespaces).isEmpty)
    }

    var body: some View {
        NavigationStack {
            Form {
                // Server type
                if offeredKinds.count > 1 {
                Section("Server Type") {
                    Picker("Type", selection: $kind) {
                        ForEach(offeredKinds, id: \.self) { k in
                            Text(k.label).tag(k)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: kind) { old, _ in
                        if name == old.label { name = kind.label }
                        if urlString.hasPrefix("http://192.168.1.x:") { urlString = "" }
                        token = ""
                        username = ""
                        // A message about the last server type says nothing about this one.
                        error = nil
                        prefillDefaults()
                    }
                }
                }

                // Connection
                Section("Connection") {
                    HStack {
                        Text("Name")
                            .foregroundStyle(Theme.textSecondary)
                        TextField(placeholderName, text: $name)
                            .multilineTextAlignment(.trailing)
                    }
                    HStack {
                        Text("URL")
                            .foregroundStyle(Theme.textSecondary)
                        TextField(placeholderURL, text: $urlString)
                            .multilineTextAlignment(.trailing)
                            .onChange(of: urlString) { _, _ in error = nil }
                            #if !os(tvOS)
                            .textInputAutocapitalization(.never)
                            .keyboardType(.URL)
                            #endif
                    }
                }

                // Auth
                Section(authLabel) {
                    if kind == .xtream {
                        HStack {
                            Text("Username")
                                .foregroundStyle(Theme.textSecondary)
                            TextField("Required", text: $username)
                                .multilineTextAlignment(.trailing)
                                .onChange(of: username) { _, _ in error = nil }
                                #if !os(tvOS)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled()
                                #endif
                        }
                    }
                    HStack {
                        Text(tokenLabel)
                            .foregroundStyle(Theme.textSecondary)
                        SecureField(kind == .nativePlaylist ? "Optional" : "Required", text: $token)
                            .multilineTextAlignment(.trailing)
                    }
                }

                // Error
                if let error {
                    Section {
                        Text(error)
                            .font(.casa(12))
                            .foregroundStyle(.red)
                    }
                }

                // How to get the token
                Section {
                    Text(tokenHelpText)
                        .font(.casa(12))
                        .foregroundStyle(Theme.textSecondary)
                }

                #if os(tvOS)
                // tvOS has no toolbar; action buttons live in the form.
                Section {
                    if isAdding {
                        HStack {
                            ProgressView()
                            Text("Connecting…").font(.casa(13)).foregroundStyle(Theme.textSecondary)
                        }
                    } else {
                        Button("Add Server") { Task { await addServer() } }
                            .disabled(!isValid)
                    }
                    Button("Cancel") { dismiss() }
                }
                #endif
            }
            .scrollingScreenTitle("Add Server")
            #if !os(tvOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    if isAdding {
                        ProgressView()
                    } else {
                        Button("Add") { Task { await addServer() } }
                            .disabled(!isValid)
                    }
                }
            }
            #endif
        }
        .onAppear { prefillDefaults() }
    }

    // MARK: - Helpers

    private func addServer() async {
        isAdding = true
        error = nil
        defer { isAdding = false }
        do {
            let secret = kind == .xtream
                ? XtreamLogin(username: username.trimmingCharacters(in: .whitespaces), password: token).stored
                : token
            try await center.addServer(kind: kind, name: name, urlString: urlString, token: secret)
            dismiss()
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func prefillDefaults() {
        if name.isEmpty { name = kind.label }
        if urlString.isEmpty && kind != .nativePlaylist && kind != .xtream { urlString = "http://192.168.1.x:\(kind.defaultPort)" }
    }

    private var placeholderName: String { kind.label }
    private var placeholderURL: String { kind == .xtream ? "https://example.com" : kind == .nativePlaylist ? "https://example.com/catalog.m3u" : "http://192.168.1.x:\(kind.defaultPort)" }
    private var authLabel: String { kind == .jellyfin ? "API Key" : "Authentication" }
    private var tokenLabel: String { kind == .xtream ? "Password" : kind == .nativePlaylist ? "Bearer Token" : (kind == .plex ? "Plex Token" : "API Key") }

    private var tokenHelpText: String {
        switch kind {
        case .plex:
            return "Find your token at plex.tv/claim or in Plex Web: Settings → Account → Manage → Authorized Devices. Never share it."
        case .nativePlaylist:
            return "Add an Extended M3U catalog from your provider. Entries must match title IDs; episodes must identify their season and episode. No Stremio add-on is needed. A link that ends in ?username=… is accepted, and that part is kept in the Keychain. The optional token authenticates the playlist only, not its videos."
        case .xtream:
            return "Enter the server address your provider gave you (just https://site.com), then your username and password. They are kept in the Keychain on this device only. Movies and shows from your provider appear as sources when you play a title."
        case .jellyfin:
            return "Create an API key in Jellyfin Dashboard → API Keys → +. Never share it."
        }
    }
}
