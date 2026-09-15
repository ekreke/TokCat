import AppKit

/// 图片附件处理：规范化/缩放/编码，控制发送体积。
enum ImageAttachment {
    /// 把任意图片数据规范化为可发送的 (data, mimeType)。
    static func normalized(
        _ data: Data,
        maxDimension: CGFloat = 2000,
        maxBytes: Int = 5_000_000
    ) -> (data: Data, mimeType: String)? {
        guard let image = NSImage(data: data) else { return nil }
        return encode(image, maxDimension: maxDimension, maxBytes: maxBytes)
    }

    static func encode(
        _ image: NSImage,
        maxDimension: CGFloat = 2000,
        maxBytes: Int = 5_000_000
    ) -> (data: Data, mimeType: String)? {
        let target = downscaled(image, maxDimension: maxDimension)

        if let png = target.pngData(), png.count <= maxBytes {
            return (png, "image/png")
        }
        if let tiff = target.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) {
            for quality in stride(from: 0.8, through: 0.3, by: -0.1) {
                if let jpeg = rep.representation(using: .jpeg, properties: [.compressionFactor: quality]),
                   jpeg.count <= maxBytes {
                    return (jpeg, "image/jpeg")
                }
            }
            if let jpeg = rep.representation(using: .jpeg, properties: [.compressionFactor: 0.3]) {
                return (jpeg, "image/jpeg")
            }
        }
        return target.pngData().map { ($0, "image/png") }
    }

    private static func downscaled(_ image: NSImage, maxDimension: CGFloat) -> NSImage {
        let size = image.size
        let longest = max(size.width, size.height)
        guard longest > maxDimension, longest > 0 else { return image }

        let scale = maxDimension / longest
        let newSize = NSSize(width: max(1, size.width * scale), height: max(1, size.height * scale))
        let result = NSImage(size: newSize)
        result.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .high
        image.draw(in: NSRect(origin: .zero, size: newSize))
        result.unlockFocus()
        return result
    }
}

extension NSImage {
    /// PNG 表示。
    func pngData() -> Data? {
        guard let tiff = tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
        return rep.representation(using: .png, properties: [:])
    }
}
