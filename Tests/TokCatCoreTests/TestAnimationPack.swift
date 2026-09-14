#if canImport(AppKit)
import AppKit
@testable import TokCatCore

/// 测试用的最小动画包实现。
final class TestAnimationPack: AnimationPack {
    let identifier: String
    let displayName: String
    let frameCount: Int
    let idleFPS: Double
    let maxFPS: Double
    let supportsColor: Bool

    init(
        identifier: String = "test.pack",
        displayName: String = "Test Pack",
        frameCount: Int = 5,
        idleFPS: Double = 2,
        maxFPS: Double = 24,
        supportsColor: Bool = false
    ) {
        self.identifier = identifier
        self.displayName = displayName
        self.frameCount = frameCount
        self.idleFPS = idleFPS
        self.maxFPS = maxFPS
        self.supportsColor = supportsColor
    }

    func image(frameIndex: Int, height: CGFloat, template: Bool) -> NSImage? {
        NSImage(size: NSSize(width: height, height: height))
    }
}
#endif
