// CasaPlay · Designed by 𝐂𝓪sΔηⓞשα
//
// The Kairo look: a pure black ground with a warm gold glow in the top-left corner, pill-shaped navigation,
// gold buttons, and dark warm cards. Colours live here so the whole app changes in one place.

import SwiftUI

enum Kairo {
    static let ground = Color(red: 0.04, green: 0.03, blue: 0.02)
    static let glow = Color(red: 0.55, green: 0.35, blue: 0.05)
    static let accent = Color(red: 0.941, green: 0.627, blue: 0.251)
    static let accentDeep = Color(red: 0.75, green: 0.47, blue: 0.15)
    /// Unselected pills.
    static let pill = Color(red: 0.18, green: 0.14, blue: 0.08)
    /// Channel and caption cards.
    static let card = Color(red: 0.14, green: 0.11, blue: 0.07)
    /// The small "ON NOW" label.
    static let label = Color(red: 0.941, green: 0.627, blue: 0.251)
    static let secondary = Color(red: 0.70, green: 0.65, blue: 0.55)
    /// Dark text on a white (focused) pill or button.
    static let onWhite = Color(red: 0.06, green: 0.04, blue: 0.02)

    static var buttonGradient: LinearGradient {
        LinearGradient(colors: [accent, accentDeep], startPoint: .leading, endPoint: .trailing)
    }
}

/// Black with a warm gold glow in the top-left corner that fades toward the bottom-right.
struct KairoBackground: View {
    var body: some View {
        ZStack {
            Kairo.ground
            RadialGradient(colors: [Kairo.glow.opacity(0.75), Kairo.glow.opacity(0)],
                           center: .topLeading, startRadius: 0, endRadius: 1300)
            LinearGradient(colors: [Color.clear, Color.black.opacity(0.45)], startPoint: .top, endPoint: .bottom)
        }
        .ignoresSafeArea()
    }
}

/// A rounded gold badge such as a rating: "7.9".
struct KairoBadge: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: Platform.isTV ? 20 : 11, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, Platform.isTV ? 10 : 6)
            .padding(.vertical, Platform.isTV ? 4 : 2)
            .background(Kairo.accentDeep, in: RoundedRectangle(cornerRadius: Platform.isTV ? 8 : 5, style: .continuous))
    }
}

/// A thin bar showing how far through something you are.
struct KairoProgress: View {
    let value: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.25))
                Capsule().fill(Color.white).frame(width: proxy.size.width * min(max(value, 0), 1))
            }
        }
    }
}

#if os(tvOS)

// MARK: - Buttons

/// A pill in the top bar: dark when idle, gold when it is the current screen, white when focused.
struct KairoPillStyle: ButtonStyle {
    var selected = false
    var circle = false

    func makeBody(configuration: Configuration) -> some View {
        PillBody(configuration: configuration, selected: selected)
    }

    private struct PillBody: View {
        let configuration: ButtonStyleConfiguration
        let selected: Bool
        @Environment(\.isFocused) private var focused

        var body: some View {
            configuration.label
                .foregroundStyle(focused ? Kairo.onWhite : Color.white)
                .background(fill, in: Capsule())
                .scaleEffect(focused ? 1.08 : 1)
                .animation(.easeOut(duration: 0.15), value: focused)
        }

        private var fill: AnyShapeStyle {
            if focused { return AnyShapeStyle(Color.white) }
            if selected { return AnyShapeStyle(Kairo.buttonGradient) }
            return AnyShapeStyle(Kairo.pill.opacity(0.85))
        }
    }
}

/// The big buttons under the hero: gold for the main one, translucent for the other, white when focused.
struct KairoActionStyle: ButtonStyle {
    var primary: Bool

    func makeBody(configuration: Configuration) -> some View {
        ActionBody(configuration: configuration, primary: primary)
    }

    private struct ActionBody: View {
        let configuration: ButtonStyleConfiguration
        let primary: Bool
        @Environment(\.isFocused) private var focused

        var body: some View {
            configuration.label
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(focused ? Kairo.onWhite : Color.white)
                .padding(.horizontal, 34)
                .padding(.vertical, 18)
                .background(fill, in: Capsule())
                .scaleEffect(focused ? 1.06 : 1)
                .animation(.easeOut(duration: 0.15), value: focused)
        }

        private var fill: AnyShapeStyle {
            if focused { return AnyShapeStyle(Color.white) }
            if primary { return AnyShapeStyle(Kairo.buttonGradient) }
            return AnyShapeStyle(Color.white.opacity(0.18))
        }
    }
}

/// Posters and channel cards: a white ring and a lift on focus. `onFocus` runs when the card gets focus,
/// which is how the hero at the top follows what you are looking at.
struct KairoCardStyle: ButtonStyle {
    var onFocus: () -> Void = {}

    func makeBody(configuration: Configuration) -> some View {
        CardBody(configuration: configuration, onFocus: onFocus)
    }

    private struct CardBody: View {
        let configuration: ButtonStyleConfiguration
        let onFocus: () -> Void
        @Environment(\.isFocused) private var focused

        var body: some View {
            configuration.label
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .strokeBorder(Color.white, lineWidth: focused ? 5 : 0)
                )
                .scaleEffect(focused ? 1.06 : 1)
                .shadow(color: .black.opacity(focused ? 0.55 : 0), radius: 22, y: 12)
                .zIndex(focused ? 1 : 0)
                .animation(.easeOut(duration: 0.15), value: focused)
                .onChange(of: focused) { _, now in
                    if now { onFocus() }
                }
        }
    }
}

// MARK: - Top bar

struct KairoTopBar: View {
    @Binding var selection: AppSection

    private struct Item: Identifiable {
        let section: AppSection
        let title: String
        var id: String { section.rawValue }
    }

    private static let items: [Item] = [
        Item(section: .home, title: "Home"), Item(section: .iptv, title: "Live TV"),
        Item(section: .movies, title: "Movies"), Item(section: .series, title: "Shows"),
        Item(section: .news, title: "News"), Item(section: .sports, title: "Sports"),
        Item(section: .extensions, title: "Extensions"), Item(section: .servers, title: "Servers")
    ]

    var body: some View {
        HStack(spacing: 14) {
            logo
                .padding(.trailing, 20)
            ForEach(Self.items) { item in
                Button { selection = item.section } label: {
                    Text(item.title)
                        .font(.system(size: 26, weight: .semibold))
                        .padding(.horizontal, 26)
                        .padding(.vertical, 14)
                }
                .buttonStyle(KairoPillStyle(selected: selection == item.section))
            }
            Spacer(minLength: 20)
            Button { selection = .profile } label: {
                Image(systemName: "gearshape.fill")
                    .font(.system(size: 26))
                    .frame(width: 58, height: 58)
            }
            .buttonStyle(KairoPillStyle(selected: selection == .profile, circle: true))
        }
        .padding(.horizontal, 70)
        .padding(.top, 36)
        .padding(.bottom, 12)
        .focusSection()
    }

    private var logo: some View {
        HStack(spacing: 10) {
            Image(systemName: "play.fill")
                .font(.system(size: 30, weight: .black))
                .foregroundStyle(Kairo.buttonGradient)
            Text("casaplay")
                .font(.system(size: 34, weight: .heavy))
                .foregroundStyle(Kairo.label)
        }
    }
}

#endif
