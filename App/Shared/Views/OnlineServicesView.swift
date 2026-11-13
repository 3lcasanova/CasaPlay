// CasaPlay · Designed by 𝐂𝓪sΔηⓞשα
//
// API keys for IMDb ratings (through OMDb) and OpenSubtitles. Saved on this device only.

import SwiftUI
import CasaPlayKit

struct OnlineServicesView: View {
    @AppStorage(ServiceKeys.tmdb) private var tmdbKey = ""
    @AppStorage(ServiceKeys.omdb) private var omdbKey = ""
    @AppStorage(ServiceKeys.openSubtitles) private var openSubtitlesKey = ""
    @AppStorage(ServiceKeys.openSubtitlesUser) private var username = ""
    @AppStorage(ServiceKeys.openSubtitlesToken) private var token = ""
    @State private var password = ""
    @State private var status: String?
    @State private var isSigningIn = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Metrics.sectionSpacing / 2) {
                ServiceSection(
                    title: "TMDB (search)",
                    detail: "Powers the Search tab — movie and TV show discovery with posters and metadata. Get a free read access token at themoviedb.org under Settings → API."
                ) {
                    SecureField("TMDB read access token", text: $tmdbKey)
                        .fieldStyle()
                    KeySourceNote(entered: tmdbKey, builtIn: ServiceKeys.builtIn(ServiceKeys.tmdb))
                }

                ServiceSection(
                    title: "IMDb ratings",
                    detail: "IMDb has no public API, so CasaPlay reads IMDb ratings through OMDb. Get a free key at omdbapi.com."
                ) {
                    SecureField("OMDb API key", text: $omdbKey)
                        .fieldStyle()
                    KeySourceNote(entered: omdbKey, builtIn: ServiceKeys.builtIn(ServiceKeys.omdb))
                }

                ServiceSection(
                    title: "OpenSubtitles",
                    detail: "Search and download subtitles. Get a free API key at opensubtitles.com under API consumers. Signing in raises the daily download limit."
                ) {
                    SecureField("OpenSubtitles API key", text: $openSubtitlesKey)
                        .fieldStyle()
                    KeySourceNote(entered: openSubtitlesKey, builtIn: ServiceKeys.builtIn(ServiceKeys.openSubtitles))
                    TextField("Username (optional)", text: $username)
                        .fieldStyle()
                        #if !os(tvOS)
                        .textInputAutocapitalization(.never)
                        #endif
                        .autocorrectionDisabled()
                    SecureField("Password (optional)", text: $password)
                        .fieldStyle()

                    HStack(spacing: Metrics.s(10)) {
                        Button(token.isEmpty ? "Sign in" : "Sign in again") {
                            Task { await signIn() }
                        }
                        .buttonStyle(.bordered)
                        .disabled(ServiceKeys.value(ServiceKeys.openSubtitles).isEmpty || username.isEmpty || password.isEmpty || isSigningIn)

                        if !token.isEmpty {
                            Button("Sign out") {
                                token = ""
                                status = "Signed out."
                            }
                            .buttonStyle(.bordered)
                        }
                        if isSigningIn { ProgressView() }
                    }

                    Text(status ?? (token.isEmpty ? "Not signed in." : "Signed in as \(username)."))
                        .font(.casa(12))
                        .foregroundStyle(Theme.textSecondary)
                }

                Text("Keys stay on this device. CasaPlay only sends them to TMDB, OMDb and OpenSubtitles.")
                    .font(.casa(12))
                    .foregroundStyle(Theme.textSecondary)
                    .focusableOnTV()
            }
            .padding(Metrics.screenPadding)
        }
        .background(Theme.background.ignoresSafeArea())
        .navigationTitle("Online services")
    }

    private func signIn() async {
        isSigningIn = true
        defer { isSigningIn = false }
        do {
            let client = OpenSubtitlesClient(apiKey: ServiceKeys.value(ServiceKeys.openSubtitles))
            token = try await client.login(username: username, password: password)
            password = ""
            status = "Signed in as \(username)."
        } catch {
            status = error.localizedDescription
        }
    }
}

/// Says which key is in use: the one typed here, the built-in one, or none.
private struct KeySourceNote: View {
    let entered: String
    let builtIn: String

    var body: some View {
        Text(
            !entered.trimmingCharacters(in: .whitespaces).isEmpty ? "Using the key entered here."
            : builtIn.isEmpty ? "No key yet. Paste one above."
            : "Using the built-in key. Paste another above to replace it."
        )
        .font(.casa(12))
        .foregroundStyle(Theme.textSecondary)
    }
}

private struct ServiceSection<Content: View>: View {
    let title: String
    let detail: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.s(10)) {
            Text(title)
                .font(.casa(17, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
            Text(detail)
                .font(.casa(12))
                .foregroundStyle(Theme.textSecondary)
            content()
        }
        .padding(Metrics.s(16))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Metrics.cornerRadius, style: .continuous))
    }
}

private extension View {
    @ViewBuilder
    func fieldStyle() -> some View {
        #if os(tvOS)
        self
        #else
        self
            .textFieldStyle(.roundedBorder)
            .font(.casa(14))
        #endif
    }
}
