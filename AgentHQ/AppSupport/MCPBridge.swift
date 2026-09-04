import Foundation

@MainActor
final class MCPBridge {
    var socketPath: URL = CodexProcess.handoffSocketURL
    var roster: () -> [HandoffRosterEntry] = { [] }
    var handleHandoff: (UUID, String, String?) async throws -> String = { _, _, _ in
        throw HandoffError.failed("Handoff is unavailable")
    }

    private var server: UnixJSONServer?

    func start() {
        stop()
        let server = UnixJSONServer(path: socketPath.path)
        server.onConnect = { [weak self] fd in
            guard let self else { return }
            Task { @MainActor in
                server.send(self.rosterPayload(), to: fd)
            }
        }
        server.onRequest = { [weak self] payload, reply in
            Task { @MainActor in
                let response = await self?.handle(payload) ?? ["ok": false, "error": "unavailable"]
                reply(response)
            }
        }
        do {
            try server.start()
            self.server = server
        } catch {
            self.server = nil
        }
    }

    func stop() {
        server?.stop()
        server = nil
    }

    func publishRoster() {
        server?.broadcast(rosterPayload())
    }

    private func rosterPayload() -> [String: Any] {
        [
            "method": "roster",
            "agents": roster().map(\.json),
        ]
    }

    private func handle(_ payload: [String: Any]) async -> [String: Any] {
        let method = payload["method"] as? String ?? ""
        let params = payload["params"] as? [String: Any] ?? payload
        var response: [String: Any]
        switch method {
        case "roster":
            response = ["ok": true, "agents": roster().map(\.json)]
        case "handoff":
            do {
                let summary = try await performHandoff(params)
                response = ["ok": true, "summary": summary]
            } catch {
                response = [
                    "ok": false,
                    "error": (error as? LocalizedError)?.errorDescription ?? error.localizedDescription,
                ]
            }
        default:
            response = ["ok": false, "error": "Unknown method"]
        }
        if let id = payload["id"] {
            response["id"] = id
        }
        return response
    }

    private func performHandoff(_ params: [String: Any]) async throws -> String {
        guard let rawID = params["agent_id"] as? String, let to = UUID(uuidString: rawID) else {
            throw HandoffError.unknownAgent
        }
        let brief = (params["brief"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !brief.isEmpty else {
            throw HandoffError.failed("brief is required")
        }
        let threadID = params["thread_id"] as? String
        return try await handleHandoff(to, brief, threadID)
    }
}
