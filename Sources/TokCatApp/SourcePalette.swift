import SwiftUI

/// 各采集源在趋势图中的颜色。
enum SourcePalette {
    private static let named: [String: Color] = [
        "opencode": .blue,
        "claude": .orange,
        "codex": .purple,
        "pi": .teal,
        "cc-switch": .pink,
        "simulated": .gray,
    ]

    static func color(for sourceId: String) -> Color {
        if let color = named[sourceId] { return color }
        return Color(hue: hashHue(sourceId), saturation: 0.65, brightness: 0.85)
    }

    /// 未知来源按 id 派生一个稳定的色相。
    private static func hashHue(_ value: String) -> Double {
        var hash: UInt64 = 5381
        for byte in value.utf8 {
            hash = (hash &* 33) ^ UInt64(byte)
        }
        return Double(hash % 360) / 360.0
    }
}
