import AppKit

/// 内置占位猫动画：以程序化绘制的侧身小猫，跑动腿部随帧摆动。
///
/// 后续可用美术 PNG 序列替换（见 `ImageSequenceAnimationPack`），
/// 接口保持一致，UI 无需改动。
public final class BuiltinCatPack: AnimationPack {
    public static let identifier = "builtin.cat"

    public var identifier: String { Self.identifier }
    public let displayName = "Cat (builtin)"
    public let frameCount = 10
    public let idleFPS = 4.5
    public let maxFPS = 24

    private struct CacheKey: Hashable { let frame: Int; let height: Int }
    private var cache: [CacheKey: NSImage] = [:]

    public init() {}

    public func image(frameIndex: Int, height: CGFloat) -> NSImage? {
        let index = ((frameIndex % frameCount) + frameCount) % frameCount
        let key = CacheKey(frame: index, height: Int(height.rounded()))
        if let cached = cache[key] { return cached }
        let image = CatFrameRenderer.render(frame: index, count: frameCount, height: height)
        cache[key] = image
        return image
    }
}

enum CatFrameRenderer {
    static func render(frame: Int, count: Int, height: CGFloat) -> NSImage {
        let h = max(8, height)
        let w = (h * 1.45).rounded()
        let size = NSSize(width: w, height: h)
        let image = NSImage(size: size, flipped: false) { _ in
            draw(frame: frame, count: count, size: size)
            return true
        }
        image.isTemplate = true
        return image
    }

    private static func draw(frame: Int, count: Int, size: NSSize) {
        let w = size.width
        let h = size.height
        let phase = 2 * Double.pi * Double(frame) / Double(max(count, 1))

        func p(_ x: Double, _ y: Double) -> NSPoint {
            NSPoint(x: x * w, y: y * h)
        }

        NSColor.black.set()
        let bob = 0.04 * sin(phase * 2)

        // 尾巴：随相位大幅摆动
        let tail = NSBezierPath()
        tail.lineWidth = 0.085 * h
        tail.lineCapStyle = .round
        tail.move(to: p(0.20, 0.50 + bob))
        tail.curve(
            to: p(0.02, 0.56 + bob + 0.22 * sin(phase)),
            controlPoint1: p(0.10, 0.54 + bob),
            controlPoint2: p(0.00, 0.64 + bob)
        )
        tail.stroke()

        // 四肢：交替大幅抬腿（步幅约占身高 22%）
        let backLift = 0.22 * max(0, sin(phase))
        let frontLift = 0.22 * max(0, sin(phase + .pi))
        drawLeg(p, x: 0.30, y0: 0.36 + bob, height: h, lift: backLift)
        drawLeg(p, x: 0.62, y0: 0.36 + bob, height: h, lift: frontLift)
        // 同一侧的第二条腿，相位错开，形成奔跑感
        drawLeg(p, x: 0.40, y0: 0.36 + bob, height: h, lift: frontLift * 0.7, width: 0.05)
        drawLeg(p, x: 0.54, y0: 0.36 + bob, height: h, lift: backLift * 0.7, width: 0.05)

        // 身体
        NSBezierPath(ovalIn: NSRect(x: 0.16 * w, y: (0.40 + bob) * h, width: 0.50 * w, height: 0.30 * h)).fill()

        // 头
        let headR = 0.145
        let headCenter = p(0.80, 0.62 + bob)
        NSBezierPath(ovalIn: NSRect(
            x: headCenter.x - headR * w,
            y: headCenter.y - headR * h,
            width: 2 * headR * w,
            height: 2 * headR * h
        )).fill()

        // 耳朵
        let earLeft = NSBezierPath()
        earLeft.move(to: p(0.70, 0.70 + bob))
        earLeft.line(to: p(0.72, 0.85 + bob))
        earLeft.line(to: p(0.79, 0.74 + bob))
        earLeft.close()
        earLeft.fill()

        let earRight = NSBezierPath()
        earRight.move(to: p(0.84, 0.74 + bob))
        earRight.line(to: p(0.90, 0.85 + bob))
        earRight.line(to: p(0.92, 0.68 + bob))
        earRight.close()
        earRight.fill()
    }

    private static func drawLeg(
        _ p: (Double, Double) -> NSPoint,
        x: Double,
        y0: Double,
        height h: CGFloat,
        lift: Double,
        width: Double = 0.065
    ) {
        let path = NSBezierPath()
        path.lineWidth = width * h
        path.lineCapStyle = .round
        path.move(to: p(x, y0))
        path.line(to: p(x + 0.03, y0 - 0.28 + lift))
        path.stroke()
    }
}
