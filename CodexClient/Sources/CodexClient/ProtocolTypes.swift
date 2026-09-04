import Foundation

public struct ClientInfo: Sendable, Codable, Equatable {
    public var name: String
    public var title: String
    public var version: String

    public init(name: String, title: String, version: String) {
        self.name = name
        self.title = title
        self.version = version
    }
}

public struct ReasoningEffort: Sendable, Codable, Equatable {
    public var reasoningEffort: String
    public var description: String

    public init(reasoningEffort: String, description: String) {
        self.reasoningEffort = reasoningEffort
        self.description = description
    }
}

public struct ModelInfo: Sendable, Codable, Equatable {
    public var id: String
    public var displayName: String
    public var defaultReasoningEffort: String?
    public var supportedReasoningEfforts: [ReasoningEffort]
    public var isDefault: Bool

    public init(
        id: String,
        displayName: String,
        defaultReasoningEffort: String? = nil,
        supportedReasoningEfforts: [ReasoningEffort] = [],
        isDefault: Bool = false
    ) {
        self.id = id
        self.displayName = displayName
        self.defaultReasoningEffort = defaultReasoningEffort
        self.supportedReasoningEfforts = supportedReasoningEfforts
        self.isDefault = isDefault
    }
}

public enum SandboxMode: String, Sendable, Codable, Equatable {
    case readOnly = "read-only"
    case workspaceWrite = "workspace-write"
    case dangerFullAccess = "danger-full-access"
}

public enum ApprovalPolicy: String, Sendable, Codable, Equatable {
    case untrusted
    case onRequest = "on-request"
    case never
}

public struct ThreadStartParams: Sendable, Codable, Equatable {
    public var cwd: String?
    public var model: String?
    public var sandbox: SandboxMode?
    public var approvalPolicy: ApprovalPolicy?
    public var developerInstructions: String?

    public init(
        cwd: String? = nil,
        model: String? = nil,
        sandbox: SandboxMode? = nil,
        approvalPolicy: ApprovalPolicy? = nil,
        developerInstructions: String? = nil
    ) {
        self.cwd = cwd
        self.model = model
        self.sandbox = sandbox
        self.approvalPolicy = approvalPolicy
        self.developerInstructions = developerInstructions
    }
}

public struct UserInput: Sendable, Codable, Equatable {
    public var type: String
    public var text: String?
    public var url: String?
    public var path: String?

    public init(type: String, text: String? = nil, url: String? = nil, path: String? = nil) {
        self.type = type
        self.text = text
        self.url = url
        self.path = path
    }

    public static func text(_ text: String) -> UserInput {
        UserInput(type: "text", text: text)
    }
}

public struct TurnStartParams: Sendable, Codable, Equatable {
    public var threadId: String
    public var input: [UserInput]
    public var model: String?
    public var effort: String?

    public init(threadId: String, input: [UserInput], model: String? = nil, effort: String? = nil) {
        self.threadId = threadId
        self.input = input
        self.model = model
        self.effort = effort
    }
}

public struct Thread: Sendable, Codable, Equatable {
    public var id: String
    public var cwd: String?
    public var preview: String?
    public var model: String?
    public var modelProvider: String?
    public var name: String?
    public var sessionId: String?
    public var turns: [Turn]

    public init(
        id: String,
        cwd: String? = nil,
        preview: String? = nil,
        model: String? = nil,
        modelProvider: String? = nil,
        name: String? = nil,
        sessionId: String? = nil,
        turns: [Turn] = []
    ) {
        self.id = id
        self.cwd = cwd
        self.preview = preview
        self.model = model
        self.modelProvider = modelProvider
        self.name = name
        self.sessionId = sessionId
        self.turns = turns
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        cwd = try container.decodeIfPresent(String.self, forKey: .cwd)
        preview = try container.decodeIfPresent(String.self, forKey: .preview)
        model = try container.decodeIfPresent(String.self, forKey: .model)
        modelProvider = try container.decodeIfPresent(String.self, forKey: .modelProvider)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        sessionId = try container.decodeIfPresent(String.self, forKey: .sessionId)
        turns = try container.decodeIfPresent([Turn].self, forKey: .turns) ?? []
    }
}

public struct Turn: Sendable, Codable, Equatable {
    public var id: String
    public var status: String
    public var items: [JSONValue]
    public var startedAt: Int64?
    public var completedAt: Int64?

    public init(
        id: String,
        status: String,
        items: [JSONValue] = [],
        startedAt: Int64? = nil,
        completedAt: Int64? = nil
    ) {
        self.id = id
        self.status = status
        self.items = items
        self.startedAt = startedAt
        self.completedAt = completedAt
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        status = try container.decodeIfPresent(String.self, forKey: .status) ?? "inProgress"
        items = try container.decodeIfPresent([JSONValue].self, forKey: .items) ?? []
        startedAt = try container.decodeIfPresent(Int64.self, forKey: .startedAt)
        completedAt = try container.decodeIfPresent(Int64.self, forKey: .completedAt)
    }
}

public struct ThreadReadResult: Sendable, Codable, Equatable {
    public var thread: Thread

    public init(thread: Thread) {
        self.thread = thread
    }
}

public enum ApprovalDecision: String, Sendable, Codable, Equatable {
    case accept
    case acceptForSession
    case decline
    case cancel
}

public struct AgentMessageDeltaNotification: Sendable, Codable, Equatable {
    public var delta: String
    public var itemId: String
    public var threadId: String
    public var turnId: String

    public init(delta: String, itemId: String, threadId: String, turnId: String) {
        self.delta = delta
        self.itemId = itemId
        self.threadId = threadId
        self.turnId = turnId
    }
}

public struct TurnCompletedNotification: Sendable, Codable, Equatable {
    public var threadId: String
    public var turn: Turn

    public init(threadId: String, turn: Turn) {
        self.threadId = threadId
        self.turn = turn
    }
}

public struct CommandExecutionRequestApprovalParams: Sendable, Codable, Equatable {
    public var threadId: String
    public var turnId: String
    public var itemId: String
    public var command: String?
    public var cwd: String?
    public var reason: String?
    public var startedAtMs: Int64

    public init(
        threadId: String,
        turnId: String,
        itemId: String,
        command: String? = nil,
        cwd: String? = nil,
        reason: String? = nil,
        startedAtMs: Int64
    ) {
        self.threadId = threadId
        self.turnId = turnId
        self.itemId = itemId
        self.command = command
        self.cwd = cwd
        self.reason = reason
        self.startedAtMs = startedAtMs
    }
}

public enum ServerEvent: Sendable, Equatable {
    case response(id: JSONRPCID, result: JSONValue)
    case agentMessageDelta(AgentMessageDeltaNotification)
    case turnCompleted(TurnCompletedNotification)
    case commandExecutionApproval(requestId: JSONRPCID, params: CommandExecutionRequestApprovalParams)
    case notification(method: String, params: JSONValue?)
    case request(id: JSONRPCID, method: String, params: JSONValue?)
    case invalidMessage
}

struct InitializeParams: Sendable, Codable {
    var clientInfo: ClientInfo
}

struct InitializeResult: Sendable, Codable {
    var userAgent: String
    var codexHome: String
    var platformFamily: String
    var platformOs: String
}

struct ModelListResult: Sendable, Codable {
    var data: [ModelDTO]
}

struct ModelDTO: Sendable, Codable {
    var id: String
    var displayName: String
    var defaultReasoningEffort: String?
    var supportedReasoningEfforts: [ReasoningEffort]
    var isDefault: Bool
}

struct ThreadEnvelope: Sendable, Codable {
    var thread: Thread
}

struct TurnEnvelope: Sendable, Codable {
    var turn: Turn
}

struct ThreadIdParams: Sendable, Codable {
    var threadId: String
}

struct ThreadReadParams: Sendable, Codable {
    var threadId: String
    var includeTurns: Bool
}

struct TurnInterruptParams: Sendable, Codable {
    var threadId: String
    var turnId: String
}

struct ApprovalResponse: Sendable, Codable {
    var decision: ApprovalDecision
}

enum AppServerMethod {
    static let initialize = "initialize"
    static let initialized = "initialized"
    static let modelList = "model/list"
    static let threadStart = "thread/start"
    static let threadResume = "thread/resume"
    static let threadRead = "thread/read"
    static let threadArchive = "thread/archive"
    static let turnStart = "turn/start"
    static let turnInterrupt = "turn/interrupt"
    static let agentMessageDelta = "item/agentMessage/delta"
    static let turnCompleted = "turn/completed"
    static let commandExecutionRequestApproval = "item/commandExecution/requestApproval"
}
