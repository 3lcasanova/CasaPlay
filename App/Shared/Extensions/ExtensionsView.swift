// CasaPlay · Designed by 𝐂𝓪sΔηⓞשα
//
// Unified Extensions screen: Repositories · Add-ons · Providers
// Works on iPhone, iPad and Apple TV.

import SwiftUI
import CasaPlayKit

// MARK: - Root view

struct ExtensionsView: View {
    @Environment(ExtensionCenter.self) private var center
    @State private var tab: Tab = .addons

    enum Tab: String, CaseIterable, Identifiable {
        case repositories, addons, providers
        var id: String { rawValue }
        var title: String {
            switch self {
            case .repositories: "Repositories"
            case .addons: "Add-ons"
            case .providers: "Providers"
            }
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Tab bar
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: Metrics.s(8)) {
                        ForEach(Tab.allCases) { t in
                            ChipButton(t.title, selected: tab == t) { tab = t }
                        }
                    }
                    .padding(.horizontal, Metrics.screenPadding)
                    .padding(.vertical, Metrics.s(10))
                }

                Divider().background(Theme.surfaceStrong)

                // Content
                switch tab {
                case .repositories: RepositoriesTab()
                case .addons: AddonsTab()
                case .providers: ProvidersTab()
                }
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Extensions")
            #if !os(tvOS)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { Task { await center.checkForUpdates() } } label: {
                        Label("Check for updates", systemImage: "arrow.triangle.2.circlepath")
                    }
                }
            }
            #endif
        }
    }
}

// MARK: - Repositories tab

private struct RepositoriesTab: View {
    @Environment(ExtensionCenter.self) private var center
    @State private var adding = false
    @State private var urlText = ""
    @State private var error: String?

    var body: some View {
        ScrollView {
            LazyVStack(spacing: Metrics.s(10)) {
                ForEach(center.state.repositories) { repo in
                    RepositoryRow(repo: repo)
                }
                addButton
            }
            .padding(Metrics.screenPadding)
        }
        .alert("Add Repository", isPresented: $adding) {
            TextField("https://…/index.json", text: $urlText)
                .autocorrectionDisabled()
                #if !os(tvOS)
                .textInputAutocapitalization(.never)
                .keyboardType(.URL)
                #endif
            Button("Add") { Task { await addRepo() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Enter the URL of a CasaPlay repository, Stremio manifest, or add-on list.")
        }
        .alert("Error", isPresented: .constant(error != nil), actions: {
            Button("OK") { error = nil }
        }, message: { Text(error ?? "") })
    }

    private var addButton: some View {
        Button {
            urlText = ""
            adding = true
        } label: {
            Label("Add Repository", systemImage: "plus.circle")
                .frame(maxWidth: .infinity)
                .padding(Metrics.s(14))
        }
        .buttonStyle(.bordered)
        .focusableOnTV()
    }

    private func addRepo() async {
        guard !urlText.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        do {
            try await center.addRepository(urlText.trimmingCharacters(in: .whitespaces))
        } catch {
            self.error = (error as? ExtensionError)?.userFacingMessage ?? error.localizedDescription
        }
    }
}

private struct RepositoryRow: View {
    @Environment(ExtensionCenter.self) private var center
    let repo: ExtensionRepository
    @State private var showRemove = false

    var body: some View {
        HStack(spacing: Metrics.s(14)) {
            Image(systemName: repo.format.icon)
                .font(.casa(20))
                .foregroundStyle(Theme.accent)
                .frame(width: Metrics.s(36))

            VStack(alignment: .leading, spacing: 2) {
                Text(repo.name ?? repo.url.host ?? repo.url.absoluteString)
                    .font(.casa(14, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(repo.url.absoluteString)
                    .font(.casa(11))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
                HStack(spacing: Metrics.s(8)) {
                    Text(repo.format.label)
                        .badgeStyle(repo.format.isSupported ? .neutral : .warning)
                    Text("\(repo.entries.count) entry", comment: "1 entry / N entries")
                        .badgeStyle(.neutral)
                    if let err = repo.lastError {
                        Text(err)
                            .badgeStyle(.error)
                            .lineLimit(1)
                    }
                }
                .padding(.top, 2)
            }

            Spacer(minLength: 0)

            Menu {
                Button { Task { await center.refreshRepository(repo.id) } } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                Button(role: .destructive) { showRemove = true } label: {
                    Label("Remove", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.casa(18))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(Metrics.s(14))
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Metrics.cornerRadius, style: .continuous))
        .focusableOnTV()
        .confirmationDialog("Remove repository?", isPresented: $showRemove, titleVisibility: .visible) {
            Button("Remove", role: .destructive) { Task { await center.removeRepository(repo.id) } }
            Button("Cancel", role: .cancel) {}
        }
    }
}

// MARK: - Add-ons tab

private struct AddonsTab: View {
    @Environment(ExtensionCenter.self) private var center
    @State private var adding = false
    @State private var urlText = ""
    @State private var selectedAddon: InstalledExtension?

    var body: some View {
        ScrollView {
            LazyVStack(spacing: Metrics.s(10)) {
                if center.state.installed.isEmpty {
                    emptyState
                }
                ForEach(center.state.installed) { addon in
                    AddonRow(addon: addon)
                        .onTapGesture { selectedAddon = addon }
                }
                // Entries from repositories that can be installed
                let installable = center.state.repositories.flatMap(\.entries).filter { $0.compatibility.isUsable && $0.manifestURL != nil }
                if !installable.isEmpty {
                    Text("From repositories")
                        .font(.casa(12, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, Metrics.s(8))
                    ForEach(installable) { entry in
                        RepositoryEntryRow(entry: entry)
                    }
                }
                addButton
            }
            .padding(Metrics.screenPadding)
        }
        .sheet(item: $selectedAddon) { AddonDetailSheet(addon: $0) }
        .alert("Install Add-on", isPresented: $adding) {
            TextField("https://…/manifest.json", text: $urlText)
                .autocorrectionDisabled()
                #if !os(tvOS)
                .textInputAutocapitalization(.never)
                .keyboardType(.URL)
                #endif
            Button("Install") { Task { await installFromURL() } }
            Button("Cancel", role: .cancel) {}
        } message: {
            if let err = center.installError {
                Text(err)
            } else {
                Text("Paste the manifest URL (ending in /manifest.json).")
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: Metrics.s(10)) {
            Image(systemName: "puzzlepiece.extension")
                .font(.casa(40))
                .foregroundStyle(Theme.textSecondary)
            Text("No add-ons installed")
                .font(.casa(16, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Text("Add a Stremio-compatible manifest URL, or browse from a repository.")
                .font(.casa(13))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Metrics.s(40))
        .focusableOnTV()
    }

    private var addButton: some View {
        Button {
            urlText = ""
            adding = true
        } label: {
            Label("Install from URL", systemImage: "plus.circle")
                .frame(maxWidth: .infinity)
                .padding(Metrics.s(14))
        }
        .buttonStyle(.bordered)
        .focusableOnTV()
    }

    private func installFromURL() async {
        let url = urlText.trimmingCharacters(in: .whitespaces)
        guard !url.isEmpty, let parsed = URL(string: url) else { return }
        try? await center.install(manifestURL: parsed)
    }
}

private struct AddonRow: View {
    @Environment(ExtensionCenter.self) private var center
    let addon: InstalledExtension
    @State private var showRemove = false

    var body: some View {
        HStack(spacing: Metrics.s(14)) {
            // Health indicator
            Circle()
                .fill(addon.health.status.color)
                .frame(width: Metrics.s(8), height: Metrics.s(8))

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: Metrics.s(6)) {
                    Text(addon.displayName)
                        .font(.casa(14, weight: .semibold))
                        .foregroundStyle(addon.isEnabled ? Theme.textPrimary : Theme.textSecondary)
                    if !addon.isEnabled {
                        Text("disabled").badgeStyle(.neutral)
                    }
                    if addon.updateAvailable {
                        Text("update").badgeStyle(.info)
                    }
                }
                Text(addon.displaySource)
                    .font(.casa(11))
                    .foregroundStyle(Theme.textSecondary)
                HStack(spacing: Metrics.s(6)) {
                    Text("v\(addon.version)").badgeStyle(.neutral)
                    ForEach(addon.capabilities, id: \.self) { c in
                        Text(c.rawValue).badgeStyle(.neutral)
                    }
                    Text(addon.role.label).badgeStyle(addon.role == .primary ? .accent : .neutral)
                }
                .padding(.top, 1)
                if let msg = addon.compatibility.limitedReason {
                    Text(msg).font(.casa(11)).foregroundStyle(Theme.accent).padding(.top, 1)
                }
                if let err = addon.health.lastError {
                    Text(err).font(.casa(11)).foregroundStyle(.red.opacity(0.85)).lineLimit(2).padding(.top, 1)
                }
            }

            Spacer(minLength: 0)

            Menu {
                Toggle("Enabled", isOn: Binding(get: { addon.isEnabled }, set: { v in Task { await center.setEnabled(addon.id, v) } }))
                Menu("Role") {
                    ForEach([ProviderRole.primary, .backup], id: \.self) { r in
                        Button {
                            Task { await center.setRole(addon.id, r) }
                        } label: {
                            if addon.role == r { Label(r.label, systemImage: "checkmark") } else { Text(r.label) }
                        }
                    }
                }
                Button { Task { await center.move(addon.id, by: -1) } } label: {
                    Label("Move up", systemImage: "arrow.up")
                }
                Button { Task { await center.move(addon.id, by: 1) } } label: {
                    Label("Move down", systemImage: "arrow.down")
                }
                if addon.updateAvailable {
                    Button { Task { try? await center.update(addon.id) } } label: {
                        Label("Update to \(addon.availableVersion ?? "latest")", systemImage: "arrow.down.circle")
                    }
                }
                Divider()
                Button(role: .destructive) { showRemove = true } label: {
                    Label("Remove", systemImage: "trash")
                }
            } label: {
                Image(systemName: "ellipsis.circle")
                    .font(.casa(18))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(Metrics.s(14))
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Metrics.cornerRadius, style: .continuous))
        .focusableOnTV()
        .confirmationDialog("Remove \(addon.displayName)?", isPresented: $showRemove, titleVisibility: .visible) {
            Button("Remove", role: .destructive) { Task { await center.remove(addon.id) } }
            Button("Cancel", role: .cancel) {}
        }
    }
}

private struct RepositoryEntryRow: View {
    @Environment(ExtensionCenter.self) private var center
    let entry: RepositoryEntry
    @State private var installing = false

    var body: some View {
        HStack(spacing: Metrics.s(14)) {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.name)
                    .font(.casa(14, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                if let d = entry.description {
                    Text(d).font(.casa(11)).foregroundStyle(Theme.textSecondary).lineLimit(2)
                }
            }
            Spacer(minLength: 0)
            Button {
                guard let url = entry.manifestURL else { return }
                installing = true
                Task {
                    try? await center.install(manifestURL: url)
                    installing = false
                }
            } label: {
                if installing {
                    ProgressView().scaleEffect(0.7)
                } else {
                    Text("Install").font(.casa(12, weight: .semibold))
                }
            }
            .buttonStyle(.bordered)
            .disabled(installing || center.state.installed.contains(where: { $0.id == entry.id }))
        }
        .padding(Metrics.s(12))
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Metrics.cornerRadius, style: .continuous))
        .focusableOnTV()
    }
}

private struct AddonDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(ExtensionCenter.self) private var center
    let addon: InstalledExtension

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Metrics.s(16)) {
                    // Header
                    HStack(spacing: Metrics.s(14)) {
                        Circle().fill(addon.health.status.color)
                            .frame(width: Metrics.s(10), height: Metrics.s(10))
                        Text(addon.displayName)
                            .font(.casa(20, weight: .bold))
                            .foregroundStyle(Theme.textPrimary)
                    }
                    if let d = addon.manifest.description {
                        Text(d).font(.casa(13)).foregroundStyle(Theme.textSecondary)
                    }
                    Divider().background(Theme.surfaceStrong)

                    // Details grid
                    InfoGrid(rows: [
                        ("Version", addon.version),
                        ("Source", addon.displaySource),
                        ("Role", addon.role.label),
                        ("Priority", "\(addon.priority)"),
                        ("Format", addon.format.label),
                        ("Installed", addon.installedAt.formatted(date: .abbreviated, time: .omitted)),
                        ("Last checked", addon.health.lastChecked?.formatted() ?? "—"),
                    ])

                    // Capabilities
                    if !addon.capabilities.isEmpty {
                        SectionHeader("Capabilities")
                        HStack(spacing: Metrics.s(6)) {
                            ForEach(addon.capabilities, id: \.self) { c in
                                Text(c.rawValue).badgeStyle(.accent)
                            }
                        }
                    }

                    // Compatibility
                    switch addon.compatibility {
                    case .supported: EmptyView()
                    case .limited(let r):
                        InfoRow(label: "⚠ Limited", value: r)
                    case .unsupported(let r):
                        InfoRow(label: "✕ Unsupported", value: r)
                    }

                    // Health error
                    if let err = addon.health.lastError {
                        SectionHeader("Last error")
                        Text(err).font(.casa(12)).foregroundStyle(.red.opacity(0.85))
                            .padding(Metrics.s(10))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Color.red.opacity(0.08), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }
                }
                .padding(Metrics.screenPadding)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Add-on Details")
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

// MARK: - Providers tab (quality mode + per-provider summary)

private struct ProvidersTab: View {
    @Environment(ExtensionCenter.self) private var center

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Metrics.s(20)) {
                // Quality mode picker
                SectionHeader("Stream Quality")
                VStack(spacing: Metrics.s(8)) {
                    ForEach([QualityMode.preferUHD, .uhdOnly, .allowFHDFallback], id: \.label) { mode in
                        QualityModeRow(mode: mode, selected: center.qualityMode == mode) {
                            center.setQualityMode(mode)
                        }
                    }
                }

                Divider().background(Theme.surfaceStrong)

                // Active add-ons acting as providers
                SectionHeader("Stream providers")
                let providers = center.state.installed.filter { $0.isEnabled && $0.capabilities.contains(.stream) }
                if providers.isEmpty {
                    Text("Install a Stremio add-on that provides streams to see it here.")
                        .font(.casa(13))
                        .foregroundStyle(Theme.textSecondary)
                        .focusableOnTV()
                } else {
                    ForEach(providers) { addon in
                        ProviderSummaryRow(addon: addon)
                    }
                }

                Text("CasaPlay searches all enabled providers simultaneously. Primary providers are tried first; backup providers fill in if primary results are absent or below quality. Verified 4K always ranks above 1080p, regardless of provider order.")
                    .font(.casa(12))
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.top, Metrics.s(4))
                    .focusableOnTV()
            }
            .padding(Metrics.screenPadding)
        }
    }
}

private struct QualityModeRow: View {
    let mode: QualityMode
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: Metrics.s(14)) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle")
                    .font(.casa(18))
                    .foregroundStyle(selected ? Theme.accent : Theme.textSecondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(mode.label)
                        .font(.casa(14, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                    Text(mode.explanation)
                        .font(.casa(11))
                        .foregroundStyle(Theme.textSecondary)
                }
                Spacer(minLength: 0)
            }
            .padding(Metrics.s(14))
            .background(selected ? Theme.accent.opacity(0.12) : Theme.surface,
                        in: RoundedRectangle(cornerRadius: Metrics.cornerRadius, style: .continuous))
        }
        .buttonStyle(.plain)
        .focusableOnTV()
    }
}

private struct ProviderSummaryRow: View {
    let addon: InstalledExtension
    var body: some View {
        HStack(spacing: Metrics.s(14)) {
            Circle().fill(addon.health.status.color)
                .frame(width: Metrics.s(8), height: Metrics.s(8))
            VStack(alignment: .leading, spacing: 2) {
                Text(addon.displayName)
                    .font(.casa(13, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(addon.displaySource)
                    .font(.casa(11))
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer(minLength: 0)
            Text(addon.role.label)
                .badgeStyle(addon.role == .primary ? .accent : .neutral)
            Text("#\(addon.priority + 1)")
                .font(.casa(11))
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(Metrics.s(12))
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Metrics.cornerRadius, style: .continuous))
        .focusableOnTV()
    }
}

// MARK: - Shared helpers

private struct SectionHeader: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text)
            .font(.casa(12, weight: .semibold))
            .foregroundStyle(Theme.textSecondary)
            .textCase(.uppercase)
            .tracking(1)
    }
}

private struct InfoGrid: View {
    let rows: [(String, String)]
    var body: some View {
        VStack(spacing: Metrics.s(8)) {
            ForEach(rows, id: \.0) { InfoRow(label: $0.0, value: $0.1) }
        }
    }
}

private struct InfoRow: View {
    let label: String
    let value: String
    var body: some View {
        HStack(alignment: .top) {
            Text(label)
                .font(.casa(12, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
                .frame(width: 100, alignment: .leading)
            Text(value)
                .font(.casa(12))
                .foregroundStyle(Theme.textPrimary)
        }
    }
}

// MARK: - Extension helpers

private extension HealthStatus {
    var color: Color {
        switch self {
        case .ok: return .green
        case .failing: return .red
        case .unknown: return Theme.textSecondary
        }
    }
}

private extension ProviderRole {
    var label: String {
        switch self {
        case .primary: "Primary"
        case .backup: "Backup"
        }
    }
}

private extension ExtensionFormat {
    var label: String {
        switch self {
        case .stremioAddon: "Stremio"
        case .casaPlayRepository: "CasaPlay repo"
        case .nuvioPlugins: "Nuvio (JS)"
        case .kodiRepository: "Kodi (Python)"
        case .unknown: "Unknown"
        }
    }
    var icon: String {
        switch self {
        case .stremioAddon, .casaPlayRepository: "puzzlepiece.extension"
        case .nuvioPlugins, .kodiRepository: "xmark.octagon"
        case .unknown: "questionmark.circle"
        }
    }
    var isSupported: Bool {
        switch self {
        case .stremioAddon, .casaPlayRepository: true
        default: false
        }
    }
}

private extension ExtensionCompatibility {
    var limitedReason: String? {
        if case .limited(let r) = self { return r }
        return nil
    }
}

private extension QualityMode {
    var label: String {
        switch self {
        case .preferUHD: return "Prefer 4K"
        case .uhdOnly: return "4K only"
        case .allowFHDFallback: return "Allow 1080p fallback"
        }
    }
    var explanation: String {
        switch self {
        case .preferUHD: return "Show all streams. Verified 4K appears first."
        case .uhdOnly: return "Only verified 4K streams are shown. Tells you plainly when none qualify."
        case .allowFHDFallback: return "Show verified 4K and 1080p. Sub-1080p streams are hidden."
        }
    }
}

private extension ExtensionError {
    var userFacingMessage: String {
        switch self {
        case .invalidURL: return "The URL is not valid."
        case .insecureURL: return "Only HTTPS add-ons are accepted."
        case .tooLarge: return "The file is too large."
        case .invalidManifest(let r): return "Invalid manifest: \(r)"
        case .unsupported(let r): return "Not supported: \(r)"
        case .requestFailed(let c): return "Network error (HTTP \(c))."
        case .notFound: return "The add-on could not be reached."
        case .timedOut: return "Connection timed out."
        case .duplicate: return "This add-on is already installed."
        }
    }
}

// MARK: - Badge style modifier

enum BadgeStyle { case neutral, accent, warning, error, info }
extension View {
    func badgeStyle(_ style: BadgeStyle) -> some View {
        self
            .font(.casa(10, weight: .semibold))
            .foregroundStyle(style.foreground)
            .padding(.horizontal, Metrics.s(6))
            .padding(.vertical, Metrics.s(2))
            .background(style.background, in: Capsule())
    }
}
private extension BadgeStyle {
    var foreground: Color {
        switch self {
        case .neutral: Theme.textSecondary
        case .accent: Theme.accent
        case .warning: Color.orange
        case .error: Color.red
        case .info: Color.blue
        }
    }
    var background: Color {
        switch self {
        case .neutral: Theme.surfaceStrong
        case .accent: Theme.accent.opacity(0.15)
        case .warning: Color.orange.opacity(0.15)
        case .error: Color.red.opacity(0.15)
        case .info: Color.blue.opacity(0.15)
        }
    }
}
