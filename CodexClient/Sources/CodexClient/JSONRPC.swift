import Foundation

/// JSON-RPC request id: string or int64, per the generated `RequestId` schema.
public enum JSONRPCID: Hashable, Sendable, Codable, Equatable {
    case int(Int64)
    case string(String)

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Int64.self) {
            self = .int(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else {
            throw DecodingError.typeMismatch(
                JSONRPCID.self,
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "RequestId must be string or integer")
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .int(let value):
            try container.encode(value)
        case .string(let value):
            try container.encode(value)
        }
    }
}

/// Untyped JSON value used for params/results we do not fully model.
public enum JSONValue: Sendable, Codable, Equatable {
    case null
    case bool(Bool)
    case int(Int64)
    case double(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int64.self) {
            self = .int(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .object(value)
        } else {
            throw DecodingError.typeMismatch(
                JSONValue.self,
                DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "Unsupported JSON value")
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null:
            try container.encodeNil()
        case .bool(let value):
            try container.encode(value)
        case .int(let value):
            try container.encode(value)
        case .double(let value):
            try container.encode(value)
        case .string(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .object(let value):
            try container.encode(value)
        }
    }

    public init<T: Encodable>(encoding value: T) throws {
        let data = try JSONRPCCodec.encode(value)
        self = try JSONRPCCodec.decode(JSONValue.self, from: data)
    }

    public func decode<T: Decodable>(as type: T.Type) throws -> T {
        let data = try JSONRPCCodec.encode(self)
        return try JSONRPCCodec.decode(type, from: data)
    }

    public var object: [String: JSONValue]? {
        if case .object(let value) = self { return value }
        return nil
    }
}

public struct JSONRPCRequest: Sendable, Codable, Equatable {
    public var id: JSONRPCID
    public var method: String
    public var params: JSONValue?

    public init(id: JSONRPCID, method: String, params: JSONValue? = nil) {
        self.id = id
        self.method = method
        self.params = params
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(method, forKey: .method)
        if let params {
            try container.encode(params, forKey: .params)
        }
    }
}

public struct JSONRPCNotification: Sendable, Codable, Equatable {
    public var method: String
    public var params: JSONValue?

    public init(method: String, params: JSONValue? = nil) {
        self.method = method
        self.params = params
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(method, forKey: .method)
        if let params {
            try container.encode(params, forKey: .params)
        }
    }
}

public struct JSONRPCResponse: Sendable, Codable, Equatable {
    public var id: JSONRPCID
    public var result: JSONValue

    public init(id: JSONRPCID, result: JSONValue) {
        self.id = id
        self.result = result
    }
}

public struct JSONRPCErrorBody: Sendable, Codable, Equatable, Error {
    public var code: Int64
    public var message: String
    public var data: JSONValue?

    public init(code: Int64, message: String, data: JSONValue? = nil) {
        self.code = code
        self.message = message
        self.data = data
    }
}

public struct JSONRPCErrorResponse: Sendable, Codable, Equatable {
    public var id: JSONRPCID
    public var error: JSONRPCErrorBody

    public init(id: JSONRPCID, error: JSONRPCErrorBody) {
        self.id = id
        self.error = error
    }
}

/// A single newline-delimited JSON-RPC message.
public enum JSONRPCMessage: Sendable, Equatable {
    case request(JSONRPCRequest)
    case notification(JSONRPCNotification)
    case response(JSONRPCResponse)
    case error(JSONRPCErrorResponse)

    public static func decode(_ data: Data) throws -> JSONRPCMessage {
        let envelope = try JSONRPCCodec.decode(MessageEnvelope.self, from: data)
        if let method = envelope.method {
            if let id = envelope.id {
                return .request(JSONRPCRequest(id: id, method: method, params: envelope.params))
            }
            return .notification(JSONRPCNotification(method: method, params: envelope.params))
        }
        guard let id = envelope.id else {
            throw JSONRPCCodecError.invalidMessage
        }
        if let error = envelope.error {
            return .error(JSONRPCErrorResponse(id: id, error: error))
        }
        if let result = envelope.result {
            return .response(JSONRPCResponse(id: id, result: result))
        }
        throw JSONRPCCodecError.invalidMessage
    }

    public func encode() throws -> Data {
        switch self {
        case .request(let value):
            return try JSONRPCCodec.encode(value)
        case .notification(let value):
            return try JSONRPCCodec.encode(value)
        case .response(let value):
            return try JSONRPCCodec.encode(value)
        case .error(let value):
            return try JSONRPCCodec.encode(value)
        }
    }

    public func encodeLine() throws -> Data {
        try JSONRPCCodec.encodeLine(self)
    }

    private struct MessageEnvelope: Decodable {
        var id: JSONRPCID?
        var method: String?
        var params: JSONValue?
        var result: JSONValue?
        var error: JSONRPCErrorBody?
    }
}

public enum JSONRPCCodecError: Error, Equatable {
    case invalidMessage
}

enum JSONRPCCodec {
    static func encode<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }

    static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        try JSONDecoder().decode(type, from: data)
    }

    static func encodeLine<T: Encodable>(_ value: T) throws -> Data {
        var data = try encode(value)
        data.append(0x0A)
        return data
    }

    /// Splits newline-delimited JSON, keeping an incomplete trailing line in `buffer`.
    static func pullLines(from buffer: inout Data) -> [Data] {
        var lines: [Data] = []
        while let range = buffer.firstRange(of: Data([0x0A])) {
            let line = buffer.subdata(in: buffer.startIndex..<range.lowerBound)
            buffer.removeSubrange(buffer.startIndex..<range.upperBound)
            if !line.isEmpty {
                lines.append(line)
            }
        }
        return lines
    }
}

extension JSONRPCMessage: Encodable {
    public func encode(to encoder: Encoder) throws {
        switch self {
        case .request(let value):
            try value.encode(to: encoder)
        case .notification(let value):
            try value.encode(to: encoder)
        case .response(let value):
            try value.encode(to: encoder)
        case .error(let value):
            try value.encode(to: encoder)
        }
    }
}

/// Allocates incrementing integer request ids; generation is serialized.
public final class JSONRPCIDGenerator: @unchecked Sendable {
    private let lock = NSLock()
    private var next = Int64(1)

    public init(startingAt start: Int64 = 1) {
        self.next = start
    }

    public func nextID() -> JSONRPCID {
        lock.lock()
        defer { lock.unlock() }
        let value = next
        next += 1
        return .int(value)
    }
}
