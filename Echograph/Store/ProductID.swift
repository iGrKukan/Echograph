import Foundation

enum ProductID: String, CaseIterable, Sendable {
    case proLifetime = "by.timberbid.echograph.pro.lifetime"
    case proPlusMonthly = "by.timberbid.echograph.proplus.monthly"
    case proPlusYearly = "by.timberbid.echograph.proplus.yearly"

    var displayName: String {
        switch self {
        case .proLifetime: return "Pro"
        case .proPlusMonthly: return "Pro+ Monthly"
        case .proPlusYearly: return "Pro+ Yearly"
        }
    }

    static var allIdentifiers: [String] { allCases.map(\.rawValue) }
}
