import Foundation

/// JSON-RPC 2.0 的请求 id（规范允许数字或字符串）。
public enum JSONRPCID: Equatable, Hashable, Sendable, Codable {
    case number(Int)
    case string(String)

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Int.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "非法 JSON-RPC id"
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .number(value): try container.encode(value)
        case let .string(value): try container.encode(value)
        }
    }
}

extension JSONRPCID: ExpressibleByIntegerLiteral {
    public init(integerLiteral value: Int) { self = .number(value) }
}

extension JSONRPCID: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) { self = .string(value) }
}

/// JSON-RPC 标准错误对象。
public struct JSONRPCError: Equatable, Sendable, Decodable {
    public let code: Int
    public let message: String
    public let data: JSONValue?

    public init(code: Int, message: String, data: JSONValue? = nil) {
        self.code = code
        self.message = message
        self.data = data
    }

    /// 方法不存在（ACP 用它表示 agent 能力未开启）。
    public static let methodNotFound = -32601
}

/// 客户端 → agent 的请求（期待一个带相同 id 的响应）。
public struct JSONRPCRequest: Equatable, Sendable {
    public let id: JSONRPCID
    public let method: String
    public let params: JSONValue

    public init(id: JSONRPCID, method: String, params: JSONValue = .null) {
        self.id = id
        self.method = method
        self.params = params
    }
}

/// 不等响应的单向通知。
public struct JSONRPCNotification: Equatable, Sendable {
    public let method: String
    public let params: JSONValue

    public init(method: String, params: JSONValue = .null) {
        self.method = method
        self.params = params
    }
}

/// 成功响应。
public struct JSONRPCResponse: Equatable, Sendable {
    public let id: JSONRPCID
    public let result: JSONValue

    public init(id: JSONRPCID, result: JSONValue = .null) {
        self.id = id
        self.result = result
    }
}

/// 失败响应。
public struct JSONRPCErrorResponse: Equatable, Sendable {
    public let id: JSONRPCID?
    public let error: JSONRPCError

    public init(id: JSONRPCID?, error: JSONRPCError) {
        self.id = id
        self.error = error
    }
}

/// 一条入站的 JSON-RPC 消息。
public enum InboundMessage: Equatable, Sendable {
    case request(JSONRPCRequest)
    case notification(JSONRPCNotification)
    case response(JSONRPCResponse)
    case error(JSONRPCErrorResponse)
}

/// 行分隔 JSON-RPC 编解码。
///
/// ACP 的 stdio 传输：每条消息是一行 JSON（`\n` 结尾，UTF-8）。这里只负责
/// 单条消息的编解码，读写与分帧由 `ACPClient` 处理。
public enum JSONRPCCodec {
    /// 编码为一行 JSON（不含结尾换行）。
    public static func encode(_ request: JSONRPCRequest) throws -> Data {
        var object: [String: JSONValue] = [
            "jsonrpc": "2.0",
            "id": try encodeID(request.id),
            "method": .string(request.method),
        ]
        if request.params != .null { object["params"] = request.params }
        return try encodeObject(object)
    }

    /// 编码成功响应。
    public static func encode(_ response: JSONRPCResponse) throws -> Data {
        var object: [String: JSONValue] = [
            "jsonrpc": "2.0",
            "id": try encodeID(response.id),
        ]
        object["result"] = response.result
        return try encodeObject(object)
    }

    /// 编码失败响应。
    public static func encode(_ response: JSONRPCErrorResponse) throws -> Data {
        var object: [String: JSONValue] = [
            "jsonrpc": "2.0",
        ]
        if let id = response.id {
            object["id"] = try encodeID(id)
        } else {
            object["id"] = .null
        }
        object["error"] = .object([
            "code": .number(Double(response.error.code)),
            "message": .string(response.error.message),
        ])
        return try encodeObject(object)
    }

    /// 解码一行 JSON 为入站消息。
    public static func decode(line: Data) throws -> InboundMessage {
        let value = try JSONDecoder().decode(JSONValue.self, from: line)
        guard let object = value.objectValue else {
            throw JSONRPCError(code: -32700, message: "消息不是 JSON 对象")
        }
        guard object["jsonrpc"]?.stringValue == "2.0" else {
            throw JSONRPCError(code: -32600, message: "缺少 jsonrpc 2.0 标识")
        }

        let method = object["method"]?.stringValue
        let hasID = object["id"] != nil && object["id"] != .null

        if let method {
            let params = object["params"] ?? .null
            if hasID, let id = try? object["id"]?.decode(JSONRPCID.self) {
                return .request(JSONRPCRequest(id: id, method: method, params: params))
            }
            return .notification(JSONRPCNotification(method: method, params: params))
        }

        // 没有 method：一定是响应。
        let id = try object["id"]?.decode(JSONRPCID.self)
        if let error = object["error"] {
            let decoded = try error.decode(JSONRPCError.self)
            return .error(JSONRPCErrorResponse(id: id, error: decoded))
        }
        return .response(JSONRPCResponse(id: id ?? .number(0), result: object["result"] ?? .null))
    }

    private static func encodeID(_ id: JSONRPCID) throws -> JSONValue {
        switch id {
        case let .number(value): return .number(Double(value))
        case let .string(value): return .string(value)
        }
    }

    private static func encodeObject(_ object: [String: JSONValue]) throws -> Data {
        try JSONEncoder().encode(JSONValue.object(object))
    }
}

extension JSONRPCError: LocalizedError {
    public var errorDescription: String? {
        if let details = data?["details"]?.stringValue, !details.isEmpty {
            return "\(message)：\(details)"
        }
        return message
    }
}
