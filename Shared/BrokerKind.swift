import Foundation

enum BrokerKind: String, Codable, CaseIterable, Identifiable {
    case fidelity
    case publicBroker = "public"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .fidelity: return "Fidelity"
        case .publicBroker: return "Public"
        }
    }

    var snapshotFilename: String {
        "positions-\(rawValue).json"
    }
}
