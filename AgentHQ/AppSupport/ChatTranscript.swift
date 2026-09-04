import CodexClient
import Foundation

struct ChatItem: Identifiable {
    let id: String
    var kind: Kind

    enum Kind {
        case user(String)
        case assistant(String)
        case working(detail: String?)
        case handoff(HandoffRecord)
        case diff(path: String, summary: String)
    }
}

enum ChatTranscript {
    static let workingID = "working"

    static func items(from thread: CodexClient.Thread) -> [ChatItem] {
        thread.turns.flatMap { turn in
            turn.items.flatMap(chatItems(from:))
        }
    }

    static func chatItems(from value: JSONValue) -> [ChatItem] {
        guard let object = value.object,
              let id = object["id"]?.string,
              let type = object["type"]?.string else { return [] }
        switch type {
        case "userMessage":
            let text = userText(from: object["content"])
            guard !text.isEmpty else { return [] }
            return [ChatItem(id: id, kind: .user(text))]
        case "agentMessage":
            return [ChatItem(id: id, kind: .assistant(object["text"]?.string ?? ""))]
        case "fileChange":
            return [diffItem(id: id, object: object)].compactMap { $0 }
        default:
            return []
        }
    }

    static func apply(_ event: ServerEvent, threadId: String, to items: inout [ChatItem]) -> Bool {
        switch event {
        case .agentMessageDelta(let delta):
            guard delta.threadId == threadId else { return false }
            upsertAssistant(id: delta.itemId, append: delta.delta, to: &items)
        case .turnCompleted(let completed):
            guard completed.threadId == threadId else { return false }
            for item in completed.turn.items {
                ingest(chatItems(from: item), into: &items)
            }
            removeWorking(from: &items)
            return true
        case .notification(let method, let params):
            guard params?.object?["threadId"]?.string == threadId else { return false }
            if method == "item/started" || method == "item/completed",
               let item = params?.object?["item"] {
                applyItemLifecycle(method: method, item: item, to: &items)
            }
        default:
            break
        }
        return false
    }

    static func setWorking(detail: String?, on items: inout [ChatItem]) {
        if let index = items.firstIndex(where: { $0.id == workingID }) {
            items[index].kind = .working(detail: detail)
        } else {
            items.append(ChatItem(id: workingID, kind: .working(detail: detail)))
        }
    }

    static func removeWorking(from items: inout [ChatItem]) {
        items.removeAll { $0.id == workingID }
    }

    static func ingest(_ incoming: [ChatItem], into items: inout [ChatItem]) {
        for item in incoming {
            if let index = items.firstIndex(where: { $0.id == item.id }) {
                items[index] = item
                continue
            }
            if case .user(let text) = item.kind,
               let index = items.lastIndex(where: { isLocalUser($0, text: text) }) {
                items[index] = item
                continue
            }
            insertBeforeWorking(item, on: &items)
        }
    }

    static func workingDetail(from item: JSONValue) -> String? {
        guard let object = item.object, let type = object["type"]?.string else { return nil }
        switch type {
        case "commandExecution":
            return object["command"]?.string
        case "fileChange":
            if let path = firstPath(in: object) {
                return "Editing \(path)"
            }
            return "Editing files"
        case "mcpToolCall":
            return object["tool"]?.string ?? object["server"]?.string
        default:
            return nil
        }
    }

    private static func applyItemLifecycle(method: String, item: JSONValue, to items: inout [ChatItem]) {
        let type = item.object?["type"]?.string
        if type == "commandExecution" || type == "fileChange" || type == "mcpToolCall" {
            if method == "item/started" {
                setWorking(detail: workingDetail(from: item), on: &items)
            }
            if method == "item/completed", type == "fileChange" {
                ingest(chatItems(from: item), into: &items)
            }
            return
        }
        if type == "userMessage" || type == "agentMessage" {
            ingest(chatItems(from: item), into: &items)
        }
    }

    private static func upsertAssistant(id: String, append delta: String, to items: inout [ChatItem]) {
        if let index = items.firstIndex(where: { $0.id == id }) {
            if case .assistant(let text) = items[index].kind {
                items[index].kind = .assistant(text + delta)
            } else {
                items[index].kind = .assistant(delta)
            }
            return
        }
        insertBeforeWorking(ChatItem(id: id, kind: .assistant(delta)), on: &items)
    }

    private static func insertBeforeWorking(_ item: ChatItem, on items: inout [ChatItem]) {
        if let index = items.firstIndex(where: { $0.id == workingID }) {
            items.insert(item, at: index)
        } else {
            items.append(item)
        }
    }

    private static func isLocalUser(_ item: ChatItem, text: String) -> Bool {
        guard item.id.hasPrefix("local-"), case .user(let existing) = item.kind else { return false }
        return existing == text
    }

    private static func userText(from content: JSONValue?) -> String {
        guard let parts = content?.array else { return "" }
        return parts.compactMap { part in
            guard let object = part.object, object["type"]?.string == "text" else { return nil }
            return object["text"]?.string
        }.joined(separator: "\n")
    }

    private static func diffItem(id: String, object: [String: JSONValue]) -> ChatItem? {
        let changes = object["changes"]?.array ?? []
        let paths = changes.compactMap { $0.object?["path"]?.string }
        guard let path = paths.first else { return nil }
        let summary: String
        if paths.count > 1 {
            summary = "\(paths.count) files changed"
        } else {
            summary = changeSummary(changes.first)
        }
        return ChatItem(id: id, kind: .diff(path: path, summary: summary))
    }

    private static func firstPath(in object: [String: JSONValue]) -> String? {
        object["changes"]?.array?.compactMap { $0.object?["path"]?.string }.first
    }

    private static func changeSummary(_ change: JSONValue?) -> String {
        switch change?.object?["kind"]?.object?["type"]?.string {
        case "add": return "added"
        case "delete": return "deleted"
        default: return "updated"
        }
    }
}

extension JSONValue {
    var string: String? {
        if case .string(let value) = self { return value }
        return nil
    }

    var array: [JSONValue]? {
        if case .array(let value) = self { return value }
        return nil
    }
}
