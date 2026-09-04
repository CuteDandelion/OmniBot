import Foundation

struct HandoffRosterEntry: Equatable {
    var id: String
    var name: String
    var role: String

    var json: [String: String] {
        ["id": id, "name": name, "role": role]
    }

    static func fromJSON(_ value: Any) -> HandoffRosterEntry? {
        guard let object = value as? [String: Any],
              let id = object["id"] as? String,
              let name = object["name"] as? String,
              let role = object["role"] as? String else { return nil }
        return HandoffRosterEntry(id: id, name: name, role: role)
    }
}

enum HandoffTool {
    static let name = "handoff"

    static func description(agents: [HandoffRosterEntry]) -> String {
        var lines = [
            "Hand work to another agent in Agent HQ. Pass agent_id from the live roster (UUID) and a brief for that agent.",
            "Do not hand off to yourself. Cycles (A waiting on B waiting on A) are rejected. One in-flight outbound handoff per agent.",
            "Roster:",
        ]
        if agents.isEmpty {
            lines.append("(no agents yet)")
        } else {
            for agent in agents {
                lines.append("- \(agent.id) · \(agent.name) · \(agent.role)")
            }
        }
        return lines.joined(separator: "\n")
    }

    static var inputSchema: [String: Any] {
        [
            "type": "object",
            "properties": [
                "agent_id": [
                    "type": "string",
                    "description": "Destination agent UUID from the roster.",
                ],
                "brief": [
                    "type": "string",
                    "description": "What the destination agent should do.",
                ],
            ],
            "required": ["agent_id", "brief"],
            "additionalProperties": false,
        ]
    }

    static func definition(agents: [HandoffRosterEntry]) -> [String: Any] {
        [
            "name": name,
            "description": description(agents: agents),
            "inputSchema": inputSchema,
        ]
    }
}

enum HandoffPrompt {
    static func make(fromName: String, fromRole: String, workspacePath: String, brief: String) -> String {
        """
        Handoff from \(fromName) (\(fromRole)).
        Their workspace: \(workspacePath)
        Brief:
        \(brief)

        Do the work in your workspace. Reply with a concise result for the sender.
        """
    }
}
