// CasaPlay · Designed by 𝐂𝓪sΔηⓞשα

import SwiftUI
import CasaPlayKit

struct ProfileView: View {
    @Environment(AppState.self) private var app
    @State private var showingAddProfile = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Metrics.sectionSpacing) {
                    Shelf(title: "Who's watching?") {
                        ForEach(app.profiles) { profile in
                            Button {
                                app.activeProfileID = profile.id
                            } label: {
                                ProfileTile(
                                    profile: profile,
                                    isSelected: profile.id == app.activeProfileID,
                                    canDelete: app.profiles.count > 1
                                ) {
                                    app.deleteProfile(id: profile.id)
                                }
                            }
                            .posterButtonStyle()
                            .contextMenu {
                                if app.profiles.count > 1 {
                                    Button("Delete \(profile.name)", systemImage: "trash", role: .destructive) {
                                        app.deleteProfile(id: profile.id)
                                    }
                                }
                            }
                        }

                        // Add profile button
                        Button { showingAddProfile = true } label: {
                            VStack(spacing: Metrics.s(8)) {
                                ZStack {
                                    Circle()
                                        .fill(Theme.surface)
                                        .frame(width: Metrics.s(72), height: Metrics.s(72))
                                    Image(systemName: "plus")
                                        .font(.casa(26))
                                        .foregroundStyle(Theme.accent)
                                }
                                .padding(Metrics.s(6))
                                Text("Add Profile")
                                    .font(.casa(13, weight: .semibold))
                                    .foregroundStyle(Theme.textSecondary)
                                    .lineLimit(1)
                            }
                            .frame(width: Metrics.s(100))
                        }
                        .posterButtonStyle()
                    }

                    VStack(alignment: .leading, spacing: Metrics.s(12)) {
                        NavigationLink {
                            SettingsView()
                        } label: {
                            SettingsLinkRow(
                                title: "Subtitles & playback",
                                detail: "Size, colour, background, position and delay",
                                symbol: "captions.bubble"
                            )
                        }
                        .posterButtonStyle()

                        NavigationLink {
                            OnlineServicesView()
                        } label: {
                            SettingsLinkRow(
                                title: "Online services",
                                detail: "IMDb ratings and OpenSubtitles",
                                symbol: "globe"
                            )
                        }
                        .posterButtonStyle()

                        if app.activeProfile.isKids {
                            Text("Kids profile: only G and PG titles are shown.")
                                .font(.casa(12))
                                .foregroundStyle(Theme.textSecondary)
                                .focusableOnTV()
                        }
                    }
                    .padding(.horizontal, Metrics.screenPadding)

                    VStack(alignment: .leading, spacing: Metrics.s(4)) {
                        Text("CasaPlay")
                            .font(.casa(13, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                        Text("Designed by 𝐂𝓪sΔηⓞשα")
                            .font(.casa(12))
                            .foregroundStyle(Theme.textSecondary)
                        Text("Early build · sample library")
                            .font(.casa(12))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .padding(.horizontal, Metrics.screenPadding)
                    .focusableOnTV()
                }
                .padding(.vertical, Metrics.s(16))
            }
            .background(Theme.background.ignoresSafeArea())
            .navigationTitle("Profile")
            .sheet(isPresented: $showingAddProfile) {
                AddProfileSheet { name, hue, isKids in
                    app.addProfile(name: name, hue: hue, isKids: isKids)
                }
            }
        }
    }
}

private struct ProfileTile: View {
    let profile: Profile
    let isSelected: Bool
    let canDelete: Bool
    let onDelete: () -> Void

    var body: some View {
        VStack(spacing: Metrics.s(8)) {
            ZStack(alignment: .topTrailing) {
                AvatarView(text: profile.glyph, hue: profile.hue, size: Metrics.s(72))
                    .overlay(
                        Circle()
                            .stroke(isSelected ? Theme.accent : Color.clear, lineWidth: Metrics.s(3))
                            .padding(-Metrics.s(5))
                    )
                    .padding(Metrics.s(6))

                #if !os(tvOS)
                if canDelete {
                    Button(role: .destructive, action: onDelete) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.casa(20))
                            .foregroundStyle(Theme.textSecondary)
                            .background(Theme.background, in: Circle())
                    }
                    .buttonStyle(.plain)
                    .offset(x: Metrics.s(4), y: -Metrics.s(4))
                }
                #endif
            }

            Text(profile.name)
                .font(.casa(13, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)

            if profile.isKids {
                Pill(text: "KIDS")
            }
        }
        .frame(width: Metrics.s(100))
    }
}

private struct AddProfileSheet: View {
    let onAdd: (String, Double, Bool) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var isKids = false
    @State private var hue: Double = Self.hues.randomElement() ?? 30

    private static let hues: [Double] = [0, 30, 55, 140, 190, 220, 270, 320]
    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            Form {
                Section("Name") {
                    TextField("Profile name", text: $name)
                }
                Section("Avatar colour") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: Metrics.s(10)) {
                            ForEach(Self.hues, id: \.self) { option in
                                Button { hue = option } label: {
                                    AvatarView(text: trimmedName.isEmpty ? "?" : String(trimmedName.prefix(1)).uppercased(),
                                               hue: option, size: Metrics.s(40))
                                        .overlay(Circle().stroke(hue == option ? Theme.accent : .clear,
                                                                 lineWidth: Metrics.s(3)).padding(-Metrics.s(3)))
                                        .padding(Metrics.s(4))
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Colour \(Int(option))")
                            }
                        }
                    }
                }
                Section {
                    Toggle("Kids profile", isOn: $isKids)
                }
                Section {
                    Button("Add Profile", action: add)
                        .disabled(trimmedName.isEmpty)
                }
            }
            .navigationTitle("New Profile")
            #if !os(tvOS)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            #endif
        }
    }

    private func add() {
        guard !trimmedName.isEmpty else { return }
        onAdd(trimmedName, hue, isKids)
        dismiss()
    }
}

private struct SettingsLinkRow: View {
    let title: String
    let detail: String
    let symbol: String

    var body: some View {
        HStack(spacing: Metrics.s(14)) {
            Image(systemName: symbol)
                .font(.casa(20))
                .foregroundStyle(Theme.accent)
                .frame(width: Metrics.s(36))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.casa(15, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(detail)
                    .font(.casa(12))
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer(minLength: Metrics.s(8))
            Image(systemName: "chevron.right")
                .font(.casa(13, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
        }
        .padding(Metrics.s(14))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Metrics.cornerRadius, style: .continuous))
    }
}
