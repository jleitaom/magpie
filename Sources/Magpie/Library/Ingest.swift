import AppKit
import ImageIO
import LinkPresentation
import MagpieKit
import UniformTypeIdentifiers

/// What a page's preview gave us, in plain values that can cross threads.
nonisolated struct PagePreview: Sendable {
    var title: String?
    var imageData: Data?
}

/// A thumbnail ready to store: downsampled JPEG, its aspect, and its main color.
nonisolated struct ProcessedImage: Sendable {
    var jpeg: Data
    var aspect: Double
    var color: UInt32?
}

/// Fills in a block after it's saved: title, thumbnail, card color. Saving never waits for this.
enum Ingest {
    /// The longest side of a stored thumbnail, in pixels (notes/design/KIT.md "thumbMax").
    nonisolated static let thumbnailMax = 600

    /// Fetches a page's title and preview image with LinkPresentation. Runs off the main
    /// actor; the callbacks are `@Sendable` so they never inherit it.
    nonisolated static func fetchPreview(_ url: URL, timeout: TimeInterval = 20) async -> PagePreview? {
        await withCheckedContinuation { (continuation: CheckedContinuation<PagePreview?, Never>) in
            let fetch = PreviewFetch(continuation: continuation)
            fetch.start(url, timeout: timeout)
        }
    }

    /// Downsamples image data to a JPEG thumbnail and finds its main color. CPU work, off the main actor.
    @concurrent
    nonisolated static func process(_ data: Data) async -> ProcessedImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: thumbnailMax,
        ]
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary),
              image.width > 0, image.height > 0 else { return nil }
        let out = NSMutableData()
        guard let dest = CGImageDestinationCreateWithData(out, UTType.jpeg.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: 0.82] as CFDictionary)
        guard CGImageDestinationFinalize(dest) else { return nil }
        return ProcessedImage(jpeg: out as Data, aspect: Double(image.width) / Double(image.height), color: mainColor(of: image))
    }

    /// The image's main color: the average of its more colorful pixels (or of all, for grey images),
    /// read from an 8 × 8 copy.
    nonisolated static func mainColor(of image: CGImage) -> UInt32? {
        let side = 8
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        guard let context = CGContext(data: &pixels, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                                      space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
        var all = (0.0, 0.0, 0.0), colorful = (0.0, 0.0, 0.0)
        var colorfulCount = 0.0
        for i in stride(from: 0, to: pixels.count, by: 4) {
            let rgb = RGB(r: Double(pixels[i]) / 255, g: Double(pixels[i + 1]) / 255, b: Double(pixels[i + 2]) / 255)
            all = (all.0 + rgb.r, all.1 + rgb.g, all.2 + rgb.b)
            if rgb.hue(greyBelow: 0.15) != nil {
                colorful = (colorful.0 + rgb.r, colorful.1 + rgb.g, colorful.2 + rgb.b)
                colorfulCount += 1
            }
        }
        let n = Double(side * side)
        let pick = colorfulCount >= n * 0.15
            ? RGB(r: colorful.0 / colorfulCount, g: colorful.1 / colorfulCount, b: colorful.2 / colorfulCount)
            : RGB(r: all.0 / n, g: all.1 / n, b: all.2 / n)
        return pick.hex
    }
}

/// One LinkPresentation fetch. LPMetadataProvider must stay alive until it calls back,
/// so this object owns it; it's only touched from the provider's callbacks, one after the other.
nonisolated private final class PreviewFetch: @unchecked Sendable {
    // @unchecked: `provider` and `metadata` aren't Sendable, but the fetch is strictly
    // sequential (start → metadata callback → image callback → resume once).
    private let continuation: CheckedContinuation<PagePreview?, Never>
    private let provider = LPMetadataProvider()
    private var finished = false

    init(continuation: CheckedContinuation<PagePreview?, Never>) {
        self.continuation = continuation
    }

    func start(_ url: URL, timeout: TimeInterval) {
        provider.timeout = timeout
        provider.shouldFetchSubresources = true
        provider.startFetchingMetadata(for: url) { @Sendable [self] metadata, _ in
            guard let metadata else { return finish(nil) }
            let title = metadata.title
            guard let imageProvider = metadata.imageProvider ?? metadata.iconProvider else {
                return finish(PagePreview(title: title, imageData: nil))
            }
            imageProvider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { @Sendable data, _ in
                self.finish(PagePreview(title: title, imageData: data))
            }
        }
    }

    private func finish(_ preview: PagePreview?) {
        guard !finished else { return }
        finished = true
        continuation.resume(returning: preview)
    }
}
