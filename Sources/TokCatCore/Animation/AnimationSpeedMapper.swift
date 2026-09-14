import Foundation

/// 把 token 消耗速率映射为动画帧率。
///
/// 采用对数曲线：低速率时灵敏度高（轻微消耗即可看到加速），
/// 高速率时趋于饱和，避免动画快到不可辨认。
public struct AnimationSpeedMapper: Equatable, Sendable {
    /// 用户灵敏度倍率。
    public var sensitivity: Double
    /// 达到最高帧率所对应的速率（单位/秒）。
    public var saturationRate: Double

    public init(sensitivity: Double = 1, saturationRate: Double = 300) {
        self.sensitivity = max(0.01, sensitivity)
        self.saturationRate = max(1, saturationRate)
    }

    /// 返回 0..1 的加速进度。
    public func progress(rate: Double) -> Double {
        guard rate > 0 else { return 0 }
        let numerator = log1p(rate * sensitivity)
        let denominator = log1p(saturationRate * sensitivity)
        guard denominator > 0 else { return 0 }
        return min(max(numerator / denominator, 0), 1)
    }

    public func fps(rate: Double, idleFPS: Double, maxFPS: Double) -> Double {
        let p = progress(rate: rate)
        return idleFPS + (maxFPS - idleFPS) * p
    }

    public func fps(rate: Double, pack: AnimationPack) -> Double {
        fps(rate: rate, idleFPS: pack.idleFPS, maxFPS: pack.maxFPS)
    }

    /// 帧间隔（秒）。速率越高间隔越小。
    public func frameInterval(rate: Double, pack: AnimationPack) -> TimeInterval {
        let f = fps(rate: rate, pack: pack)
        guard f > 0 else { return 1 }
        return 1.0 / f
    }
}
