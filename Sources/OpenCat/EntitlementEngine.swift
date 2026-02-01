import Foundation
import StoreKit

/// Resolves entitlements from transactions and checks active status.
actor EntitlementEngine {

    /// Build CustomerInfo from StoreKit 2 current entitlements (standalone mode).
    func resolveFromCurrentEntitlements(appUserId: String) async -> CustomerInfo {
        var entitlements: [String: EntitlementInfo] = [:]
        var transactions: [TransactionInfo] = []

        for await result in Transaction.currentEntitlements {
            guard case .verified(let transaction) = result else { continue }

            let txInfo = transactionInfo(from: transaction)
            transactions.append(txInfo)

            if txInfo.status == .active || txInfo.status == .gracePeriod || txInfo.status == .billingRetry {
                let entitlement = EntitlementInfo(
                    id: transaction.productID,
                    isActive: true,
                    expirationDate: transaction.expirationDate,
                    productId: transaction.productID,
                    store: .apple,
                    willRenew: transaction.revocationDate == nil && transaction.expirationDate != nil,
                    purchaseDate: transaction.purchaseDate
                )
                entitlements[transaction.productID] = entitlement
            }
        }

        return CustomerInfo(
            appUserId: appUserId,
            activeEntitlements: entitlements,
            allTransactions: transactions,
            firstSeenAt: Date()
        )
    }

    /// Check if a specific entitlement is active in cached CustomerInfo.
    func isEntitled(_ entitlementId: String, in customerInfo: CustomerInfo?) -> Bool {
        guard let info = customerInfo,
              let entitlement = info.activeEntitlements[entitlementId] else {
            return false
        }
        guard entitlement.isActive else { return false }
        if let expiration = entitlement.expirationDate {
            return expiration > Date()
        }
        return true
    }

    /// Convert a StoreKit Transaction to TransactionInfo.
    func transactionInfo(from transaction: Transaction) -> TransactionInfo {
        let status: TransactionInfo.Status
        if transaction.revocationDate != nil {
            status = .refunded
        } else if let expiration = transaction.expirationDate, expiration <= Date() {
            status = .expired
        } else {
            status = .active
        }

        return TransactionInfo(
            transactionId: String(transaction.id),
            productId: transaction.productID,
            purchaseDate: transaction.purchaseDate,
            expirationDate: transaction.expirationDate,
            status: status
        )
    }
}
