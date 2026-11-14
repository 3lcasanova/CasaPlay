// CasaPlay · Designed by 𝐂𝓪sΔηⓞשα

import SwiftUI
import CasaPlayKit
#if !os(tvOS)
import PhotosUI
#endif
#if canImport(UIKit)
import UIKit
#endif

struct ProfileView: View {
    @Environment(AppState.self) private var app
    @State private var showingAddProfile = false
    @State private var confirmingKeepOnly = false

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
                            #if !os(tvOS)
                            // Not on Apple TV: a long-press menu there can get in the way of choosing a profile.
                            // It has the "Remove other profiles" row below instead.
                            .contextMenu {
                                if app.profiles.count > 1 {
                                    Button("Delete \(profile.name)", systemImage: "trash", role: .destructive) {
                                        app.deleteProfile(id: profile.id)
                                    }
                                }
                            }
                            #endif
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
                        ProfilePhotoRows()

                        if app.profiles.count > 1 {
                            Button(role: .destructive) {
                                confirmingKeepOnly = true
                            } label: {
                                SettingsLinkRow(title: "Remove other profiles",
                                                detail: "Keep only \(app.activeProfile.name)",
                                                symbol: "person.crop.circle.badge.minus",
                                                showsChevron: false)
                            }
                            .posterButtonStyle()
                            .confirmationDialog("Remove every profile except \(app.activeProfile.name)?",
                                                isPresented: $confirmingKeepOnly,
                                                titleVisibility: .visible) {
                                Button("Remove \(app.profiles.count - 1) other profile\(app.profiles.count == 2 ? "" : "s")",
                                       role: .destructive) {
                                    app.keepOnlyActiveProfile()
                                }
                                Button("Cancel", role: .cancel) {}
                            }
                        }

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
                                detail: "TMDB, TheTVDB, IMDb ratings and OpenSubtitles",
                                symbol: "globe"
                            )
                        }
                        .posterButtonStyle()

                        NavigationLink {
                            TorrentSettingsView()
                        } label: {
                            SettingsLinkRow(
                                title: "Torrent settings",
                                detail: "Cache size, uploading and privacy",
                                symbol: "arrow.down.circle"
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
                        Text("This product uses the TMDB API but is not endorsed or certified by TMDB.")
                            .font(.casa(12))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .padding(.horizontal, Metrics.screenPadding)
                    .focusableOnTV()
                }
                .padding(.vertical, Metrics.s(16))
            }
            .screenBackground()
            .scrollingScreenTitle("Profile")
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
                ProfileAvatar(profile: profile, size: Metrics.s(72))
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
            .scrollingScreenTitle("New Profile")
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
    var showsChevron = true

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
            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.casa(13, weight: .semibold))
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(Metrics.s(14))
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.surface, in: RoundedRectangle(cornerRadius: Metrics.cornerRadius, style: .continuous))
    }
}

// MARK: - Profile photo

/// Pick a photo for the profile that is in use, or take it away. iPhone and iPad choose from the photo
/// library. Apple TV has no photo library, so it takes the web address of a picture instead.
private struct ProfilePhotoRows: View {
    @Environment(AppState.self) private var app
    @State private var message: String?
    #if os(tvOS)
    @State private var showingLink = false
    #else
    @State private var picked: PhotosPickerItem?
    #endif

    private var profile: Profile { app.activeProfile }

    private var hasPhoto: Bool {
        _ = app.photoRevision
        return ProfilePhotoStore.load(for: profile.id) != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Metrics.s(12)) {
            chooser

            if hasPhoto {
                Button(role: .destructive) {
                    app.removeProfilePhoto(for: profile.id)
                } label: {
                    SettingsLinkRow(title: "Remove photo",
                                    detail: "Go back to the coloured letter for \(profile.name)",
                                    symbol: "trash",
                                    showsChevron: false)
                }
                .posterButtonStyle()
            }

            if let message {
                Text(message)
                    .font(.casa(12))
                    .foregroundStyle(Theme.textSecondary)
                    .focusableOnTV()
            }
        }
    }

    @ViewBuilder
    private var chooser: some View {
        #if os(tvOS)
        Button {
            showingLink = true
        } label: {
            SettingsLinkRow(title: "Profile photo",
                            detail: "Use a picture from a web address for \(profile.name)",
                            symbol: "person.crop.circle.badge.plus")
        }
        .posterButtonStyle()
        .fullScreenCover(isPresented: $showingLink) {
            PhotoLinkSheet(profile: profile)
        }
        #else
        PhotosPicker(selection: $picked, matching: .images) {
            SettingsLinkRow(title: "Profile photo",
                            detail: "Choose a photo for \(profile.name)",
                            symbol: "person.crop.circle.badge.plus",
                            showsChevron: false)
        }
        .buttonStyle(.plain)
        .onChange(of: picked) { _, item in
            guard let item else { return }
            let id = profile.id
            Task { @MainActor in
                let data = try? await item.loadTransferable(type: Data.self)
                if let data, app.setProfilePhoto(data, for: id) {
                    message = nil
                } else {
                    message = "That photo couldn't be used. Try another one."
                }
                picked = nil
            }
        }
        #endif
    }
}

#if os(tvOS)
/// Apple TV: type the web address of a picture and it becomes the profile photo. This is a page of its own
/// with a solid background, so nothing from the Profile screen shows through it.
private struct PhotoLinkSheet: View {
    @Environment(AppState.self) private var app
    @Environment(\.dismiss) private var dismiss
    let profile: Profile
    @State private var text = ""
    @State private var isLoading = false
    @State private var message: String?
    @FocusState private var addressFocused: Bool

    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// What was typed, as a web address. "example.com/a.jpg" works without the https://, and http:// is
    /// upgraded, because Apple TV only talks to secure addresses.
    private var address: URL? {
        guard !trimmed.isEmpty else { return nil }
        let full = trimmed.contains("://") ? trimmed : "https://" + trimmed
        guard var parts = URLComponents(string: full), let host = parts.host, !host.isEmpty,
              let scheme = parts.scheme?.lowercased(), scheme == "https" || scheme == "http" else { return nil }
        parts.scheme = "https"
        return parts.url
    }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            HStack(alignment: .top, spacing: Metrics.s(60)) {
                VStack(spacing: Metrics.s(12)) {
                    ProfileAvatar(profile: profile, size: Metrics.s(110))
                    Text(profile.name)
                        .font(.casa(16, weight: .semibold))
                        .foregroundStyle(Theme.textPrimary)
                        .lineLimit(1)
                }
                .frame(width: Metrics.s(150))

                VStack(alignment: .leading, spacing: Metrics.s(18)) {
                    Text("Profile photo")
                        .font(.casa(30, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                    Text("Type the web address of a picture, like https://example.com/photo.jpg")
                        .font(.casa(14))
                        .foregroundStyle(Theme.textSecondary)

                    TextField("https://example.com/photo.jpg", text: $text)
                        .autocorrectionDisabled()
                        .focused($addressFocused)

                    HStack(spacing: Metrics.s(16)) {
                        Button {
                            Task { await load() }
                        } label: {
                            Text(isLoading ? "Loading…" : "Use this picture")
                        }
                        .buttonStyle(HeroButtonStyle(kind: .primary))
                        .disabled(isLoading || address == nil)

                        Button {
                            dismiss()
                        } label: {
                            Text("Cancel")
                        }
                        .buttonStyle(HeroButtonStyle(kind: .secondary))
                    }
                    .padding(.top, Metrics.s(6))

                    if let message {
                        Text(message)
                            .font(.casa(13, weight: .medium))
                            .foregroundStyle(Theme.accent)
                    }

                    Text("Tip: when you open the field, your iPhone offers its keyboard. Copy the picture address on your iPhone and paste it there.")
                        .font(.casa(12))
                        .foregroundStyle(Theme.textSecondary)
                        .padding(.top, Metrics.s(6))
                }
                .frame(maxWidth: Metrics.s(560), alignment: .leading)
            }
            .padding(Metrics.s(40))
        }
        .onAppear { addressFocused = true }
    }

    private func load() async {
        guard let url = address else {
            message = "That doesn't look like a web address."
            return
        }
        isLoading = true
        message = nil
        defer { isLoading = false }
        do {
            var request = URLRequest(url: url, timeoutInterval: 20)
            request.setValue("image/*", forHTTPHeaderField: "Accept")
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                message = "That address answered with error \(http.statusCode)."
            } else if UIImage(data: data) == nil {
                let kind = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Type") ?? "something that isn't a picture"
                message = "That address returned \(kind), not a picture. Use a link to the image file itself."
            } else if app.setProfilePhoto(data, for: profile.id) {
                dismiss()
            } else {
                message = "The picture loaded, but it couldn't be saved on this device."
            }
        } catch {
            message = error.localizedDescription
        }
    }
}
#endif
