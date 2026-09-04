import XCTest
@testable import CodexClient

final class JSONRPCTests: XCTestCase {
    func testIncrementingRequestIDs() throws {
        let generator = JSONRPCIDGenerator()
        let first = JSONRPCRequest(id: generator.nextID(), method: "initialize")
        let second = JSONRPCRequest(id: generator.nextID(), method: "thread/start")

        XCTAssertEqual(first.id, .int(1))
        XCTAssertEqual(second.id, .int(2))

        let firstLine = try JSONRPCMessage.request(first).encodeLine()
        let secondLine = try JSONRPCMessage.request(second).encodeLine()
        XCTAssertEqual(String(data: firstLine, encoding: .utf8), "{\"id\":1,\"method\":\"initialize\"}\n")
        XCTAssertEqual(String(data: secondLine, encoding: .utf8), "{\"id\":2,\"method\":\"thread/start\"}\n")
    }

    func testMatchResponseToRequestID() throws {
        let responseData = Data("{\"id\":1,\"result\":{\"userAgent\":\"codex-fake\"}}\n".utf8)
        let message = try JSONRPCMessage.decode(responseData.dropLast())
        guard case .response(let response) = message else {
            return XCTFail("expected response")
        }
        XCTAssertEqual(response.id, .int(1))
        XCTAssertEqual(response.result.object?["userAgent"], .string("codex-fake"))
    }

    func testNotificationHasNoID() throws {
        let data = Data("{\"method\":\"item/agentMessage/delta\",\"params\":{\"delta\":\"Hello\",\"itemId\":\"item-msg\",\"threadId\":\"thread-1\",\"turnId\":\"turn-1\"}}".utf8)
        let message = try JSONRPCMessage.decode(data)
        guard case .notification(let notification) = message else {
            return XCTFail("expected notification")
        }
        XCTAssertEqual(notification.method, "item/agentMessage/delta")
        XCTAssertNil(try JSONDecoder().decode(LineEnvelope.self, from: data).id)
    }

    func testStringAndIntIDsRoundTrip() throws {
        let intData = try JSONRPCCodec.encode(JSONRPCID.int(42))
        XCTAssertEqual(try JSONRPCCodec.decode(JSONRPCID.self, from: intData), .int(42))

        let stringData = try JSONRPCCodec.encode(JSONRPCID.string("approval-1"))
        XCTAssertEqual(try JSONRPCCodec.decode(JSONRPCID.self, from: stringData), .string("approval-1"))
    }

    func testPullLinesKeepsIncompleteTrailingLine() {
        var buffer = Data("{\"id\":1}\n{\"id\":2}\n{\"id\":".utf8)
        let lines = JSONRPCCodec.pullLines(from: &buffer)
        XCTAssertEqual(lines.count, 2)
        XCTAssertEqual(buffer, Data("{\"id\":".utf8))
    }

    func testSampleFixtureClassifiesMessages() throws {
        let fixture = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/app-server-sample.jsonl")
        let contents = try String(contentsOf: fixture, encoding: .utf8)
        let lines = contents.split(whereSeparator: \.isNewline).map(String.init)
        XCTAssertGreaterThanOrEqual(lines.count, 8)

        let messages = try lines.map { line in
            try JSONRPCMessage.decode(Data(line.utf8))
        }

        guard case .request(let initialize) = messages[0] else {
            return XCTFail("expected initialize request")
        }
        XCTAssertEqual(initialize.method, "initialize")
        XCTAssertEqual(initialize.id, .int(1))

        guard case .response(let initializeResult) = messages[1] else {
            return XCTFail("expected initialize result")
        }
        XCTAssertEqual(initializeResult.id, .int(1))

        guard case .notification(let initialized) = messages[2] else {
            return XCTFail("expected initialized notification")
        }
        XCTAssertEqual(initialized.method, "initialized")

        guard case .notification(let delta) = messages[5] else {
            return XCTFail("expected agent message delta")
        }
        XCTAssertEqual(delta.method, "item/agentMessage/delta")

        guard case .notification(let completed) = messages[6] else {
            return XCTFail("expected turn completed")
        }
        XCTAssertEqual(completed.method, "turn/completed")

        guard case .request(let approval) = messages[7] else {
            return XCTFail("expected approval request")
        }
        XCTAssertEqual(approval.method, "item/commandExecution/requestApproval")
        XCTAssertEqual(approval.id, .string("approval-1"))
    }
}

private struct LineEnvelope: Decodable {
    var id: JSONRPCID?
    var method: String?
}
