import AppKit

/// 可插拔动画包：提供一个可循环播放的帧序列。
///
/// 实现者只需给出帧数量与按帧索引取图的方法，速率到帧率的映射由
/// `AnimationSpeedMapper` 统一负责，因此新增动画（猫/狗/任意序列）
/// 无需改动引擎。
public protocol AnimationPack: AnyObject {
    /// 唯一标识，用于持久化用户选择。
    var identifier: String { get }
    /// 展示名称。
    var displayName: String { get }
    /// 帧总数（循环播放）。
    var frameCount: Int { get }
    /// 静止（速率为 0）时的帧率。
    var idleFPS: Double { get }
    /// 满载时的最高帧率（用于限制功耗）。
    var maxFPS: Double { get }
    /// 取指定帧的图像，`height` 为期望的渲染高度（点）。
    func image(frameIndex: Int, height: CGFloat) -> NSImage?
}

public extension AnimationPack {
    var idleFPS: Double { 1.5 }
    var maxFPS: Double { 18 }
}
