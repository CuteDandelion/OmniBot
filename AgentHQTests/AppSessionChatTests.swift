import CodexClient
import SwiftData
import XCTest
@testable import AgentHQ

@MainActor
final class AppSessionChatTests: XCTestCase {
    func testEnsureThreadStartsWhenThreadIdNil() async throws {
        let env = try ChatFakeEnv()
        defer { env.session.shutdown() }
        await env.session.retry()
        XCTAssertEqual(env.session.connectionState, .ready)

        await env.session.ensureThread(for: env.agent)
        XCTAssertEqual(env.agent.threadId, "thread-1")
        XCTAssertNil(env.session.workspaceWarning)

        let start = try env.loggedRequest(method: "thread/start")
        XCTAssertEqual(start["cwd"] as? String, env.workspace.path)
        XCTAssertEqual(start["sandbox"] as? String, "workspace-write")
        XCTAssertEqual(start["approvalPolicy"] as? String, "on-request")
        XCTAssertEqual(start["model"] as? String, "gpt-5.6")
        XCTAssertEqual(
            start["developerInstructions"] as? String,
            RolePreset.softwareEngineer.developerInstructions
        )
    }

    func testResumeMapsQuietItems() async throws {
        let env = try ChatFakeEnv(threadId: "thread-1")
        defer { env.session.shutdown() }
        await env.session.retry()
        await env.session.ensureThread(for: env.agent)

        XCTAssertEqual(env.session.items.map(\.id), ["u1", "f1", "a1"])
        XCTAssertEqual(env.session.items.userText, "hello")
        XCTAssertEqual(env.session.items.diffPath, "README.md")
        XCTAssertEqual(env.session.items.assistantText, "Hi there")
        XCTAssertFalse(env.session.items.contains { if case .working = $0.kind { return true }; return false })
        XCTAssertNotNil(try env.loggedRequest(method: "thread/resume"))
        XCTAssertNotNil(try env.loggedRequest(method: "thread/read"))
    }

    func testSendStreamsWorkingThenStop() async throws {
        let env = try ChatFakeEnv()
        defer { env.session.shutdown() }
        await env.session.retry()
        await env.session.ensureThread(for: env.agent)

        await env.session.send("what is the top-level of this repo?", from: env.agent)
        XCTAssertTrue(env.session.isTurnActive(for: env.agent.id))
        XCTAssertEqual(env.session.mascotState(for: env.agent.id), .working)
        XCTAssertTrue(env.session.items.contains { if case .working = $0.kind { return true }; return false })

        let streamed = await waitUntil(timeout: 2) {
            env.session.items.assistantText == "Top-level" && env.session.items.workingDetail != nil
        }
        XCTAssertTrue(streamed, "expected streamed assistant text and working row: \(env.session.items.map(\.id))")
        XCTAssertEqual(env.session.items.workingDetail, "ls")

        await env.session.interruptTurn(for: env.agent)
        XCTAssertFalse(env.session.isTurnActive(for: env.agent.id))
        XCTAssertNil(env.session.items.workingDetail)
        XCTAssertEqual(env.session.mascotState(for: env.agent.id), .idle)
        XCTAssertNotNil(try env.loggedRequest(method: "turn/interrupt"))
        XCTAssertEqual(try env.loggedRequest(method: "turn/interrupt")["turnId"] as? String, "turn-1")
    }

    func testStopDuringInFlightTurnStartInterruptsAfterStart() async throws {
        let env = try ChatFakeEnv(turnDelayMS: 400)
        defer { env.session.shutdown() }
        await env.session.retry()
        await env.session.ensureThread(for: env.agent)

        let sendTask = Task { await env.session.send("hi", from: env.agent) }
        let becameActive = await waitUntil(timeout: 2) {
            env.session.isTurnActive(for: env.agent.id)
        }
        XCTAssertTrue(becameActive, "send should mark the turn active before turn/start returns")
        XCTAssertTrue(env.session.items.contains { if case .working = $0.kind { return true }; return false })

        await env.session.interruptTurn(for: env.agent)
        XCTAssertTrue(env.session.isTurnActive(for: env.agent.id))
        XCTAssertNil(try? env.loggedRequest(method: "turn/interrupt"))

        await sendTask.value
        let interrupt = try env.loggedRequest(method: "turn/interrupt")
        XCTAssertEqual(interrupt["turnId"] as? String, "turn-1")
        XCTAssertEqual(interrupt["threadId"] as? String, "thread-1")
        XCTAssertFalse(env.session.isTurnActive(for: env.agent.id))
        XCTAssertNil(env.session.items.workingDetail)
        XCTAssertEqual(env.session.mascotState(for: env.agent.id), .idle)
    }

    func testDiscardClientClearsWorkingRow() async throws {
        let env = try ChatFakeEnv()
        defer { env.session.shutdown() }
        await env.session.retry()
        await env.session.ensureThread(for: env.agent)
        await env.session.send("hi", from: env.agent)
        XCTAssertTrue(env.session.isTurnActive(for: env.agent.id))
        XCTAssertTrue(env.session.items.contains { if case .working = $0.kind { return true }; return false })

        env.session.shutdown()
        XCTAssertFalse(env.session.isTurnActive(for: env.agent.id))
        XCTAssertNil(env.session.items.workingDetail)
        XCTAssertEqual(env.session.mascotState(for: env.agent.id), .idle)

        await env.session.retry()
        await env.session.ensureThread(for: env.agent)
        XCTAssertNil(env.session.items.workingDetail)
        XCTAssertFalse(env.session.isTurnActive(for: env.agent.id))
    }

    func testEventFanOutReachesMultipleSubscribers() async throws {
        let env = try ChatFakeEnv()
        defer { env.session.shutdown() }
        await env.session.retry()

        let first = Collector()
        let second = Collector()
        let stream1 = env.session.subscribeToEvents()
        let stream2 = env.session.subscribeToEvents()
        let task1 = Task {
            for await event in stream1 {
                first.append(event)
                if first.hasDelta { break }
            }
        }
        let task2 = Task {
            for await event in stream2 {
                second.append(event)
                if second.hasDelta { break }
            }
        }

        await env.session.ensureThread(for: env.agent)
        await env.session.send("hi", from: env.agent)

        let ok = await waitUntil(timeout: 2) { first.hasDelta && second.hasDelta }
        task1.cancel()
        task2.cancel()
        XCTAssertTrue(ok, "subscribers missed agentMessage/delta")
    }

    func testMissingWorkspaceSetsBanner() async throws {
        let env = try ChatFakeEnv()
        defer { env.session.shutdown() }
        env.agent.workspacePath = "/tmp/agenthq-missing-\(UUID().uuidString)"
        await env.session.retry()
        await env.session.ensureThread(for: env.agent)
        XCTAssertEqual(env.session.workspaceWarning, "Workspace folder is missing")
        XCTAssertNil(env.agent.threadId)
    }

    func testChangeWorkspaceArchivesAndStartsNewThread() async throws {
        let env = try ChatFakeEnv()
        defer { env.session.shutdown() }
        await env.session.retry()
        await env.session.ensureThread(for: env.agent)
        XCTAssertEqual(env.agent.threadId, "thread-1")

        await env.session.send("hi", from: env.agent)
        XCTAssertFalse(env.session.items.isEmpty)

        let next = FileManager.default.temporaryDirectory.appendingPathComponent("agenthq-ws-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: next, withIntermediateDirectories: true)
        await env.session.changeWorkspace(for: env.agent, to: next.path)

        XCTAssertEqual(env.agent.workspacePath, next.path)
        XCTAssertEqual(env.agent.threadId, "thread-2")
        XCTAssertTrue(env.session.items.isEmpty)
        XCTAssertNotNil(try env.loggedRequest(method: "thread/archive"))
        let starts = env.loggedMethods("thread/start")
        XCTAssertEqual(starts.count, 2)
        XCTAssertEqual(starts.last?["cwd"] as? String, next.path)
    }

    func testApprovalQueueAllowAlwaysAndDeny() async throws {
        XCTAssertEqual(ApprovalDecision.accept.rawValue, "accept")
        XCTAssertEqual(ApprovalDecision.acceptForSession.rawValue, "acceptForSession")
        XCTAssertEqual(ApprovalDecision.decline.rawValue, "decline")
        XCTAssertEqual(ApprovalDecision.cancel.rawValue, "cancel")

        let env = try ChatFakeEnv(approvalCount: 3)
        defer { env.session.shutdown() }
        await env.session.retry()
        await env.session.ensureThread(for: env.agent)
        await env.session.send("run a command outside the workspace", from: env.agent)

        let first = await waitUntil(timeout: 2) {
            env.session.pendingApproval?.command == "ls /etc"
        }
        XCTAssertTrue(first, "expected first approval: \(String(describing: env.session.pendingApproval))")
        XCTAssertEqual(env.session.pendingApproval?.reason, "Command is outside the workspace")
        XCTAssertEqual(env.session.pendingApproval?.agentID, env.agent.id)
        XCTAssertEqual(env.session.mascotState(for: env.agent.id), .needsApproval)

        await env.session.respondToPendingApproval(.accept)
        let second = await waitUntil(timeout: 2) {
            env.session.pendingApproval?.command == "curl https://example.com"
        }
        XCTAssertTrue(second, "expected queued approval after Allow: \(String(describing: env.session.pendingApproval))")
        XCTAssertEqual(env.session.mascotState(for: env.agent.id), .needsApproval)

        await env.session.respondToPendingApproval(.acceptForSession)
        let third = await waitUntil(timeout: 2) {
            env.session.pendingApproval?.command == "rm -rf /tmp/agenthq-outside"
        }
        XCTAssertTrue(third, "expected third approval after Allow always: \(String(describing: env.session.pendingApproval))")

        await env.session.respondToPendingApproval(.decline)
        let cleared = await waitUntil(timeout: 2) { env.session.pendingApproval == nil }
        XCTAssertTrue(cleared)
        XCTAssertEqual(env.session.mascotState(for: env.agent.id), .working)

        let logged = await waitUntil(timeout: 2) { env.loggedDecisions().count == 3 }
        XCTAssertTrue(logged, "missing approval RPC responses: \(env.loggedDecisions())")
        XCTAssertEqual(env.loggedDecisions().map(\.id), ["approval-1", "approval-2", "approval-3"])
        XCTAssertEqual(env.loggedDecisions().map(\.decision), ["accept", "acceptForSession", "decline"])
    }

    func testApprovalFromUnselectedAgentStillPresents() async throws {
        let env = try ChatFakeEnv(approvalCount: 1)
        defer { env.session.shutdown() }
        await env.session.retry()
        await env.session.ensureThread(for: env.agent)

        let other = Agent(
            name: "Ada",
            role: .chiefOfStaff,
            mascot: .bear,
            workspacePath: env.workspace.path
        )
        await env.session.ensureThread(for: other)
        XCTAssertEqual(other.threadId, "thread-2")

        await env.session.send("ls /etc", from: env.agent)
        let shown = await waitUntil(timeout: 2) {
            env.session.pendingApproval?.agentID == env.agent.id
        }
        XCTAssertTrue(shown, "background agent approval missing: \(String(describing: env.session.pendingApproval))")
        XCTAssertEqual(env.session.pendingApproval?.command, "ls /etc")
        XCTAssertEqual(env.session.mascotState(for: env.agent.id), .needsApproval)
        XCTAssertEqual(env.session.mascotState(for: other.id), .idle)
    }

    func testInterruptCancelsPendingApprovals() async throws {
        let env = try ChatFakeEnv(approvalCount: 2)
        defer { env.session.shutdown() }
        await env.session.retry()
        await env.session.ensureThread(for: env.agent)
        await env.session.send("run a command outside the workspace", from: env.agent)

        let shown = await waitUntil(timeout: 2) {
            env.session.pendingApproval?.command == "ls /etc"
        }
        XCTAssertTrue(shown, "expected approval before Stop: \(String(describing: env.session.pendingApproval))")
        try await Task.sleep(nanoseconds: 200_000_000)

        await env.session.interruptTurn(for: env.agent)
        XCTAssertNil(env.session.pendingApproval)
        XCTAssertFalse(env.session.isTurnActive(for: env.agent.id))
        XCTAssertEqual(env.session.mascotState(for: env.agent.id), .idle)

        let logged = await waitUntil(timeout: 2) { !env.loggedDecisions().isEmpty }
        XCTAssertTrue(logged, "expected cancel responses: \(env.loggedDecisions())")
        XCTAssertTrue(
            env.loggedDecisions().allSatisfy { $0.decision == "cancel" },
            "expected only cancel: \(env.loggedDecisions())"
        )
        XCTAssertGreaterThanOrEqual(env.loggedDecisions().count, 1)
    }

    func testHandoffSenderRequiresThreadId() async throws {
        let env = try ChatFakeEnv()
        defer { env.session.shutdown() }
        await env.session.retry()
        await env.session.ensureThread(for: env.agent)

        XCTAssertEqual(env.session.resolveHandoffSender(threadId: env.agent.threadId), env.agent.id)
        XCTAssertNil(env.session.resolveHandoffSender(threadId: nil))
        XCTAssertEqual(env.session.banner, "Handoff missing Codex thread id")
        XCTAssertNil(env.session.resolveHandoffSender(threadId: "missing-thread"))
        XCTAssertEqual(env.session.banner, "Handoff sender thread is unknown")
    }
}

private final class Collector: @unchecked Sendable {
    private let lock = NSLock()
    private var events: [ServerEvent] = []

    func append(_ event: ServerEvent) {
        lock.lock()
        events.append(event)
        lock.unlock()
    }

    var hasDelta: Bool {
        lock.lock()
        defer { lock.unlock() }
        return events.contains { if case .agentMessageDelta = $0 { return true }; return false }
    }
}

@MainActor
private struct ChatFakeEnv {
    let session: AppSession
    let agent: Agent
    let workspace: URL
    let logURL: URL
    private let context: ModelContext

    init(threadId: String? = nil, turnDelayMS: Int = 0, approvalCount: Int = 0) throws {
        let workspace = FileManager.default.temporaryDirectory.appendingPathComponent("agenthq-ws-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        let logURL = FileManager.default.temporaryDirectory.appendingPathComponent("agenthq-fake-\(UUID().uuidString).jsonl")
        FileManager.default.createFile(atPath: logURL.path, contents: Data(), attributes: nil)
        let script = try ChatFakeEnv.writeFakeServer()

        let schema = Schema([Agent.self, HandoffRecord.self])
        let container = try ModelContainer(for: schema, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = ModelContext(container)
        let agent = Agent(
            name: "Lin",
            role: .softwareEngineer,
            mascot: .cat,
            workspacePath: workspace.path,
            model: "gpt-5.6",
            reasoningEffort: "medium",
            threadId: threadId
        )
        context.insert(agent)
        try context.save()

        self.workspace = workspace
        self.logURL = logURL
        self.agent = agent
        self.context = context
        self.session = AppSession(
            resolveExecutable: { script },
            makeClient: { url in
                var extra = ["AGENTHQ_FAKE_LOG": logURL.path]
                if turnDelayMS > 0 {
                    extra["AGENTHQ_FAKE_TURN_DELAY_MS"] = String(turnDelayMS)
                }
                if approvalCount > 0 {
                    extra["AGENTHQ_FAKE_APPROVALS"] = String(approvalCount)
                }
                return AppServerClient(executableURL: url, extraConfig: extra)
            }
        )
    }

    func loggedRequest(method: String) throws -> [String: Any] {
        guard let match = loggedMethods(method).last else {
            throw NSError(domain: "ChatFakeEnv", code: 1, userInfo: [NSLocalizedDescriptionKey: "missing \(method)"])
        }
        return match
    }

    func loggedMethods(_ method: String) -> [[String: Any]] {
        guard let data = try? Data(contentsOf: logURL),
              let text = String(data: data, encoding: .utf8) else { return [] }
        return text.split(separator: "\n").compactMap { line in
            guard let obj = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  obj["method"] as? String == method else { return nil }
            return obj["params"] as? [String: Any] ?? [:]
        }
    }

    func loggedDecisions() -> [(id: String, decision: String)] {
        guard let data = try? Data(contentsOf: logURL),
              let text = String(data: data, encoding: .utf8) else { return [] }
        return text.split(separator: "\n").compactMap { line in
            guard let obj = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  obj["method"] == nil,
                  let result = obj["result"] as? [String: Any],
                  let decision = result["decision"] as? String else { return nil }
            let id: String
            if let value = obj["id"] as? String {
                id = value
            } else if let value = obj["id"] as? Int {
                id = String(value)
            } else {
                return nil
            }
            return (id, decision)
        }
    }

    private static func writeFakeServer() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("agenthq-chat-fake-\(UUID().uuidString).py")
        try script.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url
    }
}

private let script = #"""
#!/usr/bin/env python3
import json, sys, time

LOG = None
DELAY_MS = 0
APPROVALS = 0
for index, arg in enumerate(sys.argv):
    if arg != "-c" or index + 1 >= len(sys.argv):
        continue
    value = sys.argv[index + 1]
    if value.startswith("AGENTHQ_FAKE_LOG="):
        LOG = value.split("=", 1)[1]
    elif value.startswith("AGENTHQ_FAKE_TURN_DELAY_MS="):
        DELAY_MS = int(value.split("=", 1)[1])
    elif value.startswith("AGENTHQ_FAKE_APPROVALS="):
        APPROVALS = int(value.split("=", 1)[1])
STARTS = 0
APPROVAL_COMMANDS = [
    "ls /etc",
    "curl https://example.com",
    "rm -rf /tmp/agenthq-outside",
]

MODEL = {
    "id": "gpt-5.6",
    "displayName": "GPT-5.6",
    "defaultReasoningEffort": "medium",
    "description": "d",
    "hidden": False,
    "isDefault": True,
    "model": "gpt-5.6",
    "supportedReasoningEfforts": [{"description": "Medium", "reasoningEffort": "medium"}],
}

READ_ITEMS = [
    {"id": "u1", "type": "userMessage", "content": [{"type": "text", "text": "hello"}]},
    {"id": "c1", "type": "commandExecution", "command": "ls -la", "commandActions": [], "cwd": "/tmp", "status": "completed"},
    {"id": "f1", "type": "fileChange", "status": "completed", "changes": [{"path": "README.md", "diff": "+hi", "kind": {"type": "update"}}]},
    {"id": "a1", "type": "agentMessage", "text": "Hi there"},
]


def send(obj):
    sys.stdout.write(json.dumps(obj, separators=(",", ":")) + "\n")
    sys.stdout.flush()


def log(msg):
    if not LOG:
        return
    with open(LOG, "a") as handle:
        handle.write(json.dumps(msg, separators=(",", ":")) + "\n")


def handle(msg):
    global STARTS
    method = msg.get("method")
    mid = msg.get("id")
    params = msg.get("params") or {}
    log(msg)
    if method is None:
        return

    if method == "initialize":
        send({"id": mid, "result": {"userAgent": "codex-fake", "codexHome": "/tmp", "platformFamily": "unix", "platformOs": "macos"}})
        return
    if method == "initialized":
        return
    if method == "model/list":
        send({"id": mid, "result": {"data": [MODEL]}})
        return
    if method == "thread/start":
        STARTS += 1
        tid = "thread-%d" % STARTS
        send({"id": mid, "result": {"thread": {"id": tid, "turns": [], "cwd": params.get("cwd")}}})
        return
    if method == "thread/resume":
        tid = params.get("threadId") or "thread-1"
        send({"id": mid, "result": {"thread": {"id": tid, "turns": []}}})
        return
    if method == "thread/read":
        tid = params.get("threadId") or "thread-1"
        turns = [{"id": "turn-1", "status": "completed", "items": READ_ITEMS}] if params.get("includeTurns") else []
        send({"id": mid, "result": {"thread": {"id": tid, "turns": turns}}})
        return
    if method == "thread/archive":
        send({"id": mid, "result": {}})
        return
    if method == "turn/start":
        if DELAY_MS:
            time.sleep(DELAY_MS / 1000.0)
        tid = params.get("threadId") or "thread-1"
        send({"id": mid, "result": {"turn": {"id": "turn-1", "items": [], "status": "inProgress"}}})
        send({"method": "item/started", "params": {
            "threadId": tid,
            "turnId": "turn-1",
            "startedAtMs": 0,
            "item": {
                "id": "cmd-1",
                "type": "commandExecution",
                "command": "ls",
                "commandActions": [],
                "cwd": "/tmp",
                "status": "inProgress",
            },
        }})
        send({"method": "item/agentMessage/delta", "params": {
            "delta": "Top-level",
            "itemId": "msg-1",
            "threadId": tid,
            "turnId": "turn-1",
        }})
        if APPROVALS:
            for i in range(APPROVALS):
                cmd = APPROVAL_COMMANDS[i % len(APPROVAL_COMMANDS)]
                send({
                    "id": "approval-%d" % (i + 1),
                    "method": "item/commandExecution/requestApproval",
                    "params": {
                        "itemId": "item-cmd-%d" % (i + 1),
                        "startedAtMs": 0,
                        "threadId": tid,
                        "turnId": "turn-1",
                        "command": cmd,
                        "cwd": "/tmp",
                        "reason": "Command is outside the workspace",
                    },
                })
        return
    if method == "turn/interrupt":
        turn_id = params.get("turnId")
        if not isinstance(turn_id, str) or not turn_id:
            send({"id": mid, "error": {"code": -32602, "message": "invalid turnId"}})
            return
        send({"id": mid, "result": {"interruptedTurnId": turn_id}})
        send({"method": "turn/completed", "params": {
            "threadId": params.get("threadId") or "thread-1",
            "turn": {"id": turn_id, "status": "interrupted", "items": [
                {"id": "msg-1", "type": "agentMessage", "text": "Top-level"}
            ]},
        }})
        return
    if mid is not None:
        send({"id": mid, "error": {"code": -32601, "message": "Method not found: %s" % method}})


for raw in sys.stdin:
    line = raw.strip()
    if not line:
        continue
    handle(json.loads(line))
"""#

private extension Array where Element == ChatItem {
    var userText: String? {
        for item in self {
            if case .user(let text) = item.kind { return text }
        }
        return nil
    }

    var assistantText: String? {
        compactMap { item -> String? in
            if case .assistant(let text) = item.kind { return text }
            return nil
        }.last
    }

    var diffPath: String? {
        for item in self {
            if case .diff(let path, _) = item.kind { return path }
        }
        return nil
    }

    var workingDetail: String? {
        for item in self {
            if case .working(let detail) = item.kind { return detail ?? "" }
        }
        return nil
    }
}

private func waitUntil(timeout: TimeInterval, _ predicate: @escaping () -> Bool) async -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if predicate() { return true }
        try? await Task.sleep(nanoseconds: 20_000_000)
    }
    return predicate()
}
