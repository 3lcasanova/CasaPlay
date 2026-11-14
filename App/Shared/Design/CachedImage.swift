// CasaPlay · Designed by 𝐂𝓪sΔηⓞשα
//
// Pictures from the web that keep scrolling smooth. SwiftUI's AsyncImage keeps nothing in memory, so a poster
// that scrolls back on screen was fetched and decoded again, on the main thread, every time. These pictures
// are decoded once, in the background, at the size they are shown, and kept in memory. A shelf can also load
// its pictures ahead of time, so they are already there when the posters scroll in.

import SwiftUI
import UIKit
import ImageIO

/// What a CachedAsyncImage is showing. The cases match AsyncImagePhase, so the same `switch` works.
enum ImagePhase {
    case empty
    case success(Image)
    case failure(Error)

    var image: Image? {
        if case .success(let image) = self { return image }
        return nil
    }
}

enum ImagePipeline {
    /// Decoded pictures, by address. The system empties it by itself when memory runs low.
    private static let memory: NSCache<NSString, UIImage> = {
        let cache = NSCache<NSString, UIImage>()
        cache.totalCostLimit = Platform.isTV ? 160_000_000 : 120_000_000
        return cache
    }()

    /// TMDB pictures never change at a given address, so a saved copy can always be used.
    private static let session: URLSession = {
        let config = URLSessionConfiguration.default
        config.urlCache = URLCache(memoryCapacity: 16_000_000, diskCapacity: 250_000_000, diskPath: "CasaPlayImages")
        config.requestCachePolicy = .returnCacheDataElseLoad
        config.httpMaximumConnectionsPerHost = 8
        config.timeoutIntervalForRequest = 20
        return URLSession(configuration: config)
    }()

    private static let inflight = Inflight()

    /// A picture that is already decoded and waiting in memory.
    static func cachedImage(for url: URL) -> UIImage? {
        memory.object(forKey: url.absoluteString as NSString)
    }

    /// Fetches a picture and decodes it in the background, no bigger than `maxPixel` on its long side.
    /// Asking again while it is on its way waits for the same download.
    static func load(_ url: URL, maxPixel: CGFloat) async -> UIImage? {
        let key = url.absoluteString as NSString
        if let hit = memory.object(forKey: key) { return hit }

        let task = inflight.task(for: url.absoluteString) {
            Task.detached(priority: .userInitiated) {
                let image = await fetch(url, maxPixel: maxPixel)
                if let image {
                    memory.setObject(image, forKey: key, cost: cost(of: image))
                }
                inflight.remove(url.absoluteString)
                return image
            }
        }
        return await task.value
    }

    /// Starts loading pictures nobody has asked to see yet, so they are ready when they scroll in.
    static func prefetch(_ urls: [URL], maxPixel: CGFloat = 1600) {
        for url in urls where cachedImage(for: url) == nil {
            Task.detached(priority: .utility) {
                _ = await load(url, maxPixel: maxPixel)
            }
        }
    }

    // MARK: Fetch and decode

    private static func fetch(_ url: URL, maxPixel: CGFloat) async -> UIImage? {
        do {
            let (data, response) = try await session.data(from: url)
            if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) { return nil }
            return downsample(data, maxPixel: maxPixel)
        } catch {
            return nil
        }
    }

    /// Decodes right away (not later, when the picture is first drawn) at a size that fits `maxPixel`.
    private static func downsample(_ data: Data, maxPixel: CGFloat) -> UIImage? {
        let sourceOptions: [CFString: Any] = [kCGImageSourceShouldCache: false]
        guard let source = CGImageSourceCreateWithData(data as CFData, sourceOptions as CFDictionary) else { return nil }

        // A small picture is not stretched up to maxPixel.
        var longSide = maxPixel
        if let info = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
           let width = info[kCGImagePropertyPixelWidth] as? CGFloat,
           let height = info[kCGImagePropertyPixelHeight] as? CGFloat {
            longSide = min(maxPixel, max(width, height))
        }

        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceShouldCacheImmediately: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: longSide
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return UIImage(cgImage: cgImage)
    }

    private static func cost(of image: UIImage) -> Int {
        Int(image.size.width * image.scale * image.size.height * image.scale * 4)
    }
}

/// The downloads that are running, so one picture is never fetched twice at the same time.
private final class Inflight: @unchecked Sendable {
    private let lock = NSLock()
    private var tasks: [String: Task<UIImage?, Never>] = [:]

    func task(for key: String, make: () -> Task<UIImage?, Never>) -> Task<UIImage?, Never> {
        lock.lock()
        defer { lock.unlock() }
        if let existing = tasks[key] { return existing }
        let created = make()
        tasks[key] = created
        return created
    }

    func remove(_ key: String) {
        lock.lock()
        tasks[key] = nil
        lock.unlock()
    }
}

/// Like AsyncImage, but a picture that was shown before appears at once, with no empty frame first.
struct CachedAsyncImage<Content: View>: View {
    let url: URL?
    let maxPixel: CGFloat
    private let content: (ImagePhase) -> Content
    @State private var phase: ImagePhase

    init(url: URL?, maxPixel: CGFloat = 1600, @ViewBuilder content: @escaping (ImagePhase) -> Content) {
        self.url = url
        self.maxPixel = maxPixel
        self.content = content
        if let url, let hit = ImagePipeline.cachedImage(for: url) {
            _phase = State(initialValue: .success(Image(uiImage: hit)))
        } else {
            _phase = State(initialValue: .empty)
        }
    }

    var body: some View {
        content(phase)
            .task(id: url) { await load() }
    }

    @MainActor
    private func load() async {
        guard let url else {
            phase = .empty
            return
        }
        if let hit = ImagePipeline.cachedImage(for: url) {
            phase = .success(Image(uiImage: hit))
            return
        }
        phase = .empty
        if let image = await ImagePipeline.load(url, maxPixel: maxPixel) {
            phase = .success(Image(uiImage: image))
        } else if !Task.isCancelled {
            phase = .failure(URLError(.cannotDecodeContentData))
        }
    }
}
