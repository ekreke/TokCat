import Foundation

/// 动画的时序属性（帧率相关），不依赖任何 UI 框架，故可跨平台。
///
/// `AnimationPack`（macOS，含 `NSImage` 渲染）在 AppKit 可用时细化本协议；
/// `AnimationSpeedMapper` 只依赖本协议，因此速率→帧率的映射在 Windows 上也可用/可测。
public protocol AnimationTiming {
    /// 静止（速率为 0）时的帧率。
    var idleFPS: Double { get }
    /// 该动画推荐的最高帧率（实际以上限设置为准）。
    var maxFPS: Double { get }
}

/// 把 token 消耗速率映射为动画帧率。
///
/// 对齐 RunCat 的线性模型：`速度 = max(1, 负载比例 × 最大速率)`，
/// 速率越高帧率越高，到 `saturationRate` 后饱和。
public struct AnimationSpeedMapper: Equatable, Sendable {
    /// 用户灵敏度倍率（乘在速率上）。
    public var sensitivity: Double
    /// 达到最高帧率所对应的速率（单位/秒）。
    public var saturationRate: Double
    /// 最高帧率上限（RunCat 的可选项：10/20/30/40）。
    public var maxFPS: Double

    public init(sensitivity: Double = 1, saturationRate: Double = 300, maxFPS: Double = 24) {
        self.sensitivity = max(0.01, sensitivity)
        self.saturationRate = max(1, saturationRate)
        self.maxFPS = max(2, maxFPS)
    }

    /// 返回 0..1 的加速进度（线性，对齐 RunCat）。
    public func progress(rate: Double) -> Double {
        guard rate > 0 else { return 0 }
        return min(max(rate * sensitivity / saturationRate, 0), 1)
    }

    public func fps(rate: Double, idleFPS: Double, maxFPS: Double) -> Double {
        let p = progress(rate: rate)
        return idleFPS + (maxFPS - idleFPS) * p
    }

    /// 使用当前设置的最高帧率上限，空闲帧率取动画包自身定义。
    public func fps(rate: Double, pack: AnimationTiming) -> Double {
        fps(rate: rate, idleFPS: min(pack.idleFPS, maxFPS), maxFPS: maxFPS)
    }

    /// 帧间隔（秒）。速率越高间隔越小。
    public func frameInterval(rate: Double, pack: AnimationTiming) -> TimeInterval {
        let f = fps(rate: rate, pack: pack)
        guard f > 0 else { return 1 }
        return 1.0 / f
    }
}
