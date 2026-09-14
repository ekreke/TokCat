import AppKit

/// 由图片序列构成的外部动画包。
///
/// 目录结构：
/// ```
/// <Animations>/<id>/
///   manifest.json
///   00.png, 01.png, ...
/// ```
/// manifest.json 格式：
/// ```json
/// { "id": "cat-hd", "displayName": "Cat HD",
///   "frames": ["00.png", "01.png"], "idleFPS": 1.5, "maxFPS": 18 }
/// ```
public final class ImageSequenceAnimationPack: AnimationPack {
    public let identifier: String
    public let displayName: String
    public let idleFPS: Double
    public let maxFPS: Double
    public let frameCount: Int

    private let urls: [URL]
    private var cache: [CacheKey: NSImage] = [:]

    private struct CacheKey: Hashable {
        let frame: Int
        let height: Int
    }

    private struct Manifest: Decodable {
        var id: String
        var displayName: String
        var frames: [String]
        var idleFPS: Double?
        var maxFPS: Double?
    }

    public init?(directory: URL) {
        let manifestURL = directory.appendingPathComponent("manifest.json")
        guard let data = try? Data(contentsOf: manifestURL),
              let manifest = try? JSONDecoder().decode(Manifest.self, from: data),
              !manifest.frames.isEmpty else {
            return nil
        }
        self.identifier = manifest.id
        self.displayName = manifest.displayName
        self.idleFPS = manifest.idleFPS ?? 1.5
        self.maxFPS = manifest.maxFPS ?? 18
        self.urls = manifest.frames.map { directory.appendingPathComponent($0) }
        self.frameCount = urls.count
        guard urls.allSatisfy({ FileManager.default.fileExists(atPath: $0.path) }) else {
            return nil
        }
    }

    public func image(frameIndex: Int, height: CGFloat) -> NSImage? {
        let index = ((frameIndex % frameCount) + frameCount) % frameCount
        let key = CacheKey(frame: index, height: Int(height.rounded()))
        if let cached = cache[key] { return cached }
        guard let image = NSImage(contentsOf: urls[index]) else { return nil }
        image.size = NSSize(width: height * image.size.width / max(image.size.height, 1), height: height)
        image.isTemplate = true
        cache[key] = image
        return image
    }
}
