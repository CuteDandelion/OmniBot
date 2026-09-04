import CodexClient
import Darwin
import XCTest
@testable import AgentHQ

final class CodexProcessTests: XCTestCase {
    func testOverridePathWinsWhenExecutable() throws {
        let fake = try makeExecutable("codex")
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        defaults.set(fake.path, forKey: CodexProcess.pathDefaultsKey)
        let resolved = CodexProcess.resolveExecutable(
            defaults: defaults,
            environment: ["PATH": "/nope"],
            fileExists: { FileManager.default.isExecutableFile(atPath: $0) },
            extraSearchPaths: [],
            loginPATH: { nil }
        )
        XCTAssertEqual(resolved?.path, fake.path)
    }

    func testMissingOverrideDoesNotFallBackToPATH() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        defaults.set("/tmp/agenthq-missing-codex-\(UUID().uuidString)", forKey: CodexProcess.pathDefaultsKey)
        let resolved = CodexProcess.resolveExecutable(
            defaults: defaults,
            environment: ["PATH": "/usr/bin:/bin"],
            fileExists: { FileManager.default.isExecutableFile(atPath: $0) },
            extraSearchPaths: [],
            loginPATH: { nil }
        )
        XCTAssertNil(resolved)
    }

    func testPATHLookupFindsCodex() throws {
        let fake = try makeExecutable("codex")
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let resolved = CodexProcess.resolveExecutable(
            defaults: defaults,
            environment: ["PATH": fake.deletingLastPathComponent().path],
            fileExists: { FileManager.default.isExecutableFile(atPath: $0) },
            extraSearchPaths: [],
            loginPATH: { nil }
        )
        XCTAssertEqual(resolved?.path, fake.path)
    }

    func testCommonInstallDirFallback() throws {
        let fake = try makeExecutable("codex")
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let resolved = CodexProcess.resolveExecutable(
            defaults: defaults,
            environment: ["PATH": "/nope"],
            fileExists: { FileManager.default.isExecutableFile(atPath: $0) },
            extraSearchPaths: [fake.deletingLastPathComponent().path],
            loginPATH: { nil }
        )
        XCTAssertEqual(resolved?.path, fake.path)
    }

    func testLoginShellPATHFallback() throws {
        let fake = try makeExecutable("codex")
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let resolved = CodexProcess.resolveExecutable(
            defaults: defaults,
            environment: ["PATH": "/nope"],
            fileExists: { FileManager.default.isExecutableFile(atPath: $0) },
            extraSearchPaths: [],
            loginPATH: { fake.deletingLastPathComponent().path }
        )
        XCTAssertEqual(resolved?.path, fake.path)
    }

    func testExtraConfigPointsAtMCPAndHandoffSocket() {
        let config = CodexProcess.makeExtraConfig(
            mcpExecutable: URL(fileURLWithPath: "/tmp/AgentHQ.app/Contents/MacOS/AgentHQ"),
            socketPath: "/tmp/AgentHQ/Handoff.sock"
        )
        XCTAssertEqual(config["mcp_servers.agenthq.command"], "\"/tmp/AgentHQ.app/Contents/MacOS/AgentHQ\"")
        XCTAssertEqual(config["mcp_servers.agenthq.args"], "[\"--mcp\"]")
        XCTAssertEqual(config["mcp_servers.agenthq.env.AGENTHQ_HANDOFF_SOCKET"], "\"/tmp/AgentHQ/Handoff.sock\"")
        XCTAssertEqual(CodexProcess.handoffSocketURL.lastPathComponent, "Handoff.sock")
    }

    func testEmptyStateCopy() {
        XCTAssertEqual(EmptyStateCopy.title(for: .missingBinary), "Codex CLI not found")
        XCTAssertEqual(EmptyStateCopy.title(for: .notSignedIn), "Codex is not signed in")
        XCTAssertTrue(EmptyStateCopy.showsActions(.missingBinary))
        XCTAssertTrue(EmptyStateCopy.showsActions(.notSignedIn))
        XCTAssertFalse(EmptyStateCopy.showsActions(.ready))
    }

    func testAuthErrorClassification() {
        let auth = AppServerClientError.rpc(
            JSONRPCErrorBody(code: -32000, message: "codex account authentication required to read rate limits")
        )
        XCTAssertEqual(CodexErrorClassifier.kind(for: auth), .notSignedIn)
        XCTAssertEqual(CodexErrorClassifier.kind(for: AppServerClientError.processLaunchFailed("nope")), .missingBinary)
        XCTAssertEqual(CodexErrorClassifier.kind(for: AppServerClientError.processExited(1)), .crashed)
    }

    @MainActor
    func testMissingBinaryConnectionState() async {
        let session = AppSession(resolveExecutable: { nil }, makeClient: { _ in
            XCTFail("should not spawn a client")
            return AppServerClient(executableURL: URL(fileURLWithPath: "/usr/bin/true"), extraConfig: [:])
        })
        await session.retry()
        XCTAssertEqual(session.connectionState, .missingBinary)
        XCTAssertTrue(session.showsSetupEmptyState)
    }

    @MainActor
    func testStartNoopsDuringUnitTests() async {
        let session = AppSession(resolveExecutable: { nil })
        await session.start()
        XCTAssertEqual(session.connectionState, .idle)
    }

    @MainActor
    func testRetryStopsPreviousClient() async throws {
        let script = try makeFakeAppServer()
        var clients: [AppServerClient] = []
        let session = AppSession(
            resolveExecutable: { script },
            makeClient: { url in
                let client = AppServerClient(executableURL: url, extraConfig: [:])
                clients.append(client)
                return client
            }
        )
        await session.retry()
        XCTAssertEqual(session.connectionState, .ready)
        XCTAssertFalse(session.showsSetupEmptyState)
        XCTAssertEqual(clients.count, 1)
        let first = try XCTUnwrap(clients.first)
        let firstPID = try XCTUnwrap(first.processIdentifier)
        XCTAssertTrue(first.isRunning)

        await session.retry()
        XCTAssertEqual(session.connectionState, .ready)
        XCTAssertEqual(clients.count, 2)
        XCTAssertFalse(first.isRunning)
        XCTAssertTrue(clients[1].isRunning)
        XCTAssertTrue(waitUntilExited(pid: firstPID), "previous app-server pid \(firstPID) still alive")
        XCTAssertNotEqual(clients[1].processIdentifier, firstPID)
        session.shutdown()
    }

    private func makeExecutable(_ name: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("agenthq-codex-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(name)
        FileManager.default.createFile(atPath: url.path, contents: Data("#!/bin/sh\n".utf8), attributes: nil)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url
    }

    private func makeFakeAppServer() throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("agenthq-fake-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent("fake-app-server.py")
        let script = #"""
        #!/usr/bin/env python3
        import json, sys

        def send(obj):
            sys.stdout.write(json.dumps(obj, separators=(",", ":")) + "\n")
            sys.stdout.flush()

        model = {
            "id": "gpt-5.6",
            "displayName": "GPT-5.6",
            "defaultReasoningEffort": "medium",
            "description": "d",
            "hidden": False,
            "isDefault": True,
            "model": "gpt-5.6",
            "supportedReasoningEfforts": [{"description": "Medium", "reasoningEffort": "medium"}],
        }
        for line in sys.stdin:
            line = line.strip()
            if not line:
                continue
            msg = json.loads(line)
            method = msg.get("method")
            mid = msg.get("id")
            if method == "initialize":
                send({"id": mid, "result": {"userAgent": "codex-fake", "codexHome": "/tmp", "platformFamily": "unix", "platformOs": "macos"}})
            elif method == "model/list":
                send({"id": mid, "result": {"data": [model]}})
            elif method == "initialized":
                pass
        """#
        try script.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url
    }

    private func waitUntilExited(pid: Int32, timeout: TimeInterval = 2) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if kill(pid, 0) != 0 { return true }
            Thread.sleep(forTimeInterval: 0.05)
        }
        return false
    }
}

final class MCPMainTests: XCTestCase {
    func testInitializeAndEmptyToolsList() throws {
        let initLine = Data(#"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26","capabilities":{},"clientInfo":{"name":"codex","version":"1"}}}"#.utf8)
        let initData = try XCTUnwrap(MCPMain.response(for: initLine))
        let initObj = try XCTUnwrap(JSONSerialization.jsonObject(with: initData) as? [String: Any])
        XCTAssertEqual(initObj["jsonrpc"] as? String, "2.0")
        let result = try XCTUnwrap(initObj["result"] as? [String: Any])
        let serverInfo = try XCTUnwrap(result["serverInfo"] as? [String: Any])
        XCTAssertEqual(serverInfo["name"] as? String, "agenthq")

        let listLine = Data(#"{"jsonrpc":"2.0","id":2,"method":"tools/list"}"#.utf8)
        let listData = try XCTUnwrap(MCPMain.response(for: listLine))
        let listObj = try XCTUnwrap(JSONSerialization.jsonObject(with: listData) as? [String: Any])
        let listResult = try XCTUnwrap(listObj["result"] as? [String: Any])
        XCTAssertEqual((listResult["tools"] as? [Any])?.count, 0)

        XCTAssertNil(MCPMain.response(for: Data(#"{"jsonrpc":"2.0","method":"notifications/initialized"}"#.utf8)))
    }
}
