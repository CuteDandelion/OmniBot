import CodexClient
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
            fileExists: { FileManager.default.isExecutableFile(atPath: $0) }
        )
        XCTAssertEqual(resolved?.path, fake.path)
    }

    func testMissingOverrideDoesNotFallBackToPATH() {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        defaults.set("/tmp/agenthq-missing-codex-\(UUID().uuidString)", forKey: CodexProcess.pathDefaultsKey)
        let resolved = CodexProcess.resolveExecutable(
            defaults: defaults,
            environment: ["PATH": "/usr/bin:/bin"],
            fileExists: { FileManager.default.isExecutableFile(atPath: $0) }
        )
        XCTAssertNil(resolved)
    }

    func testPATHLookupFindsCodex() throws {
        let fake = try makeExecutable("codex")
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let resolved = CodexProcess.resolveExecutable(
            defaults: defaults,
            environment: ["PATH": fake.deletingLastPathComponent().path],
            fileExists: { FileManager.default.isExecutableFile(atPath: $0) }
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

    private func makeExecutable(_ name: String) throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("agenthq-codex-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(name)
        FileManager.default.createFile(atPath: url.path, contents: Data("#!/bin/sh\n".utf8), attributes: nil)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url
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
