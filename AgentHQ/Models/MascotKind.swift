import Foundation

enum MascotKind: String, Codable, CaseIterable, Identifiable {
    case bear, cat, owl, fox, rabbit, penguin, frog, corgi

    var id: String { rawValue }

    var accessibilityName: String {
        rawValue.capitalized
    }
}
