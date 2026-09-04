import SwiftData
import XCTest
@testable import AgentHQ

@MainActor
final class HandoffOrchestratorTests: XCTestCase {
    func testSuccessReturnsSummaryAndMarksDone() async throws {
        let env = try HandoffTestEnv()
        env.orchestrator.runTarget = { _, _, _ in "README.md and src/" }

        let summary = try await env.orchestrator.handoff(
            from: env.ada.id,
            to: env.lin.id,
            brief: "list files"
        )

        XCTAssertEqual(summary, "README.md and src/")
        let records = env.records()
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.status, "done")
        XCTAssertEqual(records.first?.resultSummary, "README.md and src/")
        XCTAssertEqual(records.first?.brief, "list files")
    }

    func testCycleThrowsAndCreatesNoRecord() async throws {
        let env = try HandoffTestEnv()
        let gate = AsyncGate()
        env.orchestrator.runTarget = { _, _, _ in
            await gate.wait()
            return "ok"
        }

        let first = Task {
            try await env.orchestrator.handoff(from: env.ada.id, to: env.lin.id, brief: "one")
        }
        let started = await waitUntil(timeout: 2) { env.orchestrator.inFlightRecords().count == 1 }
        XCTAssertTrue(started)

        do {
            _ = try await env.orchestrator.handoff(from: env.lin.id, to: env.ada.id, brief: "two")
            XCTFail("cycle should throw")
        } catch {
            XCTAssertEqual(error as? HandoffError, .cycle)
        }
        XCTAssertEqual(env.records().count, 1)
        XCTAssertEqual(env.records().first?.brief, "one")

        await gate.open()
        let summary = try await first.value
        XCTAssertEqual(summary, "ok")
        XCTAssertEqual(env.records().first?.status, "done")
    }

    func testInterruptMarksFailed() async throws {
        let env = try HandoffTestEnv()
        let gate = AsyncGate()
        env.orchestrator.runTarget = { _, _, _ in
            await gate.wait()
            return "should not complete"
        }

        let task = Task {
            try await env.orchestrator.handoff(from: env.ada.id, to: env.lin.id, brief: "do it")
        }
        let started = await waitUntil(timeout: 2) { env.orchestrator.inFlightRecords().count == 1 }
        XCTAssertTrue(started)

        env.orchestrator.failInvolving(env.lin.id)
        do {
            _ = try await task.value
            XCTFail("interrupt should throw")
        } catch {
            XCTAssertEqual(error as? HandoffError, .interrupted)
        }
        XCTAssertEqual(env.records().first?.status, "failed")
        await gate.open()
    }

    func testUnknownAgentCreatesNoRecord() async throws {
        let env = try HandoffTestEnv()
        do {
            _ = try await env.orchestrator.handoff(from: env.ada.id, to: UUID(), brief: "x")
            XCTFail("unknown agent should throw")
        } catch {
            XCTAssertEqual(error as? HandoffError, .unknownAgent)
        }
        XCTAssertTrue(env.records().isEmpty)
    }

    func testOutboundAlreadyPendingRejected() async throws {
        let env = try HandoffTestEnv()
        let gate = AsyncGate()
        env.orchestrator.runTarget = { _, _, _ in
            await gate.wait()
            return "ok"
        }
        let first = Task {
            try await env.orchestrator.handoff(from: env.ada.id, to: env.lin.id, brief: "one")
        }
        let started = await waitUntil(timeout: 2) { env.orchestrator.inFlightRecords().count == 1 }
        XCTAssertTrue(started)
        do {
            _ = try await env.orchestrator.handoff(from: env.ada.id, to: env.qa.id, brief: "two")
            XCTFail("second outbound should throw")
        } catch {
            XCTAssertEqual(error as? HandoffError, .alreadyPending)
        }
        XCTAssertEqual(env.records().count, 1)
        await gate.open()
        _ = try await first.value
    }

    func testSelfHandoffIsCycle() async throws {
        let env = try HandoffTestEnv()
        do {
            _ = try await env.orchestrator.handoff(from: env.ada.id, to: env.ada.id, brief: "loop")
            XCTFail("self handoff should throw")
        } catch {
            XCTAssertEqual(error as? HandoffError, .cycle)
        }
        XCTAssertTrue(env.records().isEmpty)
    }

    func testToolDescriptionIncludesLiveRoster() {
        let ada = UUID()
        let lin = UUID()
        let description = HandoffTool.description(agents: [
            HandoffRosterEntry(id: ada.uuidString, name: "Ada", role: "Chief of Staff"),
            HandoffRosterEntry(id: lin.uuidString, name: "Lin", role: "Software Engineer"),
        ])
        XCTAssertTrue(description.contains(ada.uuidString))
        XCTAssertTrue(description.contains("Ada"))
        XCTAssertTrue(description.contains("Chief of Staff"))
        XCTAssertTrue(description.contains(lin.uuidString))
        XCTAssertTrue(description.contains("Software Engineer"))
    }

    func testSocketHandoffRoundTrip() throws {
        let path = "/tmp/ahq-h-\(UUID().uuidString.prefix(8)).sock"
        let server = UnixJSONServer(path: path)
        server.onRequest = { payload, reply in
            let id = payload["id"] as Any
            reply(["id": id, "ok": true, "summary": "listed files"])
        }
        try server.start()
        defer { server.stop() }

        let client = HandoffIPCClient(path: path)
        let result = try client.request(
            method: "handoff",
            params: ["agent_id": "abc", "brief": "list files"],
            timeout: 2
        )
        XCTAssertEqual(result["ok"] as? Bool, true)
        XCTAssertEqual(result["summary"] as? String, "listed files")
        client.stop()
    }
}

@MainActor
private struct HandoffTestEnv {
    let context: ModelContext
    let orchestrator: HandoffOrchestrator
    let ada: Agent
    let lin: Agent
    let qa: Agent

    init() throws {
        let schema = Schema([Agent.self, HandoffRecord.self])
        let container = try ModelContainer(for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)
        let ada = Agent(name: "Ada", role: .chiefOfStaff, mascot: .bear, workspacePath: "/tmp/ada")
        let lin = Agent(name: "Lin", role: .softwareEngineer, mascot: .cat, workspacePath: "/tmp/lin")
        let qa = Agent(name: "Quinn", role: .qaEngineer, mascot: .owl, workspacePath: "/tmp/qa")
        context.insert(ada)
        context.insert(lin)
        context.insert(qa)
        try context.save()
        self.context = context
        self.ada = ada
        self.lin = lin
        self.qa = qa
        self.orchestrator = HandoffOrchestrator(modelContext: context)
    }

    func records() -> [HandoffRecord] {
        (try? context.fetch(FetchDescriptor<HandoffRecord>())) ?? []
    }
}

private actor AsyncGate {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { waiters.append($0) }
    }

    func open() {
        isOpen = true
        let current = waiters
        waiters = []
        current.forEach { $0.resume() }
    }
}

@MainActor
private func waitUntil(timeout: TimeInterval, _ predicate: @escaping () -> Bool) async -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if predicate() { return true }
        try? await Task.sleep(nanoseconds: 20_000_000)
    }
    return predicate()
}
