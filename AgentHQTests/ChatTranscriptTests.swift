import CodexClient
import XCTest
@testable import AgentHQ

final class ChatTranscriptTests: XCTestCase {
    func testMapsUserAssistantAndDiffAndSkipsTools() {
        let thread = CodexClient.Thread(
            id: "thread-1",
            turns: [
                Turn(
                    id: "turn-1",
                    status: "completed",
                    items: [
                        .object([
                            "id": .string("u1"),
                            "type": .string("userMessage"),
                            "content": .array([
                                .object(["type": .string("text"), "text": .string("hello")]),
                            ]),
                        ]),
                        .object([
                            "id": .string("c1"),
                            "type": .string("commandExecution"),
                            "command": .string("ls -la"),
                            "commandActions": .array([]),
                            "cwd": .string("/tmp"),
                            "status": .string("completed"),
                        ]),
                        .object([
                            "id": .string("f1"),
                            "type": .string("fileChange"),
                            "status": .string("completed"),
                            "changes": .array([
                                .object([
                                    "path": .string("README.md"),
                                    "diff": .string("+hi"),
                                    "kind": .object(["type": .string("update")]),
                                ]),
                            ]),
                        ]),
                        .object([
                            "id": .string("a1"),
                            "type": .string("agentMessage"),
                            "text": .string("Hi there"),
                        ]),
                    ]
                ),
            ]
        )

        let items = ChatTranscript.items(from: thread)
        XCTAssertEqual(items.map(\.id), ["u1", "f1", "a1"])
        XCTAssertEqual(items[0].userText, "hello")
        XCTAssertEqual(items[1].diffPath, "README.md")
        XCTAssertEqual(items[1].diffSummary, "updated")
        XCTAssertEqual(items[2].assistantText, "Hi there")
    }

    func testDeltaUpdatesAssistantAndWorkingClearsOnCompleted() {
        var items: [ChatItem] = [
            ChatItem(id: "local-1", kind: .user("hi")),
        ]
        ChatTranscript.setWorking(detail: nil, on: &items)

        let started = ServerEvent.notification(
            method: "item/started",
            params: .object([
                "threadId": .string("thread-1"),
                "turnId": .string("turn-1"),
                "item": .object([
                    "id": .string("c1"),
                    "type": .string("commandExecution"),
                    "command": .string("ls"),
                    "status": .string("inProgress"),
                ]),
            ])
        )
        XCTAssertFalse(ChatTranscript.apply(started, threadId: "thread-1", to: &items))
        XCTAssertEqual(items.workingDetail, "ls")

        let delta = ServerEvent.agentMessageDelta(
            AgentMessageDeltaNotification(delta: "Top", itemId: "m1", threadId: "thread-1", turnId: "turn-1")
        )
        XCTAssertFalse(ChatTranscript.apply(delta, threadId: "thread-1", to: &items))
        XCTAssertEqual(items.assistantText, "Top")

        let more = ServerEvent.agentMessageDelta(
            AgentMessageDeltaNotification(delta: "-level", itemId: "m1", threadId: "thread-1", turnId: "turn-1")
        )
        XCTAssertFalse(ChatTranscript.apply(more, threadId: "thread-1", to: &items))
        XCTAssertEqual(items.assistantText, "Top-level")

        let completed = ServerEvent.turnCompleted(
            TurnCompletedNotification(
                threadId: "thread-1",
                turn: Turn(
                    id: "turn-1",
                    status: "completed",
                    items: [
                        .object([
                            "id": .string("m1"),
                            "type": .string("agentMessage"),
                            "text": .string("Top-level"),
                        ]),
                    ]
                )
            )
        )
        XCTAssertTrue(ChatTranscript.apply(completed, threadId: "thread-1", to: &items))
        XCTAssertNil(items.workingDetail)
        XCTAssertEqual(items.assistantText, "Top-level")
        XCTAssertEqual(items.map(\.id), ["local-1", "m1"])
    }

    func testIgnoresEventsForOtherThreads() {
        var items: [ChatItem] = []
        let delta = ServerEvent.agentMessageDelta(
            AgentMessageDeltaNotification(delta: "nope", itemId: "m1", threadId: "other", turnId: "turn-1")
        )
        XCTAssertFalse(ChatTranscript.apply(delta, threadId: "thread-1", to: &items))
        XCTAssertTrue(items.isEmpty)
    }
}

private extension ChatItem {
    var userText: String? {
        if case .user(let text) = kind { return text }
        return nil
    }

    var assistantText: String? {
        if case .assistant(let text) = kind { return text }
        return nil
    }

    var diffPath: String? {
        if case .diff(let path, _) = kind { return path }
        return nil
    }

    var diffSummary: String? {
        if case .diff(_, let summary) = kind { return summary }
        return nil
    }
}

private extension Array where Element == ChatItem {
    var assistantText: String? {
        compactMap(\.assistantText).last
    }

    var workingDetail: String? {
        for item in self {
            if case .working(let detail) = item.kind { return detail ?? "" }
        }
        return nil
    }
}
