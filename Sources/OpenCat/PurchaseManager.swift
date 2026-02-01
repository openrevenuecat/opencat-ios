import Foundation
import StoreKit

/// Wraps StoreKit 2 for product fetching, purchasing, and transaction listening.
actor PurchaseManager {
    private var updateListenerTask: Task<Void, Never>?
    private var onTransactionUpdate: ((Transaction) async -> Void)?

    /// Start listening for Transaction.updates (renewals, revocations, etc.).
    func startTransactionListener(onUpdate: @escaping (Transaction) async -> Void) {
        self.onTransactionUpdate = onUpdate
        updateListenerTask = Task(priority: .background) {
            for await result in Transaction.updates {
                guard case .verified(let transaction) = result else { continue }
                await transaction.finish()
                await onUpdate(transaction)
            }
        }
    }

    /// Stop the transaction listener.
    func stopTransactionListener() {
        updateListenerTask?.cancel()
        updateListenerTask = nil
    }

    /// Fetch products from StoreKit.
    func getProducts(productIds: [String]) async throws -> [Product] {
        #if DEBUG
        print("[OpenCat] Fetching products for IDs: \(productIds)")
        #endif
        let products = try await Product.products(for: Set(productIds))
        #if DEBUG
        print("[OpenCat] StoreKit returned \(products.count) products: \(products.map { "\($0.id) - \($0.displayPrice)" })")
        #endif
        return products
    }

    /// Purchase a product by ID.
    func purchase(productId: String) async throws -> Transaction {
        let products = try await Product.products(for: [productId])
        guard let product = products.first else {
            throw OpenCatError.purchaseFailed("Product not found: \(productId)")
        }

        let result = try await product.purchase()

        switch result {
        case .success(let verification):
            guard case .verified(let transaction) = verification else {
                throw OpenCatError.purchaseFailed("Transaction verification failed")
            }
            await transaction.finish()
            return transaction

        case .userCancelled:
            throw OpenCatError.purchaseCancelled

        case .pending:
            throw OpenCatError.purchaseFailed("Purchase is pending approval")

        @unknown default:
            throw OpenCatError.purchaseFailed("Unknown purchase result")
        }
    }

    /// Get the JWS representation from the latest transaction for a product.
    func getJWSRepresentation(for productId: String) async -> String? {
        guard let result = await Transaction.latest(for: productId) else { return nil }
        guard case .verified = result else { return nil }
        return result.jwsRepresentation
    }

    /// Restore purchases (iterates currentEntitlements and finishes them).
    func restorePurchases() async {
        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }
            await transaction.finish()
        }
    }
}
