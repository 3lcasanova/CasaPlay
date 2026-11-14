// CasaPlay · Designed by 𝐂𝓪sΔηⓞשα
//
// API keys for TMDB, TheTVDB, IMDb ratings (through OMDb) and OpenSubtitles. Saved on this device only.

import SwiftUI
import CasaPlayKit

struct OnlineServicesView: View {
    @AppStorage(ServiceKeys.tmdb) private var tmdbKey = ""
    @AppStorage(ServiceKeys.tvdb) private var tvdbKey = ""
    @AppStorage(ServiceKeys.omdb) private var omdbKey = ""
    @AppStorage(ServiceKeys.openSubtitles) private var openSubtitlesKey = ""
    @AppStorage(ServiceKeys.openSubtitlesUser) private var username = ""
    @AppStorage(ServiceKeys.openSubtitlesToken) private var token = ""
    @AppStorage(ServiceKeys.nihonSubAddress) private var nihonSubAddress = ""
    @AppStorage(ServiceKeys.nihonSubToken) private var nihonSubToken = ""
    @State private var password = ""
    @State private var status: String?
    @State private var isSigningIn = false
    @State private var checks: [KeyCheck] = []
    @State private var isChecking = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Metrics.sectionSpacing / 2) {
                ScreenTitle("Online services")
                ServiceSection(
                    title: "TMDB (movies and shows)",
                    detail: "Posters, trending titles, details and episode lists for Home, Movies and Series. Paste the read access token or the API key from themoviedb.org under Settings → API."
                ) {
                    SecureField("TMDB read access token or API key", text: $tmdbKey)
                        .fieldStyle()
                    KeySourceNote(entered: tmdbKey, builtIn: ServiceKeys.builtIn(ServiceKeys.tmdb))
                }

                ServiceSection(
                    title: "TheTVDB (episodes)",
                    detail: "Backs up TMDB for episode lists and fills in missing episode titles, summaries and pictures. Paste your project API key from thetvdb.com under Dashboard → API keys."
                ) {
                    SecureField("TheTVDB API key", text: $tvdbKey)
                        .fieldStyle()
                    KeySourceNote(entered: tvdbKey, builtIn: ServiceKeys.builtIn(ServiceKeys.tvdb))
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

                ServiceSection(
                    title: "NihonSub (AI subtitles)",
                    detail: "Optional. Your Mac listens to a video and writes subtitles in English, Hindi or Hinglish. Start the CasaPlay bridge on the Mac (companion/start.sh), then copy the address and token it prints."
                ) {
                    TextField("Mac address, like 192.168.1.20:3100", text: $nihonSubAddress)
                        .fieldStyle()
                        #if !os(tvOS)
                        .textInputAutocapitalization(.never)
                        .keyboardType(.URL)
                        #endif
                        .autocorrectionDisabled()
                    SecureField("Bridge token", text: $nihonSubToken)
                        .fieldStyle()
                    Text(
                        nihonSubAddress.trimmingCharacters(in: .whitespaces).isEmpty || nihonSubToken.trimmingCharacters(in: .whitespaces).isEmpty
                        ? "Not set up. Subtitles made this way need your Mac to be on."
                        : "Set up. Use Test keys below to check the connection."
                    )
                    .font(.casa(12))
                    .foregroundStyle(Theme.textSecondary)
                }

                ServiceSection(
                    title: "Test keys",
                    detail: "Checks the TMDB, TheTVDB and OpenSubtitles keys against the live services, and the NihonSub bridge if you set it up."
                ) {
                    HStack(spacing: Metrics.s(10)) {
                        Button("Test keys") {
                            Task { await runChecks() }
                        }
                        .buttonStyle(.bordered)
                        .disabled(isChecking)
                        if isChecking { ProgressView() }
                    }
                    ForEach(checks) { check in
                        Label(
                            "\(check.service): \(check.message)",
                            systemImage: check.ok ? "checkmark.circle.fill" : "xmark.octagon.fill"
                        )
                        .font(.casa(12))
                        .foregroundStyle(check.ok ? Theme.textPrimary : Theme.textSecondary)
                    }
                }

                Text("Keys stay on this device. CasaPlay only sends them to TMDB, TheTVDB, OMDb and OpenSubtitles. The NihonSub token goes only to your own Mac.")
                    .font(.casa(12))
                    .foregroundStyle(Theme.textSecondary)
                    .focusableOnTV()
            }
            .padding(Metrics.screenPadding)
        }
        .screenBackground()
        .scrollingScreenTitle("Online services")
    }

    private func runChecks() async {
        isChecking = true
        defer { isChecking = false }
        var results: [KeyCheck] = []
        let tmdb = ServiceKeys.value(ServiceKeys.tmdb)
        results.append(await check("TMDB", key: tmdb) { try await TMDBClient(apiKey: tmdb).verify() })
        let tvdb = ServiceKeys.value(ServiceKeys.tvdb)
        results.append(await check("TheTVDB", key: tvdb) { try await TVDBClient(apiKey: tvdb).verify() })
        let subtitles = ServiceKeys.value(ServiceKeys.openSubtitles)
        results.append(await check("OpenSubtitles", key: subtitles) { try await OpenSubtitlesClient(apiKey: subtitles).verify() })
        // The bridge is optional, so it is only checked once something has been entered for it.
        let bridgeEntered = !(nihonSubAddress + nihonSubToken).trimmingCharacters(in: .whitespaces).isEmpty
        if bridgeEntered {
            if let bridge = NihonSubClient(address: nihonSubAddress, token: nihonSubToken) {
                results.append(await check("NihonSub", key: "set") { try await bridge.verify() })
            } else {
                results.append(KeyCheck(service: "NihonSub", ok: false, message: "enter both the Mac address and the token"))
            }
        }
        checks = results
    }

    private func check(_ service: String, key: String, _ test: () async throws -> Void) async -> KeyCheck {
        guard !key.isEmpty else { return KeyCheck(service: service, ok: false, message: "no key yet") }
        do {
            try await test()
            return KeyCheck(service: service, ok: true, message: "working")
        } catch {
            return KeyCheck(service: service, ok: false, message: error.localizedDescription)
        }
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

private struct KeyCheck: Identifiable {
    let id = UUID()
    let service: String
    let ok: Bool
    let message: String
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
