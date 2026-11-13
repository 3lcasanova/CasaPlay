// CasaPlay · Designed by 𝐂𝓪sΔηⓞשα
//
// Design tokens that match the CasaPlay design canvas: near-black ground,
// warm white text and one amber accent.

import SwiftUI

enum Platform {
    #if os(tvOS)
    static let isTV = true
    #else
    static let isTV = false
    #endif
}

enum Theme {
    static let background = Color(red: 0.027, green: 0.031, blue: 0.043)
    static let surface = Color.white.opacity(0.07)
    static let surfaceStrong = Color.white.opacity(0.16)
    static let textPrimary = Color(red: 0.953, green: 0.945, blue: 0.925)
    static let textSecondary = Color(red: 0.663, green: 0.671, blue: 0.694)
    static let accent = Color(red: 0.941, green: 0.651, blue: 0.275)
    static let onAccent = Color(red: 0.102, green: 0.071, blue: 0.031)
    static let onLight = Color(red: 0.043, green: 0.047, blue: 0.063)
}

enum Metrics {
    static let screenPadding: CGFloat = Platform.isTV ? 80 : 20
    static let shelfSpacing: CGFloat = Platform.isTV ? 40 : 14
    static let sectionSpacing: CGFloat = Platform.isTV ? 56 : 26
    static let posterWidth: CGFloat = Platform.isTV ? 220 : 124
    static let landscapeWidth: CGFloat = Platform.isTV ? 400 : 230
    static let heroHeight: CGFloat = Platform.isTV ? 640 : 420
    static let cornerRadius: CGFloat = Platform.isTV ? 20 : 12

    /// Scales a phone-sized value up for the TV.
    static func s(_ value: CGFloat) -> CGFloat {
        Platform.isTV ? value * 1.6 : value
    }
}

extension Font {
    /// System font that is sized for a phone and scaled up on Apple TV.
    static func casa(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: Platform.isTV ? size * 1.6 : size, weight: weight)
    }
}

/// Title for a pushed screen whose content scrolls. Apple TV draws a navigation title as a
/// fixed overlay that scrolling content passes underneath, so there the title is put at the
/// top of the scrolling content instead. Use with `scrollingScreenTitle(_:)`.
struct ScreenTitle: View {
    let title: String
    init(_ title: String) { self.title = title }

    var body: some View {
        #if os(tvOS)
        Text(title)
            .font(.casa(26, weight: .bold))
            .foregroundStyle(Theme.textPrimary)
            .frame(maxWidth: .infinity, alignment: .center)
        #else
        EmptyView()
        #endif
    }
}

extension View {
    /// Full-screen app background for a screen. On Apple TV a scroll view with short content can
    /// be laid out only as wide as that content, which left the system wallpaper showing in bands
    /// at the sides; filling the screen first keeps the background edge to edge.
    func screenBackground() -> some View {
        self
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Theme.background.ignoresSafeArea())
    }

    /// Navigation title on iPhone and iPad; nothing on Apple TV, where `ScreenTitle` shows it.
    @ViewBuilder
    func scrollingScreenTitle(_ title: String) -> some View {
        #if os(tvOS)
        self
        #else
        self.navigationTitle(title)
        #endif
    }

    /// Apple TV only scrolls to things it can focus, so read-only blocks opt in.
    @ViewBuilder
    func focusableOnTV() -> some View {
        #if os(tvOS)
        self.focusable()
        #else
        self
        #endif
    }

    /// Full-width list rows. On Apple TV the system focus style paints a white platter under
    /// light text, which made rows unreadable; this keeps the dark card and adds an accent ring.
    @ViewBuilder
    func cardRowButtonStyle() -> some View {
        #if os(tvOS)
        self.buttonStyle(CardRowButtonStyle())
        #else
        self.buttonStyle(.plain)
        #endif
    }

    /// A sheet on iPhone and iPad; full screen on Apple TV, where sheets are a narrow card.
    @ViewBuilder
    func adaptiveSheet<Content: View>(isPresented: Binding<Bool>,
                                      @ViewBuilder content: @escaping () -> Content) -> some View {
        #if os(tvOS)
        self.fullScreenCover(isPresented: isPresented, content: content)
        #else
        self.sheet(isPresented: isPresented, content: content)
        #endif
    }

    @ViewBuilder
    func adaptiveSheet<Item: Identifiable, Content: View>(item: Binding<Item?>,
                                                          @ViewBuilder content: @escaping (Item) -> Content) -> some View {
        #if os(tvOS)
        self.fullScreenCover(item: item, content: content)
        #else
        self.sheet(item: item, content: content)
        #endif
    }

    /// Poster-style buttons: plain on iPhone and iPad, the lift-and-glow focus effect on Apple TV.
    @ViewBuilder
    func posterButtonStyle() -> some View {
        #if os(tvOS)
        self.buttonStyle(.borderless)
        #else
        self.buttonStyle(.plain)
        #endif
    }
}

#if os(tvOS)
struct CardRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        CardRowBody(configuration: configuration)
    }

    private struct CardRowBody: View {
        let configuration: ButtonStyleConfiguration
        @Environment(\.isFocused) private var isFocused

        var body: some View {
            configuration.label
                .background(
                    RoundedRectangle(cornerRadius: Metrics.cornerRadius, style: .continuous)
                        .fill(isFocused ? Theme.surfaceStrong : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Metrics.cornerRadius, style: .continuous)
                        .strokeBorder(isFocused ? Theme.accent : Color.clear, lineWidth: 4)
                )
                .scaleEffect(configuration.isPressed ? 0.98 : (isFocused ? 1.02 : 1))
                .shadow(color: .black.opacity(isFocused ? 0.5 : 0), radius: 18, y: 10)
                .animation(.easeOut(duration: 0.15), value: isFocused)
        }
    }
}
#endif
