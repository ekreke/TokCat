import Foundation

enum DateParsing {
    private static let fractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let plain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    /// 解析 ISO8601 时间字符串，兼容带/不带毫秒。
    static func parse(_ value: Any?) -> Date? {
        guard let string = value as? String else {
            if let number = value as? NSNumber {
                return date(fromEpoch: number.doubleValue)
            }
            return nil
        }
        return fractional.date(from: string) ?? plain.date(from: string)
    }

    /// 毫秒或秒级时间戳自动识别。
    static func date(fromEpoch value: Double) -> Date {
        // 大于 1e11 视为毫秒
        let seconds = value > 100_000_000_000 ? value / 1000 : value
        return Date(timeIntervalSince1970: seconds)
    }
}

enum JSON {
    typealias Object = [String: Any]

    static func parse(_ line: String) -> Object? {
        guard let data = line.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? Object else {
            return nil
        }
        return object
    }

    static func dict(_ object: Object?, _ key: String) -> Object? {
        object?[key] as? Object
    }

    static func int(_ object: Object?, _ key: String) -> Int? {
        if let n = object?[key] as? NSNumber { return n.intValue }
        return nil
    }

    static func double(_ object: Object?, _ key: String) -> Double? {
        if let n = object?[key] as? NSNumber { return n.doubleValue }
        return nil
    }

    static func string(_ object: Object?, _ key: String) -> String? {
        object?[key] as? String
    }
}
