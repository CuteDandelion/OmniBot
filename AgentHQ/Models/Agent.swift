import Foundation
import SwiftData

@Model
final class Agent {
    @Attribute(.unique) var id: UUID
    var name: String
    var role: RolePreset
    var customRoleTitle: String?
    var customInstructions: String?
    var mascot: MascotKind
    var workspacePath: String
    var model: String
    var reasoningEffort: String
    var threadId: String?
    var createdAt: Date

    var displayRole: String {
        role == .custom ? (customRoleTitle ?? "Custom") : role.defaultTitle
    }

    var resolvedDeveloperInstructions: String {
        if role == .custom {
            return (customInstructions ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return role.developerInstructions
    }

    var displayWorkspacePath: String {
        Self.displayPath(workspacePath)
    }

    static func displayPath(_ path: String) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        if path == home { return "~" }
        if path.hasPrefix(home + "/") {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }

    init(
        id: UUID = UUID(),
        name: String,
        role: RolePreset,
        customRoleTitle: String? = nil,
        customInstructions: String? = nil,
        mascot: MascotKind,
        workspacePath: String,
        model: String = "gpt-5.6",
        reasoningEffort: String = "medium",
        threadId: String? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.role = role
        self.customRoleTitle = customRoleTitle
        self.customInstructions = customInstructions
        self.mascot = mascot
        self.workspacePath = workspacePath
        self.model = model
        self.reasoningEffort = reasoningEffort
        self.threadId = threadId
        self.createdAt = createdAt
    }
}
