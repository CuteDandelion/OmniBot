import AppKit
import Foundation

/// Stdio MCP stub so `codex app-server` can attach this binary without opening a second GUI.
enum MCPMain {
    static func run() {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let stdin = FileHandle.standardInput
        var buffer = Data()
        while true {
            let chunk = stdin.availableData
            if chunk.isEmpty { break }
            buffer.append(chunk)
            while let message = pullMessage(from: &buffer) {
                if let response = response(for: message) {
                    FileHandle.standardOutput.write(response)
                }
            }
        }
    }

    static func response(for line: Data) -> Data? {
        var trimmed = line
        if trimmed.last == 0x0D {
            trimmed.removeLast()
        }
        guard let object = try? JSONSerialization.jsonObject(with: trimmed) as? [String: Any] else {
            return nil
        }
        let method = object["method"] as? String
        let id = object["id"]
        guard let method else { return nil }
        if id == nil {
            return nil
        }

        switch method {
        case "initialize":
            let protocolVersion = ((object["params"] as? [String: Any])?["protocolVersion"] as? String)
                ?? "2025-03-26"
            return encode(
                id: id,
                result: [
                    "protocolVersion": protocolVersion,
                    "capabilities": ["tools": ["listChanged": false]],
                    "serverInfo": ["name": "agenthq", "version": "0.1.0"],
                ]
            )
        case "tools/list":
            return encode(id: id, result: ["tools": []])
        case "ping":
            return encode(id: id, result: [:])
        default:
            return encodeError(id: id, code: -32601, message: "Method not found")
        }
    }

    private static func pullMessage(from buffer: inout Data) -> Data? {
        if let framed = pullContentLength(from: &buffer) {
            return framed
        }
        if hasIncompleteContentLengthHeader(buffer) {
            return nil
        }
        guard let newline = buffer.firstRange(of: Data([0x0A])) else { return nil }
        let line = buffer.subdata(in: buffer.startIndex..<newline.lowerBound)
        buffer.removeSubrange(buffer.startIndex..<newline.upperBound)
        if line.isEmpty { return pullMessage(from: &buffer) }
        return line
    }

    private static func hasIncompleteContentLengthHeader(_ buffer: Data) -> Bool {
        guard let prefix = String(data: buffer.prefix(16), encoding: .utf8)?.lowercased() else {
            return false
        }
        return "content-length:".hasPrefix(prefix) || prefix.hasPrefix("content-length:")
    }

    private static func pullContentLength(from buffer: inout Data) -> Data? {
        guard let prefix = String(data: buffer.prefix(16), encoding: .utf8)?.lowercased(),
              prefix.hasPrefix("content-length:") else {
            return nil
        }
        let separatorCRLF = Data("\r\n\r\n".utf8)
        let separatorLF = Data("\n\n".utf8)
        let headerEnd: Range<Data.Index>
        let headerText: String
        if let range = buffer.firstRange(of: separatorCRLF) {
            headerEnd = range
            headerText = String(data: buffer.subdata(in: buffer.startIndex..<range.lowerBound), encoding: .utf8) ?? ""
        } else if let range = buffer.firstRange(of: separatorLF) {
            headerEnd = range
            headerText = String(data: buffer.subdata(in: buffer.startIndex..<range.lowerBound), encoding: .utf8) ?? ""
        } else {
            return nil
        }
        let lengthLine = headerText.split(whereSeparator: { $0 == "\n" || $0 == "\r" }).first ?? ""
        let parts = lengthLine.split(separator: ":", maxSplits: 1)
        guard parts.count == 2, let length = Int(parts[1].trimmingCharacters(in: .whitespaces)) else {
            return nil
        }
        let bodyStart = headerEnd.upperBound
        let bodyEnd = buffer.index(bodyStart, offsetBy: length, limitedBy: buffer.endIndex)
        guard let bodyEnd, bodyEnd <= buffer.endIndex else { return nil }
        let body = buffer.subdata(in: bodyStart..<bodyEnd)
        buffer.removeSubrange(buffer.startIndex..<bodyEnd)
        return body
    }

    private static func encode(id: Any?, result: [String: Any]) -> Data? {
        var payload: [String: Any] = [
            "jsonrpc": "2.0",
            "result": result,
        ]
        if let id {
            payload["id"] = id
        }
        return encodeLine(payload)
    }

    private static func encodeError(id: Any?, code: Int, message: String) -> Data? {
        var payload: [String: Any] = [
            "jsonrpc": "2.0",
            "error": ["code": code, "message": message],
        ]
        if let id {
            payload["id"] = id
        }
        return encodeLine(payload)
    }

    private static func encodeLine(_ payload: [String: Any]) -> Data? {
        guard var data = try? JSONSerialization.data(withJSONObject: payload, options: []) else {
            return nil
        }
        data.append(0x0A)
        return data
    }
}
