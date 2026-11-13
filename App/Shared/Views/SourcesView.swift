// CasaPlay · Designed by 𝐂𝓪sΔηⓞשα

import SwiftUI
import CasaPlayKit

struct SourcesView: View {
    @Environment(AppState.self) private var app
    @State private var showingInfo = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Metrics.s(12)) {
                    ForEach(app.sources) { source in
                        SourceRow(source: source)
                            .focusableOnTV()
                    }

                    Button {
                        showingInfo = true
                    } label: {
                        Label("Add source", systemImage: "plus")
                    }
                    .buttonStyle(.bordered)
                    .padding(.top, Metrics.s(8))

                    Text("These sources are samples. Real connections (Mac folder, SMB/NFS share, Plex, Jellyfin) come in the Library and Servers phases.")
                        .font(.casa(12))
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.top, Metrics.s(4))
                        .focusableOnTV()
                }
                .padding(Metrics.screenPadding)
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Sources")
            .alert("Adding sources", isPresented: $showingInfo) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("Connecting a Mac, network drive or media server is not built yet. It arrives with the Library phase.")
            }
        }
    }
}

private struct SourceRow: View {
    let source: MediaSource

    private var symbol: String {
        switch source.kind {
        case .mac: return "desktopcomputer"
        case .nas: return "externaldrive"
        case .plex: return "play.rectangle"
        case .jellyfin: return "server.rack"
        case .network: return "network"
        }
    }

    var body: some View {
        HStack(spacing: Metrics.s(14)) {
            Image(systemName: symbol)
                .font(.casa(20))
                .foregroundStyle(Theme.accent)
                .frame(width: Metrics.s(36))

            VStack(alignment: .leading, spacing: 2) {
                Text(source.name)
                    .font(.casa(15, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(source.detail)
                    .font(.casa(12))
                    .foregroundStyle(Theme.textSecondary)
            }

            Spacer(minLength: Metrics.s(8))

            Text(source.status.label)
                .font(.casa(11, weight: .bold))
                .foregroundStyle(source.status == .connected ? Theme.onAccent : Theme.textPrimary)
                .padding(.horizontal, Metrics.s(9))
                .padding(.vertical, Metrics.s(3))
                .background(
                    source.status == .connected ? Theme.accent : Theme.surfaceStrong,
                    in: Capsule()
                )
        }
        .padding(Metrics.s(14))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Metrics.cornerRadius, style: .continuous))
    }
}
