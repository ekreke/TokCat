#if canImport(AppKit)
import AppKit

/// 可插拔动画包：提供一个可循环播放的帧序列。
///
/// 实现者只需给出帧数量与按帧索引取图的方法，速率到帧率的映射由
/// `AnimationSpeedMapper` 统一负责，因此新增动画（猫/狗/任意序列）
/// 无需改动引擎。
public protocol AnimationPack: AnimationTiming {
    /// 唯一标识，用于持久化用户选择。
    var identifier: String { get }
    /// 展示名称。
    var displayName: String { get }
    /// 帧总数（循环播放）。
    var frameCount: Int { get }
    /// 是否支持彩色渲染（单色素材返回 false）。
    var supportsColor: Bool { get }

    /// 取指定帧。
    /// - Parameter template: true 输出模板图（仅 alpha，由系统着色）；false 保留原色。
    func image(frameIndex: Int, height: CGFloat, template: Bool) -> NSImage?
}

public extension AnimationPack {
    var idleFPS: Double { 2.0 }
    var maxFPS: Double { 24 }
    var supportsColor: Bool { false }

    /// 默认按模板图取帧。
    func image(frameIndex: Int, height: CGFloat) -> NSImage? {
        image(frameIndex: frameIndex, height: height, template: true)
    }
}
#endif
