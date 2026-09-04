import XCTest
@testable import CodexClient

final class AppServerClientTests: XCTestCase {
    func testFakeServerYieldsInitializeThreadDeltaAndCompleted() async throws {
        let client = makeClient()
        defer { client.shutDown() }

        let collector = Task { () -> [ServerEvent] in
            var events: [ServerEvent] = []
            for await event in client.events {
                events.append(event)
                if hasDelta(events) && hasCompleted(events) && responseCount(events) >= 2 {
                    break
                }
            }
            return events
        }

        try await client.start()
        try await client.initialize(clientInfo: .agentHQ)
        try await client.initialized()
        let thread = try await client.threadStart(
            ThreadStartParams(
                cwd: "/tmp",
                model: "gpt-5.6",
                sandbox: .workspaceWrite,
                approvalPolicy: .onRequest
            )
        )
        XCTAssertEqual(thread.id, "thread-1")

        let events = try await waitFor(collector)
        XCTAssertTrue(
            events.contains { event in
                if case .response(_, let result) = event {
                    return result.object?["userAgent"] == .string("codex-fake")
                }
                return false
            },
            "missing initialize result: \(events)"
        )
        XCTAssertTrue(
            events.contains { event in
                if case .response(_, let result) = event {
                    return result.object?["thread"]?.object?["id"] == .string("thread-1")
                }
                return false
            },
            "missing thread/start result: \(events)"
        )
        XCTAssertTrue(
            events.contains { event in
                if case .agentMessageDelta(let delta) = event {
                    return delta.delta == "Hello" && delta.threadId == "thread-1"
                }
                return false
            },
            "missing item/agentMessage/delta: \(events)"
        )
        XCTAssertTrue(
            events.contains { event in
                if case .turnCompleted(let completed) = event {
                    return completed.threadId == "thread-1" && completed.turn.status == "completed"
                }
                return false
            },
            "missing turn/completed: \(events)"
        )
    }

    func testFakeApprovalRoundTrip() async throws {
        let client = makeClient(approval: true)
        defer { client.shutDown() }

        let collector = Task { () -> [ServerEvent] in
            var events: [ServerEvent] = []
            for await event in client.events {
                events.append(event)
                if case .commandExecutionApproval(let id, _) = event {
                    try? await client.respondApproval(requestId: id, decision: .accept)
                }
                if hasApproval(events) && hasCompleted(events) {
                    break
                }
            }
            return events
        }

        try await client.start()
        try await client.initialize(clientInfo: .agentHQ)

        let events = try await waitFor(collector)
        XCTAssertTrue(
            events.contains { event in
                if case .response(_, let result) = event {
                    return result.object?["userAgent"] == .string("codex-fake")
                }
                return false
            },
            "missing initialize result: \(events)"
        )
        XCTAssertTrue(
            events.contains { event in
                if case .commandExecutionApproval(let id, let params) = event {
                    return id == .string("approval-1") && params.command == "ls -la"
                }
                return false
            },
            "missing item/commandExecution/requestApproval: \(events)"
        )
        XCTAssertTrue(
            events.contains { event in
                if case .turnCompleted(let completed) = event {
                    return completed.turn.status == "completed"
                }
                return false
            },
            "missing turn/completed after approval: \(events)"
        )
    }

    func testListModelsAndThreadLifecycle() async throws {
        let client = makeClient()
        defer { client.shutDown() }
        try await client.start()
        try await client.initialize(clientInfo: .agentHQ)

        let models = try await client.listModels()
        XCTAssertEqual(models.first?.id, "gpt-5.6")
        XCTAssertEqual(models.first?.displayName, "GPT-5.6")
        XCTAssertEqual(models.first?.isDefault, true)
        XCTAssertEqual(models.first?.supportedReasoningEfforts.first?.reasoningEffort, "medium")

        let started = try await client.threadStart(ThreadStartParams(cwd: "/tmp", model: "gpt-5.6"))
        let resumed = try await client.threadResume(threadId: started.id)
        XCTAssertEqual(resumed.id, started.id)

        let read = try await client.threadRead(threadId: started.id, includeTurns: true)
        XCTAssertEqual(read.thread.id, started.id)
        XCTAssertEqual(read.thread.turns.first?.id, "turn-1")

        let turn = try await client.turnStart(
            TurnStartParams(threadId: started.id, input: [.text("hi")], model: "gpt-5.6", effort: "medium")
        )
        XCTAssertEqual(turn.id, "turn-1")

        try await client.turnInterrupt(threadId: started.id)
        try await client.threadArchive(threadId: started.id)
    }

    private func makeClient(approval: Bool = false) -> AppServerClient {
        let script = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("FakeAppServer.py")
        var arguments = [script.path]
        if approval {
            arguments.append("--approval")
        }
        return AppServerClient(
            executableURL: URL(fileURLWithPath: "/usr/bin/python3"),
            processArguments: arguments
        )
    }
}

private extension ClientInfo {
    static let agentHQ = ClientInfo(name: "agent_hq", title: "Agent HQ", version: "0.1.0")
}

private enum TestTimeout: Error {
    case timedOut
}

private func hasDelta(_ events: [ServerEvent]) -> Bool {
    events.contains { if case .agentMessageDelta = $0 { return true }; return false }
}

private func hasCompleted(_ events: [ServerEvent]) -> Bool {
    events.contains { if case .turnCompleted = $0 { return true }; return false }
}

private func hasApproval(_ events: [ServerEvent]) -> Bool {
    events.contains { if case .commandExecutionApproval = $0 { return true }; return false }
}

private func responseCount(_ events: [ServerEvent]) -> Int {
    events.filter { if case .response = $0 { return true }; return false }.count
}

private func waitFor<T: Sendable>(_ task: Task<T, Never>, timeout: TimeInterval = 2) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { await task.value }
        group.addTask {
            try await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            throw TestTimeout.timedOut
        }
        let value = try await group.next()!
        group.cancelAll()
        return value
    }
}
