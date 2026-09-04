import Foundation

enum RolePreset: String, Codable, CaseIterable, Identifiable {
    case chiefOfStaff
    case softwareEngineer
    case qaEngineer
    case custom

    var id: String { rawValue }

    var defaultTitle: String {
        switch self {
        case .chiefOfStaff: return "Chief of Staff"
        case .softwareEngineer: return "Software Engineer"
        case .qaEngineer: return "QA Engineer"
        case .custom: return "Custom"
        }
    }

    var defaultMascot: MascotKind {
        switch self {
        case .chiefOfStaff: return .bear
        case .softwareEngineer: return .cat
        case .qaEngineer: return .owl
        case .custom: return .fox
        }
    }

    var developerInstructions: String {
        switch self {
        case .chiefOfStaff:
            return "Coordinate. Break work up. Use `handoff` to specialists. Summarize back to the user. Do not implement large code changes yourself."
        case .softwareEngineer:
            return "Implement in the workspace. Edit/write/tests as needed. Handoff to QA when implementation is ready to verify."
        case .qaEngineer:
            return "Write/run tests, report failures with evidence, hand back to Engineering with a fix brief."
        case .custom:
            return "The user blurb is the role."
        }
    }
}
