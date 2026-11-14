// CasaPlay · Designed by 𝐂𝓪sΔηⓞשα
//
// Profile photos: a picture you pick for a profile. It is kept on this device as a small square JPEG.

import SwiftUI
import UIKit
import CasaPlayKit

enum ProfilePhotoStore {
    private static var cache: [UUID: UIImage] = [:]

    private static func filename(_ id: UUID) -> String {
        "profile-photo-" + id.uuidString + ".jpg"
    }

    static func load(for id: UUID) -> UIImage? {
        if let cached = cache[id] { return cached }
        guard let data = CasaPlayStorage.read(filename(id)),
              let image = UIImage(data: data) else { return nil }
        cache[id] = image
        return image
    }

    /// Crops the picture to a square around its middle, shrinks it to 512 pixels and saves it.
    /// Returns false when the data is not a picture or can't be written.
    @discardableResult
    static func save(_ data: Data, for id: UUID) -> Bool {
        guard let original = UIImage(data: data), original.size.width > 0, original.size.height > 0 else { return false }
        let target = CGSize(width: 512, height: 512)
        let scale = max(target.width / original.size.width, target.height / original.size.height)
        let drawn = CGSize(width: original.size.width * scale, height: original.size.height * scale)

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let square = UIGraphicsImageRenderer(size: target, format: format).image { _ in
            // A tall photo keeps more of its top, because that is where the head is.
            let spareHeight = drawn.height - target.height
            original.draw(in: CGRect(x: (target.width - drawn.width) / 2,
                                     y: spareHeight > 0 ? -spareHeight * 0.2 : (target.height - drawn.height) / 2,
                                     width: drawn.width,
                                     height: drawn.height))
        }
        guard let jpeg = square.jpegData(compressionQuality: 0.85) else { return false }
        guard CasaPlayStorage.write(jpeg, to: filename(id)) else { return false }
        cache[id] = square
        return true
    }

    static func remove(for id: UUID) {
        cache[id] = nil
        CasaPlayStorage.remove(filename(id))
    }
}

/// A round profile picture: the chosen photo, or the coloured letter.
struct ProfileAvatar: View {
    @Environment(AppState.self) private var app
    let profile: Profile
    var size: CGFloat = 44

    var body: some View {
        // Reading the revision makes the avatar redraw when a photo is added, changed or removed.
        let _ = app.photoRevision
        if let image = ProfilePhotoStore.load(for: profile.id) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: size, height: size)
                .clipShape(Circle())
        } else {
            AvatarView(text: profile.glyph, hue: profile.hue, size: size)
        }
    }
}
