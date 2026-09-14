import Foundation

/// 趋势图显示用的纯数学工具（不涉及 UI，可单测）。
public enum TrendMath {
    /// 居中滑动平均：窗口取前后各 `window/2` 个点，抹平尖刺且不引入滞后。
    ///
    /// 边界点用可用的邻居求平均（窗口自动收窄），因此结果与输入等长。
    public static func movingAverage(_ values: [Double], window: Int) -> [Double] {
        guard window > 1, values.count > 1 else { return values }
        let half = window / 2
        var result = values
        for index in values.indices {
            let lower = max(0, index - half)
            let upper = min(values.count - 1, index + half)
            let slice = values[lower...upper]
            result[index] = slice.reduce(0, +) / Double(slice.count)
        }
        return result
    }

    /// 把上限取整到 1 / 2 / 5 × 10^k，让 Y 轴刻度稳定好看。
    public static func niceMax(_ value: Double) -> Double {
        guard value > 0 else { return 1 }
        let exponent = floor(log10(value))
        let base = value / pow(10, exponent)
        let nice: Double
        switch base {
        case ...1: nice = 1
        case ...2: nice = 2
        case ...5: nice = 5
        default: nice = 10
        }
        return nice * pow(10, exponent)
    }
}
