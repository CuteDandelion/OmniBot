import Foundation

enum MascotState: String, CaseIterable, Hashable {
    case idle
    case hover
    case working
    case waiting
    case needsApproval
}
