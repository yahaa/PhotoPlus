import Foundation

/// Decides which SeaweedFS collection new uploads go to. Raw values are the API's `tier`.
enum SafetyTier: String, CaseIterable, Codable, Identifiable {
    case casual
    case important

    var id: String { rawValue }

    var title: String {
        switch self {
        case .casual: "普通"
        case .important: "重要"
        }
    }
}
