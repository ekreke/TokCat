import Foundation
import TokCatCore

enum Formatting {
    /// 紧凑数字：1234 -> 1.23K，1234567 -> 1.23M。
    static func compact(_ value: Double) -> String {
        let absValue = abs(value)
        switch absValue {
        case 1_000_000_000...: return String(format: "%.2fB", value / 1_000_000_000)
        case 1_000_000...: return String(format: "%.2fM", value / 1_000_000)
        case 1_000...: return String(format: "%.2fK", value / 1_000)
        default: return String(format: "%.0f", value)
        }
    }

    static func compact(_ value: Int) -> String {
        compact(Double(value))
    }

    /// 速率展示，例如 "1.23K t/s" 或 "$0.0042/s"。
    static func rate(_ value: Double, currency: Bool) -> String {
        if currency {
            return String(format: "$%.4f/s", value)
        }
        return "\(compact(value)) t/s"
    }

    static func units(_ value: Double, currency: Bool) -> String {
        currency ? String(format: "$%.4f", value) : "\(compact(value)) t"
    }
}
