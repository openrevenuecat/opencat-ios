import Foundation

/// Represents a customer's subscription and purchase state.
public struct CustomerInfo: Codable, Sendable {
    public let appUserId: String
    public var activeEntitlements: [String: EntitlementInfo]
    public var allTransactions: [TransactionInfo]
    public let firstSeenAt: Date

    public init(
        appUserId: String,
        activeEntitlements: [String: EntitlementInfo] = [:],
        allTransactions: [TransactionInfo] = [],
        firstSeenAt: Date = Date()
    ) {
        self.appUserId = appUserId
        self.activeEntitlements = activeEntitlements
        self.allTransactions = allTransactions
        self.firstSeenAt = firstSeenAt
    }
}

/// Information about a single entitlement.
public struct EntitlementInfo: Codable, Sendable {
    public let id: String
    public let isActive: Bool
    public let expirationDate: Date?
    public let productId: String
    public let store: Store
    public let willRenew: Bool
    public let purchaseDate: Date

    public enum Store: String, Codable, Sendable {
        case apple
        case google
    }
}

/// Information about a single transaction.
public struct TransactionInfo: Codable, Sendable {
    public let transactionId: String
    public let productId: String
    public let purchaseDate: Date
    public let expirationDate: Date?
    public let status: Status

    public enum Status: String, Codable, Sendable {
        case active
        case expired
        case refunded
        case gracePeriod = "grace_period"
        case billingRetry = "billing_retry"
    }
}
