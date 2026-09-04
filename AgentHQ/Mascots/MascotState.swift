import SwiftUI

enum MascotState: String, CaseIterable, Hashable {
    case idle
    case hover
    case working
    case waiting
    case needsApproval

    var pipColor: Color {
        switch self {
        case .idle, .hover: return Tokens.muted
        case .working: return Tokens.accent
        case .waiting: return Tokens.attention
        case .needsApproval: return Tokens.danger
        }
    }

    var statusLabel: String {
        switch self {
        case .idle, .hover: return "idle"
        case .working: return "working"
        case .waiting: return "waiting"
        case .needsApproval: return "needs approval"
        }
    }
}
