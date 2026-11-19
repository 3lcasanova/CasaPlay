// CasaPlay · Designed by 𝐂𝓪sΔηⓞשα
//
// Your own IPTV (Xtream Codes) login, saved in Config/Secrets.xcconfig and copied into the app's
// Info.plist at build time, so nothing has to be typed on the Apple TV.

import Foundation

public struct PersonalXtream: Equatable, Sendable {
    public let server: URL
    public let login: XtreamLogin

    /// Nil when a part is missing, still the literal "$(NAME)" of an unset build setting, or the address
    /// isn't a plain https server address. The scheme may be left off (xcconfig treats `//` as a comment).
    public init?(server: String, username: String, password: String) {
        func clean(_ text: String) -> String? {
            let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return t.isEmpty || t.hasPrefix("$(") ? nil : t
        }
        guard var address = clean(server), let user = clean(username), let pass = clean(password) else { return nil }
        if !address.contains("://") { address = "https://" + address }
        guard let url = URL(string: address), url.scheme?.lowercased() == "https", url.host != nil,
              (try? XtreamProvider.validateURL(url)) != nil else { return nil }
        self.server = XtreamProvider.normalize(url)
        self.login = XtreamLogin(username: user, password: pass)
    }
}
