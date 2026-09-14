import AppKit

/// 位图缩放工具：用于把像素风素材按最近邻放大，保持硬边不糊。
public enum PixelScaling {
    /// 把任意位图按最近邻缩放到目标高度。
    /// - Parameters:
    ///   - targetHeight: 目标显示高度（点）。
    ///   - template: 是否输出模板图（由系统着色）。
    ///   - scale: 每点渲染的像素数（Retina 用 2）。
    public static func nearestNeighbor(
        _ image: NSImage,
        targetHeight: CGFloat,
        template: Bool,
        scale: CGFloat = 2
    ) -> NSImage? {
        guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let sourceW = cg.width
        let sourceH = cg.height
        guard sourceW > 0, sourceH > 0, targetHeight > 0 else { return nil }

        let outH = max(1, Int((targetHeight * scale).rounded()))
        let outW = max(1, Int((Double(sourceW) / Double(sourceH) * targetHeight * scale).rounded()))

        guard let context = CGContext(
            data: nil,
            width: outW,
            height: outH,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        context.interpolationQuality = .none
        context.draw(cg, in: CGRect(x: 0, y: 0, width: outW, height: outH))
        guard let output = context.makeImage() else { return nil }

        let result = NSImage(
            cgImage: output,
            size: NSSize(width: CGFloat(outW) / scale, height: CGFloat(outH) / scale)
        )
        result.isTemplate = template
        return result
    }
}
