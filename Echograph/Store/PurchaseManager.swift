import Foundation
import Observation
import StoreKit

@MainActor
@Observable
final class PurchaseManager {
    private(set) var products: [Product] = []
    private(set) var purchasedIdentifiers: Set<String> = []
    private(set) var isPurchasing: Bool = false
    private(set) var lastError: String?

    var hasPro: Bool {
        #if DEBUG
        return true
        #else
        return purchasedIdentifiers.contains(ProductID.proLifetime.rawValue) || hasProPlus
        #endif
    }

    var hasProPlus: Bool {
        #if DEBUG
        return true
        #else
        return purchasedIdentifiers.contains(ProductID.proPlusMonthly.rawValue) ||
               purchasedIdentifiers.contains(ProductID.proPlusYearly.rawValue)
        #endif
    }

    init() {
        Task { [weak self] in
            await self?.listenForUpdates()
        }
        Task { await loadProducts() }
        Task { await refreshEntitlements() }
    }

    func loadProducts() async {
        do {
            let loaded = try await Product.products(for: ProductID.allIdentifiers)
            products = loaded.sorted { lhs, rhs in
                Self.priceOrdinal(for: lhs.id) < Self.priceOrdinal(for: rhs.id)
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    func purchase(_ product: Product) async {
        guard !isPurchasing else { return }
        isPurchasing = true
        defer { isPurchasing = false }

        do {
            let result = try await product.purchase()
            switch result {
            case .success(let verification):
                let transaction = try Self.checkVerified(verification)
                await transaction.finish()
                await refreshEntitlements()
            case .userCancelled, .pending:
                break
            @unknown default:
                break
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    func restorePurchases() async {
        do {
            try await AppStore.sync()
            await refreshEntitlements()
        } catch {
            lastError = error.localizedDescription
        }
    }

    func refreshEntitlements() async {
        var ids: Set<String> = []
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result {
                ids.insert(transaction.productID)
            }
        }
        purchasedIdentifiers = ids
    }

    private func listenForUpdates() async {
        for await update in Transaction.updates {
            if case .verified(let transaction) = update {
                await transaction.finish()
                await refreshEntitlements()
            }
        }
    }

    private static func checkVerified<T>(_ result: VerificationResult<T>) throws -> T {
        switch result {
        case .verified(let value): return value
        case .unverified:
            throw PurchaseError.unverified
        }
    }

    private static func priceOrdinal(for id: String) -> Int {
        switch id {
        case ProductID.proPlusMonthly.rawValue: return 0
        case ProductID.proPlusYearly.rawValue: return 1
        case ProductID.proLifetime.rawValue: return 2
        default: return 99
        }
    }
}

enum PurchaseError: LocalizedError {
    case unverified

    var errorDescription: String? {
        switch self {
        case .unverified:
            return "Apple could not verify the purchase. Please try again."
        }
    }
}
