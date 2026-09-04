import Combine
import CodexClient
import Foundation

enum CodexConnectionState: Equatable {
    case idle
    case connecting
    case ready
    case missingBinary
    case notSignedIn
    case disconnected
}

enum EmptyStateCopy {
    static func title(for state: CodexConnectionState) -> String {
        switch state {
        case .missingBinary:
            return "Codex CLI not found"
        case .notSignedIn:
            return "Codex is not signed in"
        case .connecting, .idle:
            return "Connecting to Codex…"
        case .ready, .disconnected:
            return "Create an agent to start."
        }
    }

    static func showsActions(_ state: CodexConnectionState) -> Bool {
        state == .missingBinary || state == .notSignedIn
    }
}

enum CodexErrorClassifier {
    enum Kind: Equatable {
        case notSignedIn
        case missingBinary
        case crashed
        case other
    }

    static func kind(for error: Error) -> Kind {
        if let appError = error as? AppServerClientError {
            switch appError {
            case .processLaunchFailed:
                return .missingBinary
            case .notStarted:
                return .missingBinary
            case .processExited:
                return .crashed
            case .rpc(let body):
                if isAuthFailure(message: body.message, data: body.data) {
                    return .notSignedIn
                }
                return .other
            case .unexpectedMessage, .unknownTurn:
                return .other
            }
        }
        if isAuthFailure(message: error.localizedDescription, data: nil) {
            return .notSignedIn
        }
        return .other
    }

    static func isAuthFailure(message: String, data: JSONValue?) -> Bool {
        var parts = [message]
        if let data {
            parts.append(String(describing: data))
        }
        let haystack = parts.joined(separator: " ").lowercased()
        let needles = [
            "not signed in",
            "not authenticated",
            "authentication required",
            "unauthenticated",
            "login required",
            "please log in",
            "please login",
            "not logged in",
            "codex login",
            "auth required",
        ]
        return needles.contains { haystack.contains($0) }
    }
}

@MainActor
final class AppSession: ObservableObject {
    @Published private(set) var connectionState: CodexConnectionState = .idle
    @Published private(set) var models: [ModelInfo] = []
    @Published var banner: String?

    static let clientInfo = ClientInfo(name: "agent_hq", title: "Agent HQ", version: "0.1.0")

    private var client: AppServerClient?
    private var generation = 0
    private var reconnectUsed = false
    private var didStart = false
    private let resolveExecutable: () -> URL?
    private let makeClient: (URL) -> AppServerClient

    var showsSetupEmptyState: Bool {
        switch connectionState {
        case .missingBinary, .notSignedIn, .connecting, .idle:
            return true
        case .ready, .disconnected:
            return false
        }
    }

    init(
        resolveExecutable: @escaping () -> URL? = { CodexProcess.resolveExecutable() },
        makeClient: @escaping (URL) -> AppServerClient = { executable in
            AppServerClient(
                executableURL: executable,
                extraConfig: CodexProcess.makeExtraConfig(
                    mcpExecutable: Bundle.main.executableURL ?? executable,
                    socketPath: CodexProcess.handoffSocketURL.path
                )
            )
        }
    ) {
        self.resolveExecutable = resolveExecutable
        self.makeClient = makeClient
    }

    func start() async {
        guard !AgentHQApp.isRunningTests else { return }
        guard !didStart else { return }
        didStart = true
        await retry()
    }

    func retry() async {
        generation += 1
        let generation = generation
        reconnectUsed = false
        banner = nil
        await connect(generation: generation, allowReconnect: true)
    }

    private func connect(generation: Int, allowReconnect: Bool) async {
        guard generation == self.generation else { return }
        client = nil
        connectionState = .connecting
        writeEvidence()

        guard let executable = resolveExecutable() else {
            connectionState = .missingBinary
            models = []
            writeEvidence()
            return
        }

        let client = makeClient(executable)
        self.client = client
        do {
            try await client.start()
            guard generation == self.generation else { return }
            try await client.initialize(clientInfo: Self.clientInfo)
            guard generation == self.generation else { return }
            try await client.initialized()
            guard generation == self.generation else { return }
            let catalog = try await client.listModels()
            guard generation == self.generation else { return }
            models = catalog
            connectionState = .ready
            banner = nil
            writeEvidence()
            Task { await watch(client: client, generation: generation, allowReconnect: allowReconnect) }
        } catch {
            guard generation == self.generation else { return }
            await handleFailure(error, generation: generation, allowReconnect: allowReconnect)
        }
    }

    private func watch(client: AppServerClient, generation: Int, allowReconnect: Bool) async {
        for await _ in client.events {}
        guard generation == self.generation else { return }
        guard self.client === client else { return }
        await handleCrash(generation: generation, allowReconnect: allowReconnect)
    }

    private func handleCrash(generation: Int, allowReconnect: Bool) async {
        guard generation == self.generation else { return }
        if allowReconnect && !reconnectUsed {
            reconnectUsed = true
            await connect(generation: generation, allowReconnect: false)
            return
        }
        connectionState = .disconnected
        banner = "Codex disconnected"
        writeEvidence()
    }

    private func handleFailure(_ error: Error, generation: Int, allowReconnect: Bool) async {
        switch CodexErrorClassifier.kind(for: error) {
        case .notSignedIn:
            connectionState = .notSignedIn
            writeEvidence()
        case .missingBinary:
            connectionState = .missingBinary
            models = []
            writeEvidence()
        case .crashed:
            await handleCrash(generation: generation, allowReconnect: allowReconnect)
        case .other:
            if allowReconnect && !reconnectUsed {
                reconnectUsed = true
                await connect(generation: generation, allowReconnect: false)
            } else {
                connectionState = .disconnected
                banner = "Codex disconnected"
                writeEvidence()
            }
        }
    }

    private func writeEvidence() {
        guard let raw = ProcessInfo.processInfo.environment["AGENTHQ_EVIDENCE"], !raw.isEmpty else { return }
        let dir = URL(fileURLWithPath: raw, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let modelPayload: [[String: Any]] = models.map { model in
            var item: [String: Any] = [
                "id": model.id,
                "displayName": model.displayName,
                "isDefault": model.isDefault,
                "efforts": model.supportedReasoningEfforts.map(\.reasoningEffort),
            ]
            if let effort = model.defaultReasoningEffort {
                item["defaultReasoningEffort"] = effort
            }
            return item
        }
        var payload: [String: Any] = [
            "state": describe(connectionState),
            "modelCount": models.count,
            "models": modelPayload,
        ]
        if let banner {
            payload["banner"] = banner
        }
        if let path = resolveExecutable()?.path {
            payload["executable"] = path
        }
        if let data = try? JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys]) {
            try? data.write(to: dir.appendingPathComponent("session.json"))
        }
        if connectionState != .connecting && connectionState != .idle {
            try? "ok\n".write(to: dir.appendingPathComponent("SESSION_DONE"), atomically: true, encoding: .utf8)
        }
    }

    private func describe(_ state: CodexConnectionState) -> String {
        switch state {
        case .idle: return "idle"
        case .connecting: return "connecting"
        case .ready: return "ready"
        case .missingBinary: return "missingBinary"
        case .notSignedIn: return "notSignedIn"
        case .disconnected: return "disconnected"
        }
    }
}
