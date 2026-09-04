import AppKit
import Foundation

/// Stdio MCP server. `codex app-server` attaches this binary with `--mcp`.
enum MCPMain {
    static var rosterOverride: [HandoffRosterEntry]?
    private static var cachedRoster: [HandoffRosterEntry] = []
    private static var ipc: HandoffIPCClient?
    private static var emitListChanged = false

    static func run() {
        NSApplication.shared.setActivationPolicy(.prohibited)
        let socketPath = ProcessInfo.processInfo.environment["AGENTHQ_HANDOFF_SOCKET"]
            ?? CodexProcess.handoffSocketURL.path
        let client = HandoffIPCClient(path: socketPath)
        client.onRoster = { entries in
            cachedRoster = entries
            if emitListChanged {
                emitToolsListChanged()
            }
        }
        client.start()
        ipc = client

        let stdin = FileHandle.standardInput
        var buffer = Data()
        while true {
            let chunk = stdin.availableData
            if chunk.isEmpty { break }
            buffer.append(chunk)
            while let message = pullMessage(from: &buffer) {
                if let response = handle(message) {
                    FileHandle.standardOutput.write(response)
                }
            }
        }
        client.stop()
    }

    static func response(for line: Data) -> Data? {
        handle(line)
    }

    static func currentRoster() -> [HandoffRosterEntry] {
        rosterOverride ?? cachedRoster
    }

    private static func handle(_ line: Data) -> Data? {
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
            if method == "notifications/initialized" {
                emitListChanged = true
            }
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
                    "capabilities": ["tools": ["listChanged": true]],
                    "serverInfo": ["name": "agenthq", "version": "0.1.0"],
                ]
            )
        case "tools/list":
            return encode(id: id, result: ["tools": [HandoffTool.definition(agents: resolvedRoster())]])
        case "tools/call":
            return handleToolsCall(id: id, params: object["params"] as? [String: Any] ?? [:])
        case "ping":
            return encode(id: id, result: [:])
        default:
            return encodeError(id: id, code: -32601, message: "Method not found")
        }
    }

    private static func resolvedRoster() -> [HandoffRosterEntry] {
        if let rosterOverride { return rosterOverride }
        if !cachedRoster.isEmpty { return cachedRoster }
        if let ipc {
            if let response = try? ipc.request(method: "roster", timeout: 1.5),
               let agents = response["agents"] as? [Any] {
                let parsed = agents.compactMap(HandoffRosterEntry.fromJSON)
                cachedRoster = parsed
                return parsed
            }
        }
        return cachedRoster
    }

    private static func handleToolsCall(id: Any?, params: [String: Any]) -> Data? {
        let name = params["name"] as? String ?? ""
        guard name == HandoffTool.name else {
            return encode(
                id: id,
                result: [
                    "content": [["type": "text", "text": "Unknown tool"]],
                    "isError": true,
                ]
            )
        }
        let arguments = jsonObject(params["arguments"])
        let meta = jsonObject(params["_meta"])
        guard let agentID = arguments["agent_id"] as? String,
              let brief = arguments["brief"] as? String else {
            return encodeError(id: id, code: -32602, message: "agent_id and brief are required")
        }
        var payload: [String: Any] = [
            "agent_id": agentID,
            "brief": brief,
        ]
        if let threadID = threadID(from: meta) {
            payload["thread_id"] = threadID
        }
        do {
            let response = try (ipc ?? makeEphemeralClient()).request(
                method: "handoff",
                params: payload,
                timeout: 60 * 60
            )
            if response["ok"] as? Bool == true, let summary = response["summary"] as? String {
                return encode(
                    id: id,
                    result: [
                        "content": [["type": "text", "text": summary]],
                    ]
                )
            }
            let message = response["error"] as? String ?? "Handoff failed"
            return encode(
                id: id,
                result: [
                    "content": [["type": "text", "text": message]],
                    "isError": true,
                ]
            )
        } catch {
            return encode(
                id: id,
                result: [
                    "content": [[
                        "type": "text",
                        "text": (error as? LocalizedError)?.errorDescription ?? error.localizedDescription,
                    ]],
                    "isError": true,
                ]
            )
        }
    }

    private static func makeEphemeralClient() -> HandoffIPCClient {
        let path = ProcessInfo.processInfo.environment["AGENTHQ_HANDOFF_SOCKET"]
            ?? CodexProcess.handoffSocketURL.path
        let client = HandoffIPCClient(path: path)
        client.start()
        return client
    }

    private static func threadID(from meta: [String: Any]) -> String? {
        if let value = meta["threadId"] as? String, !value.isEmpty { return value }
        if let value = meta["thread_id"] as? String, !value.isEmpty { return value }
        let wrapped = jsonObject(meta["x-codex-turn-metadata"])
        if let value = wrapped["threadId"] as? String, !value.isEmpty { return value }
        if let value = wrapped["thread_id"] as? String, !value.isEmpty { return value }
        return nil
    }

    private static func jsonObject(_ value: Any?) -> [String: Any] {
        if let object = value as? [String: Any] { return object }
        if let text = value as? String,
           let data = text.data(using: .utf8),
           let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            return object
        }
        return [:]
    }

    private static func emitToolsListChanged() {
        guard var data = try? JSONSerialization.data(
            withJSONObject: ["jsonrpc": "2.0", "method": "notifications/tools/list_changed"],
            options: []
        ) else { return }
        data.append(0x0A)
        FileHandle.standardOutput.write(data)
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
